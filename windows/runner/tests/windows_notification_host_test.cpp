// Windows 通知宿主原生测试：断言式覆盖各模块的外部契约。自写 main，
// 不引入 gtest；非零退出码表示存在失败用例。
//
// 额外模式：--verify-product-registration <exe路径>
//   只读回读产品注册（快捷方式 AUMID/VT_CLSID、LocalServer32 双值、
//   AppUserModelId 键），供产品注册回读脚本使用；不写任何注册表/文件。
// 额外模式：--probe-live-primary
//   向产品固定 pipe 发送一条 activateWindow 探测帧并校验 ACK status=0，
//   用于确认运行中 primary 的宿主与 pipe server 健康；单次连接不重试，
//   不写任何注册表/文件，也不参与选主。
// 额外模式：--emit-queue-full-token
//   内部辅助：把队列填满后触发一次满分支拒绝，供父进程以调试器身份
//   捕获 OutputDebugStringW 输出，验证固定诊断 token 存在。

#include <windows.h>

#include <notificationactivationcallback.h>

#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/method_result.h>
#include <flutter/standard_method_codec.h>

#include <knownfolders.h>
#include <objbase.h>
#include <propkey.h>
#include <propvarutil.h>
#include <propsys.h>
#include <shlobj.h>
#include <shobjidl.h>

#include <atomic>
#include <cstdio>
#include <cstring>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <wrl/client.h>

#include "../windows_notification_activator.h"
#include "../windows_notification_host.h"
#include "../windows_notification_instance_coordinator.h"
#include "../windows_notification_protocol.h"
#include "../windows_notification_registration.h"
#include "../windows_notification_toast.h"

// —— 测试专用身份：绝不与产品身份相同，也避开一切已使用过的 AUMID/CLSID。
constexpr wchar_t kTestAumid[] = L"YuzuShiki.OmllNotifHostTest";
constexpr wchar_t kTestClsidBraced[] = L"{D8F3C2A1-4B57-4E92-9A6C-3F10B7D2E5A4}";

namespace {

// ---------------------------------------------------------------------------
// 断言与基础 helper
// ---------------------------------------------------------------------------

int g_failures = 0;
int g_checks = 0;

void Check(bool condition, const std::string& description) {
  ++g_checks;
  std::printf("[%s] %s\n", condition ? "PASS" : "FAIL", description.c_str());
  std::fflush(stdout);
  if (!condition) {
    ++g_failures;
  }
}

std::wstring UniqueKernelSuffix() {
  wchar_t buffer[64] = {};
  swprintf_s(buffer, L".t%lu", static_cast<unsigned long>(GetCurrentProcessId()));
  return buffer;
}

std::wstring TestInstanceMutexName() {
  return std::wstring(L"Local\\OmllNotifHostTest") + UniqueKernelSuffix() +
         L".Instance";
}
std::wstring TestLeaseMutexName() {
  return std::wstring(L"Local\\OmllNotifHostTest") + UniqueKernelSuffix() +
         L".Lease";
}
std::wstring TestReadyEventName() {
  return std::wstring(L"Local\\OmllNotifHostTest") + UniqueKernelSuffix() +
         L".Ready";
}
std::wstring TestPipeName() {
  return std::wstring(L"\\\\.\\pipe\\OmllNotifHostTest") + UniqueKernelSuffix() +
         L".v1";
}

WindowsNotificationHostOverrides TestOverrides(
    const std::wstring& mutex_name, const std::wstring& lease_name,
    const std::wstring& ready_name, const std::wstring& pipe_name) {
  WindowsNotificationHostOverrides overrides;
  overrides.instance_mutex_name = mutex_name.c_str();
  overrides.lease_mutex_name = lease_name.c_str();
  overrides.ready_event_name = ready_name.c_str();
  overrides.pipe_name = pipe_name.c_str();
  overrides.aumid = kTestAumid;
  overrides.clsid_braced = kTestClsidBraced;
  overrides.suppress_identity_registration = true;
  return overrides;
}

// 在当前线程 pump 一段时间的消息（hidden window 的 dispatch 依赖它）。
void PumpMessagesFor(DWORD duration_ms,
                     const std::function<bool()>& done = nullptr) {
  const ULONGLONG deadline = GetTickCount64() + duration_ms;
  for (;;) {
    MSG msg;
    while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&msg);
      DispatchMessageW(&msg);
    }
    if (done && done()) {
      return;
    }
    const ULONGLONG now = GetTickCount64();
    if (now >= deadline) {
      return;
    }
    MsgWaitForMultipleObjects(0, nullptr, FALSE,
                              static_cast<DWORD>(deadline - now), QS_ALLINPUT);
  }
}

class ScopedHandle {
 public:
  explicit ScopedHandle(HANDLE handle = nullptr) : handle_(handle) {}
  ~ScopedHandle() { Reset(); }
  HANDLE Get() const { return handle_; }
  void Reset(HANDLE handle = nullptr) {
    if (handle_ != nullptr && handle_ != INVALID_HANDLE_VALUE) {
      CloseHandle(handle_);
    }
    handle_ = handle;
  }
  ScopedHandle(const ScopedHandle&) = delete;
  ScopedHandle& operator=(const ScopedHandle&) = delete;

 private:
  HANDLE handle_ = nullptr;
};

// ---------------------------------------------------------------------------
// -Embedding token 解析
// ---------------------------------------------------------------------------

std::vector<std::wstring> Args(std::initializer_list<const wchar_t*> items) {
  std::vector<std::wstring> out;
  out.reserve(items.size());
  for (const wchar_t* item : items) {
    out.push_back(item);
  }
  return out;
}

void TestEmbeddingTokenParsing() {
  std::printf("== -Embedding token 解析 ==\n");
  Check(WindowsNotificationCommandLineHasEmbeddingToken(Args({L"-Embedding"})),
        "独立 token -Embedding 识别");
  Check(WindowsNotificationCommandLineHasEmbeddingToken(Args({L"/Embedding"})),
        "独立 token /Embedding 识别");
  Check(WindowsNotificationCommandLineHasEmbeddingToken(
            Args({L"other", L"-embedding"})),
        "大小写不敏感匹配");
  Check(WindowsNotificationCommandLineHasEmbeddingToken(
            Args({L"/EMBEDDING", L"--flag"})),
        "混合大小写 + 其他参数共存");
  Check(!WindowsNotificationCommandLineHasEmbeddingToken(
            Args({L"--Embedding"})),
        "--Embedding 不是独立 -Embedding token");
  Check(!WindowsNotificationCommandLineHasEmbeddingToken(
            Args({L"-EmbeddingX"})),
        "-EmbeddingX 不做子串匹配");
  Check(!WindowsNotificationCommandLineHasEmbeddingToken(
            Args({L"x/Embedding"})),
        "x/Embedding 不做子串匹配");
  Check(!WindowsNotificationCommandLineHasEmbeddingToken(
            Args({L"-Embedding=1"})),
        "-Embedding=1 带Suffix 拒绝");
  Check(!WindowsNotificationCommandLineHasEmbeddingToken(Args({L"-Embed"})),
        "前缀相似 token 拒绝");
  Check(!WindowsNotificationCommandLineHasEmbeddingToken({}),
        "空参数表不是 embedding 启动");
}

// ---------------------------------------------------------------------------
// 模式决策
// ---------------------------------------------------------------------------

void TestModeDecision() {
  std::printf("== primary/relay/manual secondary 模式决策 ==\n");
  const std::wstring mutex_name = TestInstanceMutexName();

  const WindowsNotificationInstanceClaim primary =
      WindowsNotificationClaimInstance(Args({L"--dart-flag"}), mutex_name.c_str());
  Check(primary.mode == WindowsNotificationHostMode::kPrimary &&
            primary.instance_mutex != nullptr,
        "mutex 空闲时选为 primary 且持有句柄");
  // 模拟另一实例：本测试进程再开一个同 mutex，模拟已存在 primary。
  ScopedHandle existing(
      CreateMutexW(nullptr, FALSE, mutex_name.c_str()));
  const WindowsNotificationInstanceClaim relay = WindowsNotificationClaimInstance(
      Args({L"-Embedding"}), mutex_name.c_str());
  Check(relay.mode == WindowsNotificationHostMode::kActivationRelay &&
            relay.instance_mutex != nullptr,
        "mutex 已存在 + -Embedding → activationRelay");
  const WindowsNotificationInstanceClaim secondary =
      WindowsNotificationClaimInstance(Args({L"--dart-flag"}), mutex_name.c_str());
  Check(secondary.mode == WindowsNotificationHostMode::kManualSecondary &&
            secondary.instance_mutex != nullptr,
        "mutex 已存在且无 embedding → manualSecondary");
  if (primary.instance_mutex != nullptr) CloseHandle(primary.instance_mutex);
  if (relay.instance_mutex != nullptr) CloseHandle(relay.instance_mutex);
  if (secondary.instance_mutex != nullptr) CloseHandle(secondary.instance_mutex);
}

// ---------------------------------------------------------------------------
// ready event 语义
// ---------------------------------------------------------------------------

void TestReadyEventSemantics() {
  std::printf("== manual-reset ready event 语义 ==\n");
  const std::wstring name = TestReadyEventName();
  ScopedHandle first_owner(WindowsNotificationOpenReadyEventAsOwner(name.c_str()));
  Check(first_owner.Get() != nullptr, "owner 可创建/打开 ready event");
  Check(!WindowsNotificationIsReadyEventSignaled(first_owner.Get()),
        "新 owner 打开后事件为非 signaled（初始复位）");

  WindowsNotificationSetReadyEvent(first_owner.Get());
  Check(WindowsNotificationIsReadyEventSignaled(first_owner.Get()),
        "长期 owner 注册并 pump 后 SetEvent");

  // 模拟上一任 owner 遗留 signaled：第二个 owner 打开时必须复位。
  ScopedHandle new_owner(WindowsNotificationOpenReadyEventAsOwner(name.c_str()));
  Check(new_owner.Get() != nullptr && first_owner.Get() != nullptr,
        "继任 owner 可打开同一命名事件");
  Check(!WindowsNotificationIsReadyEventSignaled(new_owner.Get()),
        "新 owner 复位上一任遗留的 signaled 状态");
  Check(!WindowsNotificationIsReadyEventSignaled(first_owner.Get()),
        "复位对所有句柄可见（同一 kernel object）");

  WindowsNotificationSetReadyEvent(new_owner.Get());
  WindowsNotificationResetReadyEvent(new_owner.Get());
  Check(!WindowsNotificationIsReadyEventSignaled(new_owner.Get()),
        "shutdown 在 revoke 前复位事件");
}

// ---------------------------------------------------------------------------
// pipe DACL
// ---------------------------------------------------------------------------

bool SidEquals(const std::vector<unsigned char>& a, PSID b) {
  return a.size() > 0 && b != nullptr &&
         EqualSid(reinterpret_cast<PSID>(const_cast<unsigned char*>(a.data())),
                  b);
}

void TestPipeSecurity() {
  std::printf("== pipe 显式 DACL（当前 user + LocalSystem）==\n");
  WindowsNotificationPipeSecurity security;
  Check(WindowsNotificationBuildPipeSecurity(GetCurrentProcessToken(), &security),
        "用当前进程 token 构造 DACL 成功");

  BOOL present = FALSE;
  BOOL defaulted = FALSE;
  PACL acl = nullptr;
  BOOL ok = GetSecurityDescriptorDacl(security.sa.lpSecurityDescriptor, &present,
                                      &acl, &defaulted);
  Check(ok && present && acl != nullptr, "安全描述符带 DACL");

  if (ok && present && acl != nullptr) {
    ACL_SIZE_INFORMATION info = {};
    GetAclInformation(acl, &info, sizeof(info), AclSizeInformation);
    Check(info.AceCount == 2, "DACL 恰好两条 ACE（user + LocalSystem）");

    // 取当前 user SID 与 LocalSystem SID 作对照。
    HANDLE token = nullptr;
    OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token);
    DWORD size = 0;
    GetTokenInformation(token, TokenUser, nullptr, 0, &size);
    std::vector<unsigned char> user_buffer(size, 0);
    GetTokenInformation(token, TokenUser, user_buffer.data(), size, &size);
    auto* user = reinterpret_cast<TOKEN_USER*>(user_buffer.data());
    std::vector<unsigned char> expected_user(
        GetLengthSid(user->User.Sid));
    CopySid(static_cast<DWORD>(expected_user.size()),
            reinterpret_cast<PSID>(expected_user.data()), user->User.Sid);
    CloseHandle(token);

    std::vector<unsigned char> system_sid(SECURITY_MAX_SID_SIZE);
    DWORD system_size = SECURITY_MAX_SID_SIZE;
    CreateWellKnownSid(WinLocalSystemSid, nullptr,
                       reinterpret_cast<PSID>(system_sid.data()), &system_size);

    bool found_user = false;
    bool found_system = false;
    bool all_grant = true;
    for (DWORD i = 0; i < info.AceCount; ++i) {
      void* ace = nullptr;
      if (GetAce(acl, i, &ace)) {
        auto* access = static_cast<ACCESS_ALLOWED_ACE*>(ace);
        if (access->Header.AceType != ACCESS_ALLOWED_ACE_TYPE) {
          all_grant = false;
        }
        PSID sid = reinterpret_cast<PSID>(&access->SidStart);
        if (SidEquals(expected_user, sid)) {
          found_user = true;
        }
        if (SidEquals(system_sid, sid)) {
          found_system = true;
        }
      }
    }
    Check(all_grant, "全部 ACE 都是允许访问（无拒绝项）");
    Check(found_user, "当前 logon user SID 被授权");
    Check(found_system, "LocalSystem SID 被授权");
  }

  // 失败路径：无效 token → 拒绝构造，调用方据此标记 unavailable。
  WindowsNotificationPipeSecurity bad;
  Check(!WindowsNotificationBuildPipeSecurity(
            reinterpret_cast<HANDLE>(0x1234), &bad),
        "无效 token 时 DACL 构造失败（不退回宽松 ACL）");

  // pipe server 用无效 token 启动失败；调用方仍持有 instance mutex。
  const std::wstring mutex_name = TestInstanceMutexName();
  ScopedHandle mutex(CreateMutexW(nullptr, FALSE, mutex_name.c_str()));
  WindowsNotificationPipeServer server;
  std::atomic<bool> stopping{false};
  Check(!server.Start(
            [](uint16_t, const std::vector<unsigned char>&) {
              return kWindowsNotificationAckAccepted;
            },
            &stopping, TestPipeName().c_str(),
            reinterpret_cast<HANDLE>(0x1234)),
        "DACL 构造失败时 pipe server 启动失败");
  Check(mutex.Get() != nullptr &&
            WaitForSingleObject(mutex.Get(), 0) == WAIT_OBJECT_0,
        "失败后 instance mutex 仍由本进程持有（唯一 Flutter owner 不受影响）");
  ReleaseMutex(mutex.Get());
}

// ---------------------------------------------------------------------------
// v1 frame 协议（round-trip 与拒绝）
// ---------------------------------------------------------------------------

const unsigned char* U8(const std::string& text) {
  return reinterpret_cast<const unsigned char*>(text.data());
}

std::vector<unsigned char> MutateFrame(std::vector<unsigned char> frame,
                                       size_t offset, unsigned char value) {
  frame[offset] = value;
  return frame;
}

void TestFrameProtocol() {
  std::printf("== v1 frame round-trip 与拒绝 ==\n");
  const std::string ascii = "omll|test|ascii";
  // 「中文载荷|通知点击测试」的显式 UTF-8 字节（文件保持 ASCII 安全）。
  const std::string chinese =
      std::string("\xE4\xB8\xAD\xE6\x96\x87\xE8\xBD\xBD\xE8\x8D\xA7|"
                  "\xE9\x80\x9A\xE7\x9F\xA5\xE7\x82\xB9\xE5\x87\xBB\xE6\xB5\x8B"
                  "\xE8\xAF\x95");
  const std::string boundary(kWindowsNotificationMaxPayloadBytes, 'B');
  const std::string overlong(kWindowsNotificationMaxPayloadBytes + 1, 'L');
  const std::string bad_utf8 = "omll|\xFF\xFE\x28";

  // round-trip。
  struct RoundTripCase {
    const char* name;
    uint16_t kind;
    const std::string& payload;
  };
  for (const RoundTripCase& entry :
       {RoundTripCase{"ascii", kWindowsNotificationKindActivation, ascii},
        RoundTripCase{"chinese", kWindowsNotificationKindActivation, chinese},
        RoundTripCase{"boundary1024", kWindowsNotificationKindActivation,
                      boundary},
        RoundTripCase{"focus-empty", kWindowsNotificationKindActivateWindow,
                      std::string()}}) {
    const std::vector<unsigned char> frame =
        WindowsNotificationEncodeFrame(entry.kind, U8(entry.payload),
                                       entry.payload.size());
    WindowsNotificationDecodedFrame decoded;
    const char* reason = "";
    const WindowsNotificationFrameDecodeStatus status =
        WindowsNotificationDecodeFrame(frame.data(), frame.size(), &decoded,
                                       &reason);
    const bool payload_ok =
        decoded.payload.size() == entry.payload.size() &&
        (entry.payload.empty() ||
         std::memcmp(decoded.payload.data(), entry.payload.data(),
                     entry.payload.size()) == 0);
    Check(status == WindowsNotificationFrameDecodeStatus::kOk &&
              decoded.kind == entry.kind && payload_ok,
          std::string("round-trip: ") + entry.name);
  }

  // 拒绝用例。
  struct RejectCase {
    const char* name;
    std::vector<unsigned char> frame;
    WindowsNotificationFrameDecodeStatus expected;
  };
  std::vector<RejectCase> cases;
  {
    std::vector<unsigned char> f = WindowsNotificationEncodeFrame(
        kWindowsNotificationKindActivation, U8(ascii), ascii.size());
    cases.push_back({"badMagic", MutateFrame(f, 0, 'X'),
                     WindowsNotificationFrameDecodeStatus::kBadMagic});
  }
  {
    std::vector<unsigned char> f = WindowsNotificationEncodeFrame(
        kWindowsNotificationKindActivation, U8(ascii), ascii.size());
    f[4] = 0x02;
    cases.push_back({"unknownVersion", f,
                     WindowsNotificationFrameDecodeStatus::kBadVersion});
  }
  {
    std::vector<unsigned char> f = WindowsNotificationEncodeFrame(
        kWindowsNotificationKindActivation, U8(ascii), ascii.size());
    f[6] = 0x09;
    cases.push_back({"unknownKind", f,
                     WindowsNotificationFrameDecodeStatus::kBadKind});
  }
  cases.push_back({"payloadTooLong",
                   WindowsNotificationEncodeFrame(kWindowsNotificationKindActivation,
                                                  U8(overlong), overlong.size()),
                   WindowsNotificationFrameDecodeStatus::kPayloadTooLong});
  {
    std::vector<unsigned char> f = WindowsNotificationEncodeFrame(
        kWindowsNotificationKindActivation, U8(ascii), 100);
    f.resize(kWindowsNotificationFrameHeaderSize + 50);
    cases.push_back({"truncated", f,
                     WindowsNotificationFrameDecodeStatus::kLengthMismatch});
  }
  cases.push_back({"focusWithPayload",
                   WindowsNotificationEncodeFrame(kWindowsNotificationKindActivateWindow,
                                                  U8("abcde"), 5),
                   WindowsNotificationFrameDecodeStatus::kFocusWithPayload});
  cases.push_back({"badUtf8",
                   WindowsNotificationEncodeFrame(kWindowsNotificationKindActivation,
                                                  U8(bad_utf8), bad_utf8.size()),
                   WindowsNotificationFrameDecodeStatus::kBadUtf8});
  {
    // 变量名避开 small：rpcndr.h 把 small 定义成了宏。
    std::vector<unsigned char> tiny(kWindowsNotificationFrameHeaderSize - 1, 'X');
    cases.push_back({"headerTooShort", tiny,
                     WindowsNotificationFrameDecodeStatus::kTruncated});
  }
  for (const RejectCase& entry : cases) {
    WindowsNotificationDecodedFrame decoded;
    const char* reason = "";
    const WindowsNotificationFrameDecodeStatus status =
        WindowsNotificationDecodeFrame(entry.frame.data(), entry.frame.size(),
                                       &decoded, &reason);
    Check(status == entry.expected, std::string("拒绝: ") + entry.name);
  }

  // ACK round-trip 与坏 ACK。
  for (uint16_t status : {kWindowsNotificationAckAccepted,
                          kWindowsNotificationAckInvalidFrame,
                          kWindowsNotificationAckQueueFull,
                          kWindowsNotificationAckShuttingDown}) {
    const std::vector<unsigned char> ack =
        WindowsNotificationEncodeAck(status);
    uint16_t decoded = 0xFFFF;
    Check(WindowsNotificationDecodeAck(ack.data(), ack.size(), &decoded) &&
              decoded == status,
          "ACK round-trip status=" + std::to_string(status));
  }
  {
    const std::vector<unsigned char> ack = WindowsNotificationEncodeAck(0);
    uint16_t decoded = 0;
    Check(!WindowsNotificationDecodeAck(ack.data(), ack.size() - 1, &decoded),
          "截断 ACK 拒绝");
    std::vector<unsigned char> bad = ack;
    bad[0] = 'X';
    Check(!WindowsNotificationDecodeAck(bad.data(), bad.size(), &decoded),
          "坏 magic ACK 拒绝");
  }
}

// ---------------------------------------------------------------------------
// FIFO 32 queue 与 focus 合并（含并发入队）
// ---------------------------------------------------------------------------

void TestQueueAndFocus() {
  std::printf("== FIFO 32 queue、UTF-8 上限与 focus 合并 ==\n");
  WindowsNotificationPendingQueue queue;
  for (int i = 0; i < 40; ++i) {
    queue.Push("payload-" + std::to_string(i));
  }
  Check(queue.depth() == 32, "并发前容量上界 32（第 33 条起拒绝）");
  const std::vector<std::string> drained = queue.TakeAll();
  bool fifo_ok = drained.size() == 32;
  for (size_t i = 0; i < drained.size() && fifo_ok; ++i) {
    fifo_ok = drained[i] == "payload-" + std::to_string(i);
  }
  Check(fifo_ok, "TakeAll 按 FIFO 顺序返回且不逐出旧 payload");
  Check(queue.depth() == 0 && queue.TakeAll().empty(),
        "TakeAll 原子清空，再次取走为空");

  Check(!queue.Push(std::string(kWindowsNotificationMaxPayloadBytes + 1, 'X')),
        "超长 payload 入队被拒绝");
  Check(queue.depth() == 0, "超长 payload 未进入队列");

  // 并发入队：8 线程各推 8 条（共 64），恰好 32 条被接受且每线程保持 FIFO。
  WindowsNotificationPendingQueue concurrent_queue;
  std::vector<std::thread> workers;
  std::atomic<int> accepted{0};
  for (int t = 0; t < 8; ++t) {
    workers.emplace_back([t, &concurrent_queue, &accepted]() {
      for (int i = 0; i < 8; ++i) {
        if (concurrent_queue.Push("t" + std::to_string(t) + "-" +
                                  std::to_string(i))) {
          accepted.fetch_add(1);
        }
      }
    });
  }
  for (std::thread& worker : workers) {
    worker.join();
  }
  Check(accepted.load() == 32, "并发下队列仍恰好接受 32 条");
  const std::vector<std::string> all = concurrent_queue.TakeAll();
  bool per_thread_fifo = all.size() == 32;
  std::vector<int> next_index(8, 0);
  for (const std::string& entry : all) {
    const size_t dash = entry.find('-');
    const int thread = std::stoi(entry.substr(1, dash - 1));
    const int index = std::stoi(entry.substr(dash + 1));
    if (index != next_index[thread]) {
      per_thread_fifo = false;
      break;
    }
    ++next_index[thread];
  }
  Check(per_thread_fifo, "并发入队每线程仍保持 FIFO 顺序");

  WindowsNotificationFocusFlag flag;
  flag.Request();
  flag.Request();
  flag.Request();
  Check(flag.Consume() && !flag.Consume(),
        "多次 activateWindow 合并为单个待处理 focus 标志");
}

// ---------------------------------------------------------------------------
// 队列满诊断 token（经调试通道捕获 OutputDebugStringW）
// ---------------------------------------------------------------------------

// 与 windows_notification_activator.cpp 中 Push 满分支输出的固定标记一致；
// 窄字节版本供旧式 ANSI 调试事件形态匹配（token 本身是纯 ASCII）。
constexpr wchar_t kQueueFullTokenNeedle[] = L"native_activation_queue_full";
constexpr char kQueueFullTokenNeedleNarrow[] = "native_activation_queue_full";

// 子进程入口：把队列填满后再推一条，让 Push 的满分支真实执行一次诊断
// 输出；退出码只反映入队前置条件是否成立，token 捕获由父进程完成。
int EmitQueueFullToken() {
  WindowsNotificationPendingQueue queue;
  for (int i = 0; i < 32; ++i) {
    queue.Push("fill-" + std::to_string(i));
  }
  const bool filled = queue.depth() == 32;
  const bool rejected = !queue.Push("overflow");
  std::printf("emit_queue_full filled=%d rejected=%d\n", filled ? 1 : 0,
              rejected ? 1 : 0);
  std::fflush(stdout);
  return (filled && rejected) ? 0 : 1;
}

// 父进程以调试器身份运行子进程并捕获队列满分支的诊断输出：
// OutputDebugStringW 只有在被调试时才能程序化捕获（无调试器时走内核调试
// 通道，同进程内不可观测），因此这是验证「拒绝留下固定诊断标记」的唯一
// 黑盒手段。输出形态随系统与调试接口组合而异：本机旧式 WaitForDebugEvent
// 通道实测送达 ANSI 形态的 OUTPUT_DEBUG_STRING_EVENT；宽字符事件与
// DBG_PRINTEXCEPTION_C/WIDE_C 打印异常也一并兼容。全程有界超时，异常
// 路径杀掉子进程而非悬挂测试。
void TestQueueFullDiagnosticToken() {
  std::printf("== 队列满拒绝输出固定诊断 token ==\n");
  wchar_t self_path[MAX_PATH] = {};
  if (GetModuleFileNameW(nullptr, self_path, MAX_PATH) == 0) {
    Check(false, "诊断 token 测试无法取得自身路径");
    return;
  }
  std::wstring command_line =
      std::wstring(L"\"") + self_path + L"\" --emit-queue-full-token";
  STARTUPINFOW startup = {};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION child = {};
  if (!CreateProcessW(self_path, command_line.data(), nullptr, nullptr, FALSE,
                      DEBUG_ONLY_THIS_PROCESS, nullptr, nullptr, &startup,
                      &child)) {
    Check(false, "诊断 token 测试无法以调试模式启动子进程");
    return;
  }

  bool token_seen = false;
  bool child_exited = false;
  bool timed_out = false;
  const ULONGLONG deadline = GetTickCount64() + 20000;
  while (!child_exited && !timed_out) {
    DEBUG_EVENT event = {};
    if (GetTickCount64() >= deadline || !WaitForDebugEvent(&event, 3000)) {
      timed_out = true;
      break;
    }
    DWORD continue_status = DBG_CONTINUE;
    switch (event.dwDebugEventCode) {
      case CREATE_PROCESS_DEBUG_EVENT:
      case LOAD_DLL_DEBUG_EVENT: {
        // 映像/DLL 句柄由本调试循环负责关闭，否则文件被拖住无法覆盖。
        HANDLE file_handle =
            event.dwDebugEventCode == CREATE_PROCESS_DEBUG_EVENT
                ? event.u.CreateProcessInfo.hFile
                : event.u.LoadDll.hFile;
        if (file_handle != nullptr) {
          CloseHandle(file_handle);
        }
        break;
      }
      case EXIT_PROCESS_DEBUG_EVENT:
        child_exited = true;
        break;
      case OUTPUT_DEBUG_STRING_EVENT: {
        // 旧式 WaitForDebugEvent 调试通道把宽字符输出降级为 ANSI 事件送达
        //（fUnicode=0），宽字符形态只在部分系统/接口组合出现；token 是
        // 纯 ASCII，按事件声明的编码分别读取匹配。
        const auto& ods = event.u.DebugString;
        if (ods.lpDebugStringData == nullptr || ods.nDebugStringLength == 0 ||
            ods.nDebugStringLength > 4096) {
          break;
        }
        SIZE_T read = 0;
        if (ods.fUnicode) {
          std::vector<wchar_t> buffer(ods.nDebugStringLength + 1, L'\0');
          if (ReadProcessMemory(child.hProcess, ods.lpDebugStringData,
                                buffer.data(),
                                ods.nDebugStringLength * sizeof(wchar_t),
                                &read) &&
              std::wcsstr(buffer.data(), kQueueFullTokenNeedle) != nullptr) {
            token_seen = true;
          }
        } else {
          std::vector<char> buffer(ods.nDebugStringLength + 1, '\0');
          if (ReadProcessMemory(child.hProcess, ods.lpDebugStringData,
                                buffer.data(),
                                ods.nDebugStringLength * sizeof(char),
                                &read) &&
              std::strstr(buffer.data(), kQueueFullTokenNeedleNarrow) !=
                  nullptr) {
            token_seen = true;
          }
        }
        break;
      }
      case EXCEPTION_DEBUG_EVENT: {
        const EXCEPTION_RECORD& record = event.u.Exception.ExceptionRecord;
        constexpr DWORD kDbgPrintExceptionC = 0x40010006;
        constexpr DWORD kDbgPrintExceptionWideC = 0x4001000A;
        if (record.ExceptionCode == kDbgPrintExceptionC ||
            record.ExceptionCode == kDbgPrintExceptionWideC) {
          // 打印异常参数布局：[0]=宽窄标记、[1]=字符串地址、[2]=字符数。
          if (record.NumberParameters >= 3 &&
              record.ExceptionInformation[0] != 0 &&
              record.ExceptionInformation[2] > 0 &&
              record.ExceptionInformation[2] <= 4096) {
            std::vector<wchar_t> buffer(
                static_cast<size_t>(record.ExceptionInformation[2]) + 1,
                L'\0');
            SIZE_T read = 0;
            if (ReadProcessMemory(
                    child.hProcess,
                    reinterpret_cast<LPCVOID>(record.ExceptionInformation[1]),
                    buffer.data(),
                    static_cast<SIZE_T>(record.ExceptionInformation[2]) *
                        sizeof(wchar_t),
                    &read) &&
                std::wcsstr(buffer.data(), kQueueFullTokenNeedle) != nullptr) {
              token_seen = true;
            }
          }
          // 以已处理放行，OutputDebugStringW 在子进程中正常返回。
          continue_status = DBG_CONTINUE;
        } else if (record.ExceptionCode == EXCEPTION_BREAKPOINT) {
          // 初始断点/加载器断点是调试协议的一部分，吞掉而不交给子进程 SEH；
          // 其余异常原样交还子进程自身的 SEH/CRT 处理。
          continue_status = DBG_CONTINUE;
        } else {
          continue_status = DBG_EXCEPTION_NOT_HANDLED;
        }
        break;
      }
      default:
        break;
    }
    ContinueDebugEvent(event.dwProcessId, event.dwThreadId, continue_status);
  }

  if (timed_out) {
    // 有界清理：杀掉子进程并排空剩余调试事件，避免悬挂句柄。
    TerminateProcess(child.hProcess, 1);
    DEBUG_EVENT drain = {};
    while (WaitForDebugEvent(&drain, 2000)) {
      const bool done = drain.dwDebugEventCode == EXIT_PROCESS_DEBUG_EVENT;
      ContinueDebugEvent(drain.dwProcessId, drain.dwThreadId, DBG_CONTINUE);
      if (done) {
        break;
      }
    }
  }
  WaitForSingleObject(child.hProcess, 5000);
  CloseHandle(child.hThread);
  CloseHandle(child.hProcess);

  Check(token_seen, "队列满拒绝在调试通道留下固定诊断 token");
  Check(!timed_out, "诊断 token 子进程在有界时间内正常退出");
}

// ---------------------------------------------------------------------------
// XML escaping 与 show 参数校验
// ---------------------------------------------------------------------------

void TestXmlAndShowValidation() {
  std::printf("== XML escaping 与 notification 参数校验 ==\n");
  Check(WindowsNotificationXmlEscape("<&>\"'") ==
            "&lt;&amp;&gt;&quot;&apos;",
        "XmlEscape 覆盖 & < > 双引号 单引号");

  WindowsNotificationShowParams params;
  params.id = 10000;
  params.title = "标题<title>&\"";
  params.body = "正文";
  params.payload = "omll|payload|<>&";
  Check(WindowsNotificationValidateShowParams(params), "合法参数通过校验");
  const std::string xml = WindowsNotificationBuildToastXml(params);
  Check(xml.find("&lt;title&gt;&amp;") != std::string::npos &&
            xml.find("omll|payload|&lt;&gt;&amp;") != std::string::npos,
        "Toast XML 中 title/payload 均已转义");
  Check(xml.find("<toast launch=\"") == 0 &&
            xml.find("template=\"ToastGeneric\"") != std::string::npos,
        "Toast XML 固定 ToastGeneric 模板 + launch 根属性");
  Check(xml.find("<audio") == std::string::npos &&
            xml.find("scenario") == std::string::npos &&
            xml.find("src=\"") == std::string::npos,
        "Toast XML 不含 audio/scenario/图片");

  struct InvalidCase {
    const char* name;
    WindowsNotificationShowParams params;
  };
  const std::string title_129(129, 'T');
  const std::string title_128(128, 'T');
  const std::string body_513(513, 'B');
  const std::string body_512(512, 'B');
  const std::string payload_1025(1025, 'P');
  std::vector<InvalidCase> invalid;
  {
    WindowsNotificationShowParams p = params; p.id = 9999;
    invalid.push_back({"id 下界", p});
  }
  {
    WindowsNotificationShowParams p = params; p.id = 2147483647;
    invalid.push_back({"id 上界外", p});
  }
  {
    WindowsNotificationShowParams p = params; p.title.clear();
    invalid.push_back({"空 title", p});
  }
  {
    WindowsNotificationShowParams p = params; p.title = title_129;
    invalid.push_back({"title 129 字节", p});
  }
  {
    WindowsNotificationShowParams p = params; p.body.clear();
    invalid.push_back({"空 body", p});
  }
  {
    WindowsNotificationShowParams p = params; p.body = body_513;
    invalid.push_back({"body 513 字节", p});
  }
  {
    WindowsNotificationShowParams p = params; p.payload = payload_1025;
    invalid.push_back({"payload 1025 字节", p});
  }
  for (const InvalidCase& entry : invalid) {
    Check(!WindowsNotificationValidateShowParams(entry.params) &&
              WindowsNotificationBuildToastXml(entry.params).empty(),
          std::string("拒绝非法参数: ") + entry.name);
  }

  WindowsNotificationShowParams edges = params;
  edges.id = 2147483646;
  edges.title = title_128;
  edges.body = body_512;
  Check(WindowsNotificationValidateShowParams(edges),
        "边界值 id=2147483646/title=128/body=512 通过");
}

// ---------------------------------------------------------------------------
// 固定身份构造
// ---------------------------------------------------------------------------

void TestFixedIdentity() {
  std::printf("== 固定 AUMID/CLSID/shortcut/registry value 构造 ==\n");
  Check(wcscmp(kWindowsNotificationAumid, L"YuzuShiki.OhMyLlm") == 0,
        "AUMID 固定为 YuzuShiki.OhMyLlm");
  Check(wcscmp(kWindowsNotificationClsidBraced,
               L"{7E4B2C91-5D4A-4A8E-9F1B-2C6D3A80E751}") == 0,
        "CLSID 固定为 {7E4B2C91-5D4A-4A8E-9F1B-2C6D3A80E751}");
  Check(wcscmp(kWindowsNotificationShortcutName, L"Oh My LLM.lnk") == 0,
        "快捷方式文件名固定");
  Check(wcscmp(kWindowsNotificationInstanceMutexName,
               L"Local\\YuzuShiki.OhMyLlm.NotificationHost."
               L"7E4B2C915D4A4A8E9F1B2C6D3A80E751") == 0,
        "instance mutex 名固定");
  Check(wcscmp(kWindowsNotificationPipeName,
               L"\\\\.\\pipe\\YuzuShiki.OhMyLlm.NotificationHost.v1") == 0,
        "pipe 名固定为 v1");
  Check(strcmp(kWindowsNotificationChannelName,
               "yuzu.shiki.oh_my_llm/windows_notifications") == 0,
        "Flutter channel 名固定");

  const std::wstring exe = L"C:\\app dir\\oh_my_llm.exe";
  Check(WindowsNotificationLocalServer32DefaultValue(exe) ==
            L"\"C:\\app dir\\oh_my_llm.exe\"",
        "LocalServer32 默认值为带双引号无参数路径");
  Check(WindowsNotificationLocalServer32ServerExecutableValue(exe) == exe,
        "ServerExecutable 为不带引号同一路径");
  Check(WindowsNotificationLocalServer32KeyPath() ==
            L"Software\\Classes\\CLSID\\{7E4B2C91-5D4A-4A8E-9F1B-2C6D3A80E751}"
            L"\\LocalServer32",
        "LocalServer32 键路径固定");
  Check(WindowsNotificationAumidKeyPath() ==
            L"Software\\Classes\\AppUserModelId\\YuzuShiki.OhMyLlm",
        "AppUserModelId 键路径固定");
  Check(WindowsNotificationShortcutPath(L"C:\\Users\\u\\Programs") ==
            L"C:\\Users\\u\\Programs\\Oh My LLM.lnk",
        "快捷方式路径 = Programs 目录 + 固定文件名");

  // 实测锁定的时序常量：lease/pipe/relay 的边界值经过真实环境验证，
  // 改动它们等于重新设计竞态协调，必须显式评审。
  Check(kWindowsNotificationLeaseSliceWaitMs == 250 &&
            kWindowsNotificationPrimaryLeaseTotalWaitMs == 30000 &&
            kWindowsNotificationRelayLeaseTotalWaitMs == 3000 &&
            kWindowsNotificationPipeConnectTotalMs == 2000 &&
            kWindowsNotificationPipeAckWaitMs == 3000 &&
            kWindowsNotificationRelayDrainGraceMs == 1000 &&
            kWindowsNotificationRelayMaxLifetimeMs == 15000,
        "实测锁定的时序常量未被改动");

  Check(WindowsNotificationPreComDelayMs() == 0 &&
            WindowsNotificationPostComDelayMs() == 0,
        "默认竞态 delay 为 0（release/testing=OFF 构建无 delay）");
}

// ---------------------------------------------------------------------------
// 真实 pipe server/client 集成
// ---------------------------------------------------------------------------

void TestPipeServeLoop() {
  std::printf("== pipe server/client 真实 IO（含队列满与超长拒绝）==\n");
  const std::wstring pipe_name = TestPipeName();
  WindowsNotificationPipeServer server;
  std::atomic<bool> stopping{false};
  WindowsNotificationPendingQueue queue;
  WindowsNotificationFocusFlag flag;
  const HWND dispatch_hwnd = nullptr;  // 测试不 attach 窗口，仅验证入队

  server.Start(
      [&queue, &flag, dispatch_hwnd](
          uint16_t kind, const std::vector<unsigned char>& payload) {
        if (kind == kWindowsNotificationKindActivation) {
          const std::string text(reinterpret_cast<const char*>(payload.data()),
                                 payload.size());
          return WindowsNotificationEnqueueActivationForUi(&queue,
                                                           dispatch_hwnd, text)
                     ? kWindowsNotificationAckAccepted
                     : kWindowsNotificationAckQueueFull;
        }
        WindowsNotificationEnqueueFocusForUi(&flag, dispatch_hwnd);
        return kWindowsNotificationAckAccepted;
      },
      &stopping, pipe_name.c_str());
  Sleep(150);  // 等待 pipe 实例创建。

  const std::string valid = "omll|pipe|integration";
  {
    const WindowsNotificationPipeClientResult result =
        WindowsNotificationSendPipeFrame(pipe_name.c_str(),
                                         kWindowsNotificationKindActivation,
                                         U8(valid), valid.size());
    Check(result.delivered && result.ack_status == kWindowsNotificationAckAccepted,
          "合法 activation 帧经真实 pipe 送达并被接受");
    Check(queue.depth() == 1, "server 端 payload 已入队");
  }
  {
    const WindowsNotificationPipeClientResult result =
        WindowsNotificationSendPipeFrame(pipe_name.c_str(),
                                         kWindowsNotificationKindActivateWindow,
                                         nullptr, 0);
    Check(result.delivered && flag.Consume(),
          "合法 focus 空帧送达且只设置合并标志");
  }

  struct ExpectCase {
    const char* name;
    std::vector<unsigned char> frame;
    uint16_t expected;
  };
  std::vector<ExpectCase> cases;
  {
    std::vector<unsigned char> f = WindowsNotificationEncodeFrame(
        kWindowsNotificationKindActivation, U8(valid), valid.size());
    cases.push_back({"overPipe badMagic", MutateFrame(f, 0, 'X'),
                     kWindowsNotificationAckInvalidFrame});
  }
  {
    std::vector<unsigned char> f = WindowsNotificationEncodeFrame(
        kWindowsNotificationKindActivation, U8(valid), valid.size());
    f[4] = 0x07;
    cases.push_back({"overPipe unknownVersion", f,
                     kWindowsNotificationAckInvalidFrame});
  }
  {
    std::vector<unsigned char> raw(1600, 'X');
    std::memcpy(raw.data(), "OMLN", 4);
    const uint16_t version = 1;
    const uint16_t kind = 1;
    const uint32_t declared = static_cast<uint32_t>(raw.size() - 12);
    std::memcpy(raw.data() + 4, &version, 2);
    std::memcpy(raw.data() + 6, &kind, 2);
    std::memcpy(raw.data() + 8, &declared, 4);
    cases.push_back({"overPipe oversized1600", raw,
                     kWindowsNotificationAckInvalidFrame});
  }
  cases.push_back({"overPipe badUtf8",
                   WindowsNotificationEncodeFrame(kWindowsNotificationKindActivation,
                                                  U8("omll|\xFF\xFE"), 7),
                   kWindowsNotificationAckInvalidFrame});
  for (const ExpectCase& entry : cases) {
    const WindowsNotificationPipeClientResult result =
        WindowsNotificationSendPipeFrameBytes(pipe_name.c_str(), entry.frame);
    Check(result.ack_received && result.ack_status == entry.expected,
          std::string("真实 pipe 拒绝: ") + entry.name);
  }

  // 队列满：33 条合法帧，前 32 accepted、第 33 条 queueFull。
  queue.TakeAll();
  const std::string filler = "omll|pipe|filler";
  int accepted = 0;
  uint16_t last = 0xFFFF;
  for (int i = 0; i < 33; ++i) {
    const WindowsNotificationPipeClientResult result =
        WindowsNotificationSendPipeFrame(pipe_name.c_str(),
                                         kWindowsNotificationKindActivation,
                                         U8(filler), filler.size());
    last = result.ack_status;
    if (result.ack_status == kWindowsNotificationAckAccepted) {
      ++accepted;
    }
  }
  Check(accepted == 32 && last == kWindowsNotificationAckQueueFull,
        "真实 pipe 下队列满返回 queueFull 而非逐出旧 payload");

  stopping.store(true);
  server.Stop();
}

// ---------------------------------------------------------------------------
// worker 只 post UI dispatch
// ---------------------------------------------------------------------------

constexpr wchar_t kTestDispatchWindowClass[] = L"OmllNotifHostTestDispatch";

struct DispatchRecord {
  std::atomic<int> activation_messages{0};
  std::atomic<int> focus_messages{0};
};

LRESULT CALLBACK DispatchWndProc(HWND hwnd, UINT message, WPARAM wparam,
                                 LPARAM lparam) {
  auto* record = reinterpret_cast<DispatchRecord*>(GetWindowLongPtrW(
      hwnd, GWLP_USERDATA));
  if (record != nullptr) {
    if (message == kWindowsNotificationUiMsgActivation) {
      record->activation_messages.fetch_add(1);
    } else if (message == kWindowsNotificationUiMsgFocus) {
      record->focus_messages.fetch_add(1);
    }
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

void TestWorkerOnlyPostsUiDispatch() {
  std::printf("== worker 只 post UI dispatch（不直接调用 messenger/window）==\n");
  DispatchRecord record;
  WNDCLASSW wc = {};
  wc.lpfnWndProc = &DispatchWndProc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = kTestDispatchWindowClass;
  RegisterClassW(&wc);
  HWND window = CreateWindowExW(0, kTestDispatchWindowClass, L"test",
                                WS_OVERLAPPED, 0, 0, 0, 0, HWND_MESSAGE, nullptr,
                                wc.hInstance, &record);
  Check(window != nullptr, "测试 message-only 窗口可创建");
  // wndproc 从 GWLP_USERDATA 取计数器；lpParam 不会自动进入 USERDATA。
  SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(&record));

  WindowsNotificationPendingQueue queue;
  WindowsNotificationFocusFlag flag;
  std::thread worker([&window, &queue, &flag]() {
    WindowsNotificationEnqueueActivationForUi(&queue, window, "omll|dispatch|1");
    WindowsNotificationEnqueueActivationForUi(&queue, window, "omll|dispatch|2");
    WindowsNotificationEnqueueFocusForUi(&flag, window);
  });
  worker.join();

  Check(record.activation_messages.load() == 0 &&
            record.focus_messages.load() == 0,
        "未 pump 前不产生任何 UI 侧效果（纯 PostMessage 语义）");
  PumpMessagesFor(1000, [&record]() {
    return record.activation_messages.load() >= 2 &&
           record.focus_messages.load() >= 1;
  });
  Check(record.activation_messages.load() == 2,
        "两条 activation 各投递一条 UI dispatch message");
  Check(record.focus_messages.load() == 1,
        "focus 合并后只投递一条 UI dispatch message");
  Check(queue.depth() == 2, "payload 已加锁入队，等 UI 线程取走");
  DestroyWindow(window);
  UnregisterClassW(kTestDispatchWindowClass, wc.hInstance);
}

// ---------------------------------------------------------------------------
// notification STA 状态机（ready/register/revoke/shutdown 幂等）
// ---------------------------------------------------------------------------

void TestStaStateMachine() {
  std::printf("== notification STA 状态机与幂等 shutdown ==\n");
  const std::wstring ready_name = TestReadyEventName();
  ScopedHandle ready(WindowsNotificationOpenReadyEventAsOwner(ready_name.c_str()));
  WindowsNotificationStaHost host;
  std::atomic<int> sink_calls{0};
  const char* stage = host.StartPrimary(
      WindowsNotificationActivatorIdentity{kTestAumid, kTestClsidBraced},
      ready.Get(),
      [&sink_calls](const std::string&) { sink_calls.fetch_add(1); });
  Check(stage == nullptr && host.registered(),
        "primary STA 注册成功且 ready（返回固定 stage 为空）");
  Check(WindowsNotificationIsReadyEventSignaled(ready.Get()),
        "注册并开始 pump 后 ready event 被 Set");

  host.Shutdown();
  Check(!host.registered() &&
            !WindowsNotificationIsReadyEventSignaled(ready.Get()),
        "shutdown 在 revoke 前复位 ready 并完成 revoke");
  host.Shutdown();  // 幂等：不得崩溃或死锁。
  Check(true, "重复 Shutdown 幂等");
}

// ---------------------------------------------------------------------------
// in-flight callback 与 shutdown 竞态
// ---------------------------------------------------------------------------

void TestInflightShutdownRace() {
  std::printf("== in-flight callback 与 shutdown 竞态 ==\n");
  const std::wstring ready_name = TestReadyEventName();
  ScopedHandle ready(WindowsNotificationOpenReadyEventAsOwner(ready_name.c_str()));
  ScopedHandle entered(CreateEventW(nullptr, TRUE, FALSE, nullptr));
  ScopedHandle release(CreateEventW(nullptr, TRUE, FALSE, nullptr));
  // 放行事件：activator 线程等到 shutdown 完成后再做第二次 Activate，
  // 验证 COM 对象在宿主状态销毁后仍可安全调用。
  ScopedHandle shutdown_complete(CreateEventW(nullptr, TRUE, FALSE, nullptr));

  WindowsNotificationStaHost host;
  std::string captured;
  host.StartPrimary(
      WindowsNotificationActivatorIdentity{kTestAumid, kTestClsidBraced},
      ready.Get(),
      [&captured, &entered, &release](const std::string& payload) {
        captured = payload;
        SetEvent(entered.Get());
        // 模拟有界但缓慢的 callback：等待测试放行。
        WaitForSingleObject(release.Get(), 8000);
      });
  Check(host.registered(), "竞态测试 STA 就绪");

  // 直接构造与 STA class factory 同源共享状态的 activator，从独立线程调用
  // 真实 Activate：不经 RPCSS 路由，但走完全相同的 in-flight 计数与 sink。
  Microsoft::WRL::ComPtr<INotificationActivationCallback> callback;
  callback.Attach(static_cast<INotificationActivationCallback*>(
      WindowsNotificationCreateActivatorForTest(host.shared_for_test())));
  Check(callback != nullptr, "进程内 activator 可直接构造");

  std::thread activator_thread([&callback, &shutdown_complete]() {
    callback->Activate(kTestAumid, L"race-payload", nullptr, 0);
    WaitForSingleObject(shutdown_complete.Get(), 10000);
    callback->Activate(kTestAumid, L"after-shutdown", nullptr, 0);
  });

  Check(WaitForSingleObject(entered.Get(), 8000) == WAIT_OBJECT_0,
        "Activate 已进入 callback（in-flight lease 被持有）");

  // shutdown 与在途 callback 并发：join 必须等 callback 有界完成。
  ScopedHandle shutdown_done(CreateEventW(nullptr, TRUE, FALSE, nullptr));
  std::thread shutdown_thread([&host, &shutdown_done,
                               &shutdown_complete]() {
    host.Shutdown();
    SetEvent(shutdown_done.Get());
    SetEvent(shutdown_complete.Get());
  });
  Check(WaitForSingleObject(shutdown_done.Get(), 500) == WAIT_TIMEOUT,
        "shutdown 在 in-flight callback 完成前不销毁共享状态");

  SetEvent(release.Get());
  Check(WaitForSingleObject(shutdown_done.Get(), 10000) == WAIT_OBJECT_0,
        "callback 完成后 shutdown 正常收尾（无 use-after-free）");
  shutdown_thread.join();
  Check(captured == "race-payload", "在途 payload 完整交付");

  activator_thread.join();
  Check(true, "shutdown 后对仍存活的 activator 调用 Activate 安全返回");
}

// ---------------------------------------------------------------------------
// relay 短命 STA loop（真实 COM 注册 + 管道转发 + drain 退出）
// ---------------------------------------------------------------------------

void TestRelayStaLoop() {
  std::printf("== relay 短命 STA loop（注册/转发/drain 有界退出）==\n");
  const std::wstring pipe_name = TestPipeName();
  WindowsNotificationPipeServer server;
  std::atomic<bool> stopping{false};
  std::mutex delivered_mutex;
  std::vector<std::string> delivered;
  server.Start(
      [&delivered, &delivered_mutex](
          uint16_t kind, const std::vector<unsigned char>& payload) {
        if (kind == kWindowsNotificationKindActivation) {
          std::lock_guard<std::mutex> lock(delivered_mutex);
          delivered.push_back(
              std::string(reinterpret_cast<const char*>(payload.data()),
                          payload.size()));
        }
        return kWindowsNotificationAckAccepted;
      },
      &stopping, pipe_name.c_str());

  // relay loop 在独立线程（STA）运行；注册完成后测试用共享状态直接构造
  // activator 调用 Activate——真实注册/转发/drain 语义，不经 RPCSS 路由。
  std::mutex shared_mutex;
  std::shared_ptr<WindowsNotificationActivatorShared> relay_shared;
  std::atomic<int> relay_exit{-1};
  std::thread relay_thread([&]() {
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    relay_exit.store(WindowsNotificationRunRelayStaLoop(
        WindowsNotificationActivatorIdentity{kTestAumid, kTestClsidBraced},
        [&pipe_name](const std::string& payload) {
          WindowsNotificationSendPipeFrame(pipe_name.c_str(),
                                           kWindowsNotificationKindActivation,
                                           U8(payload), payload.size());
        },
        [&relay_shared, &shared_mutex](
            std::shared_ptr<WindowsNotificationActivatorShared> shared) {
          std::lock_guard<std::mutex> lock(shared_mutex);
          relay_shared = std::move(shared);
        }));
    CoUninitialize();
  });

  bool registered = false;
  for (int attempt = 0; attempt < 160 && !registered; ++attempt) {
    {
      std::lock_guard<std::mutex> lock(shared_mutex);
      registered = relay_shared != nullptr &&
                   relay_shared->class_registered.load();
    }
    if (!registered) {
      Sleep(25);
    }
  }
  Check(registered, "relay 短命 class object 注册成功（共享状态可见）");

  if (registered) {
    Microsoft::WRL::ComPtr<INotificationActivationCallback> callback;
    {
      std::lock_guard<std::mutex> lock(shared_mutex);
      callback.Attach(static_cast<INotificationActivationCallback*>(
          WindowsNotificationCreateActivatorForTest(relay_shared)));
    }
    if (callback != nullptr) {
      callback->Activate(kTestAumid, L"relay-click-1", nullptr, 0);
      callback->Activate(kTestAumid, L"relay-click-2", nullptr, 0);
    }
  }
  relay_thread.join();
  Check(relay_exit.load() == 0, "relay loop drain 后正常退出（非错误码）");
  {
    std::lock_guard<std::mutex> lock(delivered_mutex);
    Check(delivered.size() == 2 && delivered[0] == "relay-click-1" &&
              delivered[1] == "relay-click-2",
          "两次真实 Activate 的 payload 都经 pipe 按序送达 primary");
  }
  stopping.store(true);
  server.Stop();
}

// ---------------------------------------------------------------------------
// 进程编排 seam：relay / manual secondary 的 flutterStartCount==0 与晋升
// ---------------------------------------------------------------------------

struct FlutterCounter {
  std::atomic<int> starts{0};
  int operator()() {
    starts.fetch_add(1);
    return 77;
  }
};

void TestProcessSeamModes() {
  std::printf("== 进程编排 seam：relay/secondary 不启动 Flutter，primary 启动 ==\n");

  // 1) manual secondary：mutex 已存在 + pipe 可达 → 只发 activateWindow。
  {
    const std::wstring mutex_name = TestInstanceMutexName();
    const std::wstring pipe_name = TestPipeName();
    ScopedHandle existing(CreateMutexW(nullptr, FALSE, mutex_name.c_str()));
    WindowsNotificationPipeServer server;
    std::atomic<bool> stopping{false};
    std::atomic<int> activation_frames{0};
    std::atomic<int> focus_frames{0};
    server.Start(
        [&activation_frames, &focus_frames](
            uint16_t kind, const std::vector<unsigned char>&) {
          if (kind == kWindowsNotificationKindActivation) {
            activation_frames.fetch_add(1);
          } else {
            focus_frames.fetch_add(1);
          }
          return kWindowsNotificationAckAccepted;
        },
        &stopping, pipe_name.c_str());
    Sleep(150);

    FlutterCounter flutter;
    WindowsNotificationProcessActions actions;
    actions.run_flutter = std::ref(flutter);
    const int exit_code = WindowsNotificationRunProcess(
        Args({L"--dart-flag"}),
        actions,
        TestOverrides(mutex_name, TestLeaseMutexName(), TestReadyEventName(),
                      pipe_name));
    Check(exit_code == 0 && flutter.starts.load() == 0 &&
              focus_frames.load() == 1 && activation_frames.load() == 0,
          "manualSecondary 只发一条 activateWindow 且 flutterStart==0");
    stopping.store(true);
    server.Stop();
  }

  // 2) activationRelay：无点击 → drain 静默期后退出，不启动 Flutter。
  {
    const std::wstring mutex_name = TestInstanceMutexName();
    ScopedHandle existing(CreateMutexW(nullptr, FALSE, mutex_name.c_str()));
    FlutterCounter flutter;
    WindowsNotificationProcessActions actions;
    actions.run_flutter = std::ref(flutter);
    const int exit_code = WindowsNotificationRunProcess(
        Args({L"-Embedding"}), actions,
        TestOverrides(mutex_name, TestLeaseMutexName(), TestReadyEventName(),
                      TestPipeName()));
    Check(exit_code == 0 && flutter.starts.load() == 0,
          "activationRelay 无点击 drain 退出且 flutterStart==0");
  }

  // 3) primary：新会话选主成功 → 唯一一次 run_flutter，退出码透传。
  {
    FlutterCounter flutter;
    WindowsNotificationProcessActions actions;
    actions.run_flutter = std::ref(flutter);
    const int exit_code = WindowsNotificationRunProcess(
        Args({L"--dart-flag"}), actions,
        TestOverrides(TestInstanceMutexName(), TestLeaseMutexName(),
                      TestReadyEventName(), TestPipeName()));
    Check(exit_code == 77 && flutter.starts.load() == 1,
          "primary 恰好启动一次 Flutter 并透传退出码");
  }

  // 4) relay 晋升：primary 消失 + 投递失败 → 重新选主晋升为 primary。
  //    直接持有 host（与 RunProcess 相同顺序），从另一线程经宿主测试入口
  //    驱动一次真实 Activate；不经 RPCSS 路由。
  {
    const std::wstring mutex_name = TestInstanceMutexName();
    ScopedHandle existing(CreateMutexW(nullptr, FALSE, mutex_name.c_str()));
    std::atomic<int> starts{0};
    std::atomic<int> exit_code{0};
    std::atomic<WindowsNotificationHost*> host_published{nullptr};
    std::thread runner([&]() {
      CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
      auto host = WindowsNotificationHost::Start(
          Args({L"-Embedding"}),
          TestOverrides(mutex_name, TestLeaseMutexName(), TestReadyEventName(),
                        TestPipeName()));
      if (host == nullptr) {
        CoUninitialize();
        return;
      }
      host_published.store(host.get());
      // relay：注册短命 class object → pipe 投递失败捕获 payload → drain
      // → 重新选主晋升 → 与 wWinMain 相同顺序继续「启动 Flutter」。
      host->RunSecondaryMode();
      if (host->ShouldStartFlutter()) {
        starts.fetch_add(1);
        exit_code.store(55);
      }
      host->Shutdown();
      CoUninitialize();
    });
    std::thread clicker([&]() {
      for (int attempt = 0; attempt < 80; ++attempt) {
        WindowsNotificationHost* host = host_published.load();
        Microsoft::WRL::ComPtr<INotificationActivationCallback> callback;
        if (host != nullptr) {
          void* raw = host->CreateActivatorForTest();
          if (raw != nullptr) {
            callback.Attach(static_cast<INotificationActivationCallback*>(raw));
          }
        }
        if (callback != nullptr) {
          // primary 的 pipe 不存在 → 投递失败，payload 由 relay 捕获。
          callback->Activate(kTestAumid, L"promoted-payload", nullptr, 0);
          Sleep(100);
          existing.Reset();  // 旧 primary 退出。
          return;
        }
        Sleep(50);
      }
    });
    clicker.join();
    runner.join();
    Check(starts.load() == 1 && exit_code.load() == 55,
          "relay 在 primary 退出后携带 payload 晋升并启动 Flutter");
  }
}

// ---------------------------------------------------------------------------
// host channel 胶水（AttachMessenger / takePending 原子取走 / live push /
// DetachMessenger 后不再发送）
// ---------------------------------------------------------------------------

class FakeBinaryMessenger : public flutter::BinaryMessenger {
 public:
  void Send(const std::string& channel, const uint8_t* message, size_t size,
            flutter::BinaryReply reply) const override {
    std::lock_guard<std::mutex> lock(mutex_);
    if (reply == nullptr) {
      // InvokeMethod（notificationActivated 推送）。
      sent_.push_back(std::vector<uint8_t>(message, message + size));
    } else {
      // Dart→C++ 方法调用的回复（测试触发时收集）。
      last_reply_.assign(message, message + size);
    }
  }

  void SetMessageHandler(const std::string& channel,
                         flutter::BinaryMessageHandler handler) override {
    std::lock_guard<std::mutex> lock(mutex_);
    // 先判定再 move：move 之后 handler 为空，事件记录会误判成 remove。
    const bool installed = handler != nullptr;
    handler_installed_ = installed;
    handler_ = std::move(handler);
    handler_events_.push_back(installed ? "install" : "remove");
  }

  // 依序记录的跨边界事件（用于断言 handler 先于任何查询安装）。
  mutable std::mutex mutex_;
  mutable std::vector<std::string> handler_events_;
  mutable std::vector<std::vector<uint8_t>> sent_;
  mutable std::vector<uint8_t> last_reply_;
  flutter::BinaryMessageHandler handler_;
  bool handler_installed_ = false;
};

class RecordingMethodResult : public flutter::MethodResult<flutter::EncodableValue> {
 public:
  void SuccessInternal(const flutter::EncodableValue* result) override {
    got_success = true;
    if (result != nullptr) {
      value = *result;
    }
  }
  void ErrorInternal(const std::string& code, const std::string& message,
                     const flutter::EncodableValue* details) override {
    got_error = true;
    error_code = code;
  }
  void NotImplementedInternal() override { got_not_implemented = true; }

  bool got_success = false;
  bool got_error = false;
  bool got_not_implemented = false;
  flutter::EncodableValue value = flutter::EncodableValue();
  std::string error_code;
};

const flutter::StandardMethodCodec& Codec() {
  return flutter::StandardMethodCodec::GetInstance();
}

class HostFixture {
 public:
  HostFixture()
      : mutex_name_(TestInstanceMutexName()),
        lease_name_(TestLeaseMutexName()),
        ready_name_(TestReadyEventName()),
        pipe_name_(TestPipeName()) {
    // 名称字符串由 fixture 持有：宿主内部只拷贝一次，但 overrides 里的
    // 裸指针必须指向存活到 Start 返回之后的内存。
    overrides_ = TestOverrides(mutex_name_, lease_name_, ready_name_, pipe_name_);
    host_ = WindowsNotificationHost::Start(
        Args({L"--dart-flag"}), overrides_);
  }
  ~HostFixture() {
    if (host_ != nullptr) {
      host_->Shutdown();
    }
  }
  WindowsNotificationHost* host() const { return host_.get(); }
  const std::wstring& pipe_name() const { return pipe_name_; }

 private:
  std::wstring mutex_name_;
  std::wstring lease_name_;
  std::wstring ready_name_;
  std::wstring pipe_name_;
  WindowsNotificationHostOverrides overrides_;
  std::unique_ptr<WindowsNotificationHost> host_;
};

void InvokeChannelMethod(FakeBinaryMessenger& messenger,
                         const std::string& method,
                         std::unique_ptr<flutter::EncodableValue> arguments,
                         RecordingMethodResult* result) {
  flutter::MethodCall<flutter::EncodableValue> call(
      method, std::move(arguments));
  auto encoded = Codec().EncodeMethodCall(call);
  messenger.handler_(encoded->data(), encoded->size(),
                     [&result](const uint8_t* reply, size_t size) {
                       if (reply == nullptr) {
                         // EngineMethodResult::NotImplemented 的线上形态就是
                         // 空回复；空 buffer 进 envelope 解码会被误读。
                         result->NotImplemented();
                         return;
                       }
                       Codec().DecodeAndProcessResponseEnvelope(
                           reply, size, result);
                     });
}

void TestHostChannelGlue() {
  std::printf("== host channel：status/takePending/live push/detach ==\n");
  HostFixture fixture;
  Check(fixture.host() != nullptr && fixture.host()->ShouldStartFlutter(),
        "测试宿主以 primary 启动");

  FakeBinaryMessenger messenger;
  fixture.host()->AttachMessenger(&messenger);
  Check(messenger.handler_installed_ &&
            !messenger.handler_events_.empty() &&
            messenger.handler_events_.back() == "install",
        "AttachMessenger 安装唯一 method handler");

  // getNotificationHostStatus：available=true 且无 failureStage。
  {
    RecordingMethodResult result;
    InvokeChannelMethod(messenger, "getNotificationHostStatus", nullptr,
                        &result);
    const auto* map =
        std::get_if<flutter::EncodableMap>(&result.value);
    const bool has_stage =
        map != nullptr && map->count(flutter::EncodableValue("failureStage")) > 0;
    Check(result.got_success && map != nullptr &&
              map->count(flutter::EncodableValue("available")) > 0 &&
              std::get_if<bool>(
                  &map->at(flutter::EncodableValue("available"))) != nullptr &&
              *std::get_if<bool>(
                  &map->at(flutter::EncodableValue("available"))) &&
              !has_stage,
          "getNotificationHostStatus 返回 available=true 且 failureStage 为空");
  }

  // 冷启动 pending：经宿主自己的 pipe server 交付两条 activation（真实
  // IPC 路径；UI 线程尚未 pump，payload 只入队）→ takePending 一次取走全部。
  {
    const std::string cold1 = "cold-1";
    const std::string cold2 = "cold-2";
    const WindowsNotificationPipeClientResult first =
        WindowsNotificationSendPipeFrame(
            fixture.pipe_name().c_str(), kWindowsNotificationKindActivation,
            U8(cold1), cold1.size());
    const WindowsNotificationPipeClientResult second =
        WindowsNotificationSendPipeFrame(
            fixture.pipe_name().c_str(), kWindowsNotificationKindActivation,
            U8(cold2), cold2.size());
    Check(first.delivered && second.delivered,
          "冷启动两条 activation 经 pipe 送达 primary");
  }
  {
    RecordingMethodResult result;
    InvokeChannelMethod(messenger, "takePendingNotificationActivations",
                        nullptr, &result);
    const auto* list = std::get_if<flutter::EncodableList>(&result.value);
    Check(result.got_success && list != nullptr && list->size() == 2 &&
              std::get_if<std::string>(&(*list)[0]) != nullptr &&
              *std::get_if<std::string>(&(*list)[0]) == "cold-1" &&
              *std::get_if<std::string>(&(*list)[1]) == "cold-2",
          "takePendingNotificationActivations 一次取走完整 FIFO 列表");
    // 再取一次为空。
    RecordingMethodResult again;
    InvokeChannelMethod(messenger, "takePendingNotificationActivations",
                        nullptr, &again);
    const auto* empty = std::get_if<flutter::EncodableList>(&again.value);
    Check(again.got_success && empty != nullptr && empty->empty(),
          "takePending 原子清空后再次取走为空");
  }

  // live push：取走（armed）后新激活经 UI dispatch 以 notificationActivated
  // 推送到 Dart（真实 pipe → 队列 → PostMessage → channel 链路）。
  {
    const size_t sent_before = messenger.sent_.size();
    const std::string live = "live-push";
    const WindowsNotificationPipeClientResult sent =
        WindowsNotificationSendPipeFrame(
            fixture.pipe_name().c_str(), kWindowsNotificationKindActivation,
            U8(live), live.size());
    Check(sent.delivered, "live activation 经 pipe 送达");
    PumpMessagesFor(3000, [&messenger, sent_before]() {
      return messenger.sent_.size() > sent_before;
    });
    bool pushed_ok = false;
    {
      std::lock_guard<std::mutex> lock(messenger.mutex_);
      pushed_ok = messenger.sent_.size() == sent_before + 1;
      if (pushed_ok) {
        auto call = Codec().DecodeMethodCall(messenger.sent_.back());
        pushed_ok = call != nullptr &&
                    call->method_name() == "notificationActivated" &&
                    call->arguments() != nullptr &&
                    std::get_if<std::string>(call->arguments()) != nullptr &&
                    *std::get_if<std::string>(call->arguments()) == "live-push";
      }
    }
    Check(pushed_ok, "armed 后新激活在 UI 线程以 notificationActivated 原样推送");
  }

  // show 参数校验：id 过小 → false；结构缺失 → 固定错误码。
  {
    RecordingMethodResult invalid_id;
    flutter::EncodableMap arguments;
    arguments[flutter::EncodableValue("id")] = flutter::EncodableValue(int64_t(1));
    arguments[flutter::EncodableValue("title")] =
        flutter::EncodableValue(std::string("t"));
    arguments[flutter::EncodableValue("body")] =
        flutter::EncodableValue(std::string("b"));
    arguments[flutter::EncodableValue("payload")] =
        flutter::EncodableValue(std::string("p"));
    InvokeChannelMethod(messenger, "showTerminalNotification",
                        std::make_unique<flutter::EncodableValue>(arguments),
                        &invalid_id);
    Check(invalid_id.got_success &&
              invalid_id.value == flutter::EncodableValue(false),
          "showTerminalNotification 非法 id 返回 false");
  }

  // 未知方法。
  {
    RecordingMethodResult unknown;
    InvokeChannelMethod(messenger, "noSuchMethod", nullptr, &unknown);
    Check(unknown.got_not_implemented, "未知方法返回 NotImplemented");
  }

  // Detach 后不再向 Dart 发送。
  {
    const size_t sent_before = messenger.sent_.size();
    fixture.host()->DetachMessenger();
    const std::string late = "after-detach";
    const WindowsNotificationPipeClientResult sent =
        WindowsNotificationSendPipeFrame(
            fixture.pipe_name().c_str(), kWindowsNotificationKindActivation,
            U8(late), late.size());
    Check(sent.delivered, "detach 后的 activation 仍入 native 队列");
    PumpMessagesFor(800);
    Check(messenger.sent_.size() == sent_before,
          "DetachMessenger 后不再向 Dart 推送（payload 留在 native queue）");
  }

  fixture.host()->Shutdown();
  fixture.host()->Shutdown();  // 幂等。
  Check(true, "host Shutdown 幂等（两次调用无异常）");
}

// ---------------------------------------------------------------------------
// 产品注册回读（--verify-product-registration <exe 路径>）
// ---------------------------------------------------------------------------

int VerifyProductRegistration(const std::wstring& expected_exe) {
  std::printf("== 产品注册回读 ==\n");
  int mismatches = 0;
  const auto add = [&mismatches](const char* name, bool match) {
    std::printf("verify_field %s=%s\n", name, match ? "MATCH" : "MISMATCH");
    if (!match) {
      ++mismatches;
    }
  };

  PWSTR programs = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_Programs, 0, nullptr, &programs)) ||
      programs == nullptr) {
    std::printf("verify_field programs_folder=MISMATCH\n");
    return 1;
  }
  const std::wstring shortcut =
      WindowsNotificationShortcutPath(programs);
  CoTaskMemFree(programs);

  IShellLinkW* link = nullptr;
  if (SUCCEEDED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                 IID_PPV_ARGS(&link)))) {
    IPersistFile* persist = nullptr;
    if (SUCCEEDED(link->QueryInterface(IID_PPV_ARGS(&persist))) &&
        SUCCEEDED(persist->Load(shortcut.c_str(), STGM_READ))) {
      wchar_t target[MAX_PATH] = {};
      WIN32_FIND_DATAW data = {};
      link->GetPath(target, MAX_PATH, &data, SLGP_RAWPATH);
      add("shortcut_target_matches_exe",
          _wcsicmp(target, expected_exe.c_str()) == 0);
      IPropertyStore* store = nullptr;
      if (SUCCEEDED(link->QueryInterface(IID_PPV_ARGS(&store)))) {
        PROPVARIANT value;
        PropVariantInit(&value);
        if (SUCCEEDED(store->GetValue(PKEY_AppUserModel_ID, &value)) &&
            value.vt == VT_LPWSTR) {
          add("shortcut_aumid",
              _wcsicmp(value.pwszVal, kWindowsNotificationAumid) == 0);
        } else {
          add("shortcut_aumid", false);
        }
        PropVariantClear(&value);
        PropVariantInit(&value);
        if (SUCCEEDED(store->GetValue(PKEY_AppUserModel_ToastActivatorCLSID,
                                      &value)) &&
            value.vt == VT_CLSID && value.puuid != nullptr) {
          wchar_t parsed[64] = {};
          const int chars = StringFromGUID2(*value.puuid, parsed, 64);
          add("shortcut_toast_activator_clsid_vt",
              chars > 0 &&
                  _wcsicmp(parsed, kWindowsNotificationClsidBraced) == 0);
        } else {
          add("shortcut_toast_activator_clsid_vt", false);
        }
        PropVariantClear(&value);
        store->Release();
      }
    } else {
      add("shortcut_load", false);
    }
    if (persist != nullptr) {
      persist->Release();
    }
    link->Release();
  } else {
    add("shortcut_com", false);
  }

  const auto read_string = [](const wchar_t* key_path, const wchar_t* value,
                              bool default_value, std::wstring* out,
                              DWORD* type) {
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, key_path, 0, KEY_QUERY_VALUE, &key) !=
        ERROR_SUCCESS) {
      return false;
    }
    DWORD size = 0;
    if (RegQueryValueExW(key, value, nullptr, nullptr, nullptr, &size) !=
        ERROR_SUCCESS) {
      RegCloseKey(key);
      return false;
    }
    std::wstring buffer(size / sizeof(wchar_t) + 1, L'\0');
    const LONG result =
        RegQueryValueExW(key, value, nullptr, type,
                         reinterpret_cast<BYTE*>(buffer.data()), &size);
    RegCloseKey(key);
    if (result != ERROR_SUCCESS) {
      return false;
    }
    out->assign(buffer.c_str());
    return true;
  };

  std::wstring ls32_default;
  DWORD ls32_type = 0;
  const std::wstring ls32_path = WindowsNotificationLocalServer32KeyPath();
  if (read_string(ls32_path.c_str(), nullptr, true, &ls32_default, &ls32_type)) {
    const bool quoted =
        ls32_default.size() >= 2 && ls32_default.front() == L'"' &&
        ls32_default.back() == L'"';
    const std::wstring inner =
        quoted ? ls32_default.substr(1, ls32_default.size() - 2) : ls32_default;
    add("ls32_default_quoted_no_args",
        quoted && _wcsicmp(inner.c_str(), expected_exe.c_str()) == 0);
    std::wstring server_exec;
    if (read_string(ls32_path.c_str(), L"ServerExecutable", false, &server_exec,
                    nullptr)) {
      add("ls32_server_executable_unquoted",
          _wcsicmp(inner.c_str(), server_exec.c_str()) == 0);
    } else {
      add("ls32_server_executable_unquoted", false);
    }
  } else {
    add("ls32_present", false);
  }

  const std::wstring aumid_path = WindowsNotificationAumidKeyPath();
  std::wstring display_name;
  DWORD display_type = 0;
  if (read_string(aumid_path.c_str(), L"DisplayName", false, &display_name,
                  &display_type)) {
    add("aumid_display_name_expand_sz",
        _wcsicmp(display_name.c_str(), kWindowsNotificationAppName) == 0 &&
            display_type == REG_EXPAND_SZ);
  } else {
    add("aumid_display_name_expand_sz", false);
  }
  std::wstring custom_activator;
  DWORD activator_type = 0;
  if (read_string(aumid_path.c_str(), L"CustomActivator", false,
                  &custom_activator, &activator_type)) {
    add("aumid_custom_activator_sz",
        _wcsicmp(custom_activator.c_str(), kWindowsNotificationClsidBraced) == 0 &&
            activator_type == REG_SZ);
  } else {
    add("aumid_custom_activator_sz", false);
  }

  std::printf("verify_end all_match=%d\n", mismatches == 0 ? 1 : 0);
  return mismatches == 0 ? 0 : 1;
}

// ---------------------------------------------------------------------------
// 运行中 primary 健康探测（--probe-live-primary）
// ---------------------------------------------------------------------------

// 连接产品固定 pipe 并发送一条 activateWindow 探测帧：ACK status=0 说明
// 运行中的 primary 宿主与 pipe server 健康，与注册回读共同构成 host status
// 的替代回读证据。单次连接不重试；无 primary 在线时以非零退出码结束。
int ProbeLivePrimary() {
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const WindowsNotificationPipeClientResult result =
      WindowsNotificationSendPipeFrame(kWindowsNotificationPipeName,
                                       kWindowsNotificationKindActivateWindow,
                                       nullptr, 0);
  CoUninitialize();
  std::printf("probe delivered=%d ack_received=%d ack_status=%u fail_code=%s\n",
              result.delivered ? 1 : 0, result.ack_received ? 1 : 0,
              static_cast<unsigned>(result.ack_status), result.fail_code);
  const bool ok = result.delivered &&
                  result.ack_status == kWindowsNotificationAckAccepted;
  std::printf("probe_result=%s\n", ok ? "OK" : "FAIL");
  std::fflush(stdout);
  return ok ? 0 : 1;
}

}  // namespace

int main(int argc, char** argv) {
  SetConsoleOutputCP(CP_UTF8);
  if (argc >= 3 && std::strcmp(argv[1], "--verify-product-registration") == 0) {
    const int wchar_count = MultiByteToWideChar(
        CP_UTF8, MB_ERR_INVALID_CHARS, argv[2], -1, nullptr, 0);
    std::wstring expected(wchar_count, L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, argv[2], -1,
                        expected.data(), wchar_count);
    if (!expected.empty()) {
      expected.pop_back();
    }
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const int result = VerifyProductRegistration(expected);
    CoUninitialize();
    return result;
  }
  if (argc >= 2 && std::strcmp(argv[1], "--probe-live-primary") == 0) {
    return ProbeLivePrimary();
  }
  if (argc >= 2 && std::strcmp(argv[1], "--emit-queue-full-token") == 0) {
    return EmitQueueFullToken();
  }

  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  TestEmbeddingTokenParsing();
  TestModeDecision();
  TestReadyEventSemantics();
  TestPipeSecurity();
  TestFrameProtocol();
  TestQueueAndFocus();
  TestQueueFullDiagnosticToken();
  TestXmlAndShowValidation();
  TestFixedIdentity();
  TestPipeServeLoop();
  TestWorkerOnlyPostsUiDispatch();
  TestStaStateMachine();
  TestInflightShutdownRace();
  TestRelayStaLoop();
  TestProcessSeamModes();
  TestHostChannelGlue();
  CoUninitialize();

  std::printf("== 汇总: checks=%d failures=%d ==\n", g_checks, g_failures);
  return g_failures == 0 ? 0 : 1;
}
