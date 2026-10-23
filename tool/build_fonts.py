#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""LiquidGlass for Bilibili —— 图标字体与正文字体的获取 + 子集化流水线（阶段一 #6）

产出（全部进版本库，供构建直接使用）：
  packages/liquid_glass_kit/assets/fonts/LiquidIcons.ttf        Material Symbols Rounded 子集
  packages/liquid_glass_kit/assets/fonts/LucideIcons.ttf        Lucide 子集
  packages/liquid_glass_kit/assets/fonts/LiquidText-Regular.ttf 正文字体子集（CJK + 拉丁）
  packages/liquid_glass_kit/lib/src/icons/liquid_icons.dart     生成的 IconData 常量
  packages/liquid_glass_kit/assets/fonts/LICENSES/              各字体许可证原文（素材红线要求留档）

设计约束
  * 源字体（15~18MB）**不入库**，按 URL 现取到 `tool/.cache/`（该目录已 gitignore），
    既避免仓库膨胀，也让"素材从哪来"这件事有据可查；
  * 图标清单是人写的（`tool/icons.yaml`），字体子集与 Dart 常量都由它**同源生成**——
    不会出现"代码里有这个图标、字体里没有"的错位；
  * 正文字体按 **GB2312 可编码字符集**（6763 汉字 + 拉丁 + 标点）取子集：
    覆盖简体常用字，体积从 17.7MB 降到 2~4MB 量级。

用法::

    python tool/build_fonts.py            # 缺什么下什么，然后重新生成
    python tool/build_fonts.py --force    # 强制重新下载源字体
    python tool/build_fonts.py --check    # 只校验产物是否与清单一致（CI 用）

MiSans 说明：官方只提供网页下载（https://hyperos.mi.com/font/），无法脚本直取。
拿到官方 ttf 后放进 `tool/.cache/assets/`，本脚本会自动优先使用 MiSans 作为正文字体
（名字仍是 LiquidText-*，许可证原样抄进 LICENSES/）。当前默认使用 Noto Sans SC（OFL）。
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import urllib.request
from pathlib import Path

try:
    from fontTools import subset
    from fontTools.ttLib import TTFont
except ImportError:  # pragma: no cover
    sys.exit("需要 fontTools：python -m pip install fonttools -i https://pypi.tuna.tsinghua.edu.cn/simple")

APP = Path(__file__).resolve().parent.parent
CACHE = APP / "tool" / ".cache" / "assets"
KIT = APP / "packages" / "liquid_glass_kit"
FONT_OUT = KIT / "assets" / "fonts"
ICON_DART = KIT / "lib" / "src" / "icons" / "liquid_icons.dart"
MANIFEST = APP / "tool" / "icons.yaml"

GH = "https://ghfast.top/https://raw.githubusercontent.com"
SOURCES = {
    # 名称: (URL, 许可证文件 URL, 许可证落盘名, 说明)
    "MaterialSymbolsRounded.ttf": (
        f"{GH}/google/material-design-icons/master/variablefont/"
        "MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf",
        f"{GH}/google/material-design-icons/master/LICENSE",
        "MaterialSymbols-Apache-2.0.txt",
        "Material Symbols Rounded（Apache-2.0）",
    ),
    "MaterialSymbolsRounded.codepoints": (
        f"{GH}/google/material-design-icons/master/variablefont/"
        "MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.codepoints",
        None, None, "图标名 → 码点映射",
    ),
    "lucide.ttf": (
        "https://registry.npmmirror.com/lucide-static/-/lucide-static-1.48.0.tgz",
        None, None, "Lucide 图标字体（ISC）",
    ),
    "NotoSansSC-VF.ttf": (
        f"{GH}/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf",
        f"{GH}/google/fonts/main/ofl/notosanssc/OFL.txt",
        "NotoSansSC-OFL.txt",
        "Noto Sans SC 可变字体（SIL OFL 1.1）—— MiSans 未到位时的正文字体",
    ),
}

# MiSans 官方只给网页下载；用户放到这里即自动优先使用
MISANS_CANDIDATES = ["MiSans-Regular.ttf", "MiSans-Normal.ttf", "MiSans-Medium.ttf"]


def log(msg: str) -> None:
    print(msg, flush=True)


def _make_console_safe() -> None:
    """Windows 控制台默认 GBK：任何非 GBK 字符（如 ✓）都会让脚本直接崩掉。

    与 tool/smoke_test.py 同一处置：输出流改为 errors='replace'，并且全脚本只用 ASCII 标记。
    """
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors="replace")       # type: ignore[union-attr]
        except (AttributeError, ValueError):
            pass


def download(url: str, dest: Path, force: bool = False) -> Path:
    if dest.exists() and not force:
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    log(f"  下载 {dest.name} ← {url.split('/')[-1]}")
    tmp = dest.with_suffix(dest.suffix + ".part")
    with urllib.request.urlopen(url, timeout=120) as r, open(tmp, "wb") as f:
        shutil.copyfileobj(r, f, length=1 << 20)
    tmp.replace(dest)
    log(f"    完成：{dest.stat().st_size:,} 字节")
    return dest


def ensure_sources(force: bool = False) -> None:
    log("== 1. 准备源字体 ==")
    for name, (url, lic_url, lic_name, desc) in SOURCES.items():
        dest = CACHE / name
        if dest.exists() and not force:
            log(f"  {name}（已缓存，{dest.stat().st_size:,} 字节）")
        else:
            download(url, dest, force)
        if lic_url and lic_name:
            lic = FONT_OUT / "LICENSES" / lic_name
            lic.parent.mkdir(parents=True, exist_ok=True)
            if not lic.exists() or force:
                download(lic_url, lic, force)
    # lucide 的 tgz 需要解包出 font/lucide.ttf（已解过就跳过，避免每次都重下 6.8MB）
    tgz = CACHE / "lucide.ttf"
    if (CACHE / "lucide-real.ttf").exists() and (CACHE / "lucide-codepoints.json").exists():
        log("  lucide 已解包（跳过）")
    elif tgz.exists() and tgz.read_bytes()[:2] == b"\x1f\x8b":
        import tarfile
        with tarfile.open(tgz) as tar:
            member = next((m for m in tar.getmembers() if m.name == "package/font/lucide.ttf"), None)
            if member is None:
                sys.exit("lucide 包里没有 package/font/lucide.ttf")
            with tar.extractfile(member) as src, open(CACHE / "lucide-real.ttf", "wb") as out:
                shutil.copyfileobj(src, out)
            member_cp = next((m for m in tar.getmembers() if m.name == "package/font/codepoints.json"), None)
            if member_cp:
                with tar.extractfile(member_cp) as src, open(CACHE / "lucide-codepoints.json", "wb") as out:
                    shutil.copyfileobj(src, out)
            member_lic = next((m for m in tar.getmembers() if m.name == "package/LICENSE"), None)
            if member_lic:
                lic_dir = FONT_OUT / "LICENSES"
                lic_dir.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member_lic) as src, open(lic_dir / "Lucide-ISC.txt", "wb") as out:
                    shutil.copyfileobj(src, out)
        # 保留 tgz（下次不再重下），解包结果用 lucide-real.ttf 标记


def load_manifest() -> dict:
    """手工维护的图标清单：name -> {material: <Material 名>, lucide: <Lucide 名>}"""
    import re
    text = MANIFEST.read_text(encoding="utf-8")
    icons: dict[str, dict[str, str]] = {}
    current = None
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = re.match(r"^  ([a-z0-9_]+):\s*(.*)$", line)
        if m:
            current = m.group(1)
            icons[current] = {}
            rest = m.group(2).strip()
            if rest.startswith("{"):
                for k, v in re.findall(r"(\w+):\s*([a-z0-9_\-]+)", rest):
                    icons[current][k] = v
            continue
        if current:
            for k, v in re.findall(r"(\w+):\s*([a-z0-9_\-]+)", line):
                icons[current][k] = v
    if not icons:
        sys.exit(f"图标清单为空或解析失败：{MANIFEST}")
    return icons


def subset_font(src: Path, dest: Path, codepoints: set[int], family: str) -> None:
    args = [
        str(src),
        f"--unicodes={','.join(f'U+{c:04X}' for c in sorted(codepoints))}",
        f"--output-file={dest}",
        "--layout-features=",
        "--no-hinting",
        "--desubroutinize",
        "--name-IDs=*",
        "--drop-tables+=DSIG",
    ]
    subset.main(args)
    if family:
        rename_family(dest, family)


def rename_family(path: Path, family: str) -> None:
    """把 name 表里的族名改掉（纯为可读性；Flutter 用的族名来自 pubspec 声明）。

    字体内部名字不影响渲染，因此这里失败也不该让流水线挂掉。
    """
    try:
        font = TTFont(path)
        ps_name = family.replace(" ", "")
        for rec in font["name"].names:
            if rec.nameID in (1, 16):
                rec.string = family
            elif rec.nameID == 4:
                rec.string = f"{family} Regular"
            elif rec.nameID == 6:
                rec.string = ps_name
        font.save(path)
    except Exception as e:  # noqa: BLE001
        log(f"    （改名跳过：{type(e).__name__}: {e}）")


def build_icon_fonts(icons: dict, check_only: bool = False) -> tuple[dict, dict]:
    log("== 2. 生成图标子集字体 + Dart 常量 ==")
    mat_map = {}
    for line in (CACHE / "MaterialSymbolsRounded.codepoints").read_text(encoding="utf-8").splitlines():
        if line.strip():
            name, cp = line.split()
            mat_map[name] = int(cp, 16)
    # Lucide 的 codepoints.json 是「名字 -> 十进制整数」（新版本）；老版本是十六进制字符串，两种都兼容
    lucide_raw = json.loads((CACHE / "lucide-codepoints.json").read_text(encoding="utf-8"))
    lucide_map = {
        k: (v if isinstance(v, int) else int(str(v), 16))
        for k, v in lucide_raw.items()
    }

    mat_used, luc_used = {}, {}
    missing = []
    for name, spec in sorted(icons.items()):
        if "material" in spec:
            key = spec["material"]
            if key not in mat_map:
                missing.append(f"material:{key}")
            else:
                mat_used[name] = mat_map[key]
        if "lucide" in spec:
            key = spec["lucide"]
            if key not in lucide_map:
                missing.append(f"lucide:{key}")
            else:
                luc_used[name] = lucide_map[key]
    if missing:
        sys.exit(f"清单里的图标在源字体中不存在：{', '.join(missing)}")

    if check_only:
        # 穷尽校验：清单 ↔ 子集字体 cmap ↔ 生成的 Dart 三方一致
        import re as _re
        problems: list[str] = []
        dart = ICON_DART.read_text(encoding="utf-8") if ICON_DART.exists() else ""
        if not dart:
            problems.append(f"未找到生成物 {ICON_DART}")
        for cls, wanted, font_file in (
            ("LiquidIcons", mat_used, "LiquidIcons.ttf"),
            ("LucideIcons", luc_used, "LucideIcons.ttf"),
        ):
            cmap = set(TTFont(FONT_OUT / font_file).getBestCmap()) if (FONT_OUT / font_file).exists() else set()
            if not cmap:
                problems.append(f"字体缺失或为空：{font_file}")
            for name, cp in wanted.items():
                if cp not in cmap:
                    problems.append(f"{font_file} 缺少 {name} 的码点 0x{cp:04x}")
                if not _re.search(rf"static const IconData {name} = IconData\(0x{cp:04x},", dart):
                    problems.append(f"liquid_icons.dart 与清单不一致：{cls}.{name} 0x{cp:04x}")
        extra = set(_re.findall(r"static const IconData (\w+) =", dart)) - set(mat_used) - set(luc_used)
        if extra:
            problems.append(f"liquid_icons.dart 里有清单外的图标：{', '.join(sorted(extra))}")
        log(f"  清单图标 {len(icons)} 项；三方一致性：{'通过 [OK]' if not problems else '发现问题'}")
        # 与语言/编码无关的结果标记：CI 与本地门禁按这一行判定，别依赖中文文本匹配
        # （实测：Python 输出 UTF-8、PowerShell 按 GBK 解码时，中文会变成乱码，匹配必然失败）
        print(f"CHECK_RESULT={'PASS' if not problems else 'FAIL'}", flush=True)
        for p in problems:
            log(f"    [X] {p}")
        if problems:
            sys.exit(1)
        return mat_used, luc_used

    FONT_OUT.mkdir(parents=True, exist_ok=True)
    subset_font(CACHE / "MaterialSymbolsRounded.ttf", FONT_OUT / "LiquidIcons.ttf",
                set(mat_used.values()), "LiquidIcons")
    subset_font(CACHE / "lucide-real.ttf", FONT_OUT / "LucideIcons.ttf",
                set(luc_used.values()), "LucideIcons")
    for f in ("LiquidIcons.ttf", "LucideIcons.ttf"):
        p = FONT_OUT / f
        log(f"  {f}: {p.stat().st_size:,} 字节（{len(TTFont(p).getBestCmap())} 个码点）")

    # 生成 Dart：与子集字体同源，杜绝"代码有、字体无"
    lines = [
        "// SPDX-License-Identifier: GPL-3.0-or-later",
        "//",
        "// 本文件由 tool/build_fonts.py 从 tool/icons.yaml 自动生成，请勿手改。",
        "// 图标字体：Material Symbols Rounded（Apache-2.0）与 Lucide（ISC）的子集，",
        "// 许可证原文见 packages/liquid_glass_kit/assets/fonts/LICENSES/。",
        "//",
        "// 用法：Icon(LiquidIcons.home, size: 20)  /  Icon(LucideIcons.home)",
        "// 两个类用**同一套语义名**（清单左侧），便于在两种风格间切换而不改业务代码。",
        "//",
        "// 常量名刻意用 snake_case：与 icons.yaml 的键一一对应，跨文件搜索不会错位。",
        "// ignore_for_file: constant_identifier_names",
        "",
        "import 'package:flutter/widgets.dart';",
        "",
        "/// Material Symbols Rounded 子集（UI 主图标集）",
        "abstract final class LiquidIcons {",
        "  static const String family = 'LiquidIcons';",
        "  static const String fontPackage = 'liquid_glass_kit';",
    ]
    for name, cp in sorted(mat_used.items()):
        lines.append(f"  static const IconData {name} = IconData(0x{cp:04x}, fontFamily: family, fontPackage: fontPackage);")
    lines += ["}", "", "/// Lucide 子集（线性风格图标，用于强调/空状态等场景）",
              "abstract final class LucideIcons {",
              "  static const String family = 'LucideIcons';",
              "  static const String fontPackage = 'liquid_glass_kit';"]
    for name, cp in sorted(luc_used.items()):
        lines.append(f"  static const IconData {name} = IconData(0x{cp:04x}, fontFamily: family, fontPackage: fontPackage);")
    lines += ["}", ""]
    ICON_DART.parent.mkdir(parents=True, exist_ok=True)
    ICON_DART.write_text("\n".join(lines), encoding="utf-8")
    log(f"  {ICON_DART.relative_to(APP)}: LiquidIcons {len(mat_used)} 个 / LucideIcons {len(luc_used)} 个")
    return mat_used, luc_used


def build_text_font(check_only: bool = False) -> None:
    log("== 3. 生成正文字体子集（CJK）==")
    src = None
    for cand in MISANS_CANDIDATES:
        if (CACHE / cand).exists():
            src = CACHE / cand
            log(f"  使用 MiSans：{cand}（官方文件，许可见 LICENSES/MiSans-*.txt）")
            break
    if src is None:
        src = CACHE / "NotoSansSC-VF.ttf"
        log("  未发现 MiSans 官方文件 → 使用 Noto Sans SC（SIL OFL 1.1）")

    charset = set(range(0x20, 0x7F))                       # ASCII
    charset |= set(range(0xA0, 0x100))                     # Latin-1
    charset |= set(range(0x2000, 0x2070))                  # 常用标点
    charset |= {0x2018, 0x2019, 0x201C, 0x201D, 0x2026, 0x2014, 0x00B7, 0x3001, 0x3002,
                0xFF01, 0xFF08, 0xFF09, 0xFF0C, 0xFF1A, 0xFF1B, 0xFF1F, 0xFF5E, 0x3010, 0x3011}
    for cp in range(0x4E00, 0x9FA6):                       # 汉字：GB2312 覆盖面
        try:
            chr(cp).encode("gb2312")
            charset.add(cp)
        except UnicodeEncodeError:
            pass
    charset |= set(range(0x3000, 0x3040))                  # 中日韩符号
    charset |= set(range(0xFF00, 0xFF61))                  # 全角字符

    dest = FONT_OUT / "LiquidText-Regular.ttf"
    if check_only:
        log(f"  正文字符集 {len(charset)} 个码点；产物：{'存在' if dest.exists() else '缺失'}")
        return
    subset_font(src, dest, charset, "LiquidText")
    cmap = TTFont(dest).getBestCmap()
    log(f"  LiquidText-Regular.ttf: {dest.stat().st_size:,} 字节（{len(cmap):,} 个码点）")
    han = sum(1 for c in cmap if 0x4E00 <= c <= 0x9FFF)
    log(f"    其中汉字 {han:,} 个，源字体 {src.stat().st_size:,} 字节 → 压缩比 "
        f"{dest.stat().st_size / src.stat().st_size:.1%}")


def main() -> int:
    _make_console_safe()
    ap = argparse.ArgumentParser(description="图标/正文字体的下载与子集化")
    ap.add_argument("--force", action="store_true", help="强制重新下载源字体")
    ap.add_argument("--check", action="store_true", help="只校验清单与产物，不重新生成")
    args = ap.parse_args()

    if not MANIFEST.exists():
        sys.exit(f"缺少图标清单：{MANIFEST}")
    if args.check:
        ensure_sources()
    else:
        ensure_sources(force=args.force)
    icons = load_manifest()
    build_icon_fonts(icons, check_only=args.check)
    build_text_font(check_only=args.check)
    log("== 完成 ==" + ("（--check 模式，未改动产物）" if args.check else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())