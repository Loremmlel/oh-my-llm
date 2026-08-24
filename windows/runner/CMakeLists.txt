cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "windows_notification_activator.cpp"
  "windows_notification_host.cpp"
  "windows_notification_instance_coordinator.cpp"
  "windows_notification_protocol.cpp"
  "windows_notification_registration.cpp"
  "windows_notification_toast.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# 通知宿主的最外层需要可用的 C++ 异常（catch-all 阻止异常穿过 COM ABI 与
# wWinMain），因此不用顶层 apply_standard_settings——它的 _HAS_EXCEPTIONS=0
# 组合不受 MSVC STL 支持。其余设置与模板一致，并显式启用 /utf-8：仓库 C++
# 注释为简体中文，本机代码页为 CP936，不显式指定会触发 C4819。
target_compile_features(${BINARY_NAME} PUBLIC cxx_std_17)
target_compile_options(${BINARY_NAME} PRIVATE /W4 /WX /wd"4100")
target_compile_options(${BINARY_NAME} PRIVATE /EHsc)
target_compile_options(${BINARY_NAME} PRIVATE /utf-8)
target_compile_definitions(${BINARY_NAME} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")
# 通知宿主用到的 Shell/COM/WinRT 头文件需要现代 Windows API level。
target_compile_definitions(${BINARY_NAME} PRIVATE "_WIN32_WINNT=0x0A00")
# Win32 泛型宏统一映射到宽字符（W）入口；顶层虽有 add_definitions 全局
# 提供，此处在本 target 上显式声明，不依赖目录级副作用的隐式传递。
target_compile_definitions(${BINARY_NAME} PRIVATE "UNICODE" "_UNICODE")

# ── 通知宿主测试开关与竞态 delay 变体 ────────────────────────────────
# delay 只用于在 Debug 构建上复验两个早期竞态窗口（pre-COM / post-COM），
# 绝不进入 release 或用户可配置面。默认全为 0；testing=OFF 或非 Debug 配置
# 出现非零 delay 时在 configure 阶段直接失败。
set(OMLL_NOTIFICATION_HOST_TESTING "OFF" CACHE BOOL
    "构建 windows_notification_host_test 并允许竞态 delay 构建变体")
set(OMLL_NOTIFICATION_PRE_COM_DELAY_MS "0" CACHE STRING
    "primary 竞争 activator lease 前的延迟（毫秒，仅 Debug+testing=ON）")
set(OMLL_NOTIFICATION_POST_COM_PRE_FLUTTER_DELAY_MS "0" CACHE STRING
    "COM 注册完成后、DartProject 之前的延迟（毫秒，仅 Debug+testing=ON）")

foreach(_omll_delay_var OMLL_NOTIFICATION_PRE_COM_DELAY_MS
                         OMLL_NOTIFICATION_POST_COM_PRE_FLUTTER_DELAY_MS)
  if(NOT ${_omll_delay_var} MATCHES "^[0-9]+$")
    message(FATAL_ERROR "${_omll_delay_var} 必须是十进制非负整数")
  endif()
endforeach()

set(_OMLL_NOTIFICATION_DELAY_NONZERO OFF)
if(NOT OMLL_NOTIFICATION_PRE_COM_DELAY_MS EQUAL 0 OR
   NOT OMLL_NOTIFICATION_POST_COM_PRE_FLUTTER_DELAY_MS EQUAL 0)
  set(_OMLL_NOTIFICATION_DELAY_NONZERO ON)
endif()

get_property(_OMLL_MULTI_CONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)

if(_OMLL_NOTIFICATION_DELAY_NONZERO)
  if(NOT OMLL_NOTIFICATION_HOST_TESTING)
    message(FATAL_ERROR
      "OMLL_NOTIFICATION_*_DELAY_MS 仅允许在 OMLL_NOTIFICATION_HOST_TESTING=ON 时非零")
  endif()
  # 单配置生成器在 configure 阶段就能识别 Release；多配置（Visual Studio）
  # 生成器按 CONFIG 用生成表达式把 delay 限定在 Debug，Release/Profile 编译
  # 结果仍为 0。
  if(NOT _OMLL_MULTI_CONFIG AND NOT CMAKE_BUILD_TYPE STREQUAL "Debug")
    message(FATAL_ERROR "非零竞态 delay 仅允许 Debug 构建")
  endif()
endif()

if(OMLL_NOTIFICATION_HOST_TESTING)
  if(_OMLL_MULTI_CONFIG)
    if(NOT OMLL_NOTIFICATION_PRE_COM_DELAY_MS EQUAL 0)
      target_compile_definitions(${BINARY_NAME} PRIVATE
        "$<$<CONFIG:Debug>:OMLL_NOTIFICATION_PRE_COM_DELAY_MS=${OMLL_NOTIFICATION_PRE_COM_DELAY_MS}>")
    endif()
    if(NOT OMLL_NOTIFICATION_POST_COM_PRE_FLUTTER_DELAY_MS EQUAL 0)
      target_compile_definitions(${BINARY_NAME} PRIVATE
        "$<$<CONFIG:Debug>:OMLL_NOTIFICATION_POST_COM_PRE_FLUTTER_DELAY_MS=${OMLL_NOTIFICATION_POST_COM_PRE_FLUTTER_DELAY_MS}>")
    endif()
  else()
    if(NOT OMLL_NOTIFICATION_PRE_COM_DELAY_MS EQUAL 0)
      target_compile_definitions(${BINARY_NAME} PRIVATE
        "OMLL_NOTIFICATION_PRE_COM_DELAY_MS=${OMLL_NOTIFICATION_PRE_COM_DELAY_MS}")
    endif()
    if(NOT OMLL_NOTIFICATION_POST_COM_PRE_FLUTTER_DELAY_MS EQUAL 0)
      target_compile_definitions(${BINARY_NAME} PRIVATE
        "OMLL_NOTIFICATION_POST_COM_PRE_FLUTTER_DELAY_MS=${OMLL_NOTIFICATION_POST_COM_PRE_FLUTTER_DELAY_MS}")
    endif()
  endif()

  # 原生测试 executable：与 runner 相同的模块源 + flutter 头/包装库（host
  # 的 channel 胶水直接链接真实 MethodChannel），不进 release 安装面。
  add_executable(windows_notification_host_test
    "tests/windows_notification_host_test.cpp"
    "windows_notification_activator.cpp"
    "windows_notification_host.cpp"
    "windows_notification_instance_coordinator.cpp"
    "windows_notification_protocol.cpp"
    "windows_notification_registration.cpp"
    "windows_notification_toast.cpp"
  )
  target_compile_features(windows_notification_host_test PUBLIC cxx_std_17)
  target_compile_options(windows_notification_host_test PRIVATE /W4 /WX /wd"4100")
  target_compile_options(windows_notification_host_test PRIVATE /EHsc)
  target_compile_options(windows_notification_host_test PRIVATE /utf-8)
  target_compile_definitions(windows_notification_host_test PRIVATE "NOMINMAX")
  target_compile_definitions(windows_notification_host_test PRIVATE "_WIN32_WINNT=0x0A00")
  target_link_libraries(windows_notification_host_test PRIVATE flutter flutter_wrapper_app)
  target_link_libraries(windows_notification_host_test PRIVATE
    "propsys.lib" "runtimeobject.lib" "shell32.lib" "advapi32.lib" "ole32.lib" "uuid.lib")
endif()

# Dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
# 通知宿主：property store（快捷方式 VT_CLSID）、WinRT activation（Toast）、
# COM 注册与 HKCU 写入所需的最小 SDK 库集合，显式声明、不依赖隐式链接状态。
target_link_libraries(${BINARY_NAME} PRIVATE
  "propsys.lib" "runtimeobject.lib" "shell32.lib" "advapi32.lib" "ole32.lib" "uuid.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
