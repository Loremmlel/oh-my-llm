#ifndef RUNNER_WINDOWS_NOTIFICATION_REGISTRATION_H_
#define RUNNER_WINDOWS_NOTIFICATION_REGISTRATION_H_

// Windows 通知宿主的固定身份与幂等注册。
//
// 身份值提交后不得随版本号、构建号或目录变化；开发版、发布版和同一用户
// 会话内的多个目录副本共享这些身份，先成为 primary 的副本保持注册所有权。
//
// 只有 primary 调用 EnsureWindowsNotificationRegistration；relay 与 manual
// secondary 绝不写注册表或快捷方式。所有步骤只写 HKCU，不请求管理员权限，
// 不删除旧注册。任一步失败只返回固定 failure stage token 并把宿主标记为
// unavailable；不向调用方返回绝对路径、HRESULT 文本或系统消息。

#include <windows.h>

#include <string>

// —— 产品固定身份（提交后不得改动；开发期试验用过的身份绝不进入产品）——

constexpr wchar_t kWindowsNotificationAppName[] = L"Oh My LLM";
constexpr wchar_t kWindowsNotificationAumid[] = L"YuzuShiki.OhMyLlm";
constexpr wchar_t kWindowsNotificationClsidBraced[] =
    L"{7E4B2C91-5D4A-4A8E-9F1B-2C6D3A80E751}";
constexpr wchar_t kWindowsNotificationShortcutName[] = L"Oh My LLM.lnk";

// Local\ namespace 已把 kernel objects 限定到当前 logon session。
constexpr wchar_t kWindowsNotificationInstanceMutexName[] =
    L"Local\\YuzuShiki.OhMyLlm.NotificationHost.7E4B2C915D4A4A8E9F1B2C6D3A80E751";
constexpr wchar_t kWindowsNotificationActivatorLeaseMutexName[] =
    L"Local\\YuzuShiki.OhMyLlm.NotificationActivatorLease."
    L"7E4B2C915D4A4A8E9F1B2C6D3A80E751";
constexpr wchar_t kWindowsNotificationReadyEventName[] =
    L"Local\\YuzuShiki.OhMyLlm.NotificationHostReady."
    L"7E4B2C915D4A4A8E9F1B2C6D3A80E751";
constexpr wchar_t kWindowsNotificationPipeName[] =
    L"\\\\.\\pipe\\YuzuShiki.OhMyLlm.NotificationHost.v1";

// —— 纯构造 helper（native 测试直接断言固定值）——

// LocalServer32 默认值：带双引号、无参数的 exe 绝对路径。
std::wstring WindowsNotificationLocalServer32DefaultValue(
    const std::wstring& exe_path);
// LocalServer32 的 ServerExecutable 值：不带引号、无参数的同一路径。
std::wstring WindowsNotificationLocalServer32ServerExecutableValue(
    const std::wstring& exe_path);
// HKCU 下 LocalServer32 键的相对路径（Software\Classes\CLSID\{...}\LocalServer32）。
std::wstring WindowsNotificationLocalServer32KeyPath();
// HKCU 下 AppUserModelId 键的相对路径。
std::wstring WindowsNotificationAumidKeyPath();
// 开始菜单快捷方式完整路径 = programs folder + 固定文件名。
std::wstring WindowsNotificationShortcutPath(
    const std::wstring& programs_folder);

// —— 幂等注册（仅 primary 调用）——

struct WindowsNotificationRegistrationResult {
  bool ok = false;
  // 失败时的固定 stage token；成功时为 nullptr。可能取值：
  // "exePath" / "programsFolder" / "shortcut" / "localServer32" / "aumidKey"。
  const char* failure_stage = nullptr;
};

WindowsNotificationRegistrationResult EnsureWindowsNotificationRegistration();

#endif  // RUNNER_WINDOWS_NOTIFICATION_REGISTRATION_H_
