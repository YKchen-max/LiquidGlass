# SPDX-License-Identifier: GPL-3.0-or-later
#
# task-85（规格 `docs/真折射移植计划.md` §0.1.31）：**页内帧时序产物分析器**（host 侧）。
#
# 它读 `app/lib/debug/glass_frame_timing.dart` 导出的产物（文件，或从 logcat 抓的文本——
# 两种都能吃，logcat 行会自动剥掉 "MM-DD hh:mm:ss.mmm pid tid L tag : " 前缀）。
#
# 统计口径（事前写死，规格 §0.1.31 第 4 条）：中位 / P90 / P99 / 最大 ＋ 帧数 ＋ 窗口时长。
# 空洞自检（同上）：出现"长时间无帧" ⇒ max 不可用 ⇒ 只用中位/P90/P99。
# 守卫（规格第 9 条，**不许放松**）：若算出的帧率 > 刷新率 ⇒ 自相矛盾（窗口被遮挡/未节流）
#     ⇒ `valid_as_smoothness_metric=false`，**这批数据不能当验收值**。
#     （沿用 `measure_fps.py` 的同一条守卫：`fps > refresh_hz * 1.05`。）
# 场景断言（规格第 5 条 / 手册 §18.69）：`scenario != ok` ⇒ 数据标 **未归属**（不可归属到任何一臂）。
#
# 用法：
#   python app/tool/glass_frame_timing.py <产物文件或 logcat 文本> [--refresh-hz 165]
#          [--json out.json] [--label-hint refraction]
# 退出码：0 = 数据可用（守卫+场景断言都过）；2 = 不可用（原因打印在判定块里）。
import argparse
import json
import os
import re
import statistics
import sys

FT = re.compile(r'^FT\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$')
META = re.compile(r'^META\s+(.*)$')
LOGCAT_PREFIX = re.compile(r'^\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+\s+\d+\s+\d+\s+\w\s+[^:]*:\s*')


def pct(sorted_vals, q):
    if not sorted_vals:
        return float('nan')
    if len(sorted_vals) == 1:
        return float(sorted_vals[0])
    idx = (len(sorted_vals) - 1) * q
    lo = int(idx)
    hi = min(lo + 1, len(sorted_vals) - 1)
    frac = idx - lo
    return sorted_vals[lo] * (1 - frac) + sorted_vals[hi] * frac


def strip_prefix(line):
    return LOGCAT_PREFIX.sub('', line.rstrip('\r\n'))


def parse(path):
    frames = []
    meta = {}
    with open(path, encoding='utf-8', errors='replace') as f:
        head = f.readline()
        if 'GLASS_FRAME_TIMING' not in head:
            f.seek(0)
        for raw in f:
            line = strip_prefix(raw)
            m = FT.match(line)
            if m:
                frames.append(dict(seq=int(m.group(1)), vsync_us=int(m.group(2)),
                                   build_us=int(m.group(3)), raster_us=int(m.group(4)),
                                   span_us=int(m.group(5))))
                continue
            m = META.match(line)
            if m:
                for kv in m.group(1).split():
                    if '=' in kv:
                        k, v = kv.split('=', 1)
                        meta[k] = v
    return frames, meta


def stats_ms(vals_us):
    s = sorted(vals_us)
    return dict(
        median=pct(s, 0.50) / 1000.0,
        p90=pct(s, 0.90) / 1000.0,
        p99=pct(s, 0.99) / 1000.0,
        max=s[-1] / 1000.0 if s else float('nan'),
        n=len(s),
    )


def main():
    ap = argparse.ArgumentParser(description='task-85 页内帧时序分析（build/raster/span，非帧间隔）')
    ap.add_argument('artifact', help='glass_frame_timing 产物（文件或 logcat 文本）')
    ap.add_argument('--refresh-hz', type=float, default=165.0,
                    help='刷新率（默认 165，与 task-19 口径一致）')
    ap.add_argument('--json', dest='json_out', default=None, help='把结论写成 JSON')
    ap.add_argument('--label-hint', default='', help='期望的 label（对不上只提示，不判死）')
    ap.add_argument('--scenario-required', action='store_true', default=True,
                    help='要求场景断言成立（默认开；规格要求不许放松）')
    ap.add_argument('--scenario-min-ratio', type=float, default=0.95,
                    help='场景断言判据：窗口内成立比例 ≥ 该值才算成立（task-86 事前写死 0.95）')
    args = ap.parse_args()

    if not os.path.exists(args.artifact):
        print(f'!! 找不到产物：{args.artifact}')
        return 2
    frames, meta = parse(args.artifact)
    print(f'产物：{args.artifact}')
    print(f'META：{meta if meta else "（无）"}')
    if not frames:
        print('!! 没有解析到任何 FT 行 —— 产物为空，**数据不可用**')
        return 2

    vsyncs = [f['vsync_us'] for f in frames]
    intervals_ms = [(vsyncs[i + 1] - vsyncs[i]) / 1000.0 for i in range(len(vsyncs) - 1)]
    window_ms = float(meta.get('window_ms', 0) or 0)
    span_ms = (vsyncs[-1] - vsyncs[0]) / 1000.0

    build = stats_ms([f['build_us'] for f in frames])
    raster = stats_ms([f['raster_us'] for f in frames])
    span = stats_ms([f['span_us'] for f in frames])
    iv = stats_ms([int(round(v * 1000)) for v in intervals_ms]) if intervals_ms else dict(
        median=float('nan'), p90=float('nan'), p99=float('nan'), max=float('nan'), n=0)

    # ---- task-88：「每秒 raster 占用」= Σ(逐帧 raster) / 窗口秒数（**直接可测**，不是"中位×帧率"推算 ✗）----
    window_s = (window_ms / 1000.0) if window_ms > 0 else (span_ms / 1000.0)
    sum_build_ms = sum(f['build_us'] for f in frames) / 1000.0
    sum_raster_ms = sum(f['raster_us'] for f in frames) / 1000.0
    sum_span_ms = sum(f['span_us'] for f in frames) / 1000.0
    per_s = dict(
        build_ms_per_s=(sum_build_ms / window_s) if window_s else float('nan'),
        raster_ms_per_s=(sum_raster_ms / window_s) if window_s else float('nan'),
        span_ms_per_s=(sum_span_ms / window_s) if window_s else float('nan'),
        frames_per_s=(len(frames) / window_s) if window_s else float('nan'),
        window_s=window_s, sum_raster_ms=sum_raster_ms, sum_build_ms=sum_build_ms,
    )

    # ---- 守卫 1：帧率 > 刷新率 ⇒ 自相矛盾（沿用 measure_fps.py，不许放松）----
    fps_from_interval = 1000.0 / iv['median'] if iv['median'] and iv['median'] == iv['median'] else float('nan')
    fps_from_window = (len(frames) / (window_ms / 1000.0)) if window_ms > 0 else float('nan')
    fps = fps_from_interval
    suspected = fps == fps and fps > args.refresh_hz * 1.05

    # ---- 空洞自检：长时间无帧 ⇒ max 不可用 ----
    holes = []
    if intervals_ms:
        thr = max(5.0 * iv['median'], 50.0)
        holes = [round(v, 1) for v in intervals_ms if v > thr]
    hole_flag = bool(holes) or (raster['p99'] > 0 and raster['max'] > 3 * raster['p99'])

    # ---- 场景断言 ----
    scenario = meta.get('scenario', 'none')
    scenario_ok = int(meta.get('scenario_ok', 0) or 0)
    scenario_total = int(meta.get('scenario_total', 0) or 0)
    ratio = (scenario_ok / scenario_total) if scenario_total else 0.0
    # task-86：判据由"逐帧全真"改为**"窗口内成立比例 ≥ 95%"**（Lead 事前写死 ✓；钩子同一条规则）
    attributable = scenario == 'ok' or ratio >= args.scenario_min_ratio

    print()
    print('帧时序（页内 addTimingsCallback，口径 = build/raster/span，**不是帧间隔**）：')
    print(f'  帧数={len(frames)}  窗口={window_ms:.0f}ms（META）  首末帧跨度={span_ms:.0f}ms')
    print(f'  build : 中位 {build["median"]:.2f}  P90 {build["p90"]:.2f}  '
          f'P99 {build["p99"]:.2f}  最大 {build["max"]:.2f} ms')
    print(f'  raster: 中位 {raster["median"]:.2f}  P90 {raster["p90"]:.2f}  '
          f'P99 {raster["p99"]:.2f}  最大 {raster["max"]:.2f} ms')
    print(f'  span  : 中位 {span["median"]:.2f}  P90 {span["p90"]:.2f}  '
          f'P99 {span["p99"]:.2f}  最大 {span["max"]:.2f} ms')
    print(f'  **每秒占用**: raster {per_s["raster_ms_per_s"]:.2f} ms/s'
          f'（Σraster {per_s["sum_raster_ms"]:.1f} ms ÷ {per_s["window_s"]:.1f} s）'
          f'  build {per_s["build_ms_per_s"]:.2f} ms/s  span {per_s["span_ms_per_s"]:.2f} ms/s'
          f'  **实测帧率 {per_s["frames_per_s"]:.2f} FPS**（{len(frames)} 帧）')
    print(f'  帧间隔: 中位 {iv["median"]:.2f}  P90 {iv["p90"]:.2f}  P99 {iv["p99"]:.2f} ms'
          f'（仅作守卫用，不作性能判据）')
    print(f'  帧率  : {fps:.1f} FPS（由间隔中位）／{fps_from_window:.1f} FPS（由帧数÷窗口）'
          f'  刷新率假设 {args.refresh_hz:g} Hz')
    print(f'  场景断言: scenario={scenario} ok={scenario_ok}/{scenario_total} ratio={ratio:.3f}（判据 ≥{args.scenario_min_ratio:g}）'
          f'{"（通过 → 可归属）" if attributable else "（**未成立 → 数据未归属**）"}')
    if holes:
        print(f'  ⚠️ 空洞自检：发现 {len(holes)} 处长间隔（>max(5×中位,50ms)）：{holes[:8]}'
              f'{" …" if len(holes) > 8 else ""}')
        print('     ⇒ 按既有纪律：**只用中位/P90/P99，max 不作判据**')
    elif hole_flag:
        print('  ⚠️ 空洞自检：max ≫ P99（3× 以上）⇒ max 不作判据')
    else:
        print('  ✓ 空洞自检：未发现长间隔，max 可用')
    if args.label_hint and meta.get('label', '') != args.label_hint:
        print(f'  ! label 期望 {args.label_hint}，实际 {meta.get("label", "")}（仅提示）')

    usable = (not suspected) and attributable
    print()
    print('===== 判定 =====')
    if suspected:
        print(f'  ✗ **不可用**：帧率 {fps:.1f} > 刷新率 {args.refresh_hz:g}×1.05 ⇒ 自相矛盾'
              '（窗口很可能被遮挡/未节流）⇒ 这批数据**不能当验收值**。'
              '（守卫沿用 measure_fps.py，规格 §0.1.31 第 9 条：宁缺勿滥）')
    if not attributable:
        print(f'  ✗ **未归属**：场景断言 scenario={scenario}'
              f'（{"未提供探针" if scenario == "none" else "窗口内未成立"}）'
              '⇒ 数据不可归属到任何一臂（手册 §18.69）。')
    if usable:
        print(f'  ✓ **可用于两臂对比**：口径=build/raster（非帧间隔）、场景成立'
              f'（ok={scenario_ok}/{scenario_total}）、无"帧率>刷新率"自相矛盾。'
              '判据：P99（raster）为主，中位/P90 为辅'
              + ('；存在长空洞 ⇒ **不用 max**' if hole_flag else ''))

    out = dict(
        artifact=os.path.abspath(args.artifact),
        caliber='page addTimingsCallback build/raster/span（非帧间隔）',
        label=meta.get('label', ''), frames=len(frames),
        window_ms=window_ms, span_ms=round(span_ms, 1),
        build_ms=build, raster_ms=raster, span_ms_stats=span,
        interval_ms=iv, per_second=per_s, refresh_hz=args.refresh_hz,
        fps_from_interval=round(fps, 2) if fps == fps else None,
        fps_from_window=round(fps_from_window, 2) if fps_from_window == fps_from_window else None,
        suspected_occluded_or_unthrottled=suspected,
        valid_as_smoothness_metric=not suspected,
        scenario=scenario, scenario_ok=scenario_ok, scenario_total=scenario_total,
        attributable=attributable,
        holes=holes, hole_flag=hole_flag,
        usable_for_acceptance=usable,
    )
    if args.json_out:
        with open(args.json_out, 'w', encoding='utf-8') as f:
            json.dump(out, f, ensure_ascii=False, indent=2)
        print(f'  JSON 已写：{args.json_out}')
    return 0 if usable else 2


if __name__ == '__main__':
    sys.exit(main())