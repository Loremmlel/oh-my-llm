"""仅生成 ignored 诊断字体，验证控制字符缺字与 CRLF 慢路径的因果关系。"""
import json
import sys
from pathlib import Path

from fontTools.ttLib import TTFont

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
destination.mkdir(parents=True, exist_ok=True)
metadata = {}
for label, codepoints in {
    "original": [], "cr": [13], "lf": [10], "both": [13, 10],
}.items():
    font = TTFont(source)
    original = font.getBestCmap()
    metadata[label] = {str(cp): original.get(cp) for cp in [10, 13, 32]}
    # 只在实验副本中让指定控制字符映射到已有空格字形；不作为应用修复。
    for table in font["cmap"].tables:
        if table.isUnicode():
            for cp in codepoints:
                table.cmap[cp] = original[32]
    output = destination / f"{label}.ttf"
    font.save(output)
    verified = TTFont(output)
    for tag in ["glyf", "hmtx", "hhea", "fvar", "gvar"]:
        assert font.getTableData(tag) == verified.getTableData(tag), tag
    for cp in codepoints:
        cmap = verified.getBestCmap()
        assert verified.getGlyphID(cmap[cp]) == verified.getGlyphID(cmap[32])
    verified.close()
    font.close()
print(json.dumps(metadata, ensure_ascii=False))
