#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <chrono>

// 只安装在独立诊断 runner；原生消息发给其自己的 Flutter 子窗口。
inline void InstallInputProbe(flutter::BinaryMessenger* messenger, HWND child) {
  static auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "probe/input", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([child](const auto& call, auto result) {
    if (call.method_name() != "char") {
      result->NotImplemented();
      return;
    }
    const auto start = std::chrono::steady_clock::now();
    SendMessage(child, WM_CHAR, std::get<int32_t>(*call.arguments()), 1);
    const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now() - start).count();
    result->Success(flutter::EncodableValue(static_cast<int64_t>(elapsed)));
  });
}
