/// 玻璃"守门规则"（排期 #13 实施 · task-8）
///
/// ## 这份文件解决什么
/// 播放器控制条上的玻璃是 BackdropFilter，**每帧要重采样视频外部纹理**。实测结论
/// （`docs/性能压测.md` §9，全部为交替顺序 `-Order alternate -Runs 2`、100% 前台）：
///
/// * 额外成本**不在中位**：玻璃−纯色的帧间隔中位差只有 **+0.06~+0.21 ms**（各分辨率格）；
/// * 成本在**尾部与吞吐**：纹理 ≥720p 时 **P99 +3.95~+4.72 ms、聚合吞吐 −4.5%~−7.9%**；
///   640×360 纹理时**测不出**（ΔP99 −0.29 ms、Δ吞吐 −0.1%，两独立会话复现）。
///
/// ## 为什么是"守门规则"而不是"性能策略"
/// 上面那些 P99 数字**是在稳态播放窗口里测出来的**（采样期间没有 seek / 滚动）。
/// 所以"只在 seek / 拖进度这些快变时刻退档"**清不掉稳态尾部** —— 退档能回收的上限
/// ≈ `退档时间占比 f × 端点差值`，f=5% 时只有 0.2 ms 级、低于本框架的会话重复性。
/// 结论（已与 Lead 裁决）：**本文件不宣称省帧**，它的价值是**防回归**：
///   1. 控制条不可见时**彻底不挂层**（BackdropFilter 的纪律，问题台账 §4）；
///   2. 玻璃只允许在"**安全时机**"上挂——按实测，唯一安全的是**暂停/静止**；
///   3. **可见期间不换档**：像素证据（§9.4）显示同一帧下玻璃档与纯色档的控制条区域
///      有 46.1% 的像素 `|d|>8`（mean|d|=6.50），而视频区 0.00% ⇒ **热切换是可见跳变**。
///      因此本策略只在"控制条变为可见"的那一刻定格一次档位，可见期间保持不变
///      （"退档不闪"是**由构造保证**的，不是靠过渡动画）。
///
/// ## 复测开关
/// 一行强制某档（`docs/性能压测.md` §9 的三组口径：全玻璃 / 全纯色 / 按 f 折算）：
/// ```dart
/// LiquidGlassPolicy.force = GlassPolicyForce.glass; // = 策略前
/// LiquidGlassPolicy.force = GlassPolicyForce.solid; // = 策略后（守门默认）
/// ```
/// 也可以**不改代码**、用环境变量强制（便于 A/B 复测时两个进程跑同一份产物）：
/// `GLASS_POLICY=auto|glass|solid`。
library;

import 'dart:io' show Directory, File, FileMode, Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:PiliPlus/utils/glass_accessibility.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

/// 强制档位（仅供 A/B 复测；生产走 [GlassPolicyForce.auto]）。
enum GlassPolicyForce {
  /// 跟随策略表。
  auto,

  /// 一律按玻璃档（= "策略前" 那一组）。
  glass,

  /// 一律按纯色档（= "策略后" 那一组）。
  solid,

  /// **实验臂（task-81 ✓，仅非 release 构建识别）**：一律按**真折射档** ✓。
  ///
  /// 为什么需要它："真折射 vs FakeGlass"的两臂对照要求**播放中也有玻璃** ✓，
  /// 而策略表在播放中给 `solid` ✗ ⇒ 没有这个档位就没法把两臂放进**同一可测场景** ✓
  /// （"有帧流动 vs 有玻璃"互斥，见 `docs/Android-Impeller验证.md` §12.2 ✓）。
  ///
  /// ⚠ **只是测量杠杆** ✗：**不改出厂默认**（默认仍是"暂停态折射 / 播放态 solid" ✓）。
  refraction,
}

/// 控制条"变为可见"那一刻所处的场景。
///
/// 注意：这些场景只用来在**挂载瞬间**选档，不用来做运行期热切换（见文件头）。
enum GlassBarContext {
  /// 暂停 / 无播放 / 静止：**唯一的"安全时机"**。
  pausedIdle,

  /// 播放中（稳态）。实测的 P99/吞吐代价就发生在这一态 ⇒ 默认给纯色。
  playingSteady,

  /// 正在 seek / 拖动进度。
  seeking,

  /// 全屏切换、旋转、窗口尺寸变化等布局过渡中。
  layoutTransient,
}

/// 一次挂载决策的结果（带依据，便于日志与真机核对）。
@immutable
class LiquidGlassDecision {
  const LiquidGlassDecision({
    required this.tier,
    required this.context,
    required this.reason,
  });

  /// 要用的档位（solid 即"不采背景"）。
  final LiquidGlassTier tier;

  /// 决策时观察到的场景。
  final GlassBarContext context;

  /// 人话依据（进日志）。
  final String reason;

  /// 是否真的会上 BackdropFilter（glass 档的本意就是采样背景）。
  bool get samplesBackdrop => tier != LiquidGlassTier.solid;

  @override
  String toString() =>
      'GlassDecision(tier=${tier.name}, context=${context.name}, reason=$reason)';
}

/// 播放器控制条玻璃的"守门规则"。纯逻辑 + 静态状态，便于单测与 A/B 复测。
abstract final class LiquidGlassPolicy {
  /// 一行强制开关（复测用）。生产恒为 [GlassPolicyForce.auto]。
  ///
  /// 初值可由环境变量 `GLASS_POLICY` 设定，这样复测时**不必改代码**：
  /// 同一份构建产物、两个进程分别以 `GLASS_POLICY=glass` / `GLASS_POLICY=solid` 启动即可。
  static GlassPolicyForce force = _forceFromEnv();

  /// 是否打印决策与纹理尺寸日志（真机验证时打开；见 [logTextureRequest]）。
  ///
  /// **默认 = 非 release**（2026-10-04 bug 扫描修复，原默认恒 true ✗）：
  /// `logDecision` 在控制条可见期**每次 build** 都被调用（pl_player view.dart、
  /// live header_control.dart），`logEvent` 每次 pointer 起落都调 —— 原默认让
  /// **release 用户机**也持续同步写盘（`flush:true`）且证据文件无上限增长 ✗。
  /// 取证工作流全部跑 debug/profile 构建（§103 的 `!kReleaseMode` 门控同源 ✓），
  /// 因此 debug/profile 行为逐项不变 ✓，release 归零 ✓。复测需要时仍可运行时置 true。
  static bool verbose = !kReleaseMode;

  static GlassPolicyForce _forceFromEnv() {
    try {
      final fromEnv = _parseForce(Platform.environment['GLASS_POLICY']);
      if (fromEnv != GlassPolicyForce.auto) return fromEnv;
      // task-81：**设备上不改包也能切臂** ✓ —— Android 无法给 app 注入环境变量 ✗，
      // 所以**非 release** 构建额外读一个文件（`adb shell "echo glass > /data/local/tmp/glass_policy.txt"` ✓）。
      // **如何关掉**：删掉 `/data/local/tmp/glass_policy.txt` ✓（或移除本段 ✓）⇒ 立刻回到 `auto` ✓。
      // **release 构建完全不读** ✓（`kReleaseMode` 门控 ⇒ 出厂路径零影响 ✓，`test/own` 全绿 ✓）。
      if (!kReleaseMode) {
        final f = File('/data/local/tmp/glass_policy.txt');
        if (f.existsSync()) {
          final fromFile = _parseForce(f.readAsStringSync());
          if (fromFile != GlassPolicyForce.auto) return fromFile;
        }
      }
    } catch (_) {
      // 取不到环境（单测/沙箱）时按 auto 走
    }
    return GlassPolicyForce.auto;
  }

  /// `GLASS_POLICY=auto|glass|solid|refraction` —— **`refraction` 只在非 release 生效** ✓。
  static GlassPolicyForce _parseForce(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'glass' => GlassPolicyForce.glass,
        'solid' => GlassPolicyForce.solid,
        'refraction' =>
          kReleaseMode ? GlassPolicyForce.auto : GlassPolicyForce.refraction,
        _ => GlassPolicyForce.auto,
      };

  /// **挂载瞬间**的决策。调用方必须保证：可见期间只调一次（见文件头"可见期间不换档"）。
  ///
  /// 策略表（每一行都对应 `docs/性能压测.md` §9 的实测，不是拍的）：
  ///
  /// | 场景 | 档位 | 依据 |
  /// |---|---|---|
  /// | 暂停 / 静止 | **glass** | 唯一"安全时机"：此时没有连续视频纹理更新，尾部代价无从发生 |
  /// | 播放中（稳态） | **solid** | 稳态正是 P99 +3.95~+4.72 ms / 吞吐 −4.5%~−7.9% 发生的窗口 |
  /// | seek / 拖进度 | **solid** | 快变时刻观感最不敏感，且此时流水线已在峰值，不宜再加采样 |
  /// | 全屏 / 布局过渡 | **solid** | 过渡中合成层数在变，避免叠加新的每帧采样 |
  static LiquidGlassDecision decideOnAttach(GlassBarContext context) {
    switch (force) {
      case GlassPolicyForce.glass:
        return LiquidGlassDecision(
          tier: LiquidGlassTier.fakeGlass,
          context: context,
          reason: '强制玻璃档（GlassPolicyForce.glass，复测"策略前"）',
        );
      case GlassPolicyForce.solid:
        return LiquidGlassDecision(
          tier: LiquidGlassTier.solid,
          context: context,
          reason: '强制纯色档（GlassPolicyForce.solid，复测"策略后"）',
        );
      case GlassPolicyForce.auto:
        break;
      // task-81 **实验臂**（仅非 release 能到达 ✓）：播放中也强制真折射档 ✓
      case GlassPolicyForce.refraction:
        return LiquidGlassDecision(
          tier: LiquidGlassTier.refraction,
          context: context,
          reason:
              '实验臂（task-81，非 release 才可能）：播放中也强制真折射档 ⇒ '
              '"真折射 vs FakeGlass"两臂对照用 ✗（不改出厂默认 ✗）',
        );
    }

    return switch (context) {
      GlassBarContext.pausedIdle => const LiquidGlassDecision(
        // R1（task-78）：安全时机**请求真折射档** ✓ —— 是否真能上由 kit 判定：
        // `effectiveTier` 只允许"策略 ≤ kit 运行时档位"，所以平台不支持折射时
        // 这里仍会拿到 fakeGlass ✓（策略没有资格把降档抬回去 ✓）。
        tier: LiquidGlassTier.refraction,
        context: GlassBarContext.pausedIdle,
        reason: '暂停/静止＝安全时机（无连续视频纹理更新）⇒ 请求真折射档',
      ),
      GlassBarContext.playingSteady => const LiquidGlassDecision(
        tier: LiquidGlassTier.solid,
        context: GlassBarContext.playingSteady,
        reason: '播放中（稳态）＝实测 P99 +3.95~+4.72ms / 吞吐 −4.5%~−7.9% 的窗口，守门给纯色',
      ),
      GlassBarContext.seeking => const LiquidGlassDecision(
        tier: LiquidGlassTier.solid,
        context: GlassBarContext.seeking,
        reason: 'seek/拖动中＝快变时刻，且流水线在峰值，不叠加采样',
      ),
      GlassBarContext.layoutTransient => const LiquidGlassDecision(
        tier: LiquidGlassTier.solid,
        context: GlassBarContext.layoutTransient,
        reason: '全屏/布局过渡中，合成层数在变，不叠加采样',
      ),
    };
  }

  /// 由播放器状态推导场景（把"判断逻辑"集中在策略文件里，接线点保持薄）。
  static GlassBarContext contextOf({
    required bool isPlaying,
    required bool isSeeking,
    required bool layoutTransient,
  }) {
    if (layoutTransient) return GlassBarContext.layoutTransient;
    if (isSeeking) return GlassBarContext.seeking;
    if (!isPlaying) return GlassBarContext.pausedIdle;
    return GlassBarContext.playingSteady;
  }

  /// 把策略决策与 kit 的**运行时档位**合成：**策略只能降档，不能升档**。
  ///
  /// 为什么必须这样：kit 的自动探测/黑名单是带**安全理由**的降档（例如无 offscreen MSAA 的
  /// D3D11/GLES2 路径上 BackdropFilter 行为异常，见问题台账 §3 #192918）；策略只是在
  /// "安全时机"上多降一档，**没有资格**把 kit 已经判死的档位抬回玻璃。
  /// 档位枚举从高到低排列（`refraction` < `fakeGlass` < `solid`），所以 index 越大越保守。
  static LiquidGlassTier effectiveTier(LiquidGlassTier policyTier) {
    final runtime = LiquidGlassRuntime.tier;
    final tier = policyTier.index >= runtime.index ? policyTier : runtime;
    // #18 无障碍（task-93）：**降低透明度 ⇒ 封顶到 solid**。
    // ⚠ 位置要求：必须在上面那次 capability 夹取**之后** ⇒ 只可能往下压、
    // **绝不可能抬档**（与 task-13 的守卫同序 ✓）；也不绕过 kit 的三闸门 ✗。
    return GlassAccessibility.capTier(tier);
  }

  /// R1（task-80）**局部 opt-in**：只让**播放器控制条**这一层在"能力允许"时开口用折射档 ✓，
  /// **不做全局升级** ✗（`main.dart` 不动 ✓；`LiquidGlassRuntime.tier` 是全局档位，
  /// 一旦注册 provider 会连带把首页等 `LiquidGlassSurface` 也升档 ⇒ 需单独验收 ⇒ 留 M2 ✓）。
  ///
  /// **门禁绝不绕过 capability** ✗✓，三条同时成立才放行：
  /// 1. 策略决策档位就是折射（= 暂停/静止这种**安全时机** ✓，见 `decideOnAttach`）；
  /// 2. **折射 shader 通道可用**（`ImageFilter.shader` 真支持 ✓）—— 不可用 ⇒ 回落既有路径 ✓；
  /// 3. kit 的**硬降档** `solid`（完全不玻璃）仍然优先 ✓（`LiquidGlassRuntime.glassEnabled` 同口径 ✓）。
  ///
  /// ⚠ **为什么不拿 `LiquidGlassRuntime.tier` 当门禁**：那是**全局**档位，而 app 侧至今没有注册
  /// `refractionShaderProvider`（M2 决策 ✓）⇒ 全局恒为 `fakeGlass` ⇒ 拿它做门禁会让本层
  /// **永远开不了口** ✗（task-79 的一行诊断实证：`runtime=fakeGlass` 而 `channel=true` ✓）。
  /// `LiquidGlassRefractionLayer` 自带资产与通道门（`liquid_glass_refraction_layer.dart` L103 ✓），
  /// **不依赖 provider** ✓。
  static bool useRefractionLayerFor({required LiquidGlassDecision decision}) =>
      decision.tier == LiquidGlassTier.refraction &&
      isRefractionShaderChannelAvailable &&
      LiquidGlassRuntime.glassEnabled &&
      // #18 无障碍（task-93）：**降低透明度**时折射层同样要退掉 ——
      // 折射层是最「透明」的那一档，只靠 effectiveTier 封顶会漏掉这条独立路径 ✗。
      !GlassAccessibility.reduceTransparency;

  /// 构造"把档位钉死"的 capability（与 kit 自动探测同口径，只是 tier 由策略指定）。
  ///
  /// 用途：`LiquidGlassSurface` 默认取 `LiquidGlassRuntime.tier`（全局自动探测），
  /// 而守门规则要求**只对播放器控制条这一块表面**用指定档位，且不能动全局档位
  /// （那会连带影响首页等其它玻璃）。
  static LiquidGlassCapability forcedCapability({
    required LiquidGlassTier tier,
    required String reason,
  }) => LiquidGlassCapability(
    tier: tier,
    platform: Platform.operatingSystem,
    osVersion: Platform.operatingSystemVersion,
    shaderFilterSupported: ui.ImageFilter.isShaderFilterSupported,
    reason: reason,
    forced: true,
  );

  /// 决策日志（受 [verbose] 控制）。
  ///
  /// [surface] 标注**是哪块表面**做的决策（`top` / `bottom` / 以后可能的其它控制条）。
  /// 为什么必须有（task-36）：顶栏与底栏走同一张策略表、同一份输入，两行日志**文本完全相同**，
  /// 只靠"每个周期 2 条且一致"来推断；带上归属后可以**逐表面复核**（例如过渡瞬间
  /// `surface=top` 与 `surface=bottom` 是否同 context 同 tier）。
  static void logDecision(
    LiquidGlassDecision decision, {
    required bool visible,
    required String surface,
  }) {
    if (!verbose) return;
    _emit(
      '[LiquidGlassPolicy] control-bar surface=$surface visible=$visible '
      'tier=${decision.tier.name} context=${decision.context.name} '
      'samplesBackdrop=${decision.samplesBackdrop} — ${decision.reason}',
    );
  }

  /// 视频纹理尺寸请求日志（**真机验证判据**：perf-harness 的 task-10 靠这行核对
  /// "修复前命中 720p 陷阱 / 修复后避开"；见 [VideoTextureSizePolicy]）。
  static void logTextureRequest({
    required int sourceWidth,
    required int sourceHeight,
    int? requestedWidth,
    int? requestedHeight,
    required bool trapAvoided,
    required String reason,
  }) {
    if (!verbose) return;
    _emit(
      '[LiquidGlassPolicy] video texture requested='
      '${requestedWidth == null ? 'native' : '${requestedWidth}x$requestedHeight'} '
      'source=${sourceWidth}x$sourceHeight '
      'trapAvoided=$trapAvoided — $reason',
    );
  }

  /// **事件**日志：记录"策略**输入**的变化"等非决策事件，与决策日志走**同一个证据文件**。
  ///
  /// 为什么需要它（task-36 收口）：全屏过渡标志的变化原来只走 `debugPrint`（app 控制台），
  /// 而证据文件只由 [logDecision] / [logTextureRequest] / [logTextureApplied] 写 ⇒ 抓取端
  /// 按证据文件判定时会得出"该事件一次都没发生"的**错误结论**（E1 的 0 条就是这个通道缺口，
  /// 不是代码没走到）。语义上"策略**输入**的变化"与"策略**决策**"本来就该在同一份证据里。
  ///
  /// 走 [_emit] ⇒ **双通道**：app 控制台 + `evidenceFile()`（见 [evidenceFile]）。
  static void logEvent(String message) {
    if (!verbose) return;
    _emit('[LiquidGlassPolicy] $message');
  }

  /// 纹理尺寸的**读回**日志（`controller.rect` 由原生侧回填）。
  ///
  /// 这一行是"修复**被接受**"的证据，而不是"我们调了一次 API"：
  /// `setSize` 之后原生会重建纹理并把新尺寸回填到 `VideoController.rect`，
  /// media_kit_video 自己的 `SimpleVideo` 也是靠监听 `rect`/`id` 跟随重建的
  /// （`simple_video_texture.dart` 里 `Listenable.merge([ctr.id, ctr.rect])`）。
  /// 若某平台上这行始终不出现或值没变，就说明"只发生了调用、未被接受"——如实标注。
  static void logTextureApplied({
    required int sourceWidth,
    required int sourceHeight,
    required int appliedWidth,
    required int appliedHeight,
  }) {
    if (!verbose) return;
    _emit(
      '[LiquidGlassPolicy] video texture applied=${appliedWidth}x$appliedHeight '
      'source=${sourceWidth}x$sourceHeight (rect read-back)',
    );
  }

  /// 证据通道：`debugPrint`（Android→logcat / 桌面→stdout）**加上**一个落盘文件。
  ///
  /// 为什么需要落盘：桌面下把 stdout 重定向到文件时是**全缓冲**的，进程被强杀就丢掉证据
  /// （task-8 实测：app 跑了两分钟、视频都在放，日志文件却停在 12 KB 不动，`CloseMainWindow`
  /// 也不保证 flush）。而 task-10 的真机验证同样需要一个**不依赖抓取时机**的通道：
  /// Android 上 `Directory.systemTemp` 位于应用私有 cache 目录，用项目既有的
  /// `adb shell run-as <pkg> cat <cache>/liquid_glass_policy_evidence.log` 即可读取。
  ///
  /// 开销：`verbose` 打开时每条日志一行 debugPrint + 一行同步落盘。**注意实际调用
  /// 频率不是"低频"**：logDecision 在控制条可见期每 build 一次、logEvent 每 pointer
  /// 起落一次（2026-10-04 bug 扫描确认 ✗✓）——因此 verbose 只允许在 debug/profile
  /// 取证轮打开（默认即如此 ✓），release 恒关 ✓；文件不轮转，取证轮结束自行清理。
  /// 关闭方式：`LiquidGlassPolicy.verbose = false`。
  static void _emit(String line) {
    debugPrint(line);
    try {
      evidenceFile().writeAsStringSync(
        '${DateTime.now().toIso8601String()} $line\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // 取证文件写不进去（只读文件系统/权限）时绝不影响业务
    }
  }

  /// 证据文件（`verbose` 打开时才会有内容）。
  static File evidenceFile() => File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}liquid_glass_policy_evidence.log',
  );
}
