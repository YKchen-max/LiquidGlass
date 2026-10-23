#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""LiquidGlass for Bilibili —— 用 Dart VM Service 采集 Flutter 帧时序（帧率基线）

为什么需要它：
  * Android 上 `dumpsys SurfaceFlinger --latency` 自 Android 14 起对普通调用者**不再返回帧数据**
    （实测只回一行刷新周期 16666666ns），`dumpsys gfxinfo` 又只统计 HWUI 帧、看不到 Flutter 的绘制；
  * Flutter 自己的 `Flutter.Frame` 时间线事件才是权威口径（含 build/raster/vsyncOverhead），
    也是 DevTools 性能页的数据来源。

用法（先跑一次 `flutter run --profile -d windows`，从输出里拿 VM service URI）::

    python tool/measure_fps.py --vm-service http://127.0.0.1:12345/AbCdEf= --seconds 12
    python tool/measure_fps.py --vm-service ... --json fps-report.json

口径说明：
  * FPS = 采样窗口内的帧数 / 窗口时长（帧事件由引擎在每帧提交后上报）；
  * 卡顿判定用 60Hz 的 16.7ms 预算；设备若是 120Hz，请把 --vsync-ms 设成 8.3；
  * 只做只读查询（setVMTimelineFlags / clearVMTimeline / getVMTimeline 三个 RPC）。
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
import time

try:
    import websocket  # websocket-client
except ImportError:  # pragma: no cover
    sys.exit("需要 websocket-client：python -m pip install websocket-client -i https://pypi.tuna.tsinghua.edu.cn/simple")

_next_id = [0]


def ws_url(vm_service: str) -> str:
    """http://127.0.0.1:PORT/TOKEN=/ → ws://127.0.0.1:PORT/TOKEN=/ws

    实测：新版 Dart VM Service **不接受** 根路径的 HTTP JSON-RPC（405 Method Not Allowed），
    只走 WebSocket，所以这里直接连 /ws。
    """
    u = vm_service.rstrip("/")
    if u.startswith("http://"):
        u = "ws://" + u[len("http://"):]
    elif u.startswith("https://"):
        u = "wss://" + u[len("https://"):]
    return u if u.endswith("/ws") else u + "/ws"


class VmService:
    def __init__(self, vm_service: str, timeout: float = 60.0):
        self.uri = ws_url(vm_service)
        self.ws = websocket.create_connection(self.uri, timeout=timeout)

    def rpc(self, method: str, params: dict | None = None, timeout: float = 60.0):
        _next_id[0] += 1
        rid = _next_id[0]
        self.ws.settimeout(timeout)
        self.ws.send(json.dumps({
            "jsonrpc": "2.0", "id": rid, "method": method, "params": params or {},
        }))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get("id") != rid:
                continue  # 事件流消息，跳过
            if "error" in msg:
                raise RuntimeError(f"{method} 失败: {msg['error']}")
            return msg.get("result", {})

    def close(self) -> None:
        try:
            self.ws.close()
        except Exception:  # noqa: BLE001
            pass


def percentile(values: list[float], p: float) -> float:
    if not values:
        return float("nan")
    s = sorted(values)
    k = max(0, min(len(s) - 1, int(round((p / 100.0) * (len(s) - 1)))))
    return s[k]


# task-24：替代 raster 口径的候选（按优先级），以及 B/E 配对求差的实现。
# **绝不叫 raster_ms**：这是引擎事件派生的近似，不是 FrameTiming.raster。
PROXY_PRIORITY = [
    "Rasterizer::DrawToSurfaces",              # raster 线程主力（每帧一条 B/E 对）
    "GPURasterizer::Draw",
    "CompositorContext::ScopedFrame::Raster",
    "Animator::Render",
]
PROXY_DEFINITION = (
    "引擎时间线事件 begin/end 配对求差（(name,pid,tid) 栈式配对）；"
    "**不是 FrameTiming.raster**，不可直接与 vsync 预算比较；"
    "环形缓冲截断会导致部分事件配不上（见 unpaired）"
)


def pair_be_durations(events: list) -> tuple[list[float], int]:
    """把 [(ph, ts, pid, tid)] 配对成 duration（µs）。返回 (成功列表, 配不上条数)。"""
    stacks: dict = {}
    out: list[float] = []
    unpaired = 0
    for ph, ts, pid, tid in sorted(events, key=lambda e: e[1]):
        key = (pid, tid)
        if ph == "B":
            stacks.setdefault(key, []).append(ts)
        else:  # "E"
            st = stacks.get(key)
            if st:
                out.append(float(ts - st.pop()))
            else:
                unpaired += 1
    unpaired += sum(len(s) for s in stacks.values())  # 没闭合的 B
    return out, unpaired


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="采集 Flutter 帧时序（VM Service）")
    ap.add_argument("--vm-service", required=True, help="如 http://127.0.0.1:12345/TOKEN=")
    ap.add_argument("--seconds", type=float, default=10.0, help="采样窗口（默认 10 秒）")
    ap.add_argument("--vsync-ms", type=float, default=16.7, help="帧预算（60Hz=16.7，120Hz=8.3）")
    ap.add_argument("--refresh-hz", type=float, default=165.0,
                    help="显示器刷新率：帧率显著高于它 → 说明窗口被遮挡/未按 vsync 节流，数据不可当流畅度用")
    ap.add_argument("--json", default="", help="报告输出路径")
    ap.add_argument("--label", default="", help="场景标签，如 首页 idle / 播放中")
    ap.add_argument("--raster-source", choices=["off", "engine-events"], default="off",
                    help="【替代口径，默认 off】engine-events：用引擎时间线事件的 begin/end 配对"
                         "求差，派生一个 raster **近似值**（本机 debug/profile 都不发 Flutter.Frame，"
                         "所以取不到 FrameTiming.raster）。输出在 raster_proxy_ms，带 source 标注："
                         "这**不是** FrameTiming.raster，**不可**直接与 vsync 预算比较；"
                         "比值随配置/平台变化，引用前必须用同运行的页内 addTimingsCallback 真值"
                         "重新校准（--calibration-ref-ms）")
    ap.add_argument("--calibration-ref-ms", type=float, default=None,
                    help="同一次运行里页内 addTimingsCallback 得到的 raster 中位（ms），用于把"
                         "代理值与真值的比值冻结进 calibration_note；不传则只标注未校准")
    ap.add_argument("--calibration-config", default="",
                    help="校准时的配置描述，如 debug/Skia/MG_COUNT=1（随 calibration_note 一起记录）")
    ap.add_argument("--dump-events", action="store_true",
                    help="只打印**原始**时间线的事件名分布（排查口径用），不做统计。"
                         "注意：计数是各次快照的累加（环形缓冲会重复上报同一条事件），"
                         "所以只用来看某事件是否存在与量级，不要当精确条数")
    ap.add_argument("--samples", type=int, default=30,
                    help="快照次数（时间线是环形缓冲，单次只能拿到最近几秒；多次快照取并集）。默认 30——实测只取 4 次会在并集里留下 1.7~2.6 秒空洞，max 被假造成 2 秒级、聚合 FPS 从 322 腰斩到 178")
    args = ap.parse_args(argv)

    uri = args.vm_service
    print(f"连接 VM Service: {ws_url(uri)}")
    vm = VmService(uri)

    # 1) 打开 Embedder/GC 类别（Flutter.Frame 事件来自 Embedder），清空缓冲，再等窗口结束
    vm.rpc("setVMTimelineFlags", {"recordedStreams": ["Dart", "Embedder", "GC"]})
    vm.rpc("clearVMTimeline")
    t0 = time.time()
    print(f"采样中（{args.seconds:.0f} 秒，分 {args.samples} 次快照）… 请让目标场景保持活动（滚动 / 播放）")
    merged: dict[int, dict] = {}
    animator_ts: set[int] = set()
    # task-21：原始时间线的分布要留下来。原因：--dump-events 原来统计的是**过滤后的合并结果**，
    # 所以"时间线里到底有什么"根本看不到——`build_ms/raster_ms` 恒为 null 这件事就是这样藏了很久。
    # 代价：每事件一次 dict 自增（实测 3 万级事件 × 30 次快照无感），不改变任何既有口径。
    import collections
    raw_pairs: collections.Counter = collections.Counter()        # (name, cat) -> 次数
    raw_framish: collections.Counter = collections.Counter()      # 帧相关的子集
    raw_framish_sample: dict = {}                                 # (name, cat) -> args 键（取样）
    framish_hints = ("Frame", "Animator", "Rasterizer", "Vsync", "Timing",
                     "Draw", "Present", "BUILD", "PAINT", "COMPOSITING")
    # task-24：替代 raster 口径（默认 off）。引擎事件**不带 `dur`**（探针实测：16 个候选全是
    # ph=B/E 成对事件，带 dur 的条数 = 0）⇒ 只能按 (name,pid,tid) 配对求差**派生** duration。
    # 这是 trace 处理的标准操作，但**必须显式标注**成派生值，并回报配不上的条数（环形缓冲截断）。
    proxy_events: dict = {}   # name -> [(ph, ts, pid, tid)]
    if args.raster_source == "engine-events":
        for cand in PROXY_PRIORITY:
            proxy_events[cand] = []
    per = max(0.5, args.seconds / max(1, args.samples))
    for i in range(args.samples):
        time.sleep(per)
        tl = vm.rpc("getVMTimeline", timeout=90)
        for e in tl.get("traceEvents", []):
            name, cat = e.get("name"), e.get("cat")
            raw_pairs[(name, cat)] += 1
            if proxy_events is not None and name in proxy_events:
                ph = e.get("ph")
                if ph in ("B", "E") and isinstance(e.get("ts"), int):
                    proxy_events[name].append((ph, e["ts"], e.get("pid"), e.get("tid")))
            if name and any(h in name for h in framish_hints):
                raw_framish[(name, cat)] += 1
                if (name, cat) not in raw_framish_sample:
                    ea = e.get("args")
                    raw_framish_sample[(name, cat)] = sorted(ea.keys()) if isinstance(ea, dict) else None
            if name == "Animator::BeginFrame" and e.get("ts"):
                animator_ts.add(e["ts"])
            if name == "Flutter.Frame":
                a = e.get("args") or {}
                if isinstance(a, dict) and e.get("ts"):
                    merged[e["ts"]] = {
                        "kind": "Flutter.Frame", "ts": e["ts"], "elapsed_us": a.get("elapsed"),
                        "build_us": a.get("build"), "raster_us": a.get("raster"),
                    }
            elif name == "Frame" and cat == "Dart" and e.get("ts"):
                merged.setdefault(e["ts"], {
                    "kind": "Frame@Dart", "ts": e["ts"], "elapsed_us": e.get("dur"),
                    "build_us": None, "raster_us": None,
                })
    wall = time.time() - t0
    vm.close()
    timeline = {"traceEvents": list(merged.values())}

    # task-24：替代 raster 口径（派生）。挑第一个配对样本足够的候选；配不上的条数如实带出。
    raster_proxy = None
    if args.raster_source == "engine-events":
        best = None
        for cand in PROXY_PRIORITY:
            durs, unpaired = pair_be_durations(proxy_events.get(cand) or [])
            if len(durs) >= 10:
                best = (cand, durs, unpaired)
                break
            if durs and best is None:
                best = (cand, durs, unpaired)  # 兜底：样本少也留着，但下面会标注样本不足
        if best is None:
            raster_proxy = {"source": None, "definition": PROXY_DEFINITION, "available": False,
                            "note": "候选事件在本次窗口里没有可配对的 B/E 对"}
        else:
            cand, durs, unpaired = best
            ms = [d / 1000.0 for d in durs]
            raster_proxy = {
                "available": True,
                "source": f"{cand}.B/E-paired",
                "definition": PROXY_DEFINITION,
                "n_paired": len(durs), "n_unpaired": unpaired,
                "median": statistics.median(ms), "p90": percentile(ms, 90),
            }
            if args.calibration_ref_ms and args.calibration_ref_ms > 0:
                ratio = raster_proxy["median"] / args.calibration_ref_ms
                raster_proxy["calibration_note"] = (
                    f"同运行对比：代理 {raster_proxy['median']:.3f} ms vs 页内 FrameTiming.raster 真值 "
                    f"{args.calibration_ref_ms:.3f} ms，比值 {ratio:.2f}"
                    f"{('；配置 ' + args.calibration_config) if args.calibration_config else ''}"
                    f"；该比值随配置/平台变化，引用前必须重新校准；代理不可替代 FrameTiming.raster")
            else:
                raster_proxy["calibration_note"] = (
                    "未提供页内真值（--calibration-ref-ms）⇒ 未校准：代理值只能作相对比较，"
                    "不得当绝对 raster 使用")

    if args.dump_events:
        # 打印**原始**时间线（不是过滤后的合并结果）——这是"口径诊断"唯一有用的形态。
        print(f"原始时间线事件总数 {sum(raw_pairs.values())}，按 (name, cat) 分布（top 30）：")
        for (name, cat), n in raw_pairs.most_common(30):
            print(f"  {n:7d}  {name}   [{cat}]")
        print()
        print("帧相关事件（原始）：")
        for (name, cat), n in raw_framish.most_common(20):
            print(f"  {n:7d}  {name} [{cat}]  args={raw_framish_sample.get((name, cat))}")
        print()
        has_ff = any(k[0] == "Flutter.Frame" for k in raw_pairs)
        has_fd = any(k[0] == "Frame" and k[1] == "Dart" for k in raw_pairs)
        print(f"Flutter.Frame 存在={has_ff}（带 build/raster 参数的那个）; Frame@Dart 存在={has_fd}")
        if not has_ff:
            print("⚠️ 时间线里没有 Flutter.Frame ⇒ build/raster 无法从时间线取得（与 --profile 无关，是事件本身没发）。")
            print("   raster 判据请改用页内 SchedulerBinding.addTimingsCallback（手册 §16）；")
            print("   这里可用的替代源（**口径不同，需显式批准后才可作为另一口径启用**）：")
            for (name, cat), n in raw_framish.most_common():
                if name in ("Rasterizer::DrawToSurfaces", "GPURasterizer::Draw",
                            "CompositorContext::ScopedFrame::Raster", "Animator::Render",
                            "BUILD", "PAINT", "COMPOSITING", "LayerTree::Paint"):
                    print(f"     {n:7d}  {name} [{cat}]")
        if args.json:
            with open(args.json, "w", encoding="utf-8") as fh:
                json.dump({
                    "raw_events": sum(raw_pairs.values()),
                    "pairs": {f"{k[0]}|{k[1]}": v for k, v in raw_pairs.items()},
                    "frame_ish": {f"{k[0]}|{k[1]}": v for k, v in raw_framish.items()},
                    "has_flutter_frame": has_ff, "has_frame_at_dart": has_fd,
                }, fh, ensure_ascii=False, indent=2)
            print(f"（原始分布已写入 {args.json}）")
        return 0

    # merged 里已经是归一化后的帧记录（Frame@Dart 或 Flutter.Frame），按时间排序
    frames = sorted(merged.values(), key=lambda f: f["ts"])

    if not frames:
        if len(animator_ts) >= 2:
            starts = sorted(animator_ts)
            span_s = (starts[-1] - starts[0]) / 1e6
            print(f"（未找到 Frame/Flutter.Frame，改用 Animator::BeginFrame 计数）")
            print(f"  帧数 {len(starts)} / 窗口 {span_s:.2f}s → **{(len(starts) - 1) / span_s:.1f} FPS**")
            return 0
        print("❌ 没有采到帧事件。请确认：① 用 --profile/--release 跑；② 采样期间界面确实在动；"
              "③ 先用 --dump-events 看清楚这个版本的事件名。")
        return 1

    span_s = (frames[-1]["ts"] - frames[0]["ts"]) / 1e6 if len(frames) > 1 else wall
    # 帧间隔（比"帧数/窗口"更耐得住环形缓冲截断，因为它是相邻帧的时间差）
    intervals = [round((frames[i]["ts"] - frames[i - 1]["ts"]) / 1000, 3) for i in range(1, len(frames))]
    fps = (len(frames) - 1) / span_s if span_s > 0 else float("nan")
    builds = [f["build_us"] / 1000 for f in frames if f["build_us"]]
    rasters = [f["raster_us"] / 1000 for f in frames if f["raster_us"]]
    totals = [f["elapsed_us"] / 1000 for f in frames if f["elapsed_us"]]
    budget = args.vsync_ms
    janky = [t for t in totals if t > budget]

    print()
    print(f"—— 帧时序报告 {('[' + args.label + '] ') if args.label else ''}——")
    print(f"  帧数            : {len(frames)}（口径 {frames[0]['kind']}）")
    print(f"  有效采样窗口    : {span_s:.2f} 秒（挂钟 {wall:.2f} 秒"
          f"{'；注意：时间线是环形缓冲，窗口被截断' if span_s < wall * 0.6 else ''}）")
    print(f"  **帧率          : {fps:.1f} FPS**")
    if intervals:
        print(f"  帧间隔 中位/P90 : {statistics.median(intervals):.2f} / {percentile(intervals, 90):.2f} ms"
              f"（中位间隔折算 {1000 / statistics.median(intervals):.1f} FPS）")
        print(f"  帧间隔 P99/最大 : {percentile(intervals, 99):.2f} / {max(intervals):.2f} ms")
    if builds:
        print(f"  build  中位/P90 : {statistics.median(builds):.2f} / {percentile(builds, 90):.2f} ms")
    if rasters:
        print(f"  raster 中位/P90 : {statistics.median(rasters):.2f} / {percentile(rasters, 90):.2f} ms")
    if totals:
        print(f"  帧总耗时 P90/最大: {percentile(totals, 90):.2f} / {max(totals):.2f} ms")
        print(f"  超预算(>{budget:g}ms) : {len(janky)} 帧（{len(janky) / len(totals):.1%}）")

    # task-24：替代口径的输出（带 source 标注；让人一眼看出**不是** FrameTiming.raster）
    if raster_proxy is not None:
        if raster_proxy.get("available"):
            print(f"  [替代口径] raster_proxy 中位/P90: {raster_proxy['median']:.2f} / "
                  f"{raster_proxy['p90']:.2f} ms   （source={raster_proxy['source']}，"
                  f"配对 {raster_proxy['n_paired']} / 丢弃 {raster_proxy['n_unpaired']}）")
            print(f"  [替代口径] ⚠ 这是引擎事件派生近似，**不是 FrameTiming.raster**，不可直接与 "
                  f"{budget:g}ms 预算比较")
            print(f"  [替代口径] {raster_proxy['calibration_note']}")
        else:
            print(f"  [替代口径] raster_proxy 不可用：{raster_proxy['note']}")

    # task-21：build/raster 取不到时**显式说明原因**（原来只是静默 null，表格里显示 "—"，
    # 谁也不知道是"数据不好看"还是"通道取不到"）。这里只加说明，不改任何既有字段的含义。
    has_ff = any(k[0] == "Flutter.Frame" for k in raw_pairs)
    if not (builds or rasters):
        kind = frames[0]["kind"] if frames else "?"
        print(f"  build/raster    : 取不到（本次帧事件口径 = {kind}）")
        print(f"  ↳ 原因          : 时间线里{'有' if has_ff else '没有'} Flutter.Frame"
              f"（带 build/raster 参数的事件）；Frame@Dart 只有总时长、没有 build/raster 分解。")
        print("  ↳ 可用替代      : raster 判据请用页内 SchedulerBinding.addTimingsCallback（手册 §16）；"
              "本工具 --dump-events 会列出时间线里实际可用的事件名")

    # 采样空洞自检：max 远大于 P99 说明并集里有空洞（快照太稀疏），不是真卡顿。
    # 判据来自 M1-C 实测：稀疏快照 max=2605.7ms / P99=5.94ms（真值 max=29.8ms）。
    if intervals and len(intervals) > 5:
        _p99 = percentile(intervals, 99)
        _max = max(intervals)
        if _max > max(200.0, _p99 * 20):
            print()
            print(f"  ⚠️ max({_max:.0f}ms) 比 P99({_p99:.2f}ms) 高两个数量级 → 采样并集里有空洞，"
                  f"max 与聚合 FPS 不可信；请把 --samples 调大（建议 30）后重采。")

    # 遮挡自检：Flutter 桌面端在窗口被遮挡时不按 vsync 节流，帧产出率会跑到刷新率之上。
    # 这时数字只代表"引擎画得动"，不代表用户看到的流畅度。
    suspected_occluded = fps > args.refresh_hz * 1.05
    if suspected_occluded:
        print()
        print(f"  ⚠️ 帧率({fps:.1f}) 高于刷新率({args.refresh_hz:g}Hz) → 窗口很可能被遮挡/未节流，"
              f"请把窗口置于前台且不要切换窗口后重采；该数据不可当验收值。")

    report = {
        "label": args.label, "vm_service": args.vm_service, "seconds": args.seconds,
        "vsync_budget_ms": budget, "frames": len(frames), "span_s": span_s, "fps": fps,
        "frame_interval_ms": {
            "median": statistics.median(intervals) if intervals else None,
            "p90": percentile(intervals, 90) if intervals else None,
            "p99": percentile(intervals, 99) if intervals else None,
            "max": max(intervals) if intervals else None,
        },
        "fps_from_median_interval": (1000 / statistics.median(intervals)) if intervals else None,
        "build_ms": {"median": statistics.median(builds) if builds else None,
                     "p90": percentile(builds, 90) if builds else None},
        "raster_ms": {"median": statistics.median(rasters) if rasters else None,
                      "p90": percentile(rasters, 90) if rasters else None},
        "frame_total_ms": {"p90": percentile(totals, 90) if totals else None,
                           "max": max(totals) if totals else None},
        "janky_frames": len(janky), "janky_ratio": (len(janky) / len(totals)) if totals else None,
        "frame_event_kind": frames[0]["kind"] if frames else None,
        # task-21 新增（只增不改）：build/raster 是否可用 + 不可用时的原因，便于表格自动加脚注。
        "frame_timing_available": bool(builds or rasters),
        "timeline_has_flutter_frame": has_ff,
        "frame_timing_note": None if (builds or rasters) else (
            "时间线里没有 Flutter.Frame（带 build/raster 参数的事件）⇒ build_ms/raster_ms 取不到；"
            "Frame@Dart 无分解。raster 判据用页内 SchedulerBinding.addTimingsCallback（手册 §16）。"
        ),
        "refresh_hz": args.refresh_hz,
        "suspected_occluded_or_unthrottled": suspected_occluded,
        "valid_as_smoothness_metric": not suspected_occluded,
    }
    # task-24：替代口径**只在开关打开时出现**（默认 off ⇒ 输出与之前逐字段一致）
    if raster_proxy is not None:
        report["raster_proxy_ms"] = raster_proxy
        report["raster_proxy_source"] = raster_proxy.get("source")
        report["raster_proxy_is_frametiming"] = False
    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(report, fh, ensure_ascii=False, indent=2)
        print(f"  报告            : {args.json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())