#ifndef RUNNER_WINDOWS_NOTIFICATION_INSTANCE_COORDINATOR_H_
#define RUNNER_WINDOWS_NOTIFICATION_INSTANCE_COORDINATOR_H_

// 唯一 Flutter owner 协调器：instance mutex 原子选主、manual-reset
// ready event、activator lease mutex、显式 DACL 的 named pipe server/client。
//
// 身份判断只依赖 Local\ namespace 内的 named kernel objects；禁止进程枚举、
// 进程名、窗口标题或固定 sleep。所有 kernel object 名称由调用方传入：生产
// 传入 registration.h 的产品固定名，native 测试传入进程唯一名以保证隔离。

#include <windows.h>

#include <atomic>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

// —— 实测锁定的产品 named constants（在真实 Shell/COM 环境验证过的时序，
//    不得随版本或目录改动）——

// lease mutex 等待切片（primary 与 relay 共用）。
constexpr DWORD kWindowsNotificationLeaseSliceWaitMs = 250;
// primary 竞争 activator lease 的总上界（relay 只持有有界 drain 窗口）。
constexpr DWORD kWindowsNotificationPrimaryLeaseTotalWaitMs = 30000;
// relay 竞争 activator lease 的总上界。
constexpr DWORD kWindowsNotificationRelayLeaseTotalWaitMs = 3000;
// relay / secondary 连接 primary pipe 的总上界。
constexpr DWORD kWindowsNotificationPipeConnectTotalMs = 2000;
// 单条 request 等待 pipe ACK 的上界。
constexpr DWORD kWindowsNotificationPipeAckWaitMs = 3000;
// relay 无在途 callback 的静默期，到期才允许 revoke 并退出。
constexpr DWORD kWindowsNotificationRelayDrainGraceMs = 1000;
// relay 绝对生命周期上界（防止 callback 循环卡死导致常驻）。
constexpr DWORD kWindowsNotificationRelayMaxLifetimeMs = 15000;
// primary 等待自身 notification STA 注册完成并开始 pump 的上界。
constexpr DWORD kWindowsNotificationPrimaryReadyWaitMs = 10000;
// pipe server 单次 IO 操作上界（卡死客户端不得拖垮 server）。
constexpr DWORD kWindowsNotificationPipeServerOpWaitMs = 5000;

// —— 进程模式 ——

enum class WindowsNotificationHostMode {
  kPrimary,           // 唯一可创建 Flutter engine/窗口/存储连接的进程。
  kActivationRelay,   // 含 -Embedding 且 mutex 已存在；纯原生 COM pump。
  kManualSecondary,   // 无 -Embedding 且 mutex 已存在；只发 activateWindow。
  kFatal,             // kernel object 创建失败，无法判定唯一 owner。
};

// —— -Embedding token 解析 ——
// 只接受独立的 "-Embedding" / "/Embedding" token（大小写不敏感），不做子串
// 匹配；该 token 只用于选择进程模式，不携带 payload，也不进入 Dart。
bool WindowsNotificationCommandLineHasEmbeddingToken(
    const std::vector<std::wstring>& arguments);

// —— 原子选主 ——
// CreateMutexW(nullptr, FALSE, name) 后立即检查 GetLastError()==
// ERROR_ALREADY_EXISTS；返回的句柄由调用方持有（primary 持有到进程退出）。
// CreateMutexW 本身失败时返回 kFatal（mode 句柄为 nullptr）。
struct WindowsNotificationInstanceClaim {
  WindowsNotificationHostMode mode = WindowsNotificationHostMode::kFatal;
  HANDLE instance_mutex = nullptr;  // 调用方负责 CloseHandle（kFatal 时为 null）
};
WindowsNotificationInstanceClaim WindowsNotificationClaimInstance(
    const std::vector<std::wstring>& command_line, const wchar_t* mutex_name);

// —— manual-reset ready event ——
// 只表达「当前 instance-mutex owner 的长期 class object 已注册并开始 pump」。
// 新 owner 打开/创建后必须先 ResetEvent 丢弃上一任遗留的 signaled 状态；
// relay 不得设置它。不能把上一任 primary 遗留的 signaled handle 当作 ready。
HANDLE WindowsNotificationOpenReadyEventAsOwner(const wchar_t* event_name);
void WindowsNotificationSetReadyEvent(HANDLE ready_event);
void WindowsNotificationResetReadyEvent(HANDLE ready_event);
bool WindowsNotificationIsReadyEventSignaled(HANDLE ready_event);

// —— activator lease mutex ——
// 长期 COM owner 与短命 relay 通过该 mutex 串行；任何时刻不得有两个本项目
// class object owner。Acquire 在总上界内按切片重试（relay 只持有有界窗口）。
HANDLE WindowsNotificationOpenLeaseMutex(const wchar_t* mutex_name);
// 返回 WAIT_OBJECT_0 / WAIT_ABANDONED（视为取得）或 WAIT_TIMEOUT。
DWORD WindowsNotificationAcquireLease(HANDLE lease_mutex,
                                      DWORD total_wait_ms,
                                      DWORD slice_wait_ms);
void WindowsNotificationReleaseLeaseMutex(HANDLE lease_mutex);

// —— pipe 显式 DACL ——
// 只允许当前 logon user SID 与 LocalSystem 完全访问；配合
// PIPE_REJECT_REMOTE_CLIENTS。SID/DACL 构造失败时返回 false —— 调用方必须
// 把 IPC/通知宿主标记为 unavailable，不得退回默认（宽松）pipe ACL。
struct WindowsNotificationPipeSecurity {
  SECURITY_ATTRIBUTES sa = {};
  // 以下存储在对象存活期内必须保持有效（sa 指向其中内容）。
  std::vector<unsigned char> user_sid;
  std::vector<unsigned char> system_sid;
  ACL* acl = nullptr;                       // LocalAlloc，析构释放
  SECURITY_DESCRIPTOR* descriptor = nullptr;  // LocalAlloc，析构释放

  WindowsNotificationPipeSecurity() = default;
  ~WindowsNotificationPipeSecurity();
  WindowsNotificationPipeSecurity(const WindowsNotificationPipeSecurity&) =
      delete;
  WindowsNotificationPipeSecurity& operator=(
      const WindowsNotificationPipeSecurity&) = delete;
};

// `access_token`：用于取当前 user SID 的 token 句柄；生产传
// GetCurrentProcessToken()，测试可注入无效句柄覆盖失败路径。
bool WindowsNotificationBuildPipeSecurity(
    HANDLE access_token, WindowsNotificationPipeSecurity* out);

// —— pipe server ——
// 单实例 message pipe，运行在专用 native IO 线程上，不依赖 Flutter engine/
// Dart isolate/UI thread pump。一条连接串行一条 request/ACK 后关闭。
class WindowsNotificationPipeServer {
 public:
  using ServeHandler = std::function<uint16_t(
      uint16_t kind, const std::vector<unsigned char>& payload)>;

  WindowsNotificationPipeServer() = default;
  ~WindowsNotificationPipeServer() = default;

  // 启动服务线程；失败（含 DACL 构造失败、pipe 名被占用）返回 false。
  bool Start(ServeHandler handler, std::atomic<bool>* stopping,
             const wchar_t* pipe_name,
             HANDLE access_token = GetCurrentProcessToken());
  // 停止并 join 服务线程（有界）。
  void Stop();

 private:
  static DWORD WINAPI ServeThreadProc(void* param);
  void ServeLoop();

  ServeHandler handler_;
  std::atomic<bool>* stopping_ = nullptr;
  const wchar_t* pipe_name_ = nullptr;
  HANDLE access_token_ = nullptr;
  HANDLE thread_ = nullptr;
  // 首个 pipe 实例创建完成后 SetEvent，让 Start 返回时「pipe 可达」是确定
  // 结论，调用方与测试不需要靠固定 sleep 猜测。
  HANDLE ready_event_ = nullptr;
  bool pipe_created_ = false;
  // serve 线程创建 pipe 实例时引用同一 DACL；Stop join 之后才销毁。
  std::unique_ptr<WindowsNotificationPipeSecurity> security_;
};

// —— pipe client（relay / manual secondary 一次性使用）——

struct WindowsNotificationPipeClientResult {
  bool delivered = false;       // 收到 ACK 且 status == accepted
  bool ack_received = false;
  uint16_t ack_status = 0xFFFF;
  // "connect"：连接失败（primary pipe 不存在或持续 busy）；
  // "write" / "ackTimeout" / "badAck"。
  const char* fail_code = "";
};

// 连接（受 kWindowsNotificationPipeConnectTotalMs 约束）、写入一条原始 frame
// （可故意畸形）、等待 ACK（受 kWindowsNotificationPipeAckWaitMs 约束）、关闭。
WindowsNotificationPipeClientResult WindowsNotificationSendPipeFrameBytes(
    const wchar_t* pipe_name, const std::vector<unsigned char>& frame);
WindowsNotificationPipeClientResult WindowsNotificationSendPipeFrame(
    const wchar_t* pipe_name, uint16_t kind, const unsigned char* payload,
    size_t payload_size);

#endif  // RUNNER_WINDOWS_NOTIFICATION_INSTANCE_COORDINATOR_H_
