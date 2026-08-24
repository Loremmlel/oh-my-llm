#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             WindowsNotificationHost* notification_host)
    : project_(project), notification_host_(notification_host) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // engine 就绪后立刻 attach：宿主此前收到的 activation 留在 native queue，
  // Dart 侧 initialize 时一次取走；窗口回调就绪后 pending focus 立即执行。
  if (notification_host_ != nullptr) {
    notification_host_->AttachMessenger(flutter_controller_->engine()->messenger());
    notification_host_->AttachWindowActivation(
        [this]() { RestoreAndFocus(); });
  }

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (notification_host_ != nullptr) {
    // 窗口销毁先于宿主 shutdown：先摘除 messenger，之后不再向 Dart 发送。
    notification_host_->DetachMessenger();
    notification_host_->AttachWindowActivation(nullptr);
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::RestoreAndFocus() {
  const HWND window = GetHandle();
  if (window == nullptr) {
    return;
  }
  if (!IsWindowVisible(window)) {
    ShowWindow(window, SW_SHOWNORMAL);
  }
  if (IsIconic(window)) {
    ShowWindow(window, SW_RESTORE);
  }
  SetForegroundWindow(window);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
