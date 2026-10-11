# 四月应用图标

图标保留深绿圆角底、奶油色纸卷四瓣花和金色花心，只去除圆角外的白色背景。原始图片随仓库保存，品牌图片不作为 Flutter 运行时 assets 打包。

| 文件 | 用途 |
| --- | --- |
| `siyue-icon-original.png` | 用户提供的原图，内容未改动 |
| `siyue-icon.png` | 外侧透明的 RGBA 主图，Windows 与 Android 旧版图标来源 |
| `siyue-icon-foreground.png` | 透明花朵前景，与深绿背景组合成 Android 自适应图标 |

## 生成与校验

在仓库根目录运行。重新抠图需要 PATH 中有 `ffmpeg`；各尺寸生成复用已有的 `image` 依赖：

```powershell
dart run tool/generate_app_icons.dart --from-original
dart run tool/generate_app_icons.dart
dart run tool/generate_app_icons.dart --check
```

`--from-original` 使用 FFmpeg 从原图重新生成两张透明主图及全部平台尺寸。默认命令只生成平台尺寸。`--check` 不写文件，检查主图透明通道、与原图的逐像素 RGB 一致性，以及已提交资源是否与主图生成结果一致。

Windows 的 `windows/runner/resources/app_icon.ico` 包含 16、20、24、30、32、36、40、48、60、64、72、80、96、128、256 像素的 32 位图像。窗口创建及跨显示器 DPI 改变时，按系统要求的大小分别加载标题栏和大图标；由 Windows Shell 从同一 ICO 选择文件及快捷方式图标。

Android 使用原生密度目录；Android 8.0 以下保留透明圆角 PNG，8.0 及以上由系统遮罩决定外形。自适应前景画布为 108dp，花朵居中放入最多 64dp 的区域，保留系统 66dp 安全区域的余量。背景使用深绿渐变，不预制圆角遮罩。

| 密度 | 旧版图标 | 自适应前景画布 |
| --- | --- | --- |
| mdpi | 48×48 | 108×108 |
| hdpi | 72×72 | 162×162 |
| xhdpi | 96×96 | 216×216 |
| xxhdpi | 144×144 | 324×324 |
| xxxhdpi | 192×192 | 432×432 |

规范参考：[Android 自适应图标](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)、[Windows 图标尺寸](https://learn.microsoft.com/en-us/windows/apps/design/iconography/app-icon-construction)。

## 图片处理记录

透明主图均直接由原图经 FFmpeg 色键生成，只修改 Alpha，所有像素的 RGB 与原图完全一致。主图的白色色键仅作用于四角，中央花瓣始终不透明；Android 前景使用深绿色键，并清除没有花瓣的四角。滤镜及阈值集中在 `tool/generate_app_icons.dart`，随仓库保存，不依赖图片生成模型。

色键的过渡带保留边缘抗锯齿；源图已有的混色边缘保留原始 RGB。各尺寸缩放使用预乘 Alpha，避免全透明像素中的背景颜色混入可见边缘；前景裁切明确依据透明度。高分辨率主图及最终各尺寸资源均需在深浅背景上检查。滤镜说明见 [FFmpeg colorkey](https://ffmpeg.org/ffmpeg-filters.html#colorkey) 与 [geq](https://ffmpeg.org/ffmpeg-filters.html#geq)。
