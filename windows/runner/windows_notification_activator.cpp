#include "windows_notification_activator.h"

#include <windows.h>

#include <notificationactivationcallback.h>

#include <new>

#include "windows_notification_instance_coordinator.h"
#include "windows_notification_protocol.h"

namespace {

// STA 消息窗口内部消息/定时器 ID（不与 host.h 的 UI dispatch 消息同段）。
constexpr UINT kStaMsgPumpStarted = WM_APP + 0x100;
constexpr UINT kStaMsgRelayActivationDone = WM_APP + 0x101;
constexpr UINT_PTR kStaTimerRelayDrain = 1;
constexpr UINT_PTR kStaTimerRelayMaxLifetime = 2;
constexpr wchar_t kStaWindowClassName[] = L"OmllNotificationStaWindow";

// Shutdown 等待在途 Activate 释放的上界：sink 只做「入队 + post」，正常毫秒
// 级返回；上界只是防御性兜底，超时不再阻塞进程退出。
constexpr DWORD kInFlightDrainWaitMs = 10000;

// ── COM activator ──────────────────────────────────────────────────────

class ActivatorImpl : public INotificationActivationCallback {
 public:
  explicit ActivatorImpl(
      std::shared_ptr<WindowsNotificationActivatorShared> shared)
      : shared_(std::move(shared)) {}

  ULONG STDMETHODCALLTYPE AddRef() override {
    return InterlockedIncrement(&ref_count_);
  }
  ULONG STDMETHODCALLTYPE Release() override {
    const ULONG count = InterlockedDecrement(&ref_count_);
    if (count == 0) {
      delete this;
    }
    return count;
  }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** out) override {
    if (out == nullptr) {
      return E_POINTER;
    }
    if (riid == __uuidof(IUnknown) ||
        riid == __uuidof(INotificationActivationCallback)) {
      *out = static_cast<INotificationActivationCallback*>(this);
      AddRef();
      return S_OK;
    }
    *out = nullptr;
    return E_NOINTERFACE;
  }

  // 只验证 AUMID、长度与 UTF-16→UTF-8 转换；合法 payload 原样交给 sink，
  // 安全性由 Dart 侧严格 decoder 最终判定。任何输入异常都记录固定类别并
  // 返回稳定 HRESULT，不抛出、不记录 payload 本身。
  HRESULT STDMETHODCALLTYPE Activate(
      LPCWSTR app_user_model_id, LPCWSTR invoked_args,
      const NOTIFICATION_USER_INPUT_DATA* data, ULONG count) noexcept override {
    // 本地引用保活：宿主 Shutdown 期间 Release 与 shared_ 重置并发也安全。
    const std::shared_ptr<WindowsNotificationActivatorShared> shared = shared_;
    if (shared == nullptr || shared->stopping.load()) {
      return S_OK;
    }
    if (app_user_model_id == nullptr ||
        _wcsicmp(app_user_model_id, shared->aumid.c_str()) != 0) {
      return S_OK;
    }
    try {
      std::string payload;
      if (invoked_args != nullptr &&
          !WindowsNotificationUtf8FromUtf16(invoked_args, &payload)) {
        return S_OK;
      }
      if (payload.size() > kWindowsNotificationMaxPayloadBytes) {
        return S_OK;
      }
      shared->in_flight.fetch_add(1);
      try {
        shared->sink(payload);
      } catch (...) {
        // sink 契约是不抛；防御性兜底，保证 in_flight 计数总能回落。
      }
      shared->in_flight.fetch_sub(1);
      if (shared->notify_hwnd != nullptr) {
        PostMessageW(shared->notify_hwnd, kStaMsgRelayActivationDone, 0, 0);
      }
    } catch (...) {
    }
    return S_OK;
  }

 private:
  ~ActivatorImpl() = default;
  std::shared_ptr<WindowsNotificationActivatorShared> shared_;
  LONG ref_count_ = 1;
};

class ClassFactoryImpl : public IClassFactory {
 public:
  explicit ClassFactoryImpl(
      std::shared_ptr<WindowsNotificationActivatorShared> shared)
      : shared_(std::move(shared)) {}

  ULONG STDMETHODCALLTYPE AddRef() override {
    return InterlockedIncrement(&ref_count_);
  }
  ULONG STDMETHODCALLTYPE Release() override {
    const ULONG count = InterlockedDecrement(&ref_count_);
    if (count == 0) {
      delete this;
    }
    return count;
  }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** out) override {
    if (out == nullptr) {
      return E_POINTER;
    }
    if (riid == __uuidof(IUnknown) || riid == __uuidof(IClassFactory)) {
      *out = static_cast<IClassFactory*>(this);
      AddRef();
      return S_OK;
    }
    *out = nullptr;
    return E_NOINTERFACE;
  }

  HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown* outer, REFIID riid,
                                           void** out) override {
    if (out == nullptr) {
      return E_POINTER;
    }
    if (outer != nullptr) {
      return CLASS_E_NOAGGREGATION;
    }
    auto* activator = new (std::nothrow) ActivatorImpl(shared_);
    if (activator == nullptr) {
      return E_OUTOFMEMORY;
    }
    const HRESULT hr = activator->QueryInterface(riid, out);
    activator->Release();
    return hr;
  }

  HRESULT STDMETHODCALLTYPE LockServer(BOOL lock) override { return S_OK; }

 private:
  ~ClassFactoryImpl() = default;
  // 注册的 class object 必须存活到 CoRevokeClassObject；进程内引用由
  // shared_ptr 语义自然覆盖，不再额外泄漏裸引用。
  std::shared_ptr<WindowsNotificationActivatorShared> shared_;
  LONG ref_count_ = 1;
};

// ── STA 消息窗口（primary 后台线程 / relay 调用线程共用同一 wndproc）──

struct StaWindowContext {
  std::shared_ptr<WindowsNotificationActivatorShared> shared;
  HANDLE ready_event = nullptr;  // primary 专用；由调用方持有
  bool is_relay = false;
};

LRESULT CALLBACK StaWndProc(HWND hwnd, UINT message, WPARAM wparam,
                            LPARAM lparam) {
  auto* context = reinterpret_cast<StaWindowContext*>(
      GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (context == nullptr) {
    return DefWindowProcW(hwnd, message, wparam, lparam);
  }
  switch (message) {
    case kStaMsgPumpStarted:
      // ready 只在注册成功且本线程确实进入 dispatch 后才 Set：从消息里走
      // 一遭证明 pump 已可调度，而不是注册调用恰好返回。
      if (!context->is_relay && context->ready_event != nullptr) {
        SetEvent(context->ready_event);
      }
      return 0;
    case kStaMsgRelayActivationDone:
      if (context->is_relay) {
        if (context->shared->in_flight.load() == 0) {
          SetTimer(hwnd, kStaTimerRelayDrain,
                   kWindowsNotificationRelayDrainGraceMs, nullptr);
        }
        // in-flight 未清零时不动定时器：在途 callback 收尾会再 post 本消息。
      }
      return 0;
    case WM_TIMER:
      if (wparam == kStaTimerRelayDrain) {
        if (context->shared->in_flight.load() == 0) {
          PostQuitMessage(0);
        } else {
          // 静默期内又有 callback 进入：重挂 grace。
          SetTimer(hwnd, kStaTimerRelayDrain,
                   kWindowsNotificationRelayDrainGraceMs, nullptr);
        }
        return 0;
      }
      if (wparam == kStaTimerRelayMaxLifetime) {
        // 绝对生命周期上界：即使 callback 持续到达也必须退出，防止常驻。
        PostQuitMessage(0);
        return 0;
      }
      return 0;
    default:
      return DefWindowProcW(hwnd, message, wparam, lparam);
  }
}

HWND CreateStaWindow(StaWindowContext* context) {
  static bool class_registered = false;
  if (!class_registered) {
    WNDCLASSW wc = {};
    wc.lpfnWndProc = &StaWndProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = kStaWindowClassName;
    RegisterClassW(&wc);
    class_registered = true;
  }
  HWND window =
      CreateWindowExW(0, kStaWindowClassName, L"", WS_OVERLAPPED, 0, 0, 0, 0,
                      HWND_MESSAGE, nullptr, GetModuleHandleW(nullptr), nullptr);
  if (window != nullptr) {
    SetWindowLongPtrW(window, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(context));
  }
  return window;
}

// 注册记录存线程局部：revoke 必须由注册它的同一 apartment 完成，两个线程
// （primary STA / relay STA）各自的注册互不干扰。
thread_local DWORD t_registered_cookie = 0;
// 注册期工厂引用：COM 不承诺为注册对象持有强引用，revoke 前释放会导致
// RPCSS 创建实例时 use-after-free，因此引用保留到 revoke 之后。
thread_local IClassFactory* t_registered_factory = nullptr;

bool RegisterClassObjectOnCurrentThreadWithCookie(
    const std::shared_ptr<WindowsNotificationActivatorShared>& shared) {
  CLSID clsid = {};
  if (FAILED(CLSIDFromString(shared->clsid_braced.c_str(), &clsid))) {
    return false;
  }
  auto* factory = new (std::nothrow) ClassFactoryImpl(shared);
  if (factory == nullptr) {
    return false;
  }
  DWORD cookie = 0;
  const HRESULT hr = CoRegisterClassObject(clsid, factory, CLSCTX_LOCAL_SERVER,
                                           REGCLS_MULTIPLEUSE, &cookie);
  if (FAILED(hr)) {
    factory->Release();
    return false;
  }
  t_registered_cookie = cookie;
  t_registered_factory = factory;
  shared->class_registered.store(true);
  return true;
}

void RevokeClassObjectOnCurrentThread(
    const std::shared_ptr<WindowsNotificationActivatorShared>& shared) {
  if (shared->class_registered.exchange(false)) {
    CoRevokeClassObject(t_registered_cookie);
    t_registered_cookie = 0;
    if (t_registered_factory != nullptr) {
      t_registered_factory->Release();
      t_registered_factory = nullptr;
    }
  }
}

void RunStaMessageLoop() {
  MSG msg;
  while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }
}

// ── primary 后台 STA 线程 ──────────────────────────────────────────────

struct PrimaryThreadParams {
  std::shared_ptr<WindowsNotificationActivatorShared> shared;
  HANDLE ready_event = nullptr;
  HANDLE failed_event = nullptr;  // 注册失败时 Set，让 StartPrimary 早返回
};

}  // namespace

// ---------------------------------------------------------------------------
// pending queue / focus flag / worker 投递
// ---------------------------------------------------------------------------

// 队列满丢弃的固定诊断 token：pipe ACK 拒绝、STA 入队拒绝与 relay 晋升回填
// 溢出统一经 WindowsNotificationReportQueueFullToken 输出同一个固定 token，
// 字面量只有一处来源；token 不含任何动态内容，绝不记录 payload。
constexpr wchar_t kNativeActivationQueueFullToken[] =
    L"native_activation_queue_full\n";

void WindowsNotificationReportQueueFullToken() {
  OutputDebugStringW(kNativeActivationQueueFullToken);
}

bool WindowsNotificationPendingQueue::Push(const std::string& payload_utf8) {
  if (payload_utf8.size() > kWindowsNotificationMaxPayloadBytes) {
    return false;
  }
  std::lock_guard<std::mutex> lock(mutex_);
  if (entries_.size() >= 32) {
    // 队列满：拒绝新消息且不逐出正在等待的旧 payload（cold/rapid-cold 不
    // 允许只保留最后一次）；经调试通道留下固定诊断标记供事后定位。
    WindowsNotificationReportQueueFullToken();
    return false;
  }
  entries_.push_back(payload_utf8);
  return true;
}

std::vector<std::string> WindowsNotificationPendingQueue::TakeAll() {
  std::vector<std::string> drained;
  std::lock_guard<std::mutex> lock(mutex_);
  drained.swap(entries_);
  return drained;
}

size_t WindowsNotificationPendingQueue::depth() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return entries_.size();
}

bool WindowsNotificationFocusFlag::Request() {
  return !requested_.exchange(true);
}

bool WindowsNotificationFocusFlag::Consume() {
  return requested_.exchange(false);
}

bool WindowsNotificationFocusFlag::IsRequested() const {
  return requested_.load();
}

bool WindowsNotificationEnqueueActivationForUi(
    WindowsNotificationPendingQueue* queue, HWND ui_dispatch_hwnd,
    const std::string& payload_utf8) {
  if (queue == nullptr || !queue->Push(payload_utf8)) {
    return false;
  }
  if (ui_dispatch_hwnd != nullptr) {
    PostMessageW(ui_dispatch_hwnd, kWindowsNotificationUiMsgActivation, 0, 0);
  }
  return true;
}

void WindowsNotificationEnqueueFocusForUi(
    WindowsNotificationFocusFlag* flag, HWND ui_dispatch_hwnd) {
  if (flag == nullptr || !flag->Request()) {
    return;
  }
  if (ui_dispatch_hwnd != nullptr) {
    PostMessageW(ui_dispatch_hwnd, kWindowsNotificationUiMsgFocus, 0, 0);
  }
}

// ---------------------------------------------------------------------------
// 供测试直接构造 activator（进程内真实 Activate，不经 RPCSS 路由）
// ---------------------------------------------------------------------------

void* WindowsNotificationCreateActivatorForTest(
    const std::shared_ptr<WindowsNotificationActivatorShared>& shared) {
  if (shared == nullptr) {
    return nullptr;
  }
  auto* activator = new (std::nothrow) ActivatorImpl(shared);
  return activator;
}

// ---------------------------------------------------------------------------
// notification STA（primary 后台线程 / relay 调用线程 loop）
// ---------------------------------------------------------------------------

namespace {

DWORD WINAPI PrimaryThreadProcTrampoline(void* param) {
  auto* params = static_cast<PrimaryThreadParams*>(param);
  const std::shared_ptr<WindowsNotificationActivatorShared> shared =
      params->shared;
  const HANDLE ready_event = params->ready_event;
  const HANDLE failed_event = params->failed_event;
  delete params;

  const HRESULT init_hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(init_hr)) {
    SetEvent(failed_event);
    return 0;
  }
  StaWindowContext context;
  context.shared = shared;
  context.ready_event = ready_event;
  context.is_relay = false;
  HWND window = CreateStaWindow(&context);
  if (window != nullptr && RegisterClassObjectOnCurrentThreadWithCookie(shared)) {
    // posted 而非直接调用：ready 必须等 pump 真正开始 dispatch 才 Set。
    PostMessageW(window, kStaMsgPumpStarted, 0, 0);
    RunStaMessageLoop();
    // revoke 必须发生在注册它的同一 apartment；本线程退出 pump 后立即执行。
    RevokeClassObjectOnCurrentThread(shared);
  } else {
    SetEvent(failed_event);
  }
  if (window != nullptr) {
    DestroyWindow(window);
  }
  CoUninitialize();
  return 0;
}

}  // namespace

const char* WindowsNotificationStaHost::StartPrimary(
    const WindowsNotificationActivatorIdentity& identity, HANDLE ready_event,
    const std::function<void(const std::string&)>& sink) {
  if (shared_ != nullptr) {
    return "classObject";  // 已启动过；host 生命周期内只允许一次
  }
  shared_ = std::make_shared<WindowsNotificationActivatorShared>();
  shared_->aumid = identity.aumid;
  shared_->clsid_braced = identity.clsid_braced;
  ready_event_ = ready_event;
  shared_->sink = sink;

  auto* params = new (std::nothrow) PrimaryThreadParams();
  if (params == nullptr) {
    shared_.reset();
    return "threadStart";
  }
  params->shared = shared_;
  params->ready_event = ready_event;
  params->failed_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (params->failed_event == nullptr) {
    delete params;
    shared_.reset();
    return "threadStart";
  }
  thread_ = CreateThread(nullptr, 0, &PrimaryThreadProcTrampoline, params, 0,
                         &thread_id_);
  if (thread_ == nullptr) {
    CloseHandle(params->failed_event);
    delete params;
    shared_.reset();
    return "threadStart";
  }

  HANDLE waits[2] = {ready_event, params->failed_event};
  const DWORD wait =
      WaitForMultipleObjects(2, waits, FALSE,
                             kWindowsNotificationPrimaryReadyWaitMs);
  const bool ready = wait == WAIT_OBJECT_0;
  const bool failed = wait == WAIT_OBJECT_0 + 1;
  CloseHandle(params->failed_event);
  if (ready) {
    registered_ = true;
    return nullptr;
  }
  // 失败或超时：让线程走完自己的清理路径再返回固定 stage。
  if (thread_id_ != 0) {
    PostThreadMessageW(thread_id_, WM_QUIT, 0, 0);
  }
  WaitForSingleObject(thread_, kWindowsNotificationPrimaryReadyWaitMs);
  CloseHandle(thread_);
  thread_ = nullptr;
  shared_.reset();
  return failed ? "classObject" : "activatorReady";
}

void WindowsNotificationStaHost::Shutdown() {
  if (shutdown_done_) {
    return;
  }
  shutdown_done_ = true;
  if (shared_ != nullptr) {
    shared_->stopping.store(true);
  }
  // reset 先于 revoke：ready 只表达「当前 owner 已注册并 pump」，一旦进入
  // shutdown 就不能再让 relay 把本进程视为长期 owner。
  if (ready_event_ != nullptr) {
    ResetEvent(ready_event_);
  }
  if (thread_ != nullptr) {
    if (thread_id_ != 0) {
      PostThreadMessageW(thread_id_, WM_QUIT, 0, 0);
    }
    WaitForSingleObject(thread_, kWindowsNotificationPrimaryReadyWaitMs);
    CloseHandle(thread_);
    thread_ = nullptr;
  }
  if (shared_ != nullptr) {
    // 等待在途 Activate 释放后再放弃引用：sink 持有的宿主状态（queue/IPC）
    // 在这之后才允许销毁，防止 use-after-free。
    const ULONGLONG deadline = GetTickCount64() + kInFlightDrainWaitMs;
    while (shared_->in_flight.load() > 0 && GetTickCount64() < deadline) {
      Sleep(10);
    }
  }
  registered_ = false;
  shared_.reset();
}

int WindowsNotificationRunRelayStaLoop(
    const WindowsNotificationActivatorIdentity& identity,
    const std::function<void(const std::string&)>& sink,
    const std::function<void(
        std::shared_ptr<WindowsNotificationActivatorShared>)>& shared_sink) {
  try {
    auto shared = std::make_shared<WindowsNotificationActivatorShared>();
    shared->aumid = identity.aumid;
    shared->clsid_braced = identity.clsid_braced;
    shared->sink = sink;
    if (shared_sink != nullptr) {
      // 尽早交出引用：宿主/测试在 class_registered 置位后即可直接构造
      // activator 驱动 Activate。
      shared_sink(shared);
    }

    StaWindowContext context;
    context.shared = shared;
    context.is_relay = true;
    HWND window = CreateStaWindow(&context);
    if (window == nullptr) {
      return 1;
    }
    shared->notify_hwnd = window;
    // drain grace 从注册时刻就开始计：无点击的 relay（点击已被长期 owner
    // 接走）在静默期后立即退出，不必等绝对上界。
    SetTimer(window, kStaTimerRelayDrain, kWindowsNotificationRelayDrainGraceMs,
             nullptr);
    SetTimer(window, kStaTimerRelayMaxLifetime,
             kWindowsNotificationRelayMaxLifetimeMs, nullptr);
    if (!RegisterClassObjectOnCurrentThreadWithCookie(shared)) {
      KillTimer(window, kStaTimerRelayDrain);
      KillTimer(window, kStaTimerRelayMaxLifetime);
      DestroyWindow(window);
      return 1;
    }
    RunStaMessageLoop();
    KillTimer(window, kStaTimerRelayDrain);
    KillTimer(window, kStaTimerRelayMaxLifetime);
    RevokeClassObjectOnCurrentThread(shared);
    shared->stopping.store(true);
    DestroyWindow(window);
    return 0;
  } catch (...) {
    // relay 的最外层 catch-all：任何异常都不能带着 class object 泄漏。
    return 1;
  }
}
