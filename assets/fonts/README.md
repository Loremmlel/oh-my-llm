# 字体资产

界面使用 Noto Sans SC，长文阅读和页面标题使用 Noto Serif SC。代码保留等宽字体。字体随应用打包，运行时不请求字体 CDN。

Noto Serif SC 来源：https://github.com/google/fonts/tree/main/ofl/notoserifsc

- 获取日期：2026-10-10。
- 原文件：`NotoSerifSC[wght].ttf`，25,125,512 字节。
- 原文件 SHA256：`050080D9255A86808F2945BFFAC582B31EF32BC36411CE29563B4961670C66F9`。
- 本地文件：`NotoSerifSC-VF.ttf`，2026-10-11 生成的可变字体子集，7,635,316 字节。
- 子集 SHA256：`1E0DD43E065ACCF71F0D4F305940D48A243276E362D7470A9629EA8035D8D965`。
- 许可证：`NotoSerifSC-OFL.txt`。

子集含完整 8105 个规范汉字及源字体中 2990 个非汉字字符，cmap 共 11095 项、11315 个字形。保留可变字重与 GSUB／GPOS；全字符字宽和侧承与源字体相同。完整 Noto Sans SC（17,772,300 字节）继续用于 UI 和宋体缺字后备，许可证为 `NotoSansSC-OFL.txt`，来源为 [Google Fonts](https://github.com/google/fonts/tree/main/ofl/notosanssc)。两种字体共 25,407,616 字节（24.23 MiB），比原来减少 16.68 MiB（40.77%）；这是字体资产体积，不是发布包压缩后的差值。

字体裁剪不限制输入；繁体及超出字集的汉字进入完整黑体，再进入平台后备。OFL 文件未声明 Reserved Font Name；Flutter 家族名与资产路径保持原值，本文明确标识修改后的子集。

## 复现

Python 3.12.10、fonttools 4.60.1；生成器与两份 Unicode 清单位于 `tool/fonts/`。汉字使用 [Unicode 16.0 Unihan](https://www.unicode.org/Public/16.0.0/ucd/Unihan.zip) 的 `kTGH` 字段，按 `2013:0001` 到 `2013:8105` 的序号校验，而非网页 OCR。数据许可证随清单保存。工具会验证源文件哈希、完整序号、字符唯一性、源／输出覆盖、字宽与轴范围。

```powershell
python -m venv logs/fonts/venv
logs/fonts/venv/Scripts/python.exe -m pip install fonttools==4.60.1
git archive -o logs/fonts/source.zip ff2dfd5b assets/fonts/NotoSerifSC-VF.ttf
Expand-Archive logs/fonts/source.zip logs/fonts/source -Force
Invoke-WebRequest https://www.unicode.org/Public/16.0.0/ucd/Unihan.zip -OutFile logs/fonts/Unihan-16.0.0.zip
logs/fonts/venv/Scripts/python.exe tool/fonts/subset_serif.py --source logs/fonts/source/assets/fonts/NotoSerifSC-VF.ttf --unihan logs/fonts/Unihan-16.0.0.zip
```

已重复生成至独立输出，SHA256 完全一致。完整源字体可从上述 Git 历史恢复，不把另一份完整宋体重复打进应用。
