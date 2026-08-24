#ifndef RUNNER_WINDOWS_NOTIFICATION_PROTOCOL_H_
#define RUNNER_WINDOWS_NOTIFICATION_PROTOCOL_H_

// 通知宿主 v1 管道帧协议与纯文本 helper。
//
// 一条 pipe 连接恰好承载一条 request frame 和一条 8 字节 ACK：
//   offset 0   magic "OMLN"            （4 bytes，ASCII）
//   offset 4   version LE uint16 == 1
//   offset 6   kind   LE uint16        （1=notificationActivation，2=activateWindow）
//   offset 8   payloadByteLength LE uint32
//   offset 12  payload bytes（kind=1 时必须为合法 UTF-8 且 ≤1024；kind=2 必须为空）
//
// ACK（8 bytes）：magic "OMLA"、version LE uint16 == 1、status LE uint16
// （0=accepted、1=invalidFrame、2=queueFull、3=shuttingDown）。
//
// 无条件拒绝：未知 version/kind、超长 payload、截断 frame、header 长度与
// message 长度不一致、focus frame 带 payload、非法 UTF-8、ERROR_MORE_DATA。
//
// 本文件保持零 Windows/COM 依赖，可被原生测试直接链接。

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

constexpr size_t kWindowsNotificationFrameHeaderSize = 12;
constexpr size_t kWindowsNotificationMaxPayloadBytes = 1024;
constexpr size_t kWindowsNotificationMaxFrameBytes =
    kWindowsNotificationFrameHeaderSize + kWindowsNotificationMaxPayloadBytes;
constexpr uint16_t kWindowsNotificationFrameVersion = 1;
constexpr uint16_t kWindowsNotificationKindActivation = 1;
constexpr uint16_t kWindowsNotificationKindActivateWindow = 2;

constexpr size_t kWindowsNotificationAckSize = 8;
constexpr uint16_t kWindowsNotificationAckVersion = 1;
constexpr uint16_t kWindowsNotificationAckAccepted = 0;
constexpr uint16_t kWindowsNotificationAckInvalidFrame = 1;
constexpr uint16_t kWindowsNotificationAckQueueFull = 2;
constexpr uint16_t kWindowsNotificationAckShuttingDown = 3;

enum class WindowsNotificationFrameDecodeStatus {
  kOk = 0,
  kTruncated,
  kBadMagic,
  kBadVersion,
  kBadKind,
  kPayloadTooLong,
  kLengthMismatch,
  kFocusWithPayload,
  kBadUtf8,
};

struct WindowsNotificationDecodedFrame {
  uint16_t kind = 0;
  std::vector<unsigned char> payload;
};

// 解码并完整校验一条原始 pipe message；`reason`（非空时）收到稳定 ASCII
// reason code，供固定 stage 日志使用。
WindowsNotificationFrameDecodeStatus WindowsNotificationDecodeFrame(
    const unsigned char* data, size_t size,
    WindowsNotificationDecodedFrame* out, const char** reason);

// 构造一条 request frame。调用方须自行保证 kind 对应的 payload 约束。
std::vector<unsigned char> WindowsNotificationEncodeFrame(
    uint16_t kind, const unsigned char* payload, size_t payload_size);

std::vector<unsigned char> WindowsNotificationEncodeAck(uint16_t status);

// 解码 8 字节 ACK；size/magic/version 不匹配返回 false。
bool WindowsNotificationDecodeAck(const unsigned char* data, size_t size,
                                  uint16_t* status);

const char* WindowsNotificationFrameDecodeReason(
    WindowsNotificationFrameDecodeStatus status);

// —— 文本 helper ——

// 严格 UTF-8 校验：拒绝截断序列、overlong 编码、代理半区与 > U+10FFFF。
bool WindowsNotificationIsValidUtf8(const unsigned char* data, size_t size);

// UTF-16（wchar_t）→ UTF-8；输入可为 nullptr（视为空串）。失败返回 false。
bool WindowsNotificationUtf8FromUtf16(const wchar_t* input, std::string* out);

// UTF-8 → UTF-16；失败返回 false。
bool WindowsNotificationUtf16FromUtf8(const std::string& input,
                                      std::wstring* out);

// 对双引号 XML 属性内容做集中转义（& < > " '）。
std::string WindowsNotificationXmlEscape(const std::string& input);

// 队列满丢弃的唯一诊断出口：经调试通道输出固定 token
// （native_activation_queue_full）。pending queue 满分支与 relay 晋升回填
// 溢出都收敛到这里，字面量只有一处来源；token 不含任何动态内容。
void WindowsNotificationReportQueueFullToken();

#endif  // RUNNER_WINDOWS_NOTIFICATION_PROTOCOL_H_
