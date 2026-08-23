#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <shellapi.h>

#include <memory>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"
#include "windows_notification_host.h"

namespace {

// host 的进程模式判定需要原始 token（含 -Embedding），必须保留宽字符。
std::vector<std::wstring> GetWideCommandLineArguments() {
  int argument_count = 0;
  LPWSTR* arguments = CommandLineToArgvW(GetCommandLineW(), &argument_count);
  if (arguments == nullptr) {
    return {};
  }
  std::vector<std::wstring> wide_arguments;
  wide_arguments.reserve(argument_count);
  for (int i = 0; i < argument_count; ++i) {
    wide_arguments.push_back(arguments[i]);
  }
  LocalFree(arguments);
  return wide_arguments;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g. 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins. relay 模式也在本线程跑短命 STA loop，依赖这行初始化。
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // 通知宿主先于任何 DartProject/engine 选主：COM activator 的所有权必须
  // 在 Flutter 之前建立，否则 pre-COM 窗口期的 Toast 点击会被 RPCSS 按
  // LocalServer32 拉起第二个完整进程。kFatal（kernel object 失败无法判定
  // 唯一 owner）时直接退出，不冒险成为第二个 Flutter owner。
  std::unique_ptr<WindowsNotificationHost> notification_host =
      WindowsNotificationHost::Start(GetWideCommandLineArguments());
  if (notification_host == nullptr) {
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  if (!notification_host->ShouldStartFlutter()) {
    const int secondary_exit = notification_host->RunSecondaryMode();
    if (!notification_host->ShouldStartFlutter()) {
      ::CoUninitialize();
      return secondary_exit;
    }
  }
  if (WindowsNotificationPostComDelayMs() > 0) {
    // 竞态复验钩子：只延迟 DartProject，notification STA 照常 pump。
    ::Sleep(static_cast<DWORD>(WindowsNotificationPostComDelayMs()));
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, notification_host.get());
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"oh_my_llm", origin, size)) {
    notification_host->Shutdown();
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  notification_host->Shutdown();
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
