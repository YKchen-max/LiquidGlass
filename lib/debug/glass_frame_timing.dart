// SPDX-License-Identifier: GPL-3.0-or-later
//
// task-85（规格 `docs/真折射移植计划.md` §0.1.31【口径改造规格】）：**页内帧时序采样钩子**。
//
// 为什么需要：`measure_fps.py` 的 `Frame@Dart` **帧间隔**口径在 .debug/.prof 上两臂都给出
// 249.7 / 248.3 FPS > 刷新率 165 Hz ⇒ 工具自身的守卫判"不可当验收值"（不是设计不可测，
// 是"这条口径在这个构建上不成立"）。⇒ 换口径：**页内用 `addTimingsCallback` 直接采
// `buildDuration` / `rasterDuration` / `totalSpan`**，不再依赖帧间隔。
//
// 怎么开（两道都满足才生效）：
//   1. **debug 构建**（`kDebugMode`）——release/profile 下 `kDebugMode == false` ⇒ 常量折叠 ⇒ 死代码；
//   2. **`--dart-define=GLASS_FRAME_TIMING=1`**（编译期开关）。
// 然后调用 `GlassFrameTiming.instance.start(window: ...)` 起窗口、`stop()` 收窗口并落盘。
//
// 怎么关：不加 `--dart-define` ⇒ `glassFrameTimingEnabled == false` ⇒ `install()` 立刻返回，
// **零注册、零分配、零回调**（见 `.probe/m1c/README.md` 的门控自证）。
//
// 产物格式（host 侧 `app/tool/glass_frame_timing.py` 解析；同一格式也支持从 logcat 里抓）：
//   # GLASS_FRAME_TIMING v1
//   META label=... window_ms=... frames=... first_vsync_us=... last_vsync_us=...
//   META scenario=ok|fail|none scenario_ok=... scenario_total=... export=<path>
//   FT <seq> <vsync_us> <build_us> <raster_us> <span_us>
//   ...
//
// 纪律：本文件**不碰**渲染/策略代码，只做"观测"；release 无行为是硬要求。

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// 编译期开关：**release 下恒为 false**，因此所有调用点都被折叠掉。
///
/// 打开方式：`flutter build apk --profile --dart-define=GLASS_FRAME_TIMING=true`
/// （**也接受 `=1`** ✓ —— 见下面的解释）。
///
/// task-86 把门控从 `kDebugMode` 放宽到 **`!kReleaseMode`**（照 task-81 给图内标记的先例）：
/// **本轮口径只能用 profile 包测**（`.debug` 上是另一套不可用的帧事件口径 ✗），
/// 而 `kDebugMode` 在 profile 下是 false ⇒ 钩子根本不装 ✗。
/// **`!kReleaseMode` 仍保证 release 恒 false**（即便同时给了 `--dart-define`）⇒ "release 零行为"不被破 ✓。
///
/// ⚠️ 踩过的坑（task-86 实测）：**`bool.fromEnvironment` 只认字面量 `"true"`** ——
/// `--dart-define=GLASS_FRAME_TIMING=1` 会**静默**得到 `false` ✗（钩子不装、一条 `[FT]` 都没有）。
/// 所以这里**同时接受 `true` 与 `1`**，两种写法都不会再静默失效 ✓。
const bool glassFrameTimingEnabled = !kReleaseMode &&
    (bool.fromEnvironment('GLASS_FRAME_TIMING') ||
        String.fromEnvironment('GLASS_FRAME_TIMING') == '1');

/// task-86（Lead 批准的方案 1）：**门控"常显控制条"** —— 让被测对象在测量窗口内持续存在。
///
/// 为什么口径仍成立 ✓：**两臂都有可见的控制条**（臂 B 是纯色条 ✓），"让条常显"只是让被测对象存在，
/// **不改变"谁 vs 谁"** ✓ —— 而条一隐藏，折射层就没了（task-86 实测 `window_ms=6001 frames=34` 就是它 ✗）。
///
/// 打开：`--dart-define=GLASS_KEEP_CONTROLS=true`（**也接受 `1`** ✓，同上面那个坑）；
/// **release 恒 false** ⇒ 出厂路径零影响 ✓。
const bool glassKeepControlsEnabled = !kReleaseMode &&
    (bool.fromEnvironment('GLASS_KEEP_CONTROLS') ||
        String.fromEnvironment('GLASS_KEEP_CONTROLS') == '1');

/// 页内帧时序采样器（单例）。窗口里累计每帧原始值，`stop()` 时导出。
class GlassFrameTiming {
  GlassFrameTiming._();

  /// 单例。
  static final GlassFrameTiming instance = GlassFrameTiming._();

  /// 在 `main()` 里调用**一次**即可（门控在内部；未启用时为 no-op）。
  ///
  /// 注意：必须在 `WidgetsFlutterBinding.ensureInitialized()` 之后调用
  /// （`SchedulerBinding.instance` 此时才可用）。
  static void install() {
    if (!glassFrameTimingEnabled) {
      return;
    }
    instance._installIfNeeded();
  }

  bool _installed = false;
  bool _recording = false;
  final List<String> _frameLines = <String>[];
  final Stopwatch _window = Stopwatch();
  Timer? _timer;
  bool Function()? _scenarioProbe;
  int _scenarioOk = 0;
  int _scenarioTotal = 0;
  int _firstVsyncUs = 0;
  int _lastVsyncUs = 0;
  String _label = '';
  int _seq = 0;

  /// 窗口内写了多少帧（含尚未落盘的）。
  int get frameCount => _frameLines.length;

  /// 是否正在采样。
  bool get isRecording => _recording;

  void _installIfNeeded() {
    if (_installed) {
      return;
    }
    _installed = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    debugPrint('[FT] GlassFrameTiming installed（口径=build/raster，非帧间隔）');
  }

  /// 开始一个采样窗口。
  ///
  /// * [window] 窗口时长，规格建议 **≥ 30 s**（与既有窗口可比）；到点自动 `stop()` 并落盘。
  /// * [scenarioProbe] **场景断言**（规格 §0.1.31 第 5 条 / 手册 §18.69）：
  ///   每次采样都会问它"当前场景是否成立"（例如"图内标记在位"）。
  ///   **不传 ⇒ 无法断言 ⇒ 产物标 `scenario=none` ⇒ 分析器会把数据标"未归属"**。
  /// * [label] 产物里的标签（例如 `refraction` / `solid`），便于两臂区分。
  /// * [note] 附在 META 里的一段备注（例如刷新率实测来源：`refresh_hz=144` 的 `dumpsys` 原文）。
  /// * [requireFades] **task-92 的场景判据**：窗口内**"换档淡入"至少发生 N 次**才算场景成立 ✓
  ///   （`scenario=ok` ⟺ `fades ≥ requireFades` ∧ 逐帧比例 ≥0.95 ✓）。
  ///   ⚠ 为什么不做成"逐帧 probe 返回 `fades>=N`" ✗：那是**累积量** ⇒ 窗口前段必然 false
  ///   ⇒ 比例永远上不去 ⇒ 每次都被判未归属 ✗✗；所以它按**窗口级**判定 ✓。
  void start({
    Duration window = const Duration(seconds: 30),
    bool Function()? scenarioProbe,
    String label = '',
    String note = '',
    int requireFades = 0,
    bool printFramesToLog = false,
  }) {
    if (!glassFrameTimingEnabled) {
      return;
    }
    _installIfNeeded();
    if (_recording) {
      debugPrint('[FT] 已在采样中，忽略重复 start()');
      return;
    }
    _recording = true;
    _windowId++;
    _frameLines.clear();
    _scenarioOk = 0;
    _scenarioTotal = 0;
    _firstVsyncUs = 0;
    _lastVsyncUs = 0;
    _seq = 0;
    _label = label;
    _note = note;
    _scenarioProbe = scenarioProbe;
    _requireFades = requireFades;
    _fades = 0;
    _cvVisible = 0;
    _cvTotal = 0;
    _printFramesToLog = printFramesToLog;
    _window
      ..reset()
      ..start();
    _timer = Timer(window, () {
      // 到点自动收窗口（窗口时长由本轮调用方给定，规格要求 ≥30 s）
      unawaited(stop());
    });
    debugPrint('[FT] window start id=$_windowId label=$_label '
        'window=${window.inMilliseconds}ms '
        'scenarioProbe=${scenarioProbe == null ? 'none' : 'on'}');
  }

  /// 进程内第几个窗口（1 = 该进程的唯一窗口 ⇒ 证明"单臂内不重启、不混窗口"）。
  int get windowId => _windowId;

  /// 更新产物 label（窗口结束前调用；task-86 用它按"窗口内实际走的分支"标臂）。
  void setLabel(String value) {
    _label = value;
  }

  /// task-92：把**窗口级机制量**写进产物（淡入次数 + 控制条可见统计 ✓）。
  void setFades(int fades, int requireFades) {
    _fades = fades;
    _requireFades = requireFades;
  }

  /// task-92：控制条可见心跳统计（只作参考，不当逐帧判据 ✗）。
  void setControlsVisibleStat(int visible, int total) {
    _cvVisible = visible;
    _cvTotal = total;
  }

  int _fades = 0;
  int _requireFades = 0;
  int _cvVisible = 0;
  int _cvTotal = 0;

  String _note = '';
  int _windowId = 0;

  bool _printFramesToLog = false;

  void _onTimings(List<FrameTiming> timings) {
    if (!_recording) {
      return;
    }
    for (final t in timings) {
      final vsync = t.timestampInMicroseconds(ui.FramePhase.vsyncStart);
      if (_firstVsyncUs == 0) {
        _firstVsyncUs = vsync;
      }
      _lastVsyncUs = vsync;
      _seq++;
      final line = 'FT $_seq $vsync '
          '${t.buildDuration.inMicroseconds} '
          '${t.rasterDuration.inMicroseconds} '
          '${t.totalSpan.inMicroseconds}';
      _frameLines.add(line);
      if (_printFramesToLog) {
        debugPrint(line);
      }
      if (_scenarioProbe != null) {
        _scenarioTotal++;
        if (_scenarioProbe!()) {
          _scenarioOk++;
        }
      }
    }
  }

  /// 结束窗口、落盘并返回产物全文（未启用时返回空串）。
  Future<String> stop() async {
    if (!_recording) {
      return '';
    }
    _recording = false;
    _window.stop();
    _timer?.cancel();
    _timer = null;

    final ratio =
        _scenarioTotal == 0 ? 0.0 : (_scenarioOk / _scenarioTotal);
    // task-92：**两把锁** —— 逐帧"上下文成立"（ratio ≥0.95）∧ 窗口级"机制真的发生"（fades ≥ requireFades）✓
    final fadesOk = _fades >= _requireFades;
    final scenario = _scenarioProbe == null
        ? 'none'
        : (ratio >= 0.95 && fadesOk ? 'ok' : 'fail');

    final buf = StringBuffer()
      ..writeln('# GLASS_FRAME_TIMING v1（口径：addTimingsCallback 的 '
          'build/raster/span，**不是**帧间隔）')
      ..writeln('META label=$_label window_ms=${_window.elapsedMilliseconds} '
          'frames=${_frameLines.length} first_vsync_us=$_firstVsyncUs '
          'last_vsync_us=$_lastVsyncUs')
      ..writeln('META scenario=$scenario scenario_ok=$_scenarioOk '
          'scenario_total=$_scenarioTotal '
          'scenario_ratio=${ratio.toStringAsFixed(4)} '
          'scenario_rule=ok>=0.95 && fades>=require_fades export=${exportPath()}')
      ..writeln('META fades=$_fades require_fades=$_requireFades '
          'fades_ok=${fadesOk ? 1 : 0} '
          'controls_visible_pulses=$_cvVisible controls_pulses_total=$_cvTotal '
          '(task-92：逐帧锁=上下文成立；机制锁=淡入次数 ≥require_fades)')
      ..writeln('META discipline=pid=$pid window_id=$_windowId '
          'single_window=${_windowId == 1} no_restart_during_window=true '
          'arm=$_label note=$_note')
      ..writeAll(_frameLines, '\n')
      ..writeln();
    final text = buf.toString();

    var written = '（未写盘）';
    try {
      final f = File(exportPath());
      await f.writeAsString(text, flush: true);
      written = f.path;
    } catch (e) {
      // 写盘失败不能影响被测页面本身：数据仍在 logcat 的 [FT] 行里（若开了 printFramesToLog）
      debugPrint('[FT] 写盘失败（不影响页面）：$e');
    }
    debugPrint('[FT] window stop label=$_label frames=${_frameLines.length} '
        'window_ms=${_window.elapsedMilliseconds} scenario=$scenario → $written');
    return text;
  }

  /// 产物路径：默认 `<systemTemp>/glass_frame_timing.txt`；
  /// 可用 `--dart-define=GLASS_FRAME_TIMING_PATH=...` 覆盖（例如指向 `/data/local/tmp`）。
  String exportPath() {
    const override = String.fromEnvironment('GLASS_FRAME_TIMING_PATH');
    if (override.isNotEmpty) {
      return override;
    }
    try {
      return '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'glass_frame_timing.txt';
    } catch (_) {
      return 'glass_frame_timing.txt';
    }
  }
}

/// task-86：**两臂触发与场景断言**（状态机全在这里；`view.dart` 只留 1 import + 2 行脉冲）。
///
/// `view.dart` 里就这两处（Lead 已批"2 行 + 1 import"）：
/// * `_GlassControlBar.build` **最顶上**（必须在 `if (!widget.visible) return child;` **之前**，
///   这样"控制条隐藏"也会被记到 ✓）：
///   `GlassFrameTimingDebug.pagePulse(controlsVisible: widget.visible);`
/// * 折射包裹那行的**门禁值透传**（与品红图内标记**同一个真值**，但不往 widget 树加东西）：
///   `if (GlassFrameTimingDebug.refractionGate(
///        LiquidGlassPolicy.useRefractionLayerFor(decision: decision))) {`
///
/// 规则（task-86 事前写死）：
/// * **控制条可见**时的第一次脉冲 ⇒ `start(window: 35 s)`；**3 s 无脉冲 ⇒ 自动 `stop()`**
///   （离开页面即收窗口 ✓）；
/// * **一个进程只允许一个窗口** ⇒ "单臂内不重启、不混窗口"是**结构性保证**（META 里
///   `window_id=1 single_window=true` ✓）；
/// * **臂判定**：窗口内**门禁为真（= 折射层挂过）⇒ 臂 A（refraction）**；**始终为假 ⇒ 臂 B（solid）**；
/// * **场景断言**：臂 A = 折射门禁**当前仍为真** ∧ 控制条可见；臂 B = 门禁始终为假 ∧ 控制条可见；
///   都不满足 ⇒ `scenario=fail` ⇒ 分析器标 **"未归属"** ✓。
class GlassFrameTimingDebug {
  GlassFrameTimingDebug._();

  /// "常显控制条"是否生效（`view.dart` 的 `_onControlChanged` 用它决定是否复位隐藏）。
  static bool get keepControls => glassKeepControlsEnabled;

  /// 窗口时长（≥30 s，task-86 建议 35 s）。
  static const Duration window = Duration(seconds: 35);

  /// "离开页面"兜底阈值：**窗口的正主是上面的 35 s 定时器** ✓。
  /// task-86 实测教训（两次）：控制条可见但**不重建**的间隔可以很长（>20 s）✗ ⇒
  /// 任何"按脉冲间隔收窗口"的阈值都会把 35 s 窗口提前砍掉（7 s / 24 s 都撞过 ✗✗）。
  /// **task-92 改回 12 s**：本轮把"页面上下文"当逐帧判据 ✓ ⇒ 必须能在**离开页面**时收窗 ✓，
  /// 同时 12 s 远大于实测的重建间隔（1~5 s ✓）⇒ 不会误砍 ✓。
  static const int _stallMs = 12000;

  /// "上下文成立"的新鲜度：控制条心跳至今 ≤10 s ⇒ 认为**仍在播放器页** ✓
  /// （task-92 口径 ✓：逐帧锁 = "上下文成立"，而不是"控制条可见" ✗ —— 本轮故意 hide/show，
  ///  可见比例必然 <0.95 ✗，用它当逐帧判据会每窗未归属 ✗）。
  static const int _contextFreshMs = 10000;

  static final Stopwatch _clock = Stopwatch()..start();
  static Timer? _ticker;
  static bool _started = false;
  static bool _windowUsedUp = false;
  static int _lastPulseMs = 0;
  static bool _refractionSeen = false;
  /// task-92：**窗口内"换档淡入"发生次数**（窗口级机制断言 ✓）。
  static int _fadeInWindow = 0;
  /// 需要的淡入次数（编译期常量 ⇒ 每轮由 `--dart-define` 指定 ✓）。
  static const int _requiredFades = _kGlassRequiredFades;
  /// 统计用：可见帧数 / 总帧数由 hook 的 probe 记账 ⇒ 这里只累计"可见心跳"次数。
  static int _pulseVisible = 0;
  static int _pulseTotal = 0;

  static int _nowMs() => _clock.elapsedMilliseconds;

  /// 控制条 build 顶部调用（**隐藏态也要调用** ⇒ 放在早返回之前）。
  static void pagePulse({required bool controlsVisible}) {
    if (!glassFrameTimingEnabled) {
      return;
    }
    _pulseTotal++;
    if (controlsVisible) {
      _pulseVisible++;
    }
    // 起窗条件：**控制条可见**（淡入只发生在"重新可见"时 ✓）——「上下文」由 probe 负责 ✓
    _pulse(startIfIdle: controlsVisible);
  }

  /// task-92：**淡入触发点**（`view.dart` 的 `didUpdateWidget` 里 `!old && new` 时调用 ✓）。
  ///
  /// 它既是**窗口级机制断言的计数源** ✓，也证明"此刻控制条刚重新可见" ⇒ 可以起窗 ✓。
  static void noteFadeIn() {
    if (!glassFrameTimingEnabled) {
      return;
    }
    _pulse(startIfIdle: true);
    _fadeInWindow++;
    debugPrint('[FT] fade-in #$_fadeInWindow');
  }

  /// 折射门禁值透传（**原样返回入参**，只做记录）——与品红图内标记同一个真值。
  static bool refractionGate(bool value) {
    if (!glassFrameTimingEnabled) {
      return value;
    }
    if (value) {
      _refractionSeen = true;
    }
    _pulse(startIfIdle: value);
    return value;
  }

  static void _pulse({required bool startIfIdle}) {
    try {
      _lastPulseMs = _nowMs();
      if (_started || _windowUsedUp || !startIfIdle) {
        return;
      }
      _started = true;
      _windowUsedUp = true;
      _refractionSeen = false;
      _fadeInWindow = 0;
      _pulseVisible = 0;
      _pulseTotal = 0;
      GlassFrameTiming.instance.start(
        window: window,
        scenarioProbe: _scenarioOk,
        label: 'unknown',
        // task-92：**机制断言在窗口级** —— "换档淡入 ≥4 次"才算场景成立 ✓
        requireFades: _requiredFades,
        note: 'refresh_hz=144 (dumpsys display mActiveModeId=2 '
            'fps=144.00002; 备选 60/120/144) '
            'context=bar-heartbeat<=10s stall_stop=12s',
      );
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      debugPrint('[FT] state machine armed（window=${window.inSeconds}s '
          'requireFades=$_requiredFades）');
    } catch (e) {
      debugPrint('[FT] state machine 异常（不影响页面）：$e');
    }
  }

  static void _tick() {
    try {
      if (!_started) {
        return;
      }
      GlassFrameTiming.instance
        ..setLabel(_refractionSeen ? 'refraction' : 'solid')
        ..setFades(_fadeInWindow, _requiredFades)
        ..setControlsVisibleStat(_pulseVisible, _pulseTotal);
      if (_nowMs() - _lastPulseMs > _stallMs) {
        _started = false;
        _ticker?.cancel();
        _ticker = null;
        unawaited(GlassFrameTiming.instance.stop());
      }
    } catch (_) {
      // 抢占失败不能影响被测页面
    }
  }

  /// **逐帧判据 = "上下文成立"**（task-92 口径 ✓）：控制条心跳至今 ≤10 s ⇒ 仍在播放器页 ✓。
  /// ⚠ 本轮的逐帧锁**不是**"控制条可见" ✗（故意 hide/show ⇒ 可见比例 <0.95 ✗）；
  /// "机制真的发生"由**窗口级** `fades ≥ 4` 负责 ✓（两把锁缺一不可 ✓）。
  static bool _scenarioOk() {
    try {
      return (_nowMs() - _lastPulseMs) <= _contextFreshMs;
    } catch (_) {
      return false;
    }
  }
}

/// task-92 的窗口级机制断言参数（编译期）：`--dart-define=GLASS_REQUIRE_FADES=4` ✓
/// （默认 0 = 不强制淡入次数 ⇒ task-86/87/90 那些轮次不受影响 ✓）。
const int _kGlassRequiredFades =
    int.fromEnvironment('GLASS_REQUIRE_FADES', defaultValue: 0);