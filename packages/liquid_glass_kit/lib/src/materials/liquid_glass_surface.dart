// SPDX-License-Identifier: GPL-3.0-or-later
//
// 玻璃表面组件（排期 #9）：按探测出的档位渲染，并在深浅切换时做 200ms 插值（不闪变）。
//
// 档位实现：
//   * fakeGlass —— ClipRRect → BackdropFilter(blur, TileMode.mirror) → 饱和度矩阵
//                  → Canvas 双描边高光（素材文档 §6 的降级链，Skia 兼容）
//   * solid     —— 纯色半透明 + 发丝描边（最低档，不采样背景）
//   * refraction—— 需要宿主注入折射 shader（#11）；未注入时自动退到 fakeGlass 并记录提示
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'liquid_glass_capability.dart';
import 'liquid_glass_refraction.dart';
import 'liquid_glass_runtime.dart';
import 'liquid_glass_tokens.dart';

/// 玻璃主题：把当前亮度下的 token 通过 InheritedWidget 下发，并在切换时插值。
class LiquidGlassTheme extends StatefulWidget {
  const LiquidGlassTheme({
    super.key,
    required this.child,
    this.light,
    this.dark,
    this.brightness,
    this.transitionDuration = const Duration(milliseconds: 200),
  });

  final Widget child;
  final LiquidGlassTokens? light;
  final LiquidGlassTokens? dark;

  /// 显式的明暗取值。**宿主若有自己的明暗状态（如设置项），务必传它**：
  /// MaterialApp 会把 `theme` 变化套一层 200ms 的 AnimatedTheme，而
  /// `ThemeData.brightness` 是非插值属性、在中点才翻转——若我们只依赖
  /// `Theme.of(context).brightness`，玻璃过渡会延后约 100ms 才开始，
  /// 与 Material 的动画串成"两段式"，观感上就是切换发顿。
  final Brightness? brightness;

  /// 深浅切换的过渡时长。素材与问题台账要求 200ms（防闪变）。
  final Duration transitionDuration;

  @override
  State<LiquidGlassTheme> createState() => _LiquidGlassThemeState();
}

class _LiquidGlassThemeState extends State<LiquidGlassTheme>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.transitionDuration,
    value: 1,
  );
  LiquidGlassTokens? _from;
  LiquidGlassTokens? _to;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 明暗取值：显式传入优先，否则跟随 Theme。
  Brightness _effectiveBrightness(BuildContext context) =>
      widget.brightness ?? Theme.of(context).brightness;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 亮度来自 Theme（InheritedWidget），因此深浅切换会走到这里——
    // 在这里换目标 token 并启动过渡，比在 build 里改状态更符合 Flutter 惯例。
    final target = _effectiveBrightness(context) == Brightness.dark
        ? (widget.dark ?? LiquidGlassTokens.dark)
        : (widget.light ?? LiquidGlassTokens.light);
    if (_to == null) {
      _to = target;
      _controller.value = 1;
      return;
    }
    if (_to != target) {
      _from = _currentTokens(target);
      _to = target;
      _controller
        ..value = 0
        ..forward();
    }
  }

  @override
  void didUpdateWidget(LiquidGlassTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.transitionDuration != oldWidget.transitionDuration) {
      _controller.duration = widget.transitionDuration;
    }
    // 显式传入的 token 变了也要重新过渡
    final target = _effectiveBrightness(context) == Brightness.dark
        ? (widget.dark ?? LiquidGlassTokens.dark)
        : (widget.light ?? LiquidGlassTokens.light);
    if (_to != null && _to != target) {
      _from = _currentTokens(target);
      _to = target;
      _controller
        ..value = 0
        ..forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = _effectiveBrightness(context) == Brightness.dark
        ? (widget.dark ?? LiquidGlassTokens.dark)
        : (widget.light ?? LiquidGlassTokens.light);
    _to ??= target;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final tokens = _currentTokens(target);
        return _LiquidGlassThemeScope(tokens: tokens, child: child!);
      },
      child: widget.child,
    );
  }

  /// 当前应下发的 token（过渡中则插值）。
  LiquidGlassTokens _currentTokens(LiquidGlassTokens target) {
    final to = _to ?? target;
    final from = _from;
    if (from == null || _controller.value >= 1) return to;
    return LiquidGlassTokens.lerp(
      from,
      to,
      Curves.easeInOut.transform(_controller.value),
    );
  }
}

class _LiquidGlassThemeScope extends InheritedWidget {
  const _LiquidGlassThemeScope({required this.tokens, required super.child});

  final LiquidGlassTokens tokens;

  static LiquidGlassTokens of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_LiquidGlassThemeScope>();
    if (scope != null) return scope.tokens;
    // 没有 LiquidGlassTheme 祖先时按当前亮度取默认 token（方便单测与局部使用）
    return Theme.of(context).brightness == Brightness.dark
        ? LiquidGlassTokens.dark
        : LiquidGlassTokens.light;
  }

  @override
  bool updateShouldNotify(_LiquidGlassThemeScope oldWidget) =>
      oldWidget.tokens != tokens;
}

/// 玻璃表面。**默认自动探测档位**；也可显式传入 capability 便于测试。
class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    super.key,
    this.child,
    this.material = LiquidGlassMaterial.regular,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.capability,
    this.clipBehavior = Clip.antiAlias,
    this.padding,
    this.shadow = true,
    this.shaderProvider,
  });

  final Widget? child;
  final LiquidGlassMaterial material;
  final BorderRadius borderRadius;
  final LiquidGlassCapability? capability;
  final Clip clipBehavior;
  final EdgeInsetsGeometry? padding;
  final bool shadow;

  /// 折射 shader 提供方（局部覆盖 [LiquidGlassRuntime.refractionShaderProvider]）。
  final LiquidGlassRefractionShaderProvider? shaderProvider;

  @override
  Widget build(BuildContext context) {
    final base = _LiquidGlassThemeScope.of(context);
    // #18 无障碍（task-93）：增强对比 = 宿主开关 **或** 系统高对比度主题（Windows 直接给）。
    // 默认两者都假 ⇒ 取到的 tokens 与改动前**同一个对象** ⇒ 渲染逐字节不变 ✓。
    final a11yContrast =
        LiquidGlassRuntime.increaseContrast ||
        (MediaQuery.maybeOf(context)?.highContrast ?? false);
    // #19（task-94）：强度先缩放、强对比的下限最后落 ⇒ 两个开关不互相抵消 ✓。
    // `forStrength(1.0)` 直接返回原对象 ⇒ 默认路径与改动前**同一个 tokens** ✓。
    final tokens = a11yContrast
        ? base
              .forMaterial(material)
              .forStrength(LiquidGlassRuntime.strength)
              .forIncreasedContrast()
        : base.forMaterial(material).forStrength(LiquidGlassRuntime.strength);
    // 两道闸：能力层（shader filter）+ 渲染层（shader 是否在手上）。
    final cap = capability ?? LiquidGlassRuntime.capability;
    final provider =
        shaderProvider ?? LiquidGlassRuntime.refractionShaderProvider;
    final tier = resolveRenderTier(
      // #18 无障碍（task-93）：**必须走 `cappedTier`** ✗ —— 这里用的是 `cap?.tier`
      // （`cap` = 局部覆盖 ?? 全局能力 ⇒ **几乎总是非空** ⇒ 走的是**原始**能力档位 ✓），
      // 所以"降低透明度"的封顶若只加在 `LiquidGlassRuntime.tier` getter 里**救不到**
      // app chrome（侧栏/顶栏/底导都从这里渲染）✗。封顶 = 单一收口 = 本函数 ✓。
      tier: LiquidGlassRuntime.cappedTier(cap?.tier ?? LiquidGlassRuntime.tier),
      shaderFilterSupported: cap?.shaderFilterSupported ?? false,
      shaderAvailable: provider != null,
    );

    Widget content = padding == null
        ? (child ?? const SizedBox.shrink())
        : Padding(padding: padding!, child: child ?? const SizedBox.shrink());

    final surface = switch (tier) {
      LiquidGlassTier.refraction => _buildGlass(
        tokens,
        content,
        backdropFilter: _refractionFilter(provider),
      ),
      LiquidGlassTier.fakeGlass => _buildGlass(
        tokens,
        content,
        backdropFilter: _blurFilter(tokens),
      ),
      LiquidGlassTier.solid => _buildSolid(tokens, content),
    };

    final clipped = ClipRRect(
      borderRadius: borderRadius,
      clipBehavior: clipBehavior,
      child: surface,
    );
    if (!shadow || tokens.shadowOpacity <= 0) return clipped;

    // 阴影方向跟随光角：光从左上来 → 影子往右下走（固定 (0,8) 会让"光源"与高光打架）
    final dir = Offset(
      math.cos(tokens.lightAngle),
      math.sin(tokens.lightAngle),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: tokens.shadowOpacity),
            blurRadius: 20 + 8 * tokens.lightIntensity,
            spreadRadius: -2,
            offset: Offset(dir.dx * 4, 5 + dir.dy * 3),
          ),
        ],
      ),
      child: clipped,
    );
  }

  /// 模糊档的 backdrop filter（blur == 0 时返回 null ⇒ 整层跳过，见下）。
  ui.ImageFilter? _blurFilter(LiquidGlassTokens tokens) => tokens.blur > 0
      ? ui.ImageFilter.blur(
          sigmaX: tokens.blur,
          sigmaY: tokens.blur,
          tileMode: TileMode.mirror,
        )
      : null;

  /// 折射档的 backdrop filter（#11 接线）：位移/模糊交给 shader，我们只在其上做 tint 与高光。
  /// 取不到 shader 时返回 null ⇒ 退化为不带背景采样的玻璃（且调用方已按 resolveRenderTier
  /// 判定过：能走到这里说明 provider 非空，理论上不会发生；真发生也不能让上游 assert 兜底）。
  ui.ImageFilter? _refractionFilter(
    LiquidGlassRefractionShaderProvider? provider,
  ) {
    final shader = provider?.createShader();
    if (shader == null) {
      debugPrint(
        '[LiquidGlass] refraction shader 取用失败 → 本表面无 backdrop 采样（已降级绘制）',
      );
      return null;
    }
    return ui.ImageFilter.shader(shader);
  }

  /// 玻璃本体（FakeGlass 与真折射共用）：饱和度矩阵 → 底色 → backdrop 采样 → 高光描边。
  ///
  /// [backdropFilter] 决定"怎么采样背景"：模糊（FakeGlass 档）或 shader 位移（折射档）；
  /// 为 null 时整层跳过（blur == 0 的情形，上游实测"零模糊 + srcATop"在 Impeller 上会输出空白）。
  ///
  /// #10 级增强（对齐上游 fake_glass.dart 的配方）：
  ///   * 高光用"沿光角的 4 段渐变 + 方形 bounds 校正 + hardLight/overlay 双描边"，
  ///     而不是简单两笔描边——非正方形比例下光角才不会被压扁；
  ///   * 加 Skia 光栅缓存守卫（见 [_SkiaRasterCacheGuard]）。
  Widget _buildGlass(
    LiquidGlassTokens tokens,
    Widget content, {
    required ui.ImageFilter? backdropFilter,
  }) {
    Widget surface = content;

    // 饱和度增强（Skia 兜底写法，素材文档 §6）
    if (tokens.saturation != 1) {
      surface = ColorFiltered(
        colorFilter: ColorFilter.matrix(saturationMatrix(tokens.saturation)),
        child: surface,
      );
    }

    // 玻璃底色
    surface = ColoredBox(
      color: tokens.tint.withValues(alpha: tokens.tintOpacity),
      child: surface,
    );

    // 背景采样层：FakeGlass 档是 blur(TileMode.mirror)，折射档是 shader；null 则整层跳过。
    if (backdropFilter != null) {
      surface = BackdropFilter(
        filter: backdropFilter,
        // #12 / task-9 自适应对比度保护：两道混合画在**模糊背景之上、tint 之下**，
        // 所以它只改玻璃本体（背景亮度），不会动玻璃上的文字/图标。
        child: CustomPaint(
          painter: _AdaptiveContrastPainter(tokens: tokens),
          child: surface,
        ),
      );
    }
    // 注意：backdropFilter == null（blur == 0，或折射档取不到 shader）时上面整层跳过
    // ⇒ 自适应两道混合也不会画（没有 backdrop 层可混合，画上去会混到页面背景上）。

    // 高光与描边（Canvas 画在最上层）
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        _SkiaRasterCacheGuard(child: surface),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _GlassSpecularPainter(
                tokens: tokens,
                radius: _maxRadius,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSolid(LiquidGlassTokens tokens, Widget content) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.tint.withValues(
          alpha: tokens.tintOpacity.clamp(0.5, 1.0),
        ),
        border: Border.all(
          color: tokens.borderColor,
          width: tokens.borderWidth,
        ),
      ),
      child: content,
    );
  }

  double get _maxRadius {
    final values = <double>[
      borderRadius.topLeft.x,
      borderRadius.topRight.x,
      borderRadius.bottomLeft.x,
      borderRadius.bottomRight.x,
    ];
    return values.reduce(math.max);
  }
}

/// 高光与描边（#10 级增强：对齐上游 fake_glass.dart 的 `_paintSpecular`）。
///
/// 上游配方要点（都踩过坑，照抄即可）：
///   1. **方形 bounds 校正**：渐变建在"以中心为心、边长取最长边"的正方形上，
///      否则非正方形控件会把光角压扁（45° 看起来像 30°）；
///   2. **4 段渐变**：两端亮、中段按 `ambientStrength` 回落，形成"光扫过玻璃"的观感；
///   3. **两遍描边**：细的 hardLight（边缘锐光）+ 粗的 overlay（柔和厚度感）；
///   4. 渐变方向随 `lightAngle`，与阴影、全 App 光源约定一致。
class _GlassSpecularPainter extends CustomPainter {
  _GlassSpecularPainter({required this.tokens, required this.radius});

  final LiquidGlassTokens tokens;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || size.shortestSide <= 0) return;
    if (tokens.highlightOpacity <= 0 && tokens.borderWidth <= 0) return;

    final rect = Offset.zero & size;
    // 1) 方形 bounds：保证光角不被宽高比扭曲
    final square = Rect.fromCircle(
      center: rect.center,
      radius: size.longestSide / 2,
    );

    final light = tokens.lightIntensity.clamp(0.0, 1.0);
    // 派生量走 LiquidGlassTokens（同一实现被测试复用，公式不再两边各写一份）。
    final ambient = tokens.midStopAlpha;
    final alpha = tokens.rimAlpha;
    final color = Colors.white.withValues(alpha: alpha);
    final x = math.cos(tokens.lightAngle);
    final y = math.sin(tokens.lightAngle);

    // 光的覆盖范围（亮度越高越"铺得开"）
    final coverage = ui.lerpDouble(.3, .5, light)!;
    // 光与最短边的贴合程度 / 宽高比修正（上游同款，避免长条控件上高光消失）
    final alignmentWithShortestSide = (size.aspectRatio < 1 ? y : x).abs();
    final gradientScale =
        ((1 - 1 / size.aspectRatio) * (1 - alignmentWithShortestSide)).clamp(
          0.0,
          1.0,
        );
    final inset = ui.lerpDouble(0, .5, gradientScale)!;
    final secondInset = ui.lerpDouble(coverage, .5, gradientScale)!;

    // mid stop 直接用 ambientStrength（上游语义），**不**乘 rim alpha：
    // refs/flutter_liquid_glass-main/packages/liquid_glass_renderer/lib/src/fake_glass.dart:398-404
    //   colors: [color, color.withValues(alpha: ambientStrength), ... , color]
    // 旧实现写的是 `color.a * ambient`，把 rim alpha 又乘了一遍，暗色档中段余晖只剩 0.026
    // （M1-B 根因之一）。task-7 对齐后，light/dark 的 ambientStrength 已按旧公式反算成等效值，
    // 所以渲染逐位不变（浅色档截图 sha256 相同，见 task-7 报告）。
    final shader = LinearGradient(
      colors: <Color>[
        color,
        color.withValues(alpha: ambient),
        color.withValues(alpha: ambient),
        color,
      ],
      stops: <double>[inset, secondInset, 1 - secondInset, 1 - inset],
      begin: Alignment(x, y),
      end: Alignment(-x, -y),
    ).createShader(square);

    final deflate = tokens.borderWidth / 2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          rect.deflate(deflate),
          Radius.circular(math.max(0, radius - deflate)),
        ),
      );

    // 3) 第一遍：锐利边缘光（hardLight）
    canvas.drawPath(
      path,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = ui.lerpDouble(
          tokens.borderWidth,
          tokens.borderWidth * 2,
          light,
        )!
        ..color = color.withValues(alpha: color.a * 0.4)
        ..blendMode = BlendMode.hardLight,
    );

    // 3) 第二遍：柔和厚度感（overlay），粗细跟 thickness 走
    canvas.drawPath(
      path,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = (tokens.thickness / 20).clamp(0.6, 3.0)
        ..color = color.withValues(alpha: color.a * 0.6)
        ..blendMode = BlendMode.overlay,
    );

    // 底色描边（让形状在任何背景上都读得出来）
    if (tokens.borderWidth > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = tokens.borderWidth
          ..color = tokens.borderColor,
      );
    }
  }

  @override
  bool shouldRepaint(_GlassSpecularPainter old) =>
      old.tokens != tokens || old.radius != radius;
}

/// Skia 下的光栅缓存守卫。
///
/// 上游 fake_glass.dart:245-248 的处理：**Skia 上必须给 backdrop filter 子树
/// `setWillChangeHint()`**，否则该子树会被光栅缓存，背景滚动时玻璃里的模糊内容
/// 会停在旧画面上（表现为"玻璃里是上一帧的背景"）。Impeller（shader filter 可用）
/// 不需要这一步。我们 Windows v1 正好走 Skia，所以这条是必需的，不是优化。
class _SkiaRasterCacheGuard extends SingleChildRenderObjectWidget {
  const _SkiaRasterCacheGuard({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _SkiaRasterCacheGuardRender();
}

class _SkiaRasterCacheGuardRender extends RenderProxyBox {
  @override
  void paint(PaintingContext context, Offset offset) {
    if (!ui.ImageFilter.isShaderFilterSupported) {
      context.setWillChangeHint();
    }
    super.paint(context, offset);
  }
}

/// 便捷封装：把任意子树包成"玻璃卡片"。
class LiquidGlassPanel extends StatelessWidget {
  const LiquidGlassPanel({
    super.key,
    required this.child,
    this.material = LiquidGlassMaterial.thick,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.padding = const EdgeInsets.all(16),
    this.capability,
  });

  final Widget child;
  final LiquidGlassMaterial material;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final LiquidGlassCapability? capability;

  @override
  Widget build(BuildContext context) {
    return LiquidGlassSurface(
      material: material,
      borderRadius: borderRadius,
      padding: padding,
      capability: capability,
      child: child,
    );
  }
}

/// 渲染层最终档位（#11 接线）。**第二道闸**：能力层（task-13 的 `_guardRefraction`）已保证
/// "不支持 shader filter 就不会选 refraction"；这里再确认"shader 真的在手上"。
///
/// 为什么渲染层也必须先拦：上游渲染器在 `!isShaderFilterSupported` 时是
/// `assert(...) + return child`（`poc/liquid_glass_renderer_local/lib/src/glassify.dart:58-67`）
/// —— debug 直接崩、release 静默没有玻璃且无日志。两条闸都在**选档阶段**，
/// 任一条不满足就明确回落到 FakeGlass 并打日志，而不是把问题留给底层。
@visibleForTesting
LiquidGlassTier resolveRenderTier({
  required LiquidGlassTier tier,
  required bool shaderFilterSupported,
  required bool shaderAvailable,
}) {
  if (tier != LiquidGlassTier.refraction) return tier;
  if (shaderFilterSupported && shaderAvailable) {
    return LiquidGlassTier.refraction;
  }
  debugPrint(
    '[LiquidGlass] refraction 不可渲染（shaderFilter=$shaderFilterSupported shader=$shaderAvailable）'
    ' → 本表面回落 FakeGlass',
  );
  return LiquidGlassTier.fakeGlass;
}

/// 便于测试断言：给定亮度与档位，直接算出该表面实际使用的 token。
@visibleForTesting
LiquidGlassTokens resolveTokensForTest({
  required Brightness brightness,
  required LiquidGlassMaterial material,
  LiquidGlassTokens? light,
  LiquidGlassTokens? dark,
}) {
  final base = brightness == Brightness.dark
      ? (dark ?? LiquidGlassTokens.dark)
      : (light ?? LiquidGlassTokens.light);
  return base.forMaterial(material);
}

/// #12 / task-9：自适应对比度保护（逐像素，由背景自身亮度驱动，无需 shader）。
///
/// 真折射档的 shader 是上游预编译 .iplr，我们改不了；但
/// `tools/ui-probe`/素材文档 §1.1 想要的那条规则——
/// **亮背景 → 压暗、暗背景 → 提亮**——可以用两道标准混合模式在 FakeGlass 档等价实现：
///   * `multiply(黑, α=adaptiveDarken)`：r1 = (1-darken)·d —— 压暗量正比于背景亮度，
///     所以只压亮背景、几乎不动暗背景；
///   * `screen(灰=adaptiveLift, α=1)`：r2 = lift + (1-lift)·r1 —— 提亮量正比于 (1-背景亮度)，
///     所以只抬暗背景、几乎不动亮背景。
/// 合成即 `r = lift + (1-lift)(1-darken)·d`（见 LiquidGlassTokens.adaptiveBackdropLuma）。
///
/// 为什么必须自适应：静态 tint 的合成是 `α·tint + (1-α)·d`，同一个 α 不可能既把亮背景压到
/// 白字可读（实测暗色档亮背景下 4.69:1，余量极小），又把暗背景抬到玻璃板可辨
/// （实测亮色档暗背景下深字只有 2.01:1）。两个方向的要求相反，只能让映射随 d 变。
class _AdaptiveContrastPainter extends CustomPainter {
  _AdaptiveContrastPainter({required this.tokens});

  final LiquidGlassTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final darken = tokens.adaptiveDarken.clamp(0.0, 1.0);
    final lift = tokens.adaptiveLift.clamp(0.0, 1.0);
    final rect = Offset.zero & size;
    if (darken > 0) {
      canvas.drawRect(
        rect,
        Paint()
          ..color = const Color(0xFF000000).withValues(alpha: darken)
          ..blendMode = BlendMode.multiply,
      );
    }
    if (lift > 0) {
      canvas.drawRect(
        rect,
        Paint()
          ..color = Color.from(alpha: 1.0, red: lift, green: lift, blue: lift)
          ..blendMode = BlendMode.screen,
      );
    }
  }

  @override
  bool shouldRepaint(_AdaptiveContrastPainter old) => old.tokens != tokens;
}
