#ifndef RUNNER_WINDOWS_NOTIFICATION_HOST_H_
#define RUNNER_WINDOWS_NOTIFICATION_HOST_H_

// Windows 通知宿主深模块的唯一对外接口。
// 只有本文件允许被 main.cpp / flutter_window.* include；registration /
// activator / instance_coordinator / protocol / toast 都是模块内部 seam，
// 不向 Dart 或 app composition 暴露。

#include <flutter/binary_messenger.h>

#include <functional>
#include <memory>
#include <string>
#include <vector>

// 唯一 Flutter channel；宿主与 Dart 之间不存在的第二通道。
constexpr char kWindowsNotificationChannelName[] =
    "yuzu.shiki.oh_my_llm/windows_notifications";

// native 测试注入身份/kernel object 名用（生产一律使用 registration.h 的
// 产品固定值，overrides 保持默认空即可）。字段为 nullptr 时取产品值。
struct WindowsNotificationHostOverrides {
  const wchar_t* instance_mutex_name = nullptr;
  const wchar_t* lease_mutex_name = nullptr;
  const wchar_t* ready_event_name = nullptr;
  const wchar_t* pipe_name = nullptr;
  // activator 身份（AUMID/CLSID）：测试注入测试专用值，避免与真实 primary
  // 的 class object 冲突。
  const wchar_t* aumid = nullptr;
  const wchar_t* clsid_braced = nullptr;
  // 测试进程不得改写真实快捷方式/注册表：true 时跳过身份注册并视为成功。
  bool suppress_identity_registration = false;
};

class WindowsNotificationHost {
 public:
  // 完成原子选主；primary 在返回前创建 native queue、pipe IO thread、幂等
  // 身份注册并启动 notification STA thread。COM activator 必须先于任何
  // DartProject/engine 存在，否则 pre-COM 窗口期的 Toast 点击会被 RPCSS
  // 按 LocalServer32 拉起第二个完整进程。必须在
  // runner UI 线程（已 CoInitializeEx STA）调用。
  static std::unique_ptr<WindowsNotificationHost> Start(
      const std::vector<std::wstring>& command_line,
      const WindowsNotificationHostOverrides& overrides = {});

  // false 时调用方必须在构造任何 DartProject 之前走 RunSecondaryMode 并
  // 退出（或被晋升为 primary 后继续）。
  bool ShouldStartFlutter() const;

  // relay / manual secondary 模式运行（relay 的 STA loop 在调用线程 pump）。
  // 返回进程退出码；若期间 primary 退出且本进程成功重新选主，则晋升为
  // primary（ShouldStartFlutter 变为 true），返回值仅供日志参考。
  int RunSecondaryMode();

  // AttachMessenger 才创建 MethodChannel；此前收到的 payload 留在 native
  // queue。channel handler/invoke 与 Toast show 都在 runner UI thread。
  void AttachMessenger(flutter::BinaryMessenger* messenger);
  // FlutterWindow 销毁时解除 messenger（幂等；此后不再向 Dart 发送）。
  void DetachMessenger();

  // 注册窗口恢复/聚焦回调（runner UI 线程调用）；focus 在窗口尚未 attach
  // 时只合并标志，首次 attach 后执行。
  void AttachWindowActivation(std::function<void()> activate_window);

  // 仅供原生测试：取得绑定当前 activator 共享状态的进程内 COM 对象
  // （primary STA 或 relay 短命注册已生效时），不经 RPCSS 路由直接调用
  // Activate；未注册时返回 nullptr。调用方负责 Release。
  void* CreateActivatorForTest() const;

  // 幂等：停止接收新工作 → reset ready → 注册线程 revoke 并退出 pump →
  // join pipe 线程 → 释放 WinRT 对象与 kernel handles。
  void Shutdown();

  ~WindowsNotificationHost();

 private:
  explicit WindowsNotificationHost(
      const WindowsNotificationHostOverrides& overrides);
  // mode 判定与 primary bootstrap 的内部实现归 Core；host 只做转调，
  // 保证 main.cpp/flutter_window 只见本头文件。
  struct Core;
  std::unique_ptr<Core> core_;
};

// —— 进程编排 seam（native 测试注入「启动 Flutter」动作）——
//
// 与 wWinMain 完全相同的顺序：选主 → primary bootstrap → run_flutter() →
// Shutdown；或 secondary →（可能晋升）→ 退出。测试注入计数器实现即可断言
// relay/manual secondary 从不触发 flutterStart（`flutterStartCount==0`）。
struct WindowsNotificationProcessActions {
  // 构造 DartProject/FlutterWindow 并运行 message loop，返回退出码。
  std::function<int()> run_flutter;
};

int WindowsNotificationRunProcess(
    const std::vector<std::wstring>& command_line,
    const WindowsNotificationProcessActions& actions,
    const WindowsNotificationHostOverrides& overrides = {});

// —— 竞态窗口测试钩子 ——
// 默认恒为 0；仅 Debug + OMLL_NOTIFICATION_HOST_TESTING=ON 的构建会编入
// 非零值，release/testing=OFF 构建不读取环境变量/命令行/Dart define。
int WindowsNotificationPreComDelayMs();
int WindowsNotificationPostComDelayMs();

#endif  // RUNNER_WINDOWS_NOTIFICATION_HOST_H_
