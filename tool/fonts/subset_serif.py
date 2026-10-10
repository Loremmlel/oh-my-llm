"""从固定来源生成阅读宋体子集；完整黑体继续负责后备字形。"""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import fontTools
from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[2]
SOURCE_HASH = "050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"
UNIHAN_HASH = "b8f000df69de7828d21326a2ffea462b04bc7560022989f7cc704f10521ef3e0"


def checked(path, expected):
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise ValueError(f"来源 SHA256 不一致：{path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--unihan", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "assets/fonts/NotoSerifSC-VF.ttf")
    args = parser.parse_args()
    if fontTools.__version__ != "4.60.1":
        raise ValueError("请使用 fonttools==4.60.1")
    checked(args.source, SOURCE_HASH)
    checked(args.unihan, UNIHAN_HASH)
    entries = {}
    with zipfile.ZipFile(args.unihan) as archive:
        for name in archive.namelist():
            for line in archive.read(name).decode("utf-8").splitlines():
                if "\tkTGH\t" in line:
                    code, _, value = line.split("\t")
                    year, ordinal = value.split(":")
                    assert year == "2013"
                    entries[int(ordinal)] = int(code[2:], 16)
    assert set(entries) == set(range(1, 8106))
    han = set(entries.values())
    assert len(han) == 8105
    font = TTFont(args.source, recalcTimestamp=False)
    cmap = font.getBestCmap()
    axes = [(a.axisTag, a.minValue, a.maxValue) for a in font["fvar"].axes]
    assert not han - cmap.keys(), "源字体缺少规范汉字"
    # 保留源字体的非汉字：拉丁文、标点、假名、符号等不按 UI 文案删减。
    # 固定汉字区段，不随执行机器的 Python Unicode 数据版本改变裁剪结果。
    han_ranges = ((0x3400, 0x4DBF), (0x4E00, 0x9FFF), (0xF900, 0xFAFF), (0x20000, 0x3FFFF))
    other = {cp for cp in cmap if not any(start <= cp <= end for start, end in han_ranges)}
    keep = han | other
    advances = {cp: font["hmtx"][cmap[cp]] for cp in keep}
    options = subset.Options()
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.name_legacy = True
    options.name_languages = ["*"]
    options.recalc_timestamp = False
    worker = subset.Subsetter(options=options)
    worker.populate(unicodes=keep)
    worker.subset(font)
    font.save(args.output)
    output = TTFont(args.output)
    assert set(output.getBestCmap()) == keep
    assert [(a.axisTag, a.minValue, a.maxValue) for a in output["fvar"].axes] == axes
    assert {cp: output["hmtx"][glyph] for cp, glyph in output.getBestCmap().items()} == advances
    assert all(table in output for table in ("GSUB", "GPOS", "gvar"))
    # 清单随源代码提交；不是运行时白名单，不限制用户输入。
    (ROOT / "tool/fonts/tgh-8105.txt").write_text("".join(f"U+{entries[i]:04X} # {chr(entries[i])}\n" for i in range(1, 8106)), encoding="utf-8")
    (ROOT / "tool/fonts/serif-other-unicodes.txt").write_text("\n".join(f"U+{cp:04X}" for cp in sorted(other)) + "\n", encoding="utf-8")
    result = {"fonttools": fontTools.__version__, "source_sha256": SOURCE_HASH, "unihan_sha256": UNIHAN_HASH, "han": len(han), "other": len(other), "cmap": len(keep), "source_bytes": args.source.stat().st_size, "output_bytes": args.output.stat().st_size, "output_sha256": hashlib.sha256(args.output.read_bytes()).hexdigest(), "glyphs": len(output.getGlyphOrder())}
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
