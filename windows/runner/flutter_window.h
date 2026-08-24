#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"
#include "windows_notification_host.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a FlutterWindow hosting a Flutter view running |project|.
  // |notification_host| 由 wWinMain 持有；窗口负责在 engine/窗口就绪时
  // attach messenger 与窗口恢复回调（宿主启动先于本类构造）。
  FlutterWindow(const flutter::DartProject& project,
                WindowsNotificationHost* notification_host);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message,
                         WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // activateWindow 请求到达时恢复并聚焦主窗口（可见性/最小化分别处理，
  // 每步失败不阻断后续步骤）。
  void RestoreAndFocus();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  WindowsNotificationHost* notification_host_ = nullptr;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
