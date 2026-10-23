/// 视频外部纹理尺寸规则（排期 #13 实施 · task-8）
///
/// ## 它修的是什么（实测缺陷，不是备忘）
/// app 目前**不请求纹理尺寸**——`VideoControllerConfiguration` 不带 `width/height`，
/// media_kit 于是用**源的原生解码尺寸**。实测（`docs/性能压测.md` §9.5.6，交替顺序
/// `-Order alternate -Runs 2`、100% 前台、产物数量断言通过）发现：
///
/// | 源 | 请求纹理 | mpv 是否缩放 | 纯色 P99 | 纯色吞吐 | 判定 |
/// |---|---|---|---|---|---|
/// | 720p | 1280×720（=源） | 否 | **9.52 / 10.59 ms** | **313.0 / 308.1** | **坏**（两独立会话复现） |
/// | 720p | 640×360 | 是（缩） | 6.43 / 6.45 | 322.5 / 323.4 | 干净 |
/// | 720p | **1920×1080** | 是（放） | **6.47** | **321.2** | **干净**（本规则的目标值） |
/// | 1080p | 1280×720 | 是（缩） | 6.33 | 321.9 | 干净 |
/// | 1080p | 1920×1080（=源） | 否 | 6.08 / 6.26 | 321.5 / 321.2 | 干净 |
///
/// 即：**"720p 解码结果原样进 720p 外部纹理"这一格坏**，其余实测格都干净——而且**连纯色档
/// 都变差**（视频层自己的问题，与玻璃无关）。分辨实验（`run7c`：1080p 源 → 1280×720 纹理）
/// 落回干净组，因此排除了"1280×720 这个值本身坏"。
///
/// ## 规则为什么必须是"运行期 + Windows 专属 + 只修这一格"
/// 两条代码事实（Lead 2026-10-02 指出，已逐条核实）：
///
/// 1. **构造期拿不到源尺寸**：`controller.dart` 的顺序是 `Player.create()` →
///    `VideoController.create(player, configuration: ...)` → **之后**才 `open(media)`，
///    源尺寸只有 open 之后才存在 ⇒ **无法**在 `VideoControllerConfiguration` 里"先读源尺寸再决定"。
/// 2. **`setSize` 在 Android 会抛**：`android_video_controller/real.dart` 里
///    `setSize` 直接 `throw UnsupportedError('[AndroidVideoController.setSize] is not available on Android')`。
///    桌面有真实现：`native_video_controller/real.dart:128`（**尺寸不变时 no-op**，传 `null` = 回原生尺寸）。
///    ⇒ 本文件**只在 Windows 生效**，其它平台只记日志、绝不调用 `setSize`。
///
/// 另外一条同样重要的事实（决定了"不要改成构造期按显示区派生尺寸"）：
/// **Android 的 `create()` 只发 `{'handle': …}` 给 `VideoOutputManager.Create`，
/// `configuration.width/height` 从未被读取** ⇒ 构造期派生在 Android 上**零效果**，
/// 在桌面上却是"对所有视频、所有显示尺寸"的全面改动，而请求值在非 1080p 显示器上**没有测量**。
/// 所以本文件**不做**显示区派生；若将来 task-10 的真机复测在 Android 或别的显示尺寸上
/// 测出同类陷阱，再带着证据切到"按显示区派生 + 陷阱值守卫"的形态。
///
/// ## 与观感的关系
/// 本规则**只改纹理尺寸，不改任何玻璃档位/token/几何**（Lead 要求 #3）。副作用只有"视频层清晰度"：
/// 720p 源放进 1920×1080 纹理＝由 mpv 放大一次再上屏，与"请求原生 720p 后由合成器放大上屏"
/// 相比画面不会更糊（放大发生在前端，且实测该路径更快）；真机上若观察到差异需如实上报。
library;

import 'dart:io' show Platform;

import 'package:PiliPlus/utils/liquid_glass_policy.dart';

/// 请求的视频纹理尺寸。
typedef VideoTextureRequest = ({int width, int height});

/// 规则的运行模式（复测/真机验证用；生产为 [TextureFixMode.auto]）。
///
/// 可由环境变量 `GLASS_TEXTURE_FIX` 设定，**不必改代码/重新构建**即可 A/B：
/// * `auto`（默认）：只对"源==1280×720"这一格生效；
/// * `off`：完全不改（= 修复前行为，用于对照臂）；
/// * `force`：**不论源尺寸**都请求 [VideoTextureSizePolicy.avoidTargetWidth]×[…Height]
///   —— 用于在**真实播放路径**上验证"请求→被接受"这条链路（否则得先找到 720p 片源）。
enum TextureFixMode {
  /// 只修已测的那一格。
  auto,

  /// 关闭（对照臂）。
  off,

  /// 强制请求目标尺寸（验证链路与做 A/B 用）。
  force,
}

/// 实测的"坏格"对应关系与运行时规避。
abstract final class VideoTextureSizePolicy {
  const VideoTextureSizePolicy._();

  /// 运行模式（可用环境变量 `GLASS_TEXTURE_FIX=auto|off|force` 覆盖）。
  static TextureFixMode mode = _modeFromEnv();

  /// 调试/验证用：覆盖"要请求的目标尺寸"（环境变量 `GLASS_TEXTURE_TARGET=WxH`）。
  ///
  /// 为什么需要它（task-8 实测教训）：**证明"原生接受了请求"必须让请求值 ≠ 源解码尺寸**。
  /// 源正好是 1920×1080 时，`requested=1920x1080` 与 `applied=1920x1080`（`rect` 读回）
  /// 在"被接受"和"被拒绝"两种情况下**长得一模一样**，属于"不可判别的实验"
  /// （当时视频源恰是 1080p，白跑一轮）。有了这个开关，验证时把目标设成**任何与源不同的值**
  /// （例如 `GLASS_TEXTURE_TARGET=1280x720`），`applied != source` 就同时证明了
  /// "请求发出"与"原生接受"。**只影响被请求的值，不改任何业务逻辑**；不设时用实测干净值。
  static ({int width, int height})? targetOverride = _targetFromEnv();

  static ({int width, int height})? _targetFromEnv() {
    try {
      final raw = Platform.environment['GLASS_TEXTURE_TARGET']?.trim().toLowerCase();
      if (raw == null || raw.isEmpty) return null;
      final p = raw.split('x');
      if (p.length != 2) return null;
      final w = int.tryParse(p[0].trim());
      final h = int.tryParse(p[1].trim());
      if (w == null || h == null || w <= 0 || h <= 0) return null;
      return (width: w, height: h);
    } catch (_) {
      return null;
    }
  }

  /// 实际使用的目标尺寸（[targetOverride] 优先，否则实测干净值）。
  static ({int width, int height}) get effectiveTarget =>
      targetOverride ?? (width: avoidTargetWidth, height: avoidTargetHeight);

  static TextureFixMode _modeFromEnv() {
    try {
      final raw = Platform.environment['GLASS_TEXTURE_FIX']?.trim().toLowerCase();
      return switch (raw) {
        'off' || '0' || 'false' => TextureFixMode.off,
        'force' || '1' || 'true' => TextureFixMode.force,
        _ => TextureFixMode.auto,
      };
    } catch (_) {
      return TextureFixMode.auto;
    }
  }

  /// 陷阱格（720p 源）。
  static const int trapSourceWidth = 1280;
  static const int trapSourceHeight = 720;

  /// 命中陷阱时改用的目标尺寸。
  ///
  /// 为什么是 **1920×1080** 而不是"按显示区物理尺寸算"：只有 1920×1080 与 640×360 这两格
  /// 是**实测干净**的（见文件头表格）；按显示区算出来的值（如 1898×1024）**没有测量**，
  /// 而 1920×1080 既不降清晰度、又在干净组里 ⇒ 用已测过的值，不引入新变量。
  /// （它还有个便宜的好处：1080p 源本来就是这个尺寸，对 1080p 源等价于"维持原生"。）
  static const int avoidTargetWidth = 1920;
  static const int avoidTargetHeight = 1080;

  /// 本平台是否允许运行时改纹理尺寸。
  ///
  /// 只有 Windows：实测证据来自 **Windows + Skia + 桌面 D3D11/ANGLE** 这条路径
  /// （`docs/性能压测.md` §9.7 第 9 条边界），而且 Android 的 `setSize` 会抛（见文件头）。
  static bool get applicable => Platform.operatingSystem == 'windows';

  /// 是否需要打印日志（跟随 [LiquidGlassPolicy.verbose]）。
  static bool get verbose => LiquidGlassPolicy.verbose;

  /// 决策：给定**源解码尺寸**，返回要请求的纹理尺寸；`null` = 保持原生（media_kit 默认）。
  ///
  /// 调用方约定：**只有在 [applicable] 为真时才真的调用 `setSize`**；
  /// 本方法在任何平台都会记一行日志（真机验证靠它）。
  ///
  /// [platformOverride] 仅用于单测；生产传 null，内部用 `Platform.operatingSystem`。
  static VideoTextureRequest? requestForSource({
    required int sourceWidth,
    required int sourceHeight,
    String? platformOverride,
  }) {
    final platform = platformOverride ?? Platform.operatingSystem;

    if (platform != 'windows') {
      LiquidGlassPolicy.logTextureRequest(
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        requestedWidth: null,
        requestedHeight: null,
        trapAvoided: false,
        reason: '规则只在 windows 生效（证据仅覆盖 Skia+桌面 D3D11/ANGLE，且 Android setSize 会抛），'
            '本平台保持 native —— 若这里测出同类陷阱请回报',
      );
      return null;
    }

    switch (mode) {
      case TextureFixMode.off:
        LiquidGlassPolicy.logTextureRequest(
          sourceWidth: sourceWidth,
          sourceHeight: sourceHeight,
          requestedWidth: null,
          requestedHeight: null,
          trapAvoided: false,
          reason: 'GLASS_TEXTURE_FIX=off：关闭修复（对照臂），保持 native',
        );
        return null;
      case TextureFixMode.force:
        LiquidGlassPolicy.logTextureRequest(
          sourceWidth: sourceWidth,
          sourceHeight: sourceHeight,
          requestedWidth: effectiveTarget.width,
          requestedHeight: effectiveTarget.height,
          trapAvoided: true,
          reason: 'GLASS_TEXTURE_FIX=force：不论源尺寸都请求目标值（验证"请求→被接受"链路 / A-B 用）'
              '${targetOverride == null ? '' : '（GLASS_TEXTURE_TARGET 覆盖生效）'}',
        );
        return effectiveTarget;
      case TextureFixMode.auto:
        break;
    }

    final isTrapSource =
        sourceWidth == trapSourceWidth && sourceHeight == trapSourceHeight;
    if (!isTrapSource) {
      // 其余尺寸保持原生：1080p 原生已实测干净；**其它尺寸无证据**，故不动、只记日志。
      LiquidGlassPolicy.logTextureRequest(
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        requestedWidth: null,
        requestedHeight: null,
        trapAvoided: false,
        reason: sourceHeight == 1080
            ? '源非 720p：1080p 原生尺寸已实测干净，保持 native'
            : '源非 720p 且该尺寸无实测证据，保持 native（不引入未测变量）',
      );
      return null;
    }

    LiquidGlassPolicy.logTextureRequest(
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      requestedWidth: effectiveTarget.width,
      requestedHeight: effectiveTarget.height,
      trapAvoided: true,
      reason: '命中「720p 源 + 原生纹理」陷阱（实测纯色 P99 9.52/10.59ms、吞吐 308~313，'
          '对照组 6.08~6.47ms / 320.9~323.4）⇒ 请求 ${effectiveTarget.width}x${effectiveTarget.height}'
          '（实测干净格）',
    );
    return effectiveTarget;
  }
}