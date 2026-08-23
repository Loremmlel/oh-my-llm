#include "windows_notification_protocol.h"

#include <windows.h>

#include <cstring>

namespace {

uint16_t ReadLe16(const unsigned char* p) {
  return static_cast<uint16_t>(p[0] | (p[1] << 8));
}

uint32_t ReadLe32(const unsigned char* p) {
  return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
         (static_cast<uint32_t>(p[2]) << 16) |
         (static_cast<uint32_t>(p[3]) << 24);
}

void WriteLe16(unsigned char* p, uint16_t v) {
  p[0] = static_cast<unsigned char>(v & 0xFF);
  p[1] = static_cast<unsigned char>((v >> 8) & 0xFF);
}

void WriteLe32(unsigned char* p, uint32_t v) {
  p[0] = static_cast<unsigned char>(v & 0xFF);
  p[1] = static_cast<unsigned char>((v >> 8) & 0xFF);
  p[2] = static_cast<unsigned char>((v >> 16) & 0xFF);
  p[3] = static_cast<unsigned char>((v >> 24) & 0xFF);
}

WindowsNotificationFrameDecodeStatus DecodeFrameInternal(
    const unsigned char* data, size_t size,
    WindowsNotificationDecodedFrame* out) {
  if (size < kWindowsNotificationFrameHeaderSize) {
    return WindowsNotificationFrameDecodeStatus::kTruncated;
  }
  if (std::memcmp(data, "OMLN", 4) != 0) {
    return WindowsNotificationFrameDecodeStatus::kBadMagic;
  }
  const uint16_t version = ReadLe16(data + 4);
  if (version != kWindowsNotificationFrameVersion) {
    return WindowsNotificationFrameDecodeStatus::kBadVersion;
  }
  const uint16_t kind = ReadLe16(data + 6);
  if (kind != kWindowsNotificationKindActivation &&
      kind != kWindowsNotificationKindActivateWindow) {
    return WindowsNotificationFrameDecodeStatus::kBadKind;
  }
  const uint32_t payload_len = ReadLe32(data + 8);
  if (payload_len > kWindowsNotificationMaxPayloadBytes) {
    return WindowsNotificationFrameDecodeStatus::kPayloadTooLong;
  }
  if (size != kWindowsNotificationFrameHeaderSize + payload_len) {
    return WindowsNotificationFrameDecodeStatus::kLengthMismatch;
  }
  if (kind == kWindowsNotificationKindActivateWindow && payload_len != 0) {
    return WindowsNotificationFrameDecodeStatus::kFocusWithPayload;
  }
  if (kind == kWindowsNotificationKindActivation && payload_len > 0) {
    if (!WindowsNotificationIsValidUtf8(
            data + kWindowsNotificationFrameHeaderSize, payload_len)) {
      return WindowsNotificationFrameDecodeStatus::kBadUtf8;
    }
  }
  out->kind = kind;
  out->payload.assign(data + kWindowsNotificationFrameHeaderSize,
                      data + kWindowsNotificationFrameHeaderSize + payload_len);
  return WindowsNotificationFrameDecodeStatus::kOk;
}

}  // namespace

WindowsNotificationFrameDecodeStatus WindowsNotificationDecodeFrame(
    const unsigned char* data, size_t size,
    WindowsNotificationDecodedFrame* out, const char** reason) {
  const WindowsNotificationFrameDecodeStatus status = DecodeFrameInternal(
      data, size, out);
  if (reason != nullptr) {
    *reason = WindowsNotificationFrameDecodeReason(status);
  }
  return status;
}

std::vector<unsigned char> WindowsNotificationEncodeFrame(
    uint16_t kind, const unsigned char* payload, size_t payload_size) {
  std::vector<unsigned char> frame(kWindowsNotificationFrameHeaderSize +
                                   payload_size);
  std::memcpy(frame.data(), "OMLN", 4);
  WriteLe16(frame.data() + 4, kWindowsNotificationFrameVersion);
  WriteLe16(frame.data() + 6, kind);
  WriteLe32(frame.data() + 8, static_cast<uint32_t>(payload_size));
  if (payload_size > 0 && payload != nullptr) {
    std::memcpy(frame.data() + kWindowsNotificationFrameHeaderSize, payload,
                payload_size);
  }
  return frame;
}

std::vector<unsigned char> WindowsNotificationEncodeAck(uint16_t status) {
  std::vector<unsigned char> ack(kWindowsNotificationAckSize);
  std::memcpy(ack.data(), "OMLA", 4);
  WriteLe16(ack.data() + 4, kWindowsNotificationAckVersion);
  WriteLe16(ack.data() + 6, status);
  return ack;
}

bool WindowsNotificationDecodeAck(const unsigned char* data, size_t size,
                                  uint16_t* status) {
  if (size != kWindowsNotificationAckSize) {
    return false;
  }
  if (std::memcmp(data, "OMLA", 4) != 0) {
    return false;
  }
  if (ReadLe16(data + 4) != kWindowsNotificationAckVersion) {
    return false;
  }
  *status = ReadLe16(data + 6);
  return true;
}

const char* WindowsNotificationFrameDecodeReason(
    WindowsNotificationFrameDecodeStatus status) {
  switch (status) {
    case WindowsNotificationFrameDecodeStatus::kOk:
      return "ok";
    case WindowsNotificationFrameDecodeStatus::kTruncated:
      return "truncated";
    case WindowsNotificationFrameDecodeStatus::kBadMagic:
      return "badMagic";
    case WindowsNotificationFrameDecodeStatus::kBadVersion:
      return "badVersion";
    case WindowsNotificationFrameDecodeStatus::kBadKind:
      return "badKind";
    case WindowsNotificationFrameDecodeStatus::kPayloadTooLong:
      return "tooLong";
    case WindowsNotificationFrameDecodeStatus::kLengthMismatch:
      return "lengthMismatch";
    case WindowsNotificationFrameDecodeStatus::kFocusWithPayload:
      return "focusPayload";
    case WindowsNotificationFrameDecodeStatus::kBadUtf8:
      return "badUtf8";
  }
  return "unknown";
}

bool WindowsNotificationIsValidUtf8(const unsigned char* data, size_t size) {
  size_t i = 0;
  while (i < size) {
    const unsigned char b = data[i];
    if (b < 0x80) {
      ++i;
      continue;
    }
    int continuation = 0;
    uint32_t codepoint = 0;
    if ((b & 0xE0) == 0xC0) {
      continuation = 1;
      codepoint = b & 0x1F;
      if (codepoint < 0x02) {
        // 2 字节 overlong 形式只覆盖 U+0000..U+007F，必须拒绝。
        return false;
      }
    } else if ((b & 0xF0) == 0xE0) {
      continuation = 2;
      codepoint = b & 0x0F;
    } else if ((b & 0xF8) == 0xF0) {
      continuation = 3;
      codepoint = b & 0x07;
      if (codepoint > 0x04) {
        // 超出 U+10FFFF 的首字节。
        return false;
      }
    } else {
      // 连续字节出现在首字节位置，或非法首字节。
      return false;
    }
    for (int k = 1; k <= continuation; ++k) {
      if (i + static_cast<size_t>(k) >= size) {
        // 序列在消息末尾被截断。
        return false;
      }
      const unsigned char cb = data[i + k];
      if ((cb & 0xC0) != 0x80) {
        return false;
      }
      codepoint = (codepoint << 6) | (cb & 0x3F);
    }
    if (continuation == 2 && codepoint < 0x800) {
      return false;
    }
    if (continuation == 3 && codepoint < 0x10000) {
      return false;
    }
    if (codepoint >= 0xD800 && codepoint <= 0xDFFF) {
      // UTF-16 代理半区不允许出现在合法 UTF-8 中。
      return false;
    }
    i += static_cast<size_t>(continuation) + 1;
  }
  return true;
}

bool WindowsNotificationUtf8FromUtf16(const wchar_t* input, std::string* out) {
  if (input == nullptr) {
    out->clear();
    return true;
  }
  const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, input, -1,
                                       nullptr, 0, nullptr, nullptr);
  if (size <= 0) {
    return false;
  }
  out->resize(static_cast<size_t>(size) - 1);
  const int written = WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, input, -1, out->data(),
      static_cast<int>(out->size() + 1), nullptr, nullptr);
  return written > 0;
}

bool WindowsNotificationUtf16FromUtf8(const std::string& input,
                                      std::wstring* out) {
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                       input.data(),
                                       static_cast<int>(input.size()), nullptr,
                                       0);
  if (size <= 0) {
    return false;
  }
  out->resize(static_cast<size_t>(size));
  const int written =
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input.data(),
                          static_cast<int>(input.size()), out->data(), size);
  return written > 0;
}

std::string WindowsNotificationXmlEscape(const std::string& input) {
  std::string out;
  out.reserve(input.size() + 16);
  for (const char c : input) {
    switch (c) {
      case '&':
        out += "&amp;";
        break;
      case '<':
        out += "&lt;";
        break;
      case '>':
        out += "&gt;";
        break;
      case '"':
        out += "&quot;";
        break;
      case '\'':
        out += "&apos;";
        break;
      default:
        out += c;
        break;
    }
  }
  return out;
}
