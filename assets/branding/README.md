# 四月应用图标

图标保留深绿圆角底、奶油色纸卷四瓣花和金色花心，只去除圆角外的白色背景。原始图片随仓库保存，品牌图片不作为 Flutter 运行时 assets 打包。

| 文件 | 用途 |
| --- | --- |
| `siyue-icon-original.png` | 用户提供的原图，内容未改动 |
| `siyue-icon.png` | 外侧透明的 RGBA 主图，Windows 与 Android 旧版图标来源 |
| `siyue-icon-foreground.png` | 透明花朵前景，与深绿背景组合成 Android 自适应图标 |

## 生成与校验

在仓库根目录运行，复用已有的 `image` 依赖：

```powershell
dart run tool/generate_app_icons.dart
dart run tool/generate_app_icons.dart --check
```

`--check` 不写文件，检查主图透明通道及已提交资源是否与主图生成结果一致。替换主图后重新生成，再检查原生平台预览。

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

两张透明主图均使用内置 imagegen 编辑，尺寸资源由 Dart 脚本生成。使用的提示词如下。

主图：

> Edit target: the attached Siyue application icon. Remove ONLY the white exterior background outside the dark forest green rounded-square tile and replace that exterior with true alpha transparency. Preserve the entire dark green rounded-square tile, its original corner radius, subtle green texture/gradient, and the cream folded-paper four-petal flower with the golden four-point center exactly as closely as possible. Keep the original flower geometry, cream paper folds, fine paper texture, shadows, colors, scale, center alignment and square composition. Do not remove the dark green tile. Do not redesign or add anything. Do not draw a transparency checkerboard. Output a square PNG with a real transparent background outside the rounded tile, with clean antialiased edges and no white halo. This is a final app-icon master for Windows and Android.

Android 前景：

> Edit target: this Siyue app icon. Create the foreground layer for an Android adaptive icon: remove ONLY the entire dark green rounded-square background, leaving just the existing cream folded-paper four-petal flower and its golden four-point center on true alpha transparency. Keep the flower exactly the same: original shape, orientation, proportions, paper texture, folds, colors, shadows within the petals, center point and original centered positioning within the same square canvas. Do not enlarge or shrink the flower; retain the square canvas with generous transparent margins. Preserve clean antialiased edges, no green halo or external drop shadow. No redesign, no text, no background, no checkerboard.
