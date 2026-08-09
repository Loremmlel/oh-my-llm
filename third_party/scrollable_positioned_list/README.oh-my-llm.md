# Oh My LLM fork 说明

本目录基于 pub.dev 的 `scrollable_positioned_list 0.3.8`，保留原 BSD-3-Clause
许可证。源码随主仓库提交，并由根 `pubspec.yaml` 通过相对 `path` 依赖引用；开发机
只需正常执行 `flutter pub get`，不需要修改本机 Pub Cache。

项目补丁保持最小范围：

- 为 `ScrollablePositionedList.builder` 和 `.separated` 增加固定像素
  `cacheExtent`。设置后跳过原先依赖 viewport 尺寸的 `LayoutBuilder`，避免聊天
  输入区高度动画逐帧改变缓存范围并重建昂贵的消息子树。
- viewport 尺寸改变时通过 `ScrollMetricsNotification` 刷新可见项位置，保证固定
  缓存路径下 `ItemPositionsListener` 仍能更新。
- 未传 `cacheExtent` 时保留上游 `minCacheExtent` 与两倍 viewport 缓存的原行为，
  降低 fork 对其他调用方的影响。

升级上游版本时，先对比本文件列出的补丁是否已被官方实现，再运行本目录测试和主
仓库聊天页测试，不能直接覆盖 `lib/`。fork 的静态检查使用
`flutter analyze --no-fatal-warnings --no-fatal-infos`：上游旧 lint 与新增弃用提示
不阻塞，但任何 analyzer error 仍会失败。
