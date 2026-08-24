#ifndef RUNNER_WINDOWS_NOTIFICATION_TOAST_H_
#define RUNNER_WINDOWS_NOTIFICATION_TOAST_H_

// 一次性 Toast 展示 helper：ToastGeneric XML、集中转义与 native 参数再校验。使用当前 Windows SDK 的 WRL/C++/WinRT ABI，不引入第三方 DLL。

#include <cstdint>
#include <string>

// Dart show() 的 native 参数（channel 层反序列化后填充）。
struct WindowsNotificationShowParams {
  int64_t id = 0;
  std::string title;
  std::string body;
  std::string payload;
};

// native 再校验：Dart 侧生成的参数也必须在 native 边界再次收紧，防止
// 上层将来越过 client 直接拼出越界 Toast。
//  - id ∈ [10000, 2147483646]（Toast Tag 用十进制 notification ID）；
//  - title/body 非空且分别 ≤128 / ≤512 UTF-8 bytes；
//  - payload ≤1024 UTF-8 bytes。
// 任一不满足返回 false；channel 层据此返回 false，不触发 WinRT。
bool WindowsNotificationValidateShowParams(
    const WindowsNotificationShowParams& params);

// 构造 ToastGeneric XML：root launch 属性为（已转义的）payload，
// text+text 为 title/body。参数不合法时返回空串。
// XML 不包含 <audio>、scenario、图片或自定义 URI。
std::string WindowsNotificationBuildToastXml(
    const WindowsNotificationShowParams& params);

// 在已运行 message loop 的 STA 线程上展示 Toast（生产由 runner UI STA 调
// 用）。最外层 catch-all；成功与否以 bool 返回，不向调用方抛出任何内容。
bool WindowsNotificationShowToast(
    const WindowsNotificationShowParams& params);

#endif  // RUNNER_WINDOWS_NOTIFICATION_TOAST_H_
