#include "windows_notification_instance_coordinator.h"

#include <sddl.h>

#include <cstring>

#include "windows_notification_protocol.h"

namespace {

uint32_t TickMs() {
  return static_cast<uint32_t>(GetTickCount64() & 0xFFFFFFFF);
}

// 有界等待一个 overlapped 操作：100ms 切片轮询，超时由调用方 CancelIoEx。
bool WaitOverlapped(HANDLE file, OVERLAPPED* ov, DWORD bound_ms) {
  const uint32_t started = TickMs();
  for (;;) {
    if (WaitForSingleObject(ov->hEvent, 100) == WAIT_OBJECT_0) {
      return true;
    }
    if (TickMs() - started > bound_ms) {
      return false;
    }
  }
}

bool TokenUserSid(HANDLE access_token, std::vector<unsigned char>* out) {
  DWORD size = 0;
  GetTokenInformation(access_token, TokenUser, nullptr, 0, &size);
  if (size == 0) {
    return false;
  }
  std::vector<unsigned char> buffer(size, 0);
  if (!GetTokenInformation(access_token, TokenUser, buffer.data(), size,
                           &size)) {
    return false;
  }
  const auto* user = reinterpret_cast<const TOKEN_USER*>(buffer.data());
  if (user->User.Sid == nullptr) {
    return false;
  }
  const DWORD sid_size = GetLengthSid(user->User.Sid);
  out->resize(sid_size);
  if (!CopySid(sid_size, reinterpret_cast<PSID>(out->data()),
               user->User.Sid)) {
    out->clear();
    return false;
  }
  return true;
}

}  // namespace

// ---------------------------------------------------------------------------
// -Embedding token 解析
// ---------------------------------------------------------------------------

bool WindowsNotificationCommandLineHasEmbeddingToken(
    const std::vector<std::wstring>& arguments) {
  for (const std::wstring& argument : arguments) {
    // 只接受整段等于 -Embedding / /Embedding 的独立 token：COM 启动只传这一个
    // 参数，子串匹配会把 "--Embedding" 之类用户参数误判成 COM relay。
    if (_wcsicmp(argument.c_str(), L"-Embedding") == 0 ||
        _wcsicmp(argument.c_str(), L"/Embedding") == 0) {
      return true;
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// 原子选主
// ---------------------------------------------------------------------------

WindowsNotificationInstanceClaim WindowsNotificationClaimInstance(
    const std::vector<std::wstring>& command_line, const wchar_t* mutex_name) {
  WindowsNotificationInstanceClaim claim;
  // CreateMutexW + 紧随其后的 GetLastError 检查是唯一身份判断；Local\ 命名
  // 空间已把对象限定在当前 logon session，不需要进程枚举或路径猜测。
  SetLastError(ERROR_SUCCESS);
  claim.instance_mutex = CreateMutexW(nullptr, FALSE, mutex_name);
  if (claim.instance_mutex == nullptr) {
    claim.mode = WindowsNotificationHostMode::kFatal;
    return claim;
  }
  if (GetLastError() != ERROR_ALREADY_EXISTS) {
    claim.mode = WindowsNotificationHostMode::kPrimary;
  } else if (WindowsNotificationCommandLineHasEmbeddingToken(command_line)) {
    claim.mode = WindowsNotificationHostMode::kActivationRelay;
  } else {
    claim.mode = WindowsNotificationHostMode::kManualSecondary;
  }
  return claim;
}

// ---------------------------------------------------------------------------
// manual-reset ready event
// ---------------------------------------------------------------------------

HANDLE WindowsNotificationOpenReadyEventAsOwner(const wchar_t* event_name) {
  SetLastError(ERROR_SUCCESS);
  HANDLE ready_event = CreateEventW(nullptr, TRUE, FALSE, event_name);
  if (ready_event == nullptr) {
    return nullptr;
  }
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    // 上一任 primary 可能在 shutdown reset 前被杀；新 owner 必须丢弃遗留的
    // signaled 状态，否则 relay 会把死掉的 owner 当作 ready。
    ResetEvent(ready_event);
  }
  return ready_event;
}

void WindowsNotificationSetReadyEvent(HANDLE ready_event) {
  if (ready_event != nullptr) {
    SetEvent(ready_event);
  }
}

void WindowsNotificationResetReadyEvent(HANDLE ready_event) {
  if (ready_event != nullptr) {
    ResetEvent(ready_event);
  }
}

bool WindowsNotificationIsReadyEventSignaled(HANDLE ready_event) {
  return ready_event != nullptr &&
         WaitForSingleObject(ready_event, 0) == WAIT_OBJECT_0;
}

// ---------------------------------------------------------------------------
// activator lease mutex
// ---------------------------------------------------------------------------

HANDLE WindowsNotificationOpenLeaseMutex(const wchar_t* mutex_name) {
  return CreateMutexW(nullptr, FALSE, mutex_name);
}

DWORD WindowsNotificationAcquireLease(HANDLE lease_mutex, DWORD total_wait_ms,
                                      DWORD slice_wait_ms) {
  const ULONGLONG deadline = GetTickCount64() + total_wait_ms;
  for (;;) {
    // WAIT_ABANDONED 视为取得：持有者崩溃时 OS 已释放所有权，lease 语义允许
    // 接管（对应的 class object 已随进程消失）。
    const DWORD wait = WaitForSingleObject(lease_mutex, slice_wait_ms);
    if (wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED) {
      return wait;
    }
    if (GetTickCount64() >= deadline) {
      return WAIT_TIMEOUT;
    }
  }
}

void WindowsNotificationReleaseLeaseMutex(HANDLE lease_mutex) {
  if (lease_mutex != nullptr) {
    ReleaseMutex(lease_mutex);
  }
}

// ---------------------------------------------------------------------------
// pipe 显式 DACL
// ---------------------------------------------------------------------------

WindowsNotificationPipeSecurity::~WindowsNotificationPipeSecurity() {
  if (acl != nullptr) {
    LocalFree(acl);
  }
  if (descriptor != nullptr) {
    LocalFree(descriptor);
  }
}

bool WindowsNotificationBuildPipeSecurity(
    HANDLE access_token, WindowsNotificationPipeSecurity* out) {
  if (out == nullptr || access_token == nullptr) {
    return false;
  }
  // 只允许当前 logon user SID 与 LocalSystem 完全访问；不构造成功就返回
  // false，调用方必须据此禁用 IPC，绝不能退回默认（宽松）pipe ACL。
  if (!TokenUserSid(access_token, &out->user_sid)) {
    return false;
  }
  out->system_sid.resize(SECURITY_MAX_SID_SIZE);
  DWORD system_size = SECURITY_MAX_SID_SIZE;
  if (!CreateWellKnownSid(WinLocalSystemSid, nullptr,
                          reinterpret_cast<PSID>(out->system_sid.data()),
                          &system_size)) {
    return false;
  }
  out->system_sid.resize(system_size);

  const DWORD acl_bytes =
      sizeof(ACL) +
      2 * (sizeof(ACCESS_ALLOWED_ACE) - sizeof(DWORD) +
           SECURITY_MAX_SID_SIZE);
  out->acl = static_cast<ACL*>(LocalAlloc(LMEM_ZEROINIT, acl_bytes));
  out->descriptor = static_cast<SECURITY_DESCRIPTOR*>(
      LocalAlloc(LMEM_ZEROINIT, SECURITY_DESCRIPTOR_MIN_LENGTH));
  if (out->acl == nullptr || out->descriptor == nullptr) {
    return false;
  }
  if (!InitializeAcl(out->acl, acl_bytes, ACL_REVISION)) {
    return false;
  }
  if (!InitializeSecurityDescriptor(out->descriptor,
                                    SECURITY_DESCRIPTOR_REVISION)) {
    return false;
  }
  // 两条允许 ACE：user 与 LocalSystem 各一条，均为完全访问（file 语义）。
  if (!AddAccessAllowedAce(out->acl, ACL_REVISION, FILE_ALL_ACCESS,
                           reinterpret_cast<PSID>(out->user_sid.data()))) {
    return false;
  }
  if (!AddAccessAllowedAce(out->acl, ACL_REVISION, FILE_ALL_ACCESS,
                           reinterpret_cast<PSID>(out->system_sid.data()))) {
    return false;
  }
  if (!SetSecurityDescriptorDacl(out->descriptor, TRUE, out->acl, FALSE)) {
    return false;
  }
  out->sa.nLength = sizeof(SECURITY_ATTRIBUTES);
  out->sa.lpSecurityDescriptor = out->descriptor;
  out->sa.bInheritHandle = FALSE;
  return true;
}

// ---------------------------------------------------------------------------
// pipe server
// ---------------------------------------------------------------------------

bool WindowsNotificationPipeServer::Start(ServeHandler handler,
                                          std::atomic<bool>* stopping,
                                          const wchar_t* pipe_name,
                                          HANDLE access_token) {
  if (handler == nullptr || stopping == nullptr || pipe_name == nullptr) {
    return false;
  }
  // DACL 在启动线程构造：失败立即返回 false（测试据此断言「构造失败时 server
  // 启动失败且 instance mutex 不受影响」），serve 线程只消费结果。
  auto security = std::make_unique<WindowsNotificationPipeSecurity>();
  if (!WindowsNotificationBuildPipeSecurity(access_token, security.get())) {
    return false;
  }
  security_ = std::move(security);
  handler_ = std::move(handler);
  stopping_ = stopping;
  pipe_name_ = pipe_name;
  access_token_ = access_token;
  ready_event_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (ready_event_ == nullptr) {
    return false;
  }
  thread_ = CreateThread(nullptr, 0, &WindowsNotificationPipeServer::ServeThreadProc,
                         this, 0, nullptr);
  if (thread_ == nullptr) {
    return false;
  }
  // 等 serve 线程完成首个 pipe 实例创建（或失败退出），让 Start 返回时
  // 「pipe 可达」与否是确定的；测试不需要再 Sleep 猜测。
  const DWORD wait = WaitForSingleObject(ready_event_,
                                         kWindowsNotificationPipeServerOpWaitMs);
  const bool serving = wait == WAIT_OBJECT_0 && pipe_created_;
  if (!serving) {
    Stop();
  }
  return serving;
}

void WindowsNotificationPipeServer::Stop() {
  if (thread_ != nullptr) {
    // stopping_ 由调用方置位后再调用；serve 循环在 overlapped 等待的 200ms
    // 切片间检查它，因此 join 是有界的。
    WaitForSingleObject(thread_, kWindowsNotificationPipeServerOpWaitMs + 2000);
    CloseHandle(thread_);
    thread_ = nullptr;
  }
  if (ready_event_ != nullptr) {
    CloseHandle(ready_event_);
    ready_event_ = nullptr;
  }
}

DWORD WINAPI WindowsNotificationPipeServer::ServeThreadProc(void* param) {
  static_cast<WindowsNotificationPipeServer*>(param)->ServeLoop();
  return 0;
}

void WindowsNotificationPipeServer::ServeLoop() {
  SECURITY_ATTRIBUTES* attributes = &security_->sa;
  while (!stopping_->load()) {
    const HANDLE pipe =
        CreateNamedPipeW(pipe_name_,
                         PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
                         PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT |
                             PIPE_REJECT_REMOTE_CLIENTS,
                         1, static_cast<DWORD>(kWindowsNotificationMaxFrameBytes),
                         static_cast<DWORD>(kWindowsNotificationMaxFrameBytes), 0,
                         attributes);
    if (pipe == INVALID_HANDLE_VALUE) {
      // 首个实例创建失败也要唤醒 Start 的等待，让它拿到确定的失败结论。
      if (!pipe_created_) {
        SetEvent(ready_event_);
      }
      break;
    }
    if (!pipe_created_) {
      pipe_created_ = true;
      SetEvent(ready_event_);
    }

    OVERLAPPED ov = {};
    ov.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    BOOL connected = ConnectNamedPipe(pipe, &ov);
    DWORD gle = GetLastError();
    bool have_client = false;
    if (!connected && gle == ERROR_IO_PENDING) {
      // 以 200ms 切片轮询 connect 等待，保证 shutdown 时能及时退出。
      for (;;) {
        if (WaitForSingleObject(ov.hEvent, 200) == WAIT_OBJECT_0) {
          have_client = true;
          break;
        }
        if (stopping_->load()) {
          break;
        }
      }
      if (!have_client) {
        CancelIoEx(pipe, &ov);
      }
    } else if (connected || gle == ERROR_PIPE_CONNECTED) {
      have_client = true;
    }

    if (have_client && !stopping_->load()) {
      // 读缓冲比最大帧多 1 字节：超长消息通过 ERROR_MORE_DATA 显式暴露并
      // 拒绝，而不是静默截断后误判为合法帧。
      unsigned char buffer[kWindowsNotificationMaxFrameBytes + 1];
      DWORD read_bytes = 0;
      ResetEvent(ov.hEvent);
      bool read_ok = false;
      if (ReadFile(pipe, buffer, sizeof(buffer), &read_bytes, &ov)) {
        read_ok = true;
      } else if (GetLastError() == ERROR_IO_PENDING) {
        if (WaitOverlapped(pipe, &ov, kWindowsNotificationPipeServerOpWaitMs)) {
          if (GetOverlappedResult(pipe, &ov, &read_bytes, FALSE)) {
            read_ok = true;
          }
          // 失败包含 ERROR_MORE_DATA：超长消息被读缓冲（max+1）显式暴露，
          // 与其它读失败一样回 invalidFrame，不做截断解析。
        } else {
          CancelIoEx(pipe, &ov);
        }
      }

      uint16_t ack_status = kWindowsNotificationAckInvalidFrame;
      WindowsNotificationDecodedFrame frame;
      if (read_ok) {
        const char* reason = "";
        const WindowsNotificationFrameDecodeStatus status =
            WindowsNotificationDecodeFrame(buffer, read_bytes, &frame, &reason);
        if (status == WindowsNotificationFrameDecodeStatus::kOk) {
          ack_status = handler_(frame.kind, frame.payload);
        }
      }

      DWORD written = 0;
      ResetEvent(ov.hEvent);
      const std::vector<unsigned char> ack =
          WindowsNotificationEncodeAck(ack_status);
      if (WriteFile(pipe, ack.data(), static_cast<DWORD>(ack.size()), &written,
                    &ov) ||
          (GetLastError() == ERROR_IO_PENDING &&
           WaitOverlapped(pipe, &ov, kWindowsNotificationPipeServerOpWaitMs) &&
           GetOverlappedResult(pipe, &ov, &written, FALSE))) {
        FlushFileBuffers(pipe);
      }
    }

    // 一条连接串行一条 request/ACK 后即关闭；rapid activation 用各自连接。
    DisconnectNamedPipe(pipe);
    CloseHandle(ov.hEvent);
    CloseHandle(pipe);
  }
}

// ---------------------------------------------------------------------------
// pipe client
// ---------------------------------------------------------------------------

WindowsNotificationPipeClientResult WindowsNotificationSendPipeFrameBytes(
    const wchar_t* pipe_name, const std::vector<unsigned char>& frame) {
  WindowsNotificationPipeClientResult result;
  HANDLE pipe = INVALID_HANDLE_VALUE;
  const uint32_t started = TickMs();
  while (TickMs() - started < kWindowsNotificationPipeConnectTotalMs) {
    pipe = CreateFileW(pipe_name, GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                       OPEN_EXISTING, FILE_FLAG_OVERLAPPED, nullptr);
    if (pipe != INVALID_HANDLE_VALUE) {
      break;
    }
    const DWORD gle = GetLastError();
    if (gle == ERROR_PIPE_BUSY) {
      WaitNamedPipeW(pipe_name, 200);
    } else if (gle == ERROR_FILE_NOT_FOUND) {
      Sleep(100);
    } else {
      result.fail_code = "connect";
      return result;
    }
  }
  if (pipe == INVALID_HANDLE_VALUE) {
    result.fail_code = "connect";
    return result;
  }

  DWORD mode = PIPE_READMODE_MESSAGE;
  SetNamedPipeHandleState(pipe, &mode, nullptr, nullptr);

  OVERLAPPED ov = {};
  ov.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  DWORD written = 0;
  bool ok = false;
  if (WriteFile(pipe, frame.data(), static_cast<DWORD>(frame.size()), &written,
                &ov) ||
      (GetLastError() == ERROR_IO_PENDING &&
       WaitOverlapped(pipe, &ov, kWindowsNotificationPipeAckWaitMs) &&
       GetOverlappedResult(pipe, &ov, &written, FALSE))) {
    ok = written == frame.size();
  }
  if (!ok) {
    CancelIoEx(pipe, &ov);
    CloseHandle(ov.hEvent);
    CloseHandle(pipe);
    result.fail_code = "write";
    return result;
  }

  unsigned char ack_buffer[kWindowsNotificationAckSize];
  DWORD read_bytes = 0;
  ResetEvent(ov.hEvent);
  uint16_t status = 0xFFFF;
  bool ack_ok = false;
  if (ReadFile(pipe, ack_buffer, sizeof(ack_buffer), &read_bytes, &ov) ||
      (GetLastError() == ERROR_IO_PENDING &&
       WaitOverlapped(pipe, &ov, kWindowsNotificationPipeAckWaitMs) &&
       GetOverlappedResult(pipe, &ov, &read_bytes, FALSE))) {
    ack_ok = WindowsNotificationDecodeAck(ack_buffer, read_bytes, &status);
  }

  CancelIoEx(pipe, &ov);
  FlushFileBuffers(pipe);
  CloseHandle(ov.hEvent);
  CloseHandle(pipe);

  if (!ack_ok) {
    result.fail_code = "ackTimeout";
    return result;
  }
  result.ack_received = true;
  result.ack_status = status;
  result.delivered = status == kWindowsNotificationAckAccepted;
  return result;
}

WindowsNotificationPipeClientResult WindowsNotificationSendPipeFrame(
    const wchar_t* pipe_name, uint16_t kind, const unsigned char* payload,
    size_t payload_size) {
  return WindowsNotificationSendPipeFrameBytes(
      pipe_name, WindowsNotificationEncodeFrame(kind, payload, payload_size));
}
