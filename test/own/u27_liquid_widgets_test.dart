// SPDX-License-Identifier: GPL-3.0-or-later
// ============================================================================
// #27 U5（动态＋我的）接线单测：新 liquid 组件 ＋ TabController 双向同步。
//
// 口径照 test/own/liquid_ui_components_test.dart（#23/#24b 组件套件）：
//   1. **离线夹具**：main() 顶部 installOfflineHttp()（本套件组件不挂网络图，
//      装上纯作防御层，http_offline.dart 头注释的纪律）；
//   2. **档位固定 solid**：LiquidGlassRuntime.overrideForTest(cap(solid)) ⇒
//      不挂 BackdropFilter，只断言结构与回调（顺带钉「solid 档可渲染」降级面）；
//   3. **不碰 Hive**：本套件无 NetworkImgLayer/Pref 读取路径 ⇒ 不起 Hive、
//      **tearDownAll 整段不写**（12 分钟挂死教训：裸 await Hive.close() ✗✓）；
//   4. import 只认 material_ui（fork）——flutter/material 的 Theme 在本 app
//      无人安装（S16），测试宿主也必须装 fork 主题，finder 才不失配。
//
// 覆盖：
//   LiquidTabPillBar（#24b 首页同步模式公共化）：pill 点→切页＋onSelected、
//   滑页→选中 pill 跟随、didUpdateWidget 换 controller 重绑（旧控制器脱钩）、
//   dispose 干净；
//   LiquidMenuTile/LiquidMenuGroup：回调/chevron/深浅双主题冒烟；
//   LiquidFloatingButton：回调＋tooltip；LiquidSolidCard：solid 档零 BackdropFilter。
// ============================================================================

import 'package:PiliPlus/common/widgets/liquid/liquid_floating_button.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_menu_tile.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_pill_bar.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_solid_card.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_tab_pill_bar.dart';
import 'package:PiliPlus/utils/glass_accessibility.dart';
// 见文件头第 4 条：测试宿主必须装 fork 主题（S16 教训）。
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

import 'http_offline.dart';

LiquidGlassCapability _cap(LiquidGlassTier tier) => LiquidGlassCapability(
  tier: tier,
  platform: 'test',
  osVersion: 'unit',
  shaderFilterSupported: false,
  reason: 'u27 liquid widgets test',
);

const Color _kSeed = Color(0xFF00A1D6);

Widget _host({
  required Widget child,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: _kSeed, brightness: brightness),
  ),
  home: Scaffold(body: child),
);

const List<String> _kLabels = ['全部', '投稿', '番剧', '专栏', 'UP'];

/// 双向同步宿主：LiquidTabPillBar + TabBarView 共用一个 TabController
/// （与 pages/dynamics/view.dart 的接线同构：tabBarView + pill 行同控制器）。
class _TabHarness extends StatefulWidget {
  const _TabHarness({this.onSelected});

  final ValueChanged<int>? onSelected;

  @override
  State<_TabHarness> createState() => _TabHarnessState();
}

class _TabHarnessState extends State<_TabHarness>
    with SingleTickerProviderStateMixin {
  late final TabController controller = TabController(
    length: _kLabels.length,
    vsync: this,
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LiquidTabPillBar(
          controller: controller,
          labels: _kLabels,
          onSelected: widget.onSelected,
        ),
        Expanded(
          child: TabBarView(
            controller: controller,
            children: [
              for (final l in _kLabels) Center(child: Text('page-$l')),
            ],
          ),
        ),
      ],
    );
  }
}

/// didUpdateWidget 重绑宿主：运行中换 TabController（旧控制器必须脱钩）。
class _SwapHarness extends StatefulWidget {
  const _SwapHarness({super.key});

  @override
  State<_SwapHarness> createState() => _SwapHarnessState();
}

class _SwapHarnessState extends State<_SwapHarness>
    with TickerProviderStateMixin {
  // 两个 TabController = 两个 Ticker ⇒ 必须 TickerProviderStateMixin
  // （SingleTickerProviderStateMixin 只许一个，第二创建即抛）。
  late final TabController c1 = TabController(length: 3, vsync: this);
  late final TabController c2 = TabController(length: 3, vsync: this);
  bool second = false;

  @override
  void dispose() {
    c1.dispose();
    c2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = second ? c2 : c1;
    return Column(
      children: [
        TextButton(
          onPressed: () => setState(() => second = !second),
          child: const Text('swap'),
        ),
        LiquidTabPillBar(controller: current, labels: const ['a', 'b', 'c']),
        Expanded(
          child: TabBarView(
            controller: current,
            children: const [
              Center(child: Text('page-a')),
              Center(child: Text('page-b')),
              Center(child: Text('page-c')),
            ],
          ),
        ),
      ],
    );
  }
}

int _selectedIndex(WidgetTester tester) =>
    tester.widget<LiquidPillBar>(find.byType(LiquidPillBar)).selectedIndex;

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

  // 刻意**不写 tearDownAll**：本套件不起 Hive；裸 await Hive.close() 在
  // widget 测试环境永久挂起（liquid_ui_components_test 12 分钟教训 ✓✓）。

  group('LiquidTabPillBar 双向同步（#24b 首页模式）', () {
    testWidgets('pill 点 → 切页 + onSelected（语义同原 TabBar.onTap）', (
      tester,
    ) async {
      final tapped = <int>[];
      await tester.pumpWidget(
        _host(child: _TabHarness(onSelected: tapped.add)),
      );
      await tester.pumpAndSettle();
      expect(_selectedIndex(tester), 0);

      await tester.tap(find.text('专栏'));
      await tester.pumpAndSettle();

      expect(tapped, [3]);
      expect(_selectedIndex(tester), 3);
      expect(find.text('page-专栏'), findsOneWidget);
    });

    testWidgets('滑页 → 选中 pill 跟随（controller listener）', (tester) async {
      await tester.pumpWidget(_host(child: const _TabHarness()));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(TabBarView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(_selectedIndex(tester), 1);
      expect(find.text('page-投稿'), findsOneWidget);
    });

    testWidgets('didUpdateWidget 换 controller：新控制器同步、旧控制器脱钩', (
      tester,
    ) async {
      final key = GlobalKey<_SwapHarnessState>();
      await tester.pumpWidget(_host(child: _SwapHarness(key: key)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('swap'));
      await tester.pumpAndSettle();

      // 新控制器驱动：c2 切页 ⇒ pill 跟随。
      key.currentState!.c2.animateTo(2);
      await tester.pumpAndSettle();
      expect(_selectedIndex(tester), 2);

      // 旧控制器脱钩：c1 再动 ⇒ pill 不动（listener 已 remove）。
      key.currentState!.c1.animateTo(1);
      await tester.pumpAndSettle();
      expect(_selectedIndex(tester), 2);
    });

    testWidgets('dispose 干净：摘树不抛（removeListener 生命周期齐）', (
      tester,
    ) async {
      await tester.pumpWidget(_host(child: const _TabHarness()));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('LiquidMenuTile / LiquidMenuGroup 菜单行', () {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('回调/chevron/组内发丝分隔（${brightness.name}）', (
        tester,
      ) async {
        int taps = 0;
        await tester.pumpWidget(
          _host(
            brightness: brightness,
            child: LiquidMenuGroup(
              children: [
                LiquidMenuTile(
                  icon: Icons.star_border,
                  label: '我的收藏',
                  onTap: () => taps++,
                ),
                const LiquidMenuTile(
                  icon: Icons.settings_outlined,
                  label: '设置',
                  chevron: false,
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('我的收藏'));
        await tester.pump();
        expect(taps, 1);

        // 跳转行有 chevron、开关行没有 ⇒ 全树恰好 1 个。
        expect(find.byIcon(Icons.chevron_right), findsOneWidget);
        // solid 卡组：一组一个壳。
        expect(find.byType(LiquidSolidCard), findsOneWidget);
      });
    }
  });

  group('LiquidFloatingButton / LiquidSolidCard 降级面', () {
    testWidgets('悬浮钮：回调 + tooltip 保留', (tester) async {
      int taps = 0;
      await tester.pumpWidget(
        _host(
          child: Center(
            child: LiquidFloatingButton(
              icon: Icons.add,
              tooltip: '发布动态',
              onPressed: () => taps++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('发布动态'), findsOneWidget);
      await tester.tap(find.byTooltip('发布动态'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('solid 档卡壳可渲染且零 BackdropFilter（列表卡纪律）', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          child: const Center(
            child: LiquidSolidCard(
              child: ColoredBox(
                color: _kSeed,
                child: SizedBox(width: 120, height: 60),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LiquidGlassSurface), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
