# 生成 Noto Sans SC 子集字体：收集所有脚本里出现的字符 + ASCII + 常用标点（改了文字就重跑）
# 用法（在 proto/ 目录下）：python3 tools/make_font.py /workspace/tools/NotoSansSC.ttf
import glob, subprocess, sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
src = sys.argv[1]
chars = set(chr(c) for c in range(0x20, 0x7f))
chars |= set("，。：；！？、（）【】《》“”‘’…—·×→←▶◆●○■□★☆+-=%/／～ 　0123456789")
for f in glob.glob("scripts/*.gd"):
    chars |= set(open(f, encoding="utf-8").read())
chars = {c for c in chars if c.isprintable() or c == " "}
open("/tmp/coffee_chars.txt", "w", encoding="utf-8").write("".join(sorted(chars)))
f = TTFont(src)
if "fvar" in f:
    f = instancer.instantiateVariableFont(f, {"wght": 700})
f.save("/tmp/coffee_noto_static.ttf")
subprocess.check_call(["pyftsubset", "/tmp/coffee_noto_static.ttf", "--text-file=/tmp/coffee_chars.txt",
                       "--output-file=assets/NotoSansSC-subset.ttf", "--layout-features=*", "--no-hinting"])
print(len(chars), "chars")
