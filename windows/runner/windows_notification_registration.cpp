#include "windows_notification_registration.h"

#include <knownfolders.h>
#include <objbase.h>
#include <propkey.h>
#include <propvarutil.h>
#include <propsys.h>
#include <shlobj.h>
#include <shobjidl.h>

#include <cstring>

namespace {

bool GetCurrentExePath(std::wstring* out_path) {
  wchar_t buffer[MAX_PATH] = {};
  const DWORD written = GetModuleFileNameW(nullptr, buffer, MAX_PATH);
  if (written == 0 || written >= MAX_PATH) {
    return false;
  }
  out_path->assign(buffer, written);
  return true;
}

std::wstring DirectoryOf(const std::wstring& path) {
  const size_t pos = path.find_last_of(L"\\/");
  if (pos == std::wstring::npos) {
    return path;
  }
  return path.substr(0, pos);
}

bool GetProgramsFolder(std::wstring* out) {
  PWSTR programs = nullptr;
  const HRESULT hr =
      SHGetKnownFolderPath(FOLDERID_Programs, KF_FLAG_CREATE, nullptr,
                           &programs);
  if (FAILED(hr) || programs == nullptr) {
    return false;
  }
  out->assign(programs);
  CoTaskMemFree(programs);
  return true;
}

// 快捷方式属性写入：target、working directory、AUMID 与 VT_CLSID 的
// ToastActivatorCLSID。CLSID 必须是 VT_CLSID PROPVARIANT，写成 REG_SZ 会导致
// Shell 不认 activator。
HRESULT WriteShortcutProperties(IShellLinkW* link, const std::wstring& exe_path,
                                const std::wstring& exe_dir,
                                CLSID activator) {
  HRESULT hr = link->SetPath(exe_path.c_str());
  if (SUCCEEDED(hr)) {
    hr = link->SetWorkingDirectory(exe_dir.c_str());
  }
  IPropertyStore* store = nullptr;
  if (SUCCEEDED(hr)) {
    hr = link->QueryInterface(IID_PPV_ARGS(&store));
  }
  if (SUCCEEDED(hr)) {
    PROPVARIANT aumid;
    PropVariantInit(&aumid);
    hr = InitPropVariantFromString(kWindowsNotificationAumid, &aumid);
    if (SUCCEEDED(hr)) {
      hr = store->SetValue(PKEY_AppUserModel_ID, aumid);
    }
    PropVariantClear(&aumid);
  }
  if (SUCCEEDED(hr)) {
    PROPVARIANT clsid;
    PropVariantInit(&clsid);
    clsid.vt = VT_CLSID;
    clsid.puuid = static_cast<CLSID*>(CoTaskMemAlloc(sizeof(CLSID)));
    if (clsid.puuid == nullptr) {
      hr = E_OUTOFMEMORY;
    } else {
      *clsid.puuid = activator;
      hr = store->SetValue(PKEY_AppUserModel_ToastActivatorCLSID, clsid);
      PropVariantClear(&clsid);
    }
  }
  if (SUCCEEDED(hr)) {
    hr = store->Commit();
  }
  if (store != nullptr) {
    store->Release();
  }
  return hr;
}

HRESULT CreateOrUpdateShortcut(const std::wstring& shortcut_path,
                               const std::wstring& exe_path,
                               const std::wstring& exe_dir, CLSID activator) {
  IShellLinkW* link = nullptr;
  HRESULT hr = CoCreateInstance(CLSID_ShellLink, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link));
  if (FAILED(hr)) {
    return hr;
  }
  hr = WriteShortcutProperties(link, exe_path, exe_dir, activator);
  if (SUCCEEDED(hr)) {
    IPersistFile* persist = nullptr;
    hr = link->QueryInterface(IID_PPV_ARGS(&persist));
    if (SUCCEEDED(hr)) {
      // 第二参 TRUE：已存在的快捷方式直接覆盖（幂等修复路径的含义）。
      hr = persist->Save(shortcut_path.c_str(), TRUE);
      persist->Release();
    }
  }
  link->Release();
  return hr;
}

HRESULT WriteLocalServer32(const std::wstring& exe_path) {
  const std::wstring key_path = WindowsNotificationLocalServer32KeyPath();
  HKEY key = nullptr;
  LONG result = RegCreateKeyExW(HKEY_CURRENT_USER, key_path.c_str(), 0, nullptr,
                                REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr,
                                &key, nullptr);
  if (result != ERROR_SUCCESS) {
    return HRESULT_FROM_WIN32(result);
  }
  // 默认值带双引号、无参数：COM 按 LocalServer32 启动时自动追加
  // -Embedding，注册值不得自创参数；ServerExecutable 为不带引号同一路径。
  const std::wstring quoted =
      WindowsNotificationLocalServer32DefaultValue(exe_path);
  const std::wstring server_executable =
      WindowsNotificationLocalServer32ServerExecutableValue(exe_path);
  result = RegSetValueExW(key, nullptr, 0, REG_SZ,
                          reinterpret_cast<const BYTE*>(quoted.c_str()),
                          static_cast<DWORD>((quoted.size() + 1) *
                                             sizeof(wchar_t)));
  if (result == ERROR_SUCCESS) {
    result = RegSetValueExW(key, L"ServerExecutable", 0, REG_SZ,
                            reinterpret_cast<const BYTE*>(
                                server_executable.c_str()),
                            static_cast<DWORD>((server_executable.size() + 1) *
                                               sizeof(wchar_t)));
  }
  RegCloseKey(key);
  return HRESULT_FROM_WIN32(result);
}

HRESULT WriteAumidKey() {
  const std::wstring key_path = WindowsNotificationAumidKeyPath();
  HKEY key = nullptr;
  LONG result = RegCreateKeyExW(HKEY_CURRENT_USER, key_path.c_str(), 0, nullptr,
                                REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr,
                                &key, nullptr);
  if (result != ERROR_SUCCESS) {
    return HRESULT_FROM_WIN32(result);
  }
  result = RegSetValueExW(key, L"DisplayName", 0, REG_EXPAND_SZ,
                          reinterpret_cast<const BYTE*>(
                              kWindowsNotificationAppName),
                          static_cast<DWORD>((wcslen(kWindowsNotificationAppName) +
                                                 1) * sizeof(wchar_t)));
  if (result == ERROR_SUCCESS) {
    result = RegSetValueExW(key, L"CustomActivator", 0, REG_SZ,
                            reinterpret_cast<const BYTE*>(
                                kWindowsNotificationClsidBraced),
                            static_cast<DWORD>(
                                (wcslen(kWindowsNotificationClsidBraced) + 1) *
                                sizeof(wchar_t)));
  }
  RegCloseKey(key);
  return HRESULT_FROM_WIN32(result);
}

}  // namespace

std::wstring WindowsNotificationLocalServer32DefaultValue(
    const std::wstring& exe_path) {
  return L"\"" + exe_path + L"\"";
}

std::wstring WindowsNotificationLocalServer32ServerExecutableValue(
    const std::wstring& exe_path) {
  return exe_path;
}

std::wstring WindowsNotificationLocalServer32KeyPath() {
  return std::wstring(L"Software\\Classes\\CLSID\\") +
         kWindowsNotificationClsidBraced + L"\\LocalServer32";
}

std::wstring WindowsNotificationAumidKeyPath() {
  return std::wstring(L"Software\\Classes\\AppUserModelId\\") +
         kWindowsNotificationAumid;
}

std::wstring WindowsNotificationShortcutPath(
    const std::wstring& programs_folder) {
  return programs_folder + L"\\" + kWindowsNotificationShortcutName;
}

WindowsNotificationRegistrationResult EnsureWindowsNotificationRegistration() {
  WindowsNotificationRegistrationResult result;
  try {
    CLSID activator = {};
    if (FAILED(CLSIDFromString(kWindowsNotificationClsidBraced, &activator))) {
      result.failure_stage = "exePath";
      return result;
    }
    std::wstring exe_path;
    if (!GetCurrentExePath(&exe_path)) {
      result.failure_stage = "exePath";
      return result;
    }
    std::wstring programs;
    if (!GetProgramsFolder(&programs)) {
      result.failure_stage = "programsFolder";
      return result;
    }
    const HRESULT shortcut_hr = CreateOrUpdateShortcut(
        WindowsNotificationShortcutPath(programs), exe_path,
        DirectoryOf(exe_path), activator);
    if (FAILED(shortcut_hr)) {
      result.failure_stage = "shortcut";
      return result;
    }
    if (FAILED(WriteLocalServer32(exe_path))) {
      result.failure_stage = "localServer32";
      return result;
    }
    if (FAILED(WriteAumidKey())) {
      result.failure_stage = "aumidKey";
      return result;
    }
    result.ok = true;
    return result;
  } catch (...) {
    // 注册链全是 Win32/COM 调用，理论上不抛；catch-all 保证异常不越过
    // 调用方（wWinMain），失败语义与其它 stage 一致。
    result.ok = false;
    result.failure_stage = "shortcut";
    return result;
  }
}
