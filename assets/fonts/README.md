# 字体资产

界面使用 Noto Sans SC，长文阅读和页面标题使用 Noto Serif SC。代码保留等宽字体。字体随应用打包，运行时不请求字体 CDN。

## Noto Serif SC（阅读与主要标题）

来源：https://github.com/google/fonts/tree/main/ofl/notoserifsc

- 获取日期：2026-10-10。
- 原文件：`NotoSerifSC[wght].ttf`，25,125,512 字节。
- 原文件 SHA256：`050080D9255A86808F2945BFFAC582B31EF32BC36411CE29563B4961670C66F9`。
- 本地文件：`NotoSerifSC-VF.ttf`，2026-10-11 生成的可变字体子集，7,635,316 字节（约 7.28 MiB）。
- 子集 SHA256：`1E0DD43E065ACCF71F0D4F305940D48A243276E362D7470A9629EA8035D8D965`。
- 许可证：`NotoSerifSC-OFL.txt`。
- 覆盖范围：完整 8105 个规范汉字及源字体中 2990 个非汉字字符，cmap 共 11095 项、11315 个字形。

## Noto Sans SC（界面操作、编辑与后备）

来源：https://github.com/google/fonts/tree/main/ofl/notosanssc

- 原文件：`NotoSansSC[wght].ttf`，17,772,300 字节（约 16.95 MiB）。
- 原文件 SHA256：`A3041811A78C361B1DE50F953C805E0244951C21C5BD412F7232EF0D899AF0DA`。
- 本地文件：`NotoSansSC-VF.ttf`，2026-11-21 生成的可变字体子集，5,467,820 字节（约 5.21 MiB）。
- 子集 SHA256：`589D7E76746BAD7DFDC6B03BF9688B1BDC0BA0844C5B5984C2E463229E91ACD8`。
- 许可证：`NotoSansSC-OFL.txt`。
- 覆盖范围：完整 8105 个规范汉字及源字体中 2990 个非汉字字符，cmap 共 11095 项、11324 个字形。

两套子集均保留可变字重与 GSUB／GPOS，全字符字宽和侧承与源字体相同。两种字体合计 13,103,136 字节（约 12.50 MiB），比两套完整源字体（42,897,812 字节，约 40.91 MiB）减少 28.41 MiB（69.46%）；这是字体资产体积，不是发布包压缩后的差值。

字体裁剪不限制输入；繁体及超出 8105 字集的汉字由平台系统字体后备。OFL 文件未声明 Reserved Font Name；Flutter 家族名与资产路径保持原值，本文明确标识修改后的子集。

## 复现

Python 3.12.10、fonttools 4.60.1；生成器与 Unicode 清单位于 `tool/fonts/`。汉字使用 [Unicode 16.0 Unihan](https://www.unicode.org/Public/16.0.0/ucd/Unihan.zip) 的 `kTGH` 字段，按 `2013:0001` 到 `2013:8105` 的序号校验，而非网页 OCR。数据许可证随清单保存。工具会验证源文件哈希、完整序号、字符唯一性、源／输出覆盖、字宽与轴范围。

```powershell
python -m venv logs/fonts/venv
logs/fonts/venv/Scripts/python.exe -m pip install fonttools==4.60.1
Invoke-WebRequest https://www.unicode.org/Public/16.0.0/ucd/Unihan.zip -OutFile logs/fonts/Unihan-16.0.0.zip

# 复现宋体子集
git archive -o logs/fonts/serif-source.zip ff2dfd5b assets/fonts/NotoSerifSC-VF.ttf
Expand-Archive logs/fonts/serif-source.zip logs/fonts/serif-source -Force
logs/fonts/venv/Scripts/python.exe tool/fonts/subset_serif.py --source logs/fonts/serif-source/assets/fonts/NotoSerifSC-VF.ttf --unihan logs/fonts/Unihan-16.0.0.zip

# 复现黑体子集
git archive -o logs/fonts/sans-source.zip 93a50e16 assets/fonts/NotoSansSC-VF.ttf
Expand-Archive logs/fonts/sans-source.zip logs/fonts/sans-source -Force
logs/fonts/venv/Scripts/python.exe tool/fonts/subset_sans.py --source logs/fonts/sans-source/assets/fonts/NotoSansSC-VF.ttf --unihan logs/fonts/Unihan-16.0.0.zip
```

两套子集均已重复生成至独立输出，SHA256 完全一致。完整源字体可从上述 Git 历史恢复，不把完整源字体重复打进应用。
