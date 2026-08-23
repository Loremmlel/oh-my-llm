#include "windows_notification_host.h"

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <mutex>

#include "windows_notification_activator.h"
#include "windows_notification_instance_coordinator.h"
#include "windows_notification_protocol.h"
#include "windows_notification_registration.h"
#include "windows_notification_toast.h"

// 竞态 delay 编译定义由 CMake 仅在 Debug + testing=ON 时注入；此处不读取
// 环境变量/命令行，release 构建恒为 0。
#ifndef OMLL_NOTIFICATION_PRE_COM_DELAY_MS
#define OMLL_NOTIFICATION_PRE_COM_DELAY_MS 0
#endif
#ifndef OMLL_NOTIFICATION_POST_COM_PRE_FLUTTER_DELAY_MS
#define OMLL_NOTIFICATION_POST_COM_PRE_FLUTTER_DELAY_MS 0
#endif

int WindowsNotificationPreComDelayMs() { return OMLL_NOTIFICATION_PRE_COM_DELAY_MS; }
int WindowsNotificationPostComDelayMs() {
  return OMLL_NOTIFICATION_POST_COM_PRE_FLUTTER_DELAY_MS;
}

// message-only dispatch 窗口类名（constexpr 数组具内部链接，不进匿名命名
// 空间的原因：Core 的成员定义不能再嵌进另一个命名空间）。
constexpr wchar_t kDispatchWindowClassName[] = L"OmllNotificationHostDispatch";

// ---------------------------------------------------------------------------
// Core：宿主的全部可变状态与内部实现
// ---------------------------------------------------------------------------

struct WindowsNotificationHost::Core {
  Core(const WindowsNotificationHostOverrides& overrides);
  ~Core();

  // ── 解析后的身份（生产固定值 / 测试注入值）──
  // 名称/身份一律持有拷贝：overrides 只带裸指针，调用方的字符串（测试里的
  // 进程唯一名）可能在 host 存活期间销毁，而 pipe 线程会长期使用这些名字。
  std::wstring instance_mutex_name;
  std::wstring lease_mutex_name;
  std::wstring ready_event_name;
  std::wstring pipe_name;
  std::wstring aumid;
  std::wstring clsid_braced;
  bool suppress_registration = false;

  WindowsNotificationHostMode mode = WindowsNotificationHostMode::kFatal;
  HANDLE instance_mutex = nullptr;  // primary 持有到 shutdown
  HANDLE ready_event = nullptr;     // 仅 primary
  HANDLE lease_mutex = nullptr;     // 仅 primary（relay 的 lease 是局部的）
  std::atomic<bool> stopping{false};
  bool shutdown_done = false;

  WindowsNotificationPendingQueue queue;
  WindowsNotificationFocusFlag focus_flag;
  WindowsNotificationPipeServer pipe_server;
  bool pipe_started = false;
  WindowsNotificationStaHost sta;

  // relay 短命注册的共享状态：测试从其他线程经 CreateActivatorForTest 读取，
  // 用互斥保护发布。
  std::mutex relay_shared_mutex;
  std::shared_ptr<WindowsNotificationActivatorShared> relay_shared;

  // UI 线程专用：dispatch 窗口、channel、armed 标志、窗口恢复回调。
  HWND dispatch_window = nullptr;
  flutter::BinaryMessenger* messenger = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;
  bool dart_armed = false;
  std::function<void()> activate_window;

  bool available = true;
  const char* failure_stage = nullptr;

  // relay/secondary 晋升判定用：投递失败时捕获的 payload（互斥保护：测试
  // 直接驱动 Activate 时 sink 可能跑在非 relay 线程上）。
  std::mutex undelivered_mutex;
  std::vector<std::string> undelivered;

  // ── 流程 ──
  bool BootstrapPrimary();
  int RunManualSecondary();
  int RunActivationRelay();
  int TryPromoteOrExit();

  // ── channel / dispatch（全部 UI 线程）──
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void DrainQueueToDart();
  void ConsumeFocusRequest();

  void CloseChannel();
  void ReleaseKernelObjects();

  // ── dispatch 窗口（message-only；worker 只允许 PostMessage 到这里）──
  static LRESULT CALLBACK DispatchWndProc(HWND hwnd, UINT message,
                                          WPARAM wparam, LPARAM lparam);
  static HWND CreateDispatchWindow(Core* core);
};

WindowsNotificationHost::Core::Core(
    const WindowsNotificationHostOverrides& overrides) {
  instance_mutex_name = overrides.instance_mutex_name != nullptr
                            ? overrides.instance_mutex_name
                            : kWindowsNotificationInstanceMutexName;
  lease_mutex_name = overrides.lease_mutex_name != nullptr
                         ? overrides.lease_mutex_name
                         : kWindowsNotificationActivatorLeaseMutexName;
  ready_event_name = overrides.ready_event_name != nullptr
                         ? overrides.ready_event_name
                         : kWindowsNotificationReadyEventName;
  pipe_name =
      overrides.pipe_name != nullptr ? overrides.pipe_name
                                     : kWindowsNotificationPipeName;
  aumid = overrides.aumid != nullptr ? overrides.aumid
                                     : kWindowsNotificationAumid;
  clsid_braced = overrides.clsid_braced != nullptr
                     ? overrides.clsid_braced
                     : kWindowsNotificationClsidBraced;
  suppress_registration = overrides.suppress_identity_registration;
}

WindowsNotificationHost::Core::~Core() { ReleaseKernelObjects(); }

void WindowsNotificationHost::Core::ReleaseKernelObjects() {
  if (lease_mutex != nullptr) {
    WindowsNotificationReleaseLeaseMutex(lease_mutex);
    CloseHandle(lease_mutex);
    lease_mutex = nullptr;
  }
  if (ready_event != nullptr) {
    CloseHandle(ready_event);
    ready_event = nullptr;
  }
  if (instance_mutex != nullptr) {
    CloseHandle(instance_mutex);
    instance_mutex = nullptr;
  }
}

// ── dispatch 窗口：worker 只允许 PostMessage 到这里 ──────────────────

LRESULT CALLBACK WindowsNotificationHost::Core::DispatchWndProc(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == kWindowsNotificationUiMsgActivation ||
      message == kWindowsNotificationUiMsgFocus) {
    auto* core = reinterpret_cast<Core*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (core != nullptr) {
      if (message == kWindowsNotificationUiMsgActivation) {
        core->DrainQueueToDart();
      } else {
        core->ConsumeFocusRequest();
      }
    }
    return 0;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

HWND WindowsNotificationHost::Core::CreateDispatchWindow(Core* core) {
  static bool class_registered = false;
  if (!class_registered) {
    WNDCLASSW wc = {};
    wc.lpfnWndProc = &Core::DispatchWndProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = kDispatchWindowClassName;
    RegisterClassW(&wc);
    class_registered = true;
  }
  // message-only 窗口：不参与可见 UI，只承载 worker → UI 线程的 dispatch。
  HWND window =
      CreateWindowExW(0, kDispatchWindowClassName, L"", WS_OVERLAPPED, 0, 0, 0,
                      0, HWND_MESSAGE, nullptr, GetModuleHandleW(nullptr),
                      nullptr);
  if (window != nullptr) {
    SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(core));
  }
  return window;
}

// ---------------------------------------------------------------------------
// primary bootstrap
// ---------------------------------------------------------------------------

bool WindowsNotificationHost::Core::BootstrapPrimary() {
  // dispatch 窗口先于 pipe/STA 存在：worker 投递的 HWND 从第一条消息起就
  // 有效，早期窗口期（引擎未起）的 activation 只入队不丢消息。创建失败只
  // 记录 stage（live push 缺席，takePending 仍可用），不阻断协调链。
  dispatch_window = CreateDispatchWindow(this);
  if (dispatch_window == nullptr) {
    available = false;
    failure_stage = "dispatchWindow";
  }

  // manual-reset ready event：新 owner 打开即 reset，丢弃上一任遗留 signaled。
  ready_event =
      WindowsNotificationOpenReadyEventAsOwner(ready_event_name.c_str());
  if (ready_event == nullptr) {
    available = false;
    failure_stage = "readyEvent";
    return false;
  }

  // pipe server 先行：pre-COM 延迟/慢注册期间 relay 的交付必须可达，且
  // pipe ACK 不依赖 Flutter UI thread pump。DACL 构造失败只禁用 IPC；
  // instance mutex 仍由本进程持有（唯一 Flutter owner 不受影响），但通知
  // 宿主整体标记 unavailable，不得退回宽松 ACL 重试。
  if (!pipe_server.Start(
          [this](uint16_t kind,
                 const std::vector<unsigned char>& payload) -> uint16_t {
            if (stopping.load()) {
              return kWindowsNotificationAckShuttingDown;
            }
            if (kind == kWindowsNotificationKindActivation) {
              const std::string text(
                  reinterpret_cast<const char*>(payload.data()),
                  payload.size());
              return WindowsNotificationEnqueueActivationForUi(&queue,
                                                                dispatch_window,
                                                                text)
                         ? kWindowsNotificationAckAccepted
                         : kWindowsNotificationAckQueueFull;
            }
            WindowsNotificationEnqueueFocusForUi(&focus_flag, dispatch_window);
            return kWindowsNotificationAckAccepted;
          },
          &stopping, pipe_name.c_str())) {
    available = false;
    failure_stage = "pipe";
    return false;
  }
  pipe_started = true;

  if (!suppress_registration) {
    const WindowsNotificationRegistrationResult registration =
        EnsureWindowsNotificationRegistration();
    if (!registration.ok) {
      // 注册失败只禁用冷启动激活；长期 owner（lease/STA/pipe）继续工作，
      // 不阻断应用启动。
      available = false;
      failure_stage = registration.failure_stage;
    }
  }

  if (WindowsNotificationPreComDelayMs() > 0) {
    // pre-COM 竞态复验：只延迟 lease 竞争，pipe 线程照常服务。
    Sleep(static_cast<DWORD>(WindowsNotificationPreComDelayMs()));
  }

  // lease：relay 只持有有界 drain 窗口，这里按固定上界等待。
  lease_mutex = WindowsNotificationOpenLeaseMutex(lease_mutex_name.c_str());
  if (lease_mutex == nullptr ||
      WindowsNotificationAcquireLease(
          lease_mutex, kWindowsNotificationPrimaryLeaseTotalWaitMs,
          kWindowsNotificationLeaseSliceWaitMs) == WAIT_TIMEOUT) {
    available = false;
    failure_stage = "lease";
    return false;
  }

  const char* sta_stage = sta.StartPrimary(
      WindowsNotificationActivatorIdentity{aumid.c_str(), clsid_braced.c_str()},
      ready_event,
      [this](const std::string& payload) {
        // STA/pipe worker 的共同约束：只「加锁入队 + post UI dispatch」，
        // 不触碰 messenger/窗口。
        WindowsNotificationEnqueueActivationForUi(&queue, dispatch_window,
                                                  payload);
      });
  if (sta_stage != nullptr) {
    available = false;
    failure_stage = sta_stage;
    return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// secondary 模式
// ---------------------------------------------------------------------------

int WindowsNotificationHost::Core::RunManualSecondary() {
  // 只发 activateWindow；一条连接一条 request/ACK。
  const WindowsNotificationPipeClientResult result =
      WindowsNotificationSendPipeFrame(pipe_name.c_str(),
                                       kWindowsNotificationKindActivateWindow,
                                       nullptr, 0);
  if (result.delivered) {
    return 0;
  }
  // primary 的 pipe 不可达：可能是已退出。只有 mutex 确认消失才晋升，
  // 否则有界退出，绝不为「保底」构造第二个 Flutter。
  return TryPromoteOrExit();
}

int WindowsNotificationHost::Core::RunActivationRelay() {
  // ready event 只作观察（SYNCHRONIZE）；relay 永远不设置它。
  HANDLE ready_observer =
      OpenEventW(SYNCHRONIZE, FALSE, ready_event_name.c_str());
  HANDLE lease = WindowsNotificationOpenLeaseMutex(lease_mutex_name.c_str());
  if (lease == nullptr) {
    if (ready_observer != nullptr) {
      CloseHandle(ready_observer);
    }
    return 0;
  }

  // 有界竞争 lease（总上界 kRelayLeaseTotalWaitMs，切片等待期间反复观察
  // primary ready）：ready 已亮且 lease 被真 primary 持有 → 无 relay 工作。
  const ULONGLONG deadline =
      GetTickCount64() + kWindowsNotificationRelayLeaseTotalWaitMs;
  bool lease_acquired = false;
  while (GetTickCount64() < deadline) {
    const bool primary_ready =
        ready_observer != nullptr &&
        WaitForSingleObject(ready_observer, 0) == WAIT_OBJECT_0;
    if (primary_ready &&
        WaitForSingleObject(lease, 0) != WAIT_OBJECT_0) {
      // 真 primary 已注册并持 lease：RPCSS 会把请求交给长期 owner。
      CloseHandle(lease);
      if (ready_observer != nullptr) {
        CloseHandle(ready_observer);
      }
      return 0;
    }
    const DWORD wait = WaitForSingleObject(
        lease, kWindowsNotificationLeaseSliceWaitMs);
    if (wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED) {
      lease_acquired = true;
      break;
    }
  }
  if (ready_observer != nullptr) {
    CloseHandle(ready_observer);
  }
  if (!lease_acquired) {
    // relay lease 上界内未取得：有界退出。
    CloseHandle(lease);
    return 0;
  }

  const int relay_exit = WindowsNotificationRunRelayStaLoop(
      WindowsNotificationActivatorIdentity{aumid.c_str(), clsid_braced.c_str()},
      [this](const std::string& payload) {
        const WindowsNotificationPipeClientResult result =
            WindowsNotificationSendPipeFrame(
                pipe_name.c_str(), kWindowsNotificationKindActivation,
                reinterpret_cast<const unsigned char*>(payload.data()),
                payload.size());
        if (!result.delivered) {
          // primary 不可达（未 ready 就退出 / pipe 失联）：payload 先捕获，
          // 是否晋升由 mutex 重新选主决定。
          std::lock_guard<std::mutex> lock(undelivered_mutex);
          undelivered.push_back(payload);
        }
      },
      [this](std::shared_ptr<WindowsNotificationActivatorShared> shared) {
        std::lock_guard<std::mutex> lock(relay_shared_mutex);
        relay_shared = std::move(shared);
      });

  WindowsNotificationReleaseLeaseMutex(lease);
  CloseHandle(lease);
  if (relay_exit != 0) {
    return relay_exit;
  }
  {
    std::lock_guard<std::mutex> lock(undelivered_mutex);
    if (undelivered.empty()) {
      return 0;
    }
  }
  return TryPromoteOrExit();
}

int WindowsNotificationHost::Core::TryPromoteOrExit() {
  // 关闭旧的（非 owner）instance mutex 句柄后重新原子选主；只有确认为新
  // primary 才允许携带已捕获 payload 晋升并继续 Flutter 启动。
  if (instance_mutex != nullptr) {
    CloseHandle(instance_mutex);
    instance_mutex = nullptr;
  }
  const std::vector<std::wstring> no_arguments;
  const WindowsNotificationInstanceClaim claim =
      WindowsNotificationClaimInstance(no_arguments,
                                       instance_mutex_name.c_str());
  if (claim.mode != WindowsNotificationHostMode::kPrimary) {
    if (claim.instance_mutex != nullptr) {
      CloseHandle(claim.instance_mutex);
    }
    // primary 仍存活：放弃晋升，有界退出，保持一个 Flutter owner。
    return 0;
  }
  instance_mutex = claim.instance_mutex;
  mode = WindowsNotificationHostMode::kPrimary;
  {
    // 捕获的 payload 按原顺序补进 pending queue（冷启动语义）。
    std::lock_guard<std::mutex> lock(undelivered_mutex);
    for (const std::string& payload : undelivered) {
      queue.Push(payload);
    }
    undelivered.clear();
  }
  available = true;
  failure_stage = nullptr;
  BootstrapPrimary();
  return 0;
}

// ---------------------------------------------------------------------------
// channel / dispatch（UI 线程）
// ---------------------------------------------------------------------------

void WindowsNotificationHost::Core::CloseChannel() {
  if (messenger != nullptr) {
    // MethodChannel 析构不会自动摘除 handler，必须显式置空，否则 shutdown
    // 后 engine 侧仍会把消息派到悬垂的 handler 上。
    messenger->SetMessageHandler(kWindowsNotificationChannelName, nullptr);
    messenger = nullptr;
  }
  channel.reset();
}

void WindowsNotificationHost::Core::DrainQueueToDart() {
  if (!dart_armed || channel == nullptr) {
    // Dart 尚未取走过冷启动 pending（未 armed）或 messenger 已摘除：
    // payload 留在 native queue，等待 takePending 或 attach。
    return;
  }
  for (const std::string& payload : queue.TakeAll()) {
    channel->InvokeMethod(
        "notificationActivated",
        std::make_unique<flutter::EncodableValue>(payload));
  }
}

void WindowsNotificationHost::Core::ConsumeFocusRequest() {
  if (activate_window == nullptr) {
    // 窗口尚未 attach：保持合并标志，首次 attach 后执行。
    return;
  }
  if (focus_flag.Consume()) {
    activate_window();
  }
}

void WindowsNotificationHost::Core::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "getNotificationHostStatus") {
    flutter::EncodableMap status;
    status[flutter::EncodableValue("available")] =
        flutter::EncodableValue(available);
    if (!available && failure_stage != nullptr) {
      // 只回固定 stage token：不暴露路径、HRESULT 文本或系统消息。
      status[flutter::EncodableValue("failureStage")] =
          flutter::EncodableValue(std::string(failure_stage));
    }
    result->Success(flutter::EncodableValue(status));
    return;
  }
  if (method == "showTerminalNotification") {
    WindowsNotificationShowParams params;
    const auto* arguments = call.arguments();
    const auto* map =
        arguments != nullptr
            ? std::get_if<flutter::EncodableMap>(arguments)
            : nullptr;
    if (map == nullptr || map->size() != 4 ||
        map->count(flutter::EncodableValue("id")) == 0 ||
        map->count(flutter::EncodableValue("title")) == 0 ||
        map->count(flutter::EncodableValue("body")) == 0 ||
        map->count(flutter::EncodableValue("payload")) == 0) {
      // 参数 map 只能含 id/title/body/payload 四键；结构错误与数值越界
      // 分开：结构错误是调用方契约违约，返回固定错误码。
      result->Error("badArguments");
      return;
    }
    const auto* id32 = std::get_if<int32_t>(&map->at(flutter::EncodableValue("id")));
    const auto* id64 = std::get_if<int64_t>(&map->at(flutter::EncodableValue("id")));
    const auto* title =
        std::get_if<std::string>(&map->at(flutter::EncodableValue("title")));
    const auto* body =
        std::get_if<std::string>(&map->at(flutter::EncodableValue("body")));
    const auto* payload =
        std::get_if<std::string>(&map->at(flutter::EncodableValue("payload")));
    if ((id32 == nullptr && id64 == nullptr) || title == nullptr ||
        body == nullptr || payload == nullptr) {
      result->Error("badArguments");
      return;
    }
    params.id = id32 != nullptr ? *id32 : *id64;
    params.title = *title;
    params.body = *body;
    params.payload = *payload;
    // channel 层只做结构解析；数值/长度/UTF-8 收敛在 native 再校验，
    // 越界返回 false（不是错误）。
    result->Success(flutter::EncodableValue(
        WindowsNotificationShowToast(params)));
    return;
  }
  if (method == "takePendingNotificationActivations") {
    // 首次 takePending 之后视为 armed：此后新 activation 经 UI dispatch
    // 以 notificationActivated 直推 Dart，避免 pending+live 双通道重复。
    dart_armed = true;
    flutter::EncodableList payloads;
    for (const std::string& payload : queue.TakeAll()) {
      payloads.push_back(flutter::EncodableValue(payload));
    }
    result->Success(flutter::EncodableValue(payloads));
    return;
  }
  result->NotImplemented();
}

// ---------------------------------------------------------------------------
// WindowsNotificationHost 对外接口（转调 Core）
// ---------------------------------------------------------------------------

WindowsNotificationHost::WindowsNotificationHost(
    const WindowsNotificationHostOverrides& overrides)
    : core_(new Core(overrides)) {}
WindowsNotificationHost::~WindowsNotificationHost() { Shutdown(); }

std::unique_ptr<WindowsNotificationHost> WindowsNotificationHost::Start(
    const std::vector<std::wstring>& command_line,
    const WindowsNotificationHostOverrides& overrides) {
  // 最外层 catch-all：任何异常都不允许穿过 wWinMain；kernel object 创建
  // 失败（kFatal）时返回 nullptr，调用方直接退出而不是冒险成为第二个 owner。
  try {
    auto host = std::unique_ptr<WindowsNotificationHost>(
        new WindowsNotificationHost(overrides));
    Core* core = host->core_.get();
    const WindowsNotificationInstanceClaim claim =
        WindowsNotificationClaimInstance(command_line,
                                         core->instance_mutex_name.c_str());
    core->mode = claim.mode;
    core->instance_mutex = claim.instance_mutex;
    if (core->mode == WindowsNotificationHostMode::kFatal) {
      return nullptr;
    }
    if (core->mode == WindowsNotificationHostMode::kPrimary) {
      core->BootstrapPrimary();
    }
    return host;
  } catch (...) {
    return nullptr;
  }
}

bool WindowsNotificationHost::ShouldStartFlutter() const {
  return core_->mode == WindowsNotificationHostMode::kPrimary;
}

int WindowsNotificationHost::RunSecondaryMode() {
  try {
    if (core_->mode == WindowsNotificationHostMode::kManualSecondary) {
      return core_->RunManualSecondary();
    }
    if (core_->mode == WindowsNotificationHostMode::kActivationRelay) {
      return core_->RunActivationRelay();
    }
    return 0;
  } catch (...) {
    return 0;
  }
}

void WindowsNotificationHost::AttachMessenger(
    flutter::BinaryMessenger* messenger) {
  if (core_->mode != WindowsNotificationHostMode::kPrimary ||
      messenger == nullptr) {
    return;
  }
  core_->messenger = messenger;
  core_->channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kWindowsNotificationChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  core_->channel->SetMethodCallHandler(
      [core = core_.get()](const flutter::MethodCall<flutter::EncodableValue>& call,
                           std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                               result) {
        core->HandleMethodCall(call, std::move(result));
      });
}

void WindowsNotificationHost::DetachMessenger() { core_->CloseChannel(); }

void WindowsNotificationHost::AttachWindowActivation(
    std::function<void()> activate_window) {
  core_->activate_window = std::move(activate_window);
  core_->ConsumeFocusRequest();
}

void* WindowsNotificationHost::CreateActivatorForTest() const {
  {
    std::lock_guard<std::mutex> lock(core_->relay_shared_mutex);
    if (core_->relay_shared != nullptr &&
        core_->relay_shared->class_registered.load()) {
      return WindowsNotificationCreateActivatorForTest(core_->relay_shared);
    }
  }
  if (core_->sta.registered()) {
    return WindowsNotificationCreateActivatorForTest(
        core_->sta.shared_for_test());
  }
  return nullptr;
}

void WindowsNotificationHost::Shutdown() {
  Core* core = core_.get();
  if (core == nullptr || core->shutdown_done) {
    return;
  }
  core->shutdown_done = true;
  core->stopping.store(true);
  // 顺序固定：停止接收 → reset ready（先于 revoke）→ 注册线程 revoke 并
  // join → 停 pipe → 摘 channel → 销毁 dispatch 窗口 → 释放 kernel 对象。
  if (core->ready_event != nullptr) {
    WindowsNotificationResetReadyEvent(core->ready_event);
  }
  core->sta.Shutdown();
  if (core->pipe_started) {
    core->pipe_server.Stop();
    core->pipe_started = false;
  }
  core->CloseChannel();
  if (core->dispatch_window != nullptr) {
    DestroyWindow(core->dispatch_window);
    core->dispatch_window = nullptr;
  }
  core->ReleaseKernelObjects();
}

// ---------------------------------------------------------------------------
// 进程编排（与 wWinMain 相同顺序的测试 seam）
// ---------------------------------------------------------------------------

int WindowsNotificationRunProcess(
    const std::vector<std::wstring>& command_line,
    const WindowsNotificationProcessActions& actions,
    const WindowsNotificationHostOverrides& overrides) {
  std::unique_ptr<WindowsNotificationHost> host =
      WindowsNotificationHost::Start(command_line, overrides);
  if (host == nullptr) {
    return -1;
  }
  if (!host->ShouldStartFlutter()) {
    const int secondary_exit = host->RunSecondaryMode();
    if (!host->ShouldStartFlutter()) {
      return secondary_exit;
    }
  }
  if (WindowsNotificationPostComDelayMs() > 0) {
    Sleep(static_cast<DWORD>(WindowsNotificationPostComDelayMs()));
  }
  const int exit_code = actions.run_flutter();
  host->Shutdown();
  return exit_code;
}
