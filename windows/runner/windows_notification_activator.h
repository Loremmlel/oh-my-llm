#ifndef RUNNER_WINDOWS_NOTIFICATION_ACTIVATOR_H_
#define RUNNER_WINDOWS_NOTIFICATION_ACTIVATOR_H_

// COM activator、notification STA 与原生早期队列。
//
// 线程与所有权模型：
//  - primary 的 notification STA 是一条专用线程：独立
//    CoInitializeEx(COINIT_APARTMENTTHREADED)、CoRegisterClassObject
//    (CLSCTX_LOCAL_SERVER, REGCLS_MULTIPLEUSE)、持续 pump native message
//    loop；ready event 只在注册成功且 pump 开始 dispatch 后才 Set。
//  - relay 在调用线程（已初始化 STA COM）运行同型短命 loop：drain grace +
//    max lifetime 定时器到期后 revoke、退出，绝不触碰 Flutter/窗口/存储。
//  - class factory 与 activator 持有 shared_ptr 的共享宿主状态而非裸指针；
//    Shutdown 先标记 stopping、reset ready、由注册线程 revoke 并退出 pump，
//    join 后才允许销毁 queue/IPC state，防止 use-after-free。
//  - worker（STA 线程 / pipe 线程）只允许「加锁入队 + PostMessage 到 UI
//    dispatch 窗口」，绝不允许直接调用 messenger/window 回调。
//
// `Activate(appUserModelId, invokedArgs, data, count)` 为 noexcept + catch-all，
// 只验证 AUMID、长度与 UTF-16→UTF-8 转换；合法 payload 原样入队，安全性由
// Dart 侧严格 decoder 最终判定。

#include <windows.h>

#include <atomic>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

// runner UI 线程自定义 window message：worker 只允许 PostMessage 这两个值，
// UI 线程在自己的 message loop 中 dispatch；任何 worker 直接调用
// messenger/window 都会与 engine 生命周期产生竞态，因此被结构性禁止。
constexpr UINT kWindowsNotificationUiMsgActivation = WM_APP + 0x210;
constexpr UINT kWindowsNotificationUiMsgFocus = WM_APP + 0x211;

// —— COM activator 身份（生产用 registration.h 的产品固定值；native 测试
//    注入测试专用 AUMID/CLSID，避免与真实 primary 的 class object 冲突）——

struct WindowsNotificationActivatorIdentity {
  const wchar_t* aumid;
  const wchar_t* clsid_braced;
};

// —— 原生 pending queue（FIFO，容量 32，单项 ≤1024 UTF-8 bytes）——

class WindowsNotificationPendingQueue {
 public:
  // 满或超限时返回 false（不逐出已排队 payload）。
  bool Push(const std::string& payload_utf8);
  // 原子取走全部并清空（takePendingNotificationActivations 语义）。
  std::vector<std::string> TakeAll();
  size_t depth() const;

 private:
  mutable std::mutex mutex_;
  std::vector<std::string> entries_;  // 用 vector 维持 FIFO 追加语义
};

// pending focus 合并标志：多次 activateWindow 只合并为一个待处理标志。
class WindowsNotificationFocusFlag {
 public:
  // 置位；返回是否从无到有（首次），调用方据此只 post 一次 UI dispatch。
  bool Request();
  // 取走并清除；返回 false 表示当前没有待处理 focus。
  bool Consume();
  bool IsRequested() const;

 private:
  std::atomic<bool> requested_{false};
};

// —— worker 安全投递（只入队 + PostMessage）——
// `ui_dispatch_hwnd` 为空时仅排队（窗口尚未 attach 的早期窗口期）。
// 返回 false 表示队列已满（payload 被丢弃，记录固定类别）。
bool WindowsNotificationEnqueueActivationForUi(
    WindowsNotificationPendingQueue* queue, HWND ui_dispatch_hwnd,
    const std::string& payload_utf8);
void WindowsNotificationEnqueueFocusForUi(
    WindowsNotificationFocusFlag* flag, HWND ui_dispatch_hwnd);

// —— 共享宿主状态（class factory / activator 持有引用）——

struct WindowsNotificationActivatorShared {
  std::atomic<bool> stopping{false};
  // 在途 Activate callback 数（shutdown join 的依据；callback 本身有界）。
  std::atomic<int> in_flight{0};
  // payload 原样交付；sink 内部不得抛出、不得阻塞在 Flutter/路由/窗口上。
  std::function<void(const std::string& payload_utf8)> sink;
  // 身份持有拷贝：COM 对象的生命周期可能超过宿主（shutdown 后仍被外部
  // 持有的 activator 引用），裸指针会指向已析构的宿主字符串。
  std::wstring aumid;
  std::wstring clsid_braced;
  // CoRegisterClassObject 成功后置位；relay 据此判断短命注册已生效。
  std::atomic<bool> class_registered{false};
  // 非空时（relay STA），每次 Activate 收尾后向该窗口 post 完成消息，
  // 驱动 drain grace 重挂；primary 为空（payload 只入队，无需 drain）。
  HWND notify_hwnd = nullptr;
};

// —— notification STA（primary：后台线程；relay：调用线程 loop）——

class WindowsNotificationStaHost {
 public:
  WindowsNotificationStaHost() = default;
  ~WindowsNotificationStaHost() = default;

  // 启动 primary 专用 STA 线程并等待 ready event（注册成功 + pump 开始）。
  // 返回固定 stage token：nullptr=成功，"classObject"=注册失败，
  // "activatorReady"=ready 等待超时，"threadStart"=线程创建失败。
  const char* StartPrimary(const WindowsNotificationActivatorIdentity& identity,
                           HANDLE ready_event,
                           const std::function<void(const std::string&)>& sink);

  // 幂等：向注册线程 post WM_QUIT，由该线程在自身 apartment revoke 后退出
  // 并 join（有界等待，超时不再阻塞进程退出）。
  void Shutdown();

  bool registered() const { return registered_; }

  // 仅供原生测试：暴露 STA 线程同源的共享状态，测试用
  // WindowsNotificationCreateActivatorForTest 在进程内直接调用 Activate，
  // 不依赖 RPCSS 真实路由。
  const std::shared_ptr<WindowsNotificationActivatorShared>& shared_for_test()
      const {
    return shared_;
  }

 private:
  static DWORD WINAPI PrimaryThreadProc(void* param);
  void RunPrimarySta();

  HANDLE thread_ = nullptr;
  DWORD thread_id_ = 0;
  // ready event 由调用方持有；这里只保存以便 Shutdown 在 revoke 前复位——
  // 「shutdown 在 revoke 前再次 reset ready」是宿主对外的固定语义。
  HANDLE ready_event_ = nullptr;
  std::shared_ptr<WindowsNotificationActivatorShared> shared_;
  bool registered_ = false;
  bool shutdown_done_ = false;
};

// relay 短命 STA loop：在调用线程（须已 CoInitializeEx STA）注册同一 CLSID
// 的短命 class object 并 pump；每次 Activate 后重置 drain grace，静默期到期
// 或超过 max lifetime 后 revoke 并返回 0；注册失败返回非 0。
// `shared_sink`（可选）在 loop 开始前回调共享状态引用：宿主用它向原生测试
// 暴露进程内直接构造 activator 的入口（回调可能来自另一线程，宿主自行加锁）。
int WindowsNotificationRunRelayStaLoop(
    const WindowsNotificationActivatorIdentity& identity,
    const std::function<void(const std::string&)>& sink,
    const std::function<void(
        std::shared_ptr<WindowsNotificationActivatorShared>)>& shared_sink =
        nullptr);

// 供 native 测试直接构造 activator COM 对象（进程内真实调用 Activate，
// 不依赖 RPCSS）：调用方负责 Release。
void* WindowsNotificationCreateActivatorForTest(
    const std::shared_ptr<WindowsNotificationActivatorShared>& shared);

#endif  // RUNNER_WINDOWS_NOTIFICATION_ACTIVATOR_H_
