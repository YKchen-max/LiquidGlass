// SPDX-License-Identifier: GPL-3.0-or-later
// ============================================================================
// #28a 详情页主题级准收官：两件新组件的 widget 测试。
//
// 口径照 test/own/u27_liquid_widgets_test.dart：
//   1. **离线夹具**：main() 顶部 installOfflineHttp()（本套件不挂网络图，
//      装上纯作防御层，http_offline.dart 头注释的纪律）；
//   2. **不起 Hive、不写 tearDownAll**（12 分钟挂死教训：裸 await
//      Hive.close() 在 widget 测试环境永久挂起 ✗✓）；
//   3. import 只认 material_ui（fork）——测试宿主必须装 fork 主题（S16 教训），
//      finder 类型才不失配；
//   4. 档位用 LiquidGlassRuntime.overrideForTest 显式钉：默认 solid（冒烟＋
//      降级面），A3 用例单独升 fakeGlass（thick 才有 BackdropFilter 可断言）。
//
// 覆盖：
//   LiquidAppBarSkin：preferredSize 透传（PreferredSizeWidget 子件逐字透传 /
//   非 PreferredSizeWidget 落 fallback）、布局零影响（高度=子件高度）、主题注入
//   （液态字阶/图标色/surface 背景 token＋skin 外对照组）、零真玻璃（预算 §0.3）、
//   Semantics 透传、深浅双主题冒烟；
//   LiquidSheetShell：solid 档冒烟、A3 门（≤85% 无 BackdropFilter / >85% 挂上 /
//   0.85 边界钉 > 语义）、约束透明（Column+Expanded 满高内容零溢出——5 个既有
//   面板的接线生命线）、intrinsic 内容高度=内容+把手区、showHandle:false 关把手、
//   内容手势透传（IgnorePointer 把手不抢点击）。
// ============================================================================

import 'package:PiliPlus/common/widgets/liquid/liquid_appbar_skin.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_sheet_shell.dart';
import 'package:PiliPlus/utils/glass_accessibility.dart';
// 见文件头第 3 条：测试宿主必须装 fork 主题（S16 教训）。
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

import 'http_offline.dart';

LiquidGlassCapability _cap(LiquidGlassTier tier) => LiquidGlassCapability(
  tier: tier,
  platform: 'test',
  osVersion: 'unit',
  shaderFilterSupported: false,
  reason: 'u28 skin widgets test',
);

const Color _kSeed = Color(0xFF00A1D6);

ColorScheme _scheme(Brightness brightness) =>
    ColorScheme.fromSeed(seedColor: _kSeed, brightness: brightness);

Widget _host({
  required Widget child,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: ThemeData(colorScheme: _scheme(brightness)),
  home: Scaffold(body: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  installOfflineHttp();

  setUp(() {
    GlassAccessibility.debugReset();
    LiquidGlassRuntime.overrideForTest(_cap(LiquidGlassTier.solid));
  });

  tearDown(() {
    GlassAccessibility.debugReset();
    LiquidGlassRuntime.overrideForTest(null);
  });

  // 刻意**不写 tearDownAll**：本套件不起 Hive（u27 同款纪律）。

  group('LiquidAppBarSkin：preferredSize 透传', () {
    test('子件是 PreferredSizeWidget ⇒ 逐字透传（纯 getter，无需渲染）', () {
      const skin = LiquidAppBarSkin(
        child: PreferredSize(
          preferredSize: Size.fromHeight(42),
          child: SizedBox(),
        ),
      );
      expect(skin.preferredSize, const Size.fromHeight(42));
    });

    test('子件不是 PreferredSizeWidget（SimpleAppBar 形态）⇒ 落 fallback', () {
      const skin = LiquidAppBarSkin(child: SizedBox(height: 37));
      expect(skin.preferredSize, const Size.fromHeight(kToolbarHeight));
      const custom = LiquidAppBarSkin(
        fallbackPreferredSize: Size.fromHeight(24),
        child: SizedBox(height: 37),
      );
      expect(custom.preferredSize, const Size.fromHeight(24));
    });

    testWidgets('pump 后透传仍成立（widget 树里读同一 getter）', (tester) async {
      await tester.pumpWidget(
        _host(
          child: Align(
            alignment: Alignment.topCenter,
            child: LiquidAppBarSkin(
              child: PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Container(height: 56, color: Colors.black),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final skin = tester.widget<LiquidAppBarSkin>(
        find.byType(LiquidAppBarSkin),
      );
      expect(skin.preferredSize, const Size.fromHeight(56));
    });
  });

  group('LiquidAppBarSkin：布局/语义零影响（透传零改）', () {
    testWidgets('高度 = 子件高度（Theme 注入零 RenderBox）', (tester) async {
      await tester.pumpWidget(
        _host(
          child: const Align(
            alignment: Alignment.topCenter,
            child: LiquidAppBarSkin(
              child: SizedBox(
                width: 120,
                height: 37,
                child: ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // SimpleScaffold 的 appBar 槽位按实测高度布局 ⇒ 这条就是「槽位量到的
      // 高度包装前后不变」的等价断言。
      expect(tester.getSize(find.byType(LiquidAppBarSkin)).height, 37);
      expect(tester.getSize(find.byType(LiquidAppBarSkin)).width, 120);
    });

    testWidgets('Semantics 透传：skin 内语义节点原样可达', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          child: LiquidAppBarSkin(
            child: Semantics(
              button: true,
              label: '返回按钮',
              child: const SizedBox(width: 40, height: 40),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('返回按钮'), findsOneWidget);
      handle.dispose();
    });
  });

  group('LiquidAppBarSkin：solid 档主题注入（预算 §0.3，零真玻璃）', () {
    testWidgets('字阶/图标色/背景 token 注入 ＋ skin 外对照组不受染', (
      tester,
    ) async {
      late ThemeData injected;
      late ThemeData outer;
      final expected = _scheme(Brightness.light);
      await tester.pumpWidget(
        _host(
          child: Column(
            children: [
              Builder(
                builder: (context) {
                  outer = Theme.of(context);
                  return const SizedBox(height: 1);
                },
              ),
              LiquidAppBarSkin(
                child: Builder(
                  builder: (context) {
                    injected = Theme.of(context);
                    return const SizedBox(height: 10);
                  },
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 液态字阶：正文族 = LiquidText。
      expect(injected.textTheme.bodyMedium!.fontFamily, LiquidFontFamily.text);
      expect(
        outer.textTheme.bodyMedium!.fontFamily,
        isNot(LiquidFontFamily.text),
        reason: '对照组必须不受染 ⇒ 注入确实发生在 skin 子树内',
      );
      // 图标色：onSurface 系。
      expect(injected.iconTheme.color, expected.onSurface);
      expect(injected.primaryIconTheme.color, expected.onSurface);
      // 背景 = colorScheme.surface 系（appBar 默认底色 token）。
      expect(injected.appBarTheme.backgroundColor, expected.surface);
      expect(injected.appBarTheme.foregroundColor, expected.onSurface);
      // colorScheme 本体不被篡改（透传纪律）。
      expect(injected.colorScheme, expected);
    });

    testWidgets('fakeGlass 档下也零 BackdropFilter/LiquidGlassSurface（不加真玻璃）', (
      tester,
    ) async {
      LiquidGlassRuntime.overrideForTest(_cap(LiquidGlassTier.fakeGlass));
      await tester.pumpWidget(
        _host(
          child: const LiquidAppBarSkin(
            child: SizedBox(
              width: 120,
              height: 37,
              child: ColoredBox(color: Colors.black),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 详情页常驻真玻璃预算已满（顶栏＋底栏 2 处）⇒ skin 永不挂玻璃层。
      expect(find.byType(LiquidGlassSurface), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('深色主题冒烟（S16 雷区：黑字糊黑卡不许复现）', (tester) async {
      await tester.pumpWidget(
        _host(
          brightness: Brightness.dark,
          child: LiquidAppBarSkin(
            child: Builder(
              builder: (context) {
                final scheme = Theme.of(context).colorScheme;
                return SizedBox(
                  width: 100,
                  height: 30,
                  child: ColoredBox(
                    color: scheme.surface,
                    child: Icon(Icons.arrow_back, color: scheme.onSurface),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('LiquidSheetShell：solid 档冒烟（降级面可渲染）', () {
    testWidgets('solid 档渲染＋把手在位＋内容透传＋零 BackdropFilter', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          child: const Align(
            alignment: Alignment.bottomCenter,
            child: LiquidSheetShell(
              child: SizedBox(
                width: 300,
                height: 200,
                child: Center(child: Text('弹层内容')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('弹层内容'), findsOneWidget);
      expect(find.byKey(LiquidSheetShell.handleKey), findsOneWidget);
      expect(find.byType(LiquidGlassPanel), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('深色主题冒烟', (tester) async {
      await tester.pumpWidget(
        _host(
          brightness: Brightness.dark,
          child: const Align(
            alignment: Alignment.bottomCenter,
            child: LiquidSheetShell(
              child: SizedBox(width: 300, height: 120, child: Text('暗色弹层')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('暗色弹层'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('LiquidSheetShell：A3 纪律（>85% 才挂玻璃层）', () {
    testWidgets('动画 0.5/0.85 ⇒ solid 零采样；0.9 ⇒ thick 挂 BackdropFilter', (
      tester,
    ) async {
      LiquidGlassRuntime.overrideForTest(_cap(LiquidGlassTier.fakeGlass));
      final controller = AnimationController(
        vsync: const TestVSync(),
        value: 0.5,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 240,
              child: LiquidSheetShell(
                animation: controller,
                child: const SizedBox(height: 200, child: Text('A3 弹层')),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // 过渡期（0.5 ≤ 0.85）：solid ⇒ 零背景采样。
      expect(find.byType(BackdropFilter), findsNothing);

      // 边界钉「>」语义：恰好 0.85 仍不算 settle（与 liquid_action_sheet 同款判据）。
      controller.value = 0.85;
      await tester.pump();
      expect(find.byType(BackdropFilter), findsNothing);

      // settle（0.9 > 0.85）：thick 真玻璃挂上。
      controller.value = 0.9;
      await tester.pump();
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('A3 弹层'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('animation 缺省 ⇒ 取 ModalRoute 动画（宿主 route 静止即 settle）', (
      tester,
    ) async {
      LiquidGlassRuntime.overrideForTest(_cap(LiquidGlassTier.fakeGlass));
      await tester.pumpWidget(
        _host(
          child: const Align(
            alignment: Alignment.bottomCenter,
            child: LiquidSheetShell(
              child: SizedBox(width: 300, height: 160, child: Text('route 弹层')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // "/" route 动画走完（1.0 > 0.85）⇒ thick ⇒ 有 BackdropFilter。
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });

  group('LiquidSheetShell：约束透明（5 个既有面板的接线生命线）', () {
    testWidgets('满高内容（Column max + Expanded）零溢出、总高恰 = 给定高', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          child: const Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 300,
              width: 300,
              child: LiquidSheetShell(
                child: Column(
                  children: [
                    Expanded(child: ColoredBox(color: _kSeed)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // AiConclusionPanel/PgcIntroPanel/EpisodePanel 全是这种满高形态：
      // 壳若用 Column 追加把手会溢 14px ✗ ⇒ padding 顶区方案必须零溢出。
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(LiquidGlassPanel)).height, 300);
    });

    testWidgets('intrinsic 内容：壳高 = 内容 + 把手区(14)；关把手 = 内容原高', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          child: const Align(
            alignment: Alignment.bottomCenter,
            child: LiquidSheetShell(
              child: SizedBox(
                width: 200,
                height: 200,
                child: ColoredBox(color: _kSeed),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(LiquidGlassPanel)).height,
        200 + LiquidSheetShell.handleZoneHeight,
      );

      await tester.pumpWidget(
        _host(
          child: const Align(
            alignment: Alignment.bottomCenter,
            child: LiquidSheetShell(
              showHandle: false,
              child: SizedBox(
                width: 200,
                height: 200,
                child: ColoredBox(color: _kSeed),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(LiquidSheetShell.handleKey), findsNothing);
      expect(tester.getSize(find.byType(LiquidGlassPanel)).height, 200);
    });
  });

  group('LiquidSheetShell：内容手势透传（把手 IgnorePointer 不抢点击）', () {
    testWidgets('壳内按钮点击回调照常触发', (tester) async {
      int taps = 0;
      await tester.pumpWidget(
        _host(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: LiquidSheetShell(
              child: SizedBox(
                width: 300,
                height: 160,
                child: Center(
                  child: TextButton(
                    onPressed: () => taps++,
                    child: const Text('关闭'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('关闭'));
      await tester.pump();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
