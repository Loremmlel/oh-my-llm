#include "windows_notification_toast.h"

#include <windows.h>

#include <roapi.h>
#include <winstring.h>
#include <wrl/client.h>

#include <windows.data.xml.dom.h>
#include <windows.foundation.h>
#include <windows.ui.notifications.h>

#include "windows_notification_protocol.h"
#include "windows_notification_registration.h"

namespace {

// Toast Tag 使用十进制 notification ID；区间与 Dart 侧生成的 ID 契约一致。
constexpr int64_t kMinNotificationId = 10000;
constexpr int64_t kMaxNotificationId = 2147483646;
constexpr size_t kMaxTitleBytes = 128;
constexpr size_t kMaxBodyBytes = 512;

// HSTRING 的 RAII 包装：WindowsDeleteString 必须与 WindowsCreateString 成对，
// 提前 return 的错误路径很容易漏掉，集中在这里处理。
class ScopedHString {
 public:
  explicit ScopedHString(const wchar_t* text) {
    WindowsCreateString(text, static_cast<UINT32>(wcslen(text)), &handle_);
  }
  ~ScopedHString() { WindowsDeleteString(handle_); }
  HSTRING get() const { return handle_; }
  ScopedHString(const ScopedHString&) = delete;
  ScopedHString& operator=(const ScopedHString&) = delete;

 private:
  HSTRING handle_ = nullptr;
};

}  // namespace

bool WindowsNotificationValidateShowParams(
    const WindowsNotificationShowParams& params) {
  if (params.id < kMinNotificationId || params.id > kMaxNotificationId) {
    return false;
  }
  if (params.title.empty() || params.title.size() > kMaxTitleBytes) {
    return false;
  }
  if (params.body.empty() || params.body.size() > kMaxBodyBytes) {
    return false;
  }
  if (params.payload.size() > kWindowsNotificationMaxPayloadBytes) {
    return false;
  }
  // title/body/payload 会被拼进 XML 与 launch 属性，必须是合法 UTF-8。
  if (!WindowsNotificationIsValidUtf8(
          reinterpret_cast<const unsigned char*>(params.title.data()),
          params.title.size()) ||
      !WindowsNotificationIsValidUtf8(
          reinterpret_cast<const unsigned char*>(params.body.data()),
          params.body.size()) ||
      !WindowsNotificationIsValidUtf8(
          reinterpret_cast<const unsigned char*>(params.payload.data()),
          params.payload.size())) {
    return false;
  }
  return true;
}

std::string WindowsNotificationBuildToastXml(
    const WindowsNotificationShowParams& params) {
  if (!WindowsNotificationValidateShowParams(params)) {
    return std::string();
  }
  // 固定 ToastGeneric 双 text 模板；launch 属性承载 Dart payload（已转义）。
  // 不包含 audio/scenario/图片，声音语义交给系统默认。
  return "<toast launch=\"" + WindowsNotificationXmlEscape(params.payload) +
         "\"><visual><binding template=\"ToastGeneric\"><text>" +
         WindowsNotificationXmlEscape(params.title) + "</text><text>" +
         WindowsNotificationXmlEscape(params.body) +
         "</text></binding></visual></toast>";
}

bool WindowsNotificationShowToast(
    const WindowsNotificationShowParams& params) {
  using ABI::Windows::Data::Xml::Dom::IXmlDocument;
  using ABI::Windows::Data::Xml::Dom::IXmlDocumentIO;
  using ABI::Windows::UI::Notifications::IToastNotification;
  using ABI::Windows::UI::Notifications::IToastNotificationFactory;
  using ABI::Windows::UI::Notifications::IToastNotificationManagerStatics;
  using ABI::Windows::UI::Notifications::IToastNotifier;
  using Microsoft::WRL::ComPtr;

  try {
    const std::string xml = WindowsNotificationBuildToastXml(params);
    if (xml.empty()) {
      return false;
    }
    std::wstring xml_wide;
    if (!WindowsNotificationUtf16FromUtf8(xml, &xml_wide)) {
      return false;
    }

    // Toast 的 AUMID 必须与 shortcut/AppUserModelId 注册一致，从 registration
    // 头取产品固定值，避免第二处硬编码漂移。
    const std::wstring aumid_wide(kWindowsNotificationAumid);

    // ToastNotificationManager 静态类的 base 接口只有无参 CreateToastNotifier
    // （取调用方包身份）；未打包应用必须用带 AUMID 的 WithId 变体。
    ScopedHString manager_name(
        RuntimeClass_Windows_UI_Notifications_ToastNotificationManager);
    ComPtr<IToastNotificationManagerStatics> manager;
    HRESULT hr = RoGetActivationFactory(
        manager_name.get(), IID_PPV_ARGS(manager.GetAddressOf()));
    if (FAILED(hr)) {
      return false;
    }

    ScopedHString aumid(aumid_wide.c_str());
    ComPtr<IToastNotifier> notifier;
    hr = manager->CreateToastNotifierWithId(aumid.get(),
                                            notifier.GetAddressOf());
    if (FAILED(hr)) {
      return false;
    }

    // XmlDocument 没有 LoadXml 静态方法：先激活实例，再经 IXmlDocumentIO 加载。
    ScopedHString document_name(
        RuntimeClass_Windows_Data_Xml_Dom_XmlDocument);
    ComPtr<IActivationFactory> document_factory;
    hr = RoGetActivationFactory(document_name.get(),
                                IID_PPV_ARGS(document_factory.GetAddressOf()));
    ComPtr<IXmlDocument> document;
    ComPtr<IXmlDocumentIO> document_io;
    if (SUCCEEDED(hr)) {
      ComPtr<IInspectable> inspectable;
      hr = document_factory->ActivateInstance(inspectable.GetAddressOf());
      if (SUCCEEDED(hr)) {
        hr = inspectable.As(&document);
      }
      if (SUCCEEDED(hr)) {
        hr = inspectable.As(&document_io);
      }
    }
    if (SUCCEEDED(hr)) {
      ScopedHString xml_string(xml_wide.c_str());
      hr = document_io->LoadXml(xml_string.get());
    }
    if (FAILED(hr)) {
      return false;
    }

    ScopedHString toast_name(
        RuntimeClass_Windows_UI_Notifications_ToastNotification);
    ComPtr<IToastNotificationFactory> toast_factory;
    hr = RoGetActivationFactory(toast_name.get(),
                                IID_PPV_ARGS(toast_factory.GetAddressOf()));
    ComPtr<IToastNotification> notification;
    if (SUCCEEDED(hr)) {
      hr = toast_factory->CreateToastNotification(document.Get(),
                                                  notification.GetAddressOf());
    }
    if (FAILED(hr)) {
      return false;
    }

    // Tag 用十进制 notification ID：同 ID 的后续展示由系统按 Tag 去重替换。
    // put_Tag 在 IToastNotification2（当前 SDK 的版本化接口）上。
    ComPtr<ABI::Windows::UI::Notifications::IToastNotification2> tagged;
    hr = notification.As(&tagged);
    if (SUCCEEDED(hr)) {
      ScopedHString tag(std::to_wstring(params.id).c_str());
      hr = tagged->put_Tag(tag.get());
    }
    if (FAILED(hr)) {
      return false;
    }

    hr = notifier->Show(notification.Get());
    return SUCCEEDED(hr);
  } catch (...) {
    // 最外层 catch-all：WinRT activation/COM 的任何异常都不越过调用方；
    // 失败以 false 返回，由 channel 层转成固定结果。
    return false;
  }
}
