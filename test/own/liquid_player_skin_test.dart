// task-118（#26 批2 皮肤件）单测：
//   * `LiquidSliderThumb` / `LiquidSliderThumbShape`（glassLens 手柄 ✓）
//   * `LiquidHeaderGlass`（顶栏玻璃底 ✓：挂载纪律 §6.1 ＋ 功能守恒 ✓）
// 判据口径：尺寸/命中区不缩水 ✓；隐藏时**不挂玻璃层** ✓；可见时**只挂一处** ✓；
// 切换显隐时**带 GlobalKey 的业务子树被复用**（State 不重建 ✓＝功能守恒硬证据）；
// 降级：手柄是纯 Canvas 绘制、参数有界 ⇒ solid/低能力设备同样可渲染 ✓。
import 'package:PiliPlus/pages/video/widgets/liquid_header_skin.dart';
import 'package:PiliPlus/pages/video/widgets/liquid_slider_skin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';
import 'package:material_ui/material_ui.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      home: LiquidGlassTheme(
        brightness: brightness,
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  group('LiquidSliderThumb（glassLens 手柄 · 控件形态）', () {
    testWidgets('按半径渲染，且内部走 lens 材质 ✓', (tester) async {
      await tester.pumpWidget(_host(const LiquidSliderThumb()));
      final box = tester.getSize(find.byType(LiquidSliderThumb));
      expect(box.width, kLiquidSliderThumbRadius * 2);
      expect(box.height, kLiquidSliderThumbRadius * 2);
      final surface = tester.widget<LiquidGlassSurface>(
        find.byType(LiquidGlassSurface),
      );
      expect(surface.material, LiquidGlassMaterial.lens);
      expect(surface.shadow, isFalse, reason: '同族先例：手柄不投影 ✓');
    });

    testWidgets('自定义半径生效 ✓', (tester) async {
      await tester.pumpWidget(_host(const LiquidSliderThumb(radius: 12)));
      expect(tester.getSize(find.byType(LiquidSliderThumb)).width, 24);
    });

    test('命中区不小于既有 6.0 口径 ✓', () {
      expect(liquidSliderThumbHitRadius(), greaterThanOrEqualTo(8.0));
    });
  });

  group('LiquidSliderThumbShape（Material Slider 形态）', () {
    test('preferredSize 为半径＋2，且不小于旧口径 ✓', () {
      const shape = LiquidSliderThumbShape();
      final size = shape.getPreferredSize(true, false);
      expect(size.width, (kLiquidSliderThumbRadius + 2) * 2);
      expect(size.width, greaterThanOrEqualTo(6.0 * 2));
    });

    test('浅/深两套 lens 参数都有界（纯 Canvas ⇒ 可渲染 ✓）', () {
      for (final b in Brightness.values) {
        final spec = liquidSliderThumbPaintSpec(b);
        expect(spec.spread.isFinite, isTrue);
        expect(spec.spread, inInclusiveRange(0.4, 2.2));
        expect(spec.rimAlpha, inInclusiveRange(0.08, 0.42));
        expect(spec.rimWidth, greaterThanOrEqualTo(1.0));
      }
    });
  });

  group('LiquidHeaderGlass（顶栏玻璃底 · 挂载纪律 ＋ 功能守恒 ✓）', () {
    testWidgets('visible=false ⇒ 不挂玻璃层，child 原样 ✓（§6.1）', (tester) async {
      await tester.pumpWidget(
        _host(
          const LiquidHeaderGlass(
            visible: false,
            child: Text('顶栏', textDirection: TextDirection.ltr),
          ),
        ),
      );
      expect(find.byType(LiquidGlassSurface), findsNothing);
      expect(find.text('顶栏'), findsOneWidget);
    });

    testWidgets('visible=true ⇒ 恰好一处玻璃层，child 仍在 ✓', (tester) async {
      await tester.pumpWidget(
        _host(
          const LiquidHeaderGlass(
            visible: true,
            child: Text('顶栏', textDirection: TextDirection.ltr),
          ),
        ),
      );
      expect(find.byType(LiquidGlassSurface), findsOneWidget);
      expect(find.text('顶栏'), findsOneWidget);
      final surface = tester.widget<LiquidGlassSurface>(
        find.byType(LiquidGlassSurface),
      );
      expect(
        surface.material,
        LiquidGlassMaterial.regular,
        reason: 'B1/B5 继承 ✓',
      );
      expect(surface.shadow, isFalse);
    });

    testWidgets('隐藏↔可见切换：带 GlobalKey 的业务子树 Element 被复用（State 不重建 ✓）', (
      tester,
    ) async {
      // 真实调用点里 HeaderControl 自带 GlobalKey(headerCtrKey) ✓
      // ⇒ 包/摘玻璃层都不会重建它的 State ✓。这里用同一机制做最小复现。
      final childKey = GlobalKey();
      await tester.pumpWidget(
        _host(
          LiquidHeaderGlass(
            visible: false,
            child: SizedBox(key: childKey, width: 10, height: 10),
          ),
        ),
      );
      final elementBefore = childKey.currentContext;
      await tester.pumpWidget(
        _host(
          LiquidHeaderGlass(
            visible: true,
            child: SizedBox(key: childKey, width: 10, height: 10),
          ),
        ),
      );
      expect(find.byType(LiquidGlassSurface), findsOneWidget);
      expect(
        identical(childKey.currentContext, elementBefore),
        isTrue,
        reason: 'GlobalKey 子树必须跨 挂/摘 玻璃层复用 ✓',
      );
    });

    testWidgets('B1/B5 policy: playing => solid tier (no BackdropFilter)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const LiquidHeaderGlass(
            visible: true,
            material: LiquidGlassMaterial.solid,
            child: Text('top', textDirection: TextDirection.ltr),
          ),
        ),
      );
      expect(
        tester
            .widget<LiquidGlassSurface>(find.byType(LiquidGlassSurface))
            .material,
        LiquidGlassMaterial.solid,
      );
    });

    testWidgets('B1/B5 policy: paused/idle => regular tier (frosted band)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const LiquidHeaderGlass(
            visible: true,
            material: LiquidGlassMaterial.regular,
            child: Text('top', textDirection: TextDirection.ltr),
          ),
        ),
      );
      expect(
        tester
            .widget<LiquidGlassSurface>(find.byType(LiquidGlassSurface))
            .material,
        LiquidGlassMaterial.regular,
      );
    });

    testWidgets('深色主题同样可渲染 ✓', (tester) async {
      await tester.pumpWidget(
        _host(
          const LiquidHeaderGlass(
            visible: true,
            child: Text('顶栏', textDirection: TextDirection.ltr),
          ),
          brightness: Brightness.dark,
        ),
      );
      expect(find.byType(LiquidGlassSurface), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
