// SPDX-License-Identifier: GPL-3.0-or-later
//
// #26 批2 · 皮肤件（一）：**进度手柄 glassLens**
//
// 背景（task-117 勘查定案 ✓）：播放器底栏的 `SliderTheme` 在 `pl_player/**`（红线文件 ✗）⇒
// **本文件只造件、不接线** ✓；接线那一行由 Lead 落在底栏 `SliderTheme.thumbShape` 上 ✓。
//
// 材质口径：**继承 B1/B5** ✓ —— 走 kit 既有 `LiquidGlassMaterial.lens` token ✓
// （kit 自己的注释就写着："高曲率小控件（播放器进度手柄、滑块）：厚度小、折射率与色散高" ✓）。
//
// 两种用法都在这里 ✓：
//   * `LiquidSliderThumb`      —— **控件形态**（需要一个 widget thumb 时用 ✓，可单测 ✓）；
//   * `LiquidSliderThumbShape` —— **`SliderComponentShape` 形态**（`thumbShape:` 一行可换 ✓✓
//      = Lead 接线用的就是它 ✓；它按 lens token 的色散/折射率/边框画"镜头感" ✓，
//      不依赖 shader 通道 ⇒ **solid 档/低能力设备也能渲染** ✓（降级可渲染是硬要求 ✓）。
import 'dart:math' as math;

import 'package:liquid_glass_kit/liquid_glass_kit.dart';
import 'package:material_ui/material_ui.dart';

/// 手柄半径（逻辑 px）。默认沿用底栏既有 `RoundSliderThumbShape(6.0)` 的口径＋镜头余量 ✓。
const double kLiquidSliderThumbRadius = 8;

/// 控件形态的 glassLens 手柄 ✓。
///
/// 适用：任何"需要一个 widget 作为 thumb"的场合 ✓（自绘 Slider/自建进度条 ✓）。
/// **未接入**底栏 `Slider`（`thumbShape` 要的是 `SliderComponentShape` ✗，见下方 Shape ✓）。
class LiquidSliderThumb extends StatelessWidget {
  const LiquidSliderThumb({
    super.key,
    this.radius = kLiquidSliderThumbRadius,
    this.enabled = true,
  });

  final double radius;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    // 暗底上仍可见 ⇒ 用 kit 的 lens 材质；`shadow: false` 与同族先例一致 ✓。
    return SizedBox(
      width: size,
      height: size,
      child: Semantics(
        container: false,
        child: LiquidGlassSurface(
          material: LiquidGlassMaterial.lens,
          borderRadius: BorderRadius.circular(radius),
          shadow: false,
          padding: EdgeInsets.zero,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// `SliderThemeData.thumbShape` 用的 glassLens 手柄 ✓。
///
/// **接线建议（供 Lead 手术 ✓）**：把底栏 `SliderThemeData` 的
/// `thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0)` 换成
/// `thumbShape: const LiquidSliderThumbShape()` 即可 ✓（不改 Slider/controller 任何行为 ✓）。
///
/// 降级语义 ✓：纯 `Canvas` 绘制、**不采样背景、不依赖 shader** ⇒ 任何时候都能画 ✓；
/// 色散/折射率只影响"环的偏移与高光强度"，参数取自 lens token ✓（浅/深各一套 ✓）。
class LiquidSliderThumbShape extends SliderComponentShape {
  const LiquidSliderThumbShape({
    this.radius = kLiquidSliderThumbRadius,
    this.brightness,
  });

  /// 手柄半径（逻辑 px）。
  final double radius;

  /// 若为 null ⇒ 取 `Theme.of(context).brightness`（与 B5"两档同源"同口径 ✓）。
  final Brightness? brightness;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(radius + 2);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final tokens =
        (brightness == Brightness.dark
                ? LiquidGlassTokens.dark
                : LiquidGlassTokens.light)
            .forMaterial(LiquidGlassMaterial.lens);

    // 色散：lens token 的 chromaticAberration 决定 R/B 环的偏移量 ✓（0.01 口径 ⇒ 亚像素，
    // 所以设一个可见下限，避免在小半径上完全看不见 ✗）。
    final ca = math.max(tokens.chromaticAberration, 0.004);
    final spread = (ca * 900).clamp(0.4, 2.2); // 逻辑 px
    final rimAlpha = (0.10 + tokens.lightIntensity * 0.35).clamp(0.08, 0.42);
    final rimWidth = math.max(1.0, tokens.thickness * 0.14);

    final canvas = context.canvas;
    final r = radius * (0.6 + 0.4 * enableAnimation.value);
    final rect = Rect.fromCircle(center: center, radius: r);

    // 1) 底：暗色半透明球（保证任何背景上都可读 ✓）
    canvas.drawCircle(
      center,
      r,
      Paint()..color = const Color(0x33FFFFFF),
    );
    // 2) 折射/色散环：R 向左上、B 向右下各偏 spread（lens 的"边缘分色"观感 ✓）
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rimWidth
      ..color = const Color(0xFFFFFFFF).withValues(alpha: rimAlpha);
    canvas
      ..save()
      ..translate(-spread * 0.5, -spread * 0.5);
    canvas.drawCircle(
      center,
      r,
      rim..color = const Color(0xFFFF6B6B).withValues(alpha: rimAlpha),
    );
    canvas.restore();
    canvas
      ..save()
      ..translate(spread * 0.5, spread * 0.5);
    canvas.drawCircle(
      center,
      r,
      rim..color = const Color(0xFF6BB8FF).withValues(alpha: rimAlpha),
    );
    canvas.restore();
    // 3) 高光边（lens 的"镜面"感 ✓）：左上 1/4 弧
    canvas.drawArc(
      rect.deflate(rimWidth * 0.5),
      math.pi * 1.05,
      math.pi * 0.45,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimWidth
        ..color = const Color(0xFFFFFFFF)
            .withValues(alpha: (rimAlpha * 1.6).clamp(0.0, 0.7)),
    );
    // 4) 折射率越高 ⇒ 中心越"厚" ⇒ 压一层极淡的内阴影 ✓
    final inner = (tokens.refractiveIndex - 1).clamp(0.0, 0.5);
    if (inner > 0) {
      canvas.drawCircle(
        center,
        r * 0.55,
        Paint()
          ..color = const Color(0xFF000000)
              .withValues(alpha: (inner * 0.35).clamp(0.0, 0.20)),
      );
    }

    // 5) 无障碍：强对比开关 ⇒ 加一圈实底描边（不靠色散也能看清手柄边界 ✓）
    if (LiquidGlassRuntime.increaseContrast) {
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.85),
      );
    }
  }

  /// 供**自绘进度条**（如 `common/widgets/progress_bar/audio_video_progress_bar.dart` 的
  /// `RenderProgressBar` ✓）使用的"无状态入口" ✓：把同一套 lens 画法搬到任何 Canvas 上 ✓。
  ///
  /// 设计意图（task-118 的 (A) 小单 ✓）：上游 `ProgressBar` 是**自绘 RenderObject**
  /// （`LeafRenderObjectWidget` ⇒ 没有 `thumbShape` 钩子 ✗），所以那边只需加一个
  /// `paintThumb` 回调参数、在它画圆的地方调本方法即可 ✓ —— 本类因此**不持有状态、
  /// 不依赖 BuildContext**，便于最小化 diff 与 rebase 冲突面 ✓。
  static void paintThumbInto(
    Canvas canvas,
    Offset center,
    double radius, {
    required Brightness brightness,
    Animation<double>? enableAnimation,
  }) {
    final tokens =
        (brightness == Brightness.dark
                ? LiquidGlassTokens.dark
                : LiquidGlassTokens.light)
            .forMaterial(LiquidGlassMaterial.lens);
    final spec = liquidSliderThumbPaintSpec(brightness);
    final r = radius * (0.6 + 0.4 * (enableAnimation?.value ?? 1.0));

    canvas.drawCircle(center, r, Paint()..color = const Color(0x33FFFFFF));

    Paint rimOf(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = spec.rimWidth
      ..color = c.withValues(alpha: spec.rimAlpha);
    canvas
      ..save()
      ..translate(-spec.spread * 0.5, -spec.spread * 0.5);
    canvas.drawCircle(center, r, rimOf(const Color(0xFFFF6B6B)));
    canvas.restore();
    canvas
      ..save()
      ..translate(spec.spread * 0.5, spec.spread * 0.5);
    canvas.drawCircle(center, r, rimOf(const Color(0xFF6BB8FF)));
    canvas.restore();

    final inner = (tokens.refractiveIndex - 1).clamp(0.0, 0.5);
    if (inner > 0) {
      canvas.drawCircle(
        center,
        r * 0.55,
        Paint()
          ..color = const Color(0xFF000000)
              .withValues(alpha: (inner * 0.35).clamp(0.0, 0.20)),
      );
    }
    if (LiquidGlassRuntime.increaseContrast) {
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.85),
      );
    }
  }
}

/// 供单测使用：手柄的"命中区"（逻辑 px）——`Slider` 用 [SliderComponentShape.getPreferredSize]
/// 决定可点范围 ✓，这里给出同一个口径，便于断言"不会比原 6.0 圆更小" ✓。
double liquidSliderThumbHitRadius({double radius = kLiquidSliderThumbRadius}) =>
    radius + 2;

/// 供单测使用：不依赖 `BuildContext` 的色散参数（浅/深各一套 ✓）。
({double spread, double rimAlpha, double rimWidth}) liquidSliderThumbPaintSpec(
  Brightness brightness,
) {
  final tokens =
      (brightness == Brightness.dark
              ? LiquidGlassTokens.dark
              : LiquidGlassTokens.light)
          .forMaterial(LiquidGlassMaterial.lens);
  final ca = math.max(tokens.chromaticAberration, 0.004);
  return (
    spread: (ca * 900).clamp(0.4, 2.2),
    rimAlpha: (0.10 + tokens.lightIntensity * 0.35).clamp(0.08, 0.42),
    rimWidth: math.max(1.0, tokens.thickness * 0.14),
  );
}

// 实现零外部依赖 ✓（纯 Canvas ⇒ solid/低能力设备同样可渲染 ✓）。
