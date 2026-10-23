// SPDX-License-Identifier: GPL-3.0-or-later
// ============================================================================
// ui_liquidglass 暂存区组件单测（排期 #23 验收缺口"单测"的补齐）。
//
// 位置：`test/own/` —— 门禁第 3 项跑的就是 `flutter test test/own`
// （没被门禁覆盖的测试等于没有测试，与 glass_accessibility_test.dart 同一约定）。
//
// 三条口径：
//   1. **不依赖网络 / 真实字体**：只用 mock 数据；`GlassAccessibility` 里
//      对 Pref 的读取在存储未初始化时被它自己的 try/catch 兜住（按"关"）；
//      组件声明的 `LiquidFontFamily.text` 在测试环境取不到字体也无妨（回落 Ahem）。
//      例外：#24b 起 LiquidVideoCard 封面走 NetworkImgLayer（上游同口径），其
//      build 路径会读 `Pref.picQuality`/`Pref.reduceLuxColor`（GStorage.setting）——
//      setUpAll 在系统临时目录初始化 Hive 并只接 setting 箱（不碰 path_provider/
//      GStorage.init 的其余箱）， hermetic 且与生产口径一致。
//   2. **档位固定 solid**：`LiquidGlassRuntime.overrideForTest(cap(solid))` ⇒
//      组件树不挂 BackdropFilter，本文件只断言**结构与回调**（玻璃渲染档位本身
//      由 kit 侧测试负责，不在这里重复覆盖）。
//   3. **接缝清理**：setUp/tearDown 都跑 `GlassAccessibility.debugReset()` +
//      `LiquidGlassRuntime.overrideForTest(null)` + 弹层防重入守卫复位。
//
// 覆盖清单（每组件至少一条浅/深参数化冒烟 + 交互断言）：
//   LiquidPressable（缩放/过冲回弹/减弱动效阶跃/禁用/越界抬手/手势共存/ripple 开关）、
//   LiquidPillBar、LiquidFloatingNav、LiquidVideoCard（含 C1 更多按钮契约）、
//   LiquidTopBar、LiquidCommentTile、showLiquidActionSheet（先 pop 再回调 / 取消 /
//   防重入 / useRootNavigator / 键盘 viewInsets / A3 挂载时机 / 超高不溢出）、
//   预览页（明暗钮热区不重叠的回归位 + 动效小节存在）。
// ============================================================================

import 'dart:io';

import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_action_sheet.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_comment_tile.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_floating_nav.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_motion.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_pill_bar.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_top_bar.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_video_card.dart';
import 'package:PiliPlus/ui_liquidglass/previews/liquid_components_preview.dart';
import 'package:PiliPlus/ui_liquidglass/previews/mock_data.dart';
import 'package:PiliPlus/utils/glass_accessibility.dart';
import 'package:PiliPlus/utils/storage.dart';
// 注意：**必须 import material_ui（fork）而不是 flutter/material**——
// 组件侧已全部切到 fork（#25 真机取证：flutter/material 的 Theme 在本 app
// 无人安装，Theme.of 静默落亮色 fallback ⇒ 深色模式黑字糊黑卡）。
// 测试若留在 flutter/material，find.byType(InkWell/Material) 与组件内
// fork 类型不匹配，finder 全假阴性（本会话实证 -15）。
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

import 'http_offline.dart';

/// 造一个指定档位的 capability（`overrideForTest` 要用，同 glass_accessibility_test）。
LiquidGlassCapability _cap(LiquidGlassTier tier) => LiquidGlassCapability(
  tier: tier,
  platform: 'test',
  osVersion: 'unit',
  shaderFilterSupported: false,
  reason: 'liquid ui components test',
);

/// 主题种子色（B 站蓝）：深浅两套都由它派生，断言与平台默认主题无关。
const Color _kSeed = Color(0xFF00A1D6);

/// flutter_test 默认窗口 800x600；键盘避让与热区两条断言要用绝对坐标算。
const double _kScreenWidth = 800;
const double _kScreenHeight = 600;

/// 按压目标方块：**必须自己可命中**（[ColoredBox] 会绘制 ⇒ `hitTestSelf` 为真）。
/// 裸 [SizedBox] 只有尺寸、不可命中，而 LiquidPressable 的 Listener 是
/// `HitTestBehavior.deferToChild` ⇒ 那种 child 按下去不会有反馈（组件的刻意约定，
/// 见 liquid_motion.dart 的类注释）。
const Widget _kPressPad = ColoredBox(
  color: Color(0xFF00A1D6),
  child: SizedBox(width: 120, height: 60),
);

/// 组件宿主：MaterialApp + Scaffold（InkWell 之流需要 Material 载体）。
///
/// [keyboardInset] / [viewPaddingBottom] 经 `MaterialApp.builder` 注入，
/// **必须注在 Navigator 之内**：包在 MaterialApp 外面会被 App 自己下发的
/// MediaQuery 顶掉（WidgetsApp 按 view 的度量重建 MediaQuery）。
Widget _host({
  required Widget child,
  Brightness brightness = Brightness.light,
  List<NavigatorObserver> observers = const <NavigatorObserver>[],
  double keyboardInset = 0,
  double viewPaddingBottom = 0,
}) {
  final bool overrideMedia = keyboardInset != 0 || viewPaddingBottom != 0;
  return MaterialApp(
    navigatorObservers: observers,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _kSeed, brightness: brightness),
    ),
    builder: (context, appChild) {
      if (!overrideMedia) return appChild!;
      final MediaQueryData data = MediaQuery.of(context);
      return MediaQuery(
        data: data.copyWith(
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
          viewPadding: EdgeInsets.only(bottom: viewPaddingBottom),
          padding: EdgeInsets.only(bottom: viewPaddingBottom),
        ),
        child: appChild!,
      );
    },
    home: Scaffold(body: child),
  );
}

/// 读当前缩放：[LiquidPressable] 自己那层 Transform。
/// （本文件用例里被按压的 child 不含二级 Transform ⇒ `.first` 就是它。）
///
/// ⚠️ 取 `transform.storage[0]`（矩阵 x 轴分量）而**不是** `getMaxScaleOnAxis()`：
/// `Transform.scale(scale: s)` 生成的矩阵 **z 轴固定为 1.0**，而
/// `getMaxScaleOnAxis()` 返回三轴里的最大值 ⇒ s < 1 时它恒等于 1.0，
/// 根本读不出缩小（这个坑在本文件初版里让所有按压断言全部假失败）。
/// 卡片的有效命中点＝封面区（#24b 起根为 Align(topCenter)：tight 约束下组件盒
/// 含底部透明余量，那部分按设计不响应指针 ⇒ byType 中心不再是合法命中点）。
Finder _cardHit() => find.descendant(
      of: find.byType(LiquidVideoCard),
      matching: find.byType(AspectRatio),
    );

double _scaleOf(WidgetTester tester) {
  final Transform transform = tester.widget<Transform>(
    find
        .descendant(
          of: find.byType(LiquidPressable),
          matching: find.byType(Transform),
        )
        .first,
  );
  return transform.transform.storage[0];
}

/// 按下并推进到"按到底"（默认 120ms > 90ms 的进场时长 ⇒ 缩放已到位）。
Future<TestGesture> _pressDown(
  WidgetTester tester,
  Finder target, {
  Duration hold = const Duration(milliseconds: 120),
}) async {
  final TestGesture gesture = await tester.createGesture();
  await gesture.down(tester.getCenter(target));
  await tester.pump();
  await tester.pump(hold);
  return gesture;
}

/// 记录 pop 次数的导航观察者（钉死"先 pop 再回调"的**顺序**契约）。
class _PopCounter extends NavigatorObserver {
  int pops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops += 1;
  }
}

/// 记录 push 次数的导航观察者：挂在**嵌套 Navigator** 上，它只看得到推到自己
/// 这一层的 route ⇒ 计数增量就是"useRootNavigator 有没有跳过当前层"的直接读数。
class _PushCounter extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes += 1;
  }
}

/// 弹层宿主：把"调用 showLiquidActionSheet"收进 State 的**同步**方法里。
///
/// 为什么要这么绕：测试体是 async 的，若把 `BuildContext` 存进局部变量再在
/// `await tester.pump…` 之后使用，会命中 `use_build_context_synchronously`
/// —— 这条 lint 防的是真实缺陷（await 之后上下文可能已失效）。改用
/// `State.context` 的同步方法 ⇒ 调用点不碰上下文；测试用 `tap(打开弹层)`
/// 触发，防重入用例则经 [onFuture] 拿到每次调用的返回值做断言。
class _SheetHost extends StatefulWidget {
  const _SheetHost({
    this.labels = const <String>['稍后再看', '不感兴趣'],
    this.useRootNavigator = false,
    this.onItemTap,
    this.onFuture,
  });

  /// 菜单条目文案（第一条挂 [onItemTap]）。
  final List<String> labels;

  /// 透传给 showLiquidActionSheet 的 useRootNavigator。
  final bool useRootNavigator;

  /// 第一条目的回调（验证"先 pop 再回调"）。
  final VoidCallback? onItemTap;

  /// 每次调用 showLiquidActionSheet 都把它返回的 Future 交出去。
  final ValueChanged<Future<void>>? onFuture;

  @override
  State<_SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends State<_SheetHost> {
  /// 打开弹层（同步方法 ⇒ 内部用 State.context 合法）。
  void open() {
    final Future<void> future = showLiquidActionSheet(
      context,
      title: '视频操作',
      useRootNavigator: widget.useRootNavigator,
      items: <LiquidActionSheetItem>[
        for (int i = 0; i < widget.labels.length; i++)
          LiquidActionSheetItem(
            label: widget.labels[i],
            icon: LiquidIcons.history,
            onTap: i == 0 ? widget.onItemTap : null,
          ),
      ],
    );
    widget.onFuture?.call(future);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: TextButton(onPressed: open, child: const Text('打开弹层')),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 离线夹具（M3 提前启用，task-122 ①）：本文件头注释第 1 条写的"不依赖网络"
  // 在 preview 页（其 mock 数据带 URL ⇒ 会挂 NetworkImgLayer 真发请求 ⇒
  // 图片流不结束 ⇒ pumpAndSettle 永久 loading ⇒ 曾有 12 分钟 tearDownAll 超时 ✗）
  // 之前并不成立；装上它之后**任何请求即刻 404 + 空体** ⇒ 断言可跑、套件不再挂 ✓。
  // 只装在本套件（Lead 裁定：先小爆炸半径证机制；全 test/own 是否升格由 Lead 收口时裁 ✓）。
  installOfflineHttp();

  setUpAll(() async {
    // #24b 封面接线（NetworkImgLayer）的存储夹具：其 build 读 Pref.picQuality/
    // reduceLuxColor（GStorage.setting）。在临时目录起 Hive、只接 setting 箱——
    // 不走 GStorage.init（它依赖 path_provider，widget test 里不可用）。
    final Directory tmp = await Directory.systemTemp.createTemp('liquid_ui_test');
    Hive.init(tmp.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.localCache = await Hive.openBox('localCache');
  });

  tearDownAll(() async {
    // #26a（task-122）根因定位：**卡死点一直是这里**，不是网络 ✗。
    // 判据：只跑预览页两组（用例 4/4 全过 ✓）后，卡的是 `tearDownAll` ⇒
    // `await Hive.close()` 在 widget 测试环境下**永久挂起** ✗ ⇒ 文件级
    // "Test timed out after 12 minutes" ✗（此前我一直误判为图片流不结束 ✗）。
    // 处置：测试进程结束即回收临时目录，这里不做 close；将来若确需清理，
    // 用带超时的写法（`Hive.close().timeout(...)`），**不要裸 await** ✓。
  });

  setUp(() {
    GlassAccessibility.debugReset();
    resetLiquidActionSheetGuard();
    // 固定 solid 档：不挂 BackdropFilter，只测结构与回调（档位渲染由 kit 覆盖）。
    LiquidGlassRuntime.overrideForTest(_cap(LiquidGlassTier.solid));
  });

  tearDown(() {
    GlassAccessibility.debugReset();
    LiquidGlassRuntime.overrideForTest(null);
    resetLiquidActionSheetGuard();
  });

  // ══════════════════════════════════ LiquidPressable（动效原语）
  group('LiquidPressable 果冻按压', () {
    testWidgets('按下缩小、抬手带过冲弹回，child 的 onTap 仍生效', (tester) async {
      int taps = 0;
      await tester.pumpWidget(
        _host(
          child: Center(
            child: LiquidPressable(
              pressedScale: 0.8,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  taps += 1;
                },
                child: const SizedBox(width: 160, height: 90),
              ),
            ),
          ),
        ),
      );
      expect(_scaleOf(tester), 1.0, reason: '静止态必须精确等于 1.0');

      final TestGesture gesture = await _pressDown(tester, find.byType(LiquidPressable));
      expect(_scaleOf(tester), lessThan(1.0), reason: '按下 ⇒ scale 缩下去');
      expect(_scaleOf(tester), closeTo(0.8, 0.001), reason: '90ms easeOut 走完即到位');

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // 果冻的证据：回弹中段**越过静止值**（reverseCurve 过冲 ⇒ 归一化进度短暂为负）
      expect(_scaleOf(tester), greaterThan(1.0), reason: '回弹要有过冲，否则只是普通缩放');

      await tester.pumpAndSettle();
      expect(_scaleOf(tester), closeTo(1.0, 0.0001), reason: '最终落回静止值');
      expect(taps, 1, reason: 'Listener 不进手势竞技场 ⇒ 不抢 child 的点击');
      expect(tester.takeException(), isNull);
    });

    testWidgets('减弱动效（debugReduceMotion）⇒ 一帧阶跃到位、不留动画尾巴', (tester) async {
      GlassAccessibility.debugReduceMotion = true;
      await tester.pumpWidget(
        _host(child: const Center(child: LiquidPressable(pressedScale: 0.9, child: _kPressPad))),
      );

      final TestGesture gesture = await tester.createGesture();
      await gesture.down(tester.getCenter(find.byType(LiquidPressable)));
      await tester.pump(); // 只推进一帧，不给 90ms 的余地
      expect(_scaleOf(tester), closeTo(0.9, 0.0001), reason: '时长为 0 ⇒ 直接赋值阶跃到底');

      await gesture.up();
      await tester.pump();
      expect(_scaleOf(tester), 1.0, reason: '抬手同样阶跃回位（无回弹段）');
      // 没有挂起的动画：一次 pump 就收敛（否则 teardown 报 pending timer）
      expect(await tester.pumpAndSettle(const Duration(milliseconds: 100)), 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('enabled=false ⇒ 不响应按压', (tester) async {
      await tester.pumpWidget(
        _host(
          child: const Center(
            child: LiquidPressable(pressedScale: 0.8, enabled: false, child: _kPressPad),
          ),
        ),
      );
      final TestGesture gesture = await _pressDown(tester, find.byType(LiquidPressable));
      expect(_scaleOf(tester), 1.0, reason: '禁用态不参与动效');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_scaleOf(tester), 1.0);
    });

    testWidgets('在组件外抬手也能回位（down 时缓存的命中路径被复用）', (tester) async {
      await tester.pumpWidget(
        _host(child: const Center(child: LiquidPressable(pressedScale: 0.85, child: _kPressPad))),
      );
      final TestGesture gesture = await _pressDown(tester, find.byType(LiquidPressable));
      expect(_scaleOf(tester), lessThan(1.0));
      await gesture.moveTo(const Offset(760, 560)); // 滑到组件外
      await tester.pump();
      await gesture.up(); // 在组件外抬手
      await tester.pumpAndSettle();
      expect(_scaleOf(tester), closeTo(1.0, 0.0001), reason: '不能卡在按压态');
    });

    testWidgets('ripple 默认关；显式开启才叠一层 InkWell', (tester) async {
      Finder inkInPressable = find.descendant(
        of: find.byType(LiquidPressable),
        matching: find.byType(InkWell),
      );
      await tester.pumpWidget(
        _host(
          child: const Center(
            child: LiquidPressable(child: SizedBox(width: 60, height: 60)),
          ),
        ),
      );
      expect(inkInPressable, findsNothing, reason: '列表卡默认只要缩放，不要水波纹');

      await tester.pumpWidget(
        _host(
          child: Center(
            child: LiquidPressable(
              ripple: true,
              borderRadius: BorderRadius.circular(12),
              child: const SizedBox(width: 60, height: 60),
            ),
          ),
        ),
      );
      inkInPressable = find.descendant(
        of: find.byType(LiquidPressable),
        matching: find.byType(InkWell),
      );
      expect(inkInPressable, findsOneWidget, reason: 'ripple=true 时叠 InkWell + 透明 Material');
      expect(
        find.descendant(
          of: find.byType(LiquidPressable),
          matching: find.byType(Material),
        ),
        findsOneWidget,
      );
    });
  });

  // ══════════════════════════════════ LiquidPillBar
  group('LiquidPillBar', () {
    for (final Brightness brightness in Brightness.values) {
      testWidgets('$brightness：冒烟 + 点选回调 + 玻璃片跟着选中走', (tester) async {
        int? tapped;
        Widget bar(int index) => SizedBox(
          width: 500,
          child: LiquidPillBar(
            items: mockChannels,
            selectedIndex: index,
            onSelected: (int i) {
              tapped = i;
            },
          ),
        );

        await tester.pumpWidget(_host(brightness: brightness, child: bar(1)));
        await tester.pumpAndSettle();
        expect(find.byType(LiquidGlassSurface), findsOneWidget, reason: '只有选中项挂玻璃');
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('glass')),
            matching: find.text('推荐'),
          ),
          findsOneWidget,
          reason: '初始 selectedIndex=1 ⇒ 玻璃片在"推荐"上',
        );

        await tester.tap(find.text('热门'));
        await tester.pump();
        expect(tapped, 2, reason: '回调给的是 index，不是 label');

        // 宿主 setState 后的下一帧：selectedIndex 变 2
        await tester.pumpWidget(_host(brightness: brightness, child: bar(2)));
        await tester.pumpAndSettle();
        expect(find.byType(LiquidGlassSurface), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('glass')),
            matching: find.text('热门'),
          ),
          findsOneWidget,
          reason: '玻璃片切到新选中项（A2 的 ValueKey 结构未被按压反馈破坏）',
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('plain')),
            matching: find.text('推荐'),
          ),
          findsOneWidget,
          reason: '原选中项落回 plain 层',
        );
        expect(find.byType(LiquidPressable), findsNWidgets(mockChannels.length));
      });

      testWidgets('$brightness：B2 选中项自动滚回视口（旗2 族根·窄视口验证）', (tester) async {
        // 窄视口（200px）＋ 8 个长标签 ⇒ 行可滚动；切到末位选中 ⇒ 自动 ensureVisible。
        final items = <LiquidPillBarItem>[
          for (int i = 0; i < 8; i++)
            LiquidPillBarItem(id: 'i$i', label: 'channel$i-long'),
        ];
        Widget bar(int index) => SizedBox(
          width: 200,
          child: LiquidPillBar(items: items, selectedIndex: index),
        );

        await tester.pumpWidget(
          _host(brightness: brightness, child: bar(0)),
        );
        await tester.pumpAndSettle();

        final barRect = tester.getRect(find.byType(LiquidPillBar));
        bool visible(String label) {
          final finder = find.text(label);
          if (finder.evaluate().isEmpty) return false;
          final r = tester.getRect(finder);
          return r.left >= barRect.left - 1 && r.right <= barRect.right + 1;
        }

        expect(
          visible('channel7-long'),
          isFalse,
          reason: '选中 0 时末位项在视口外 ⇒ 行确实可滚（旗2 的前提成立）',
        );

        // 换 selectedIndex ⇒ didUpdateWidget 后 ensureVisible 把末位项滚回
        await tester.pumpWidget(
          _host(brightness: brightness, child: bar(7)),
        );
        await tester.pumpAndSettle();
        expect(
          visible('channel7-long'),
          isTrue,
          reason: '选中末位项 ⇒ B2 自动滚回视口（对齐 0.5）',
        );
      });
    }
  });

  // ══════════════════════════════════ LiquidFloatingNav
  group('LiquidFloatingNav', () {
    for (final Brightness brightness in Brightness.values) {
      testWidgets('$brightness：冒烟 + 点选回调 + 选中项 = 亮着的玻璃片', (tester) async {
        int? tapped;
        Widget nav(int index) => LiquidFloatingNav(
          items: mockNavItems,
          selectedIndex: index,
          onSelected: (int i) {
            tapped = i;
          },
        );

        await tester.pumpWidget(_host(brightness: brightness, child: nav(0)));
        await tester.pumpAndSettle();
        // 导航条 1 块 + 每个 tab 各 1 块玻璃片（未选中那两片 opacity=0，仍在树上）
        expect(find.byType(LiquidGlassSurface), findsNWidgets(1 + mockNavItems.length));
        // 只有一片处于"亮"（opacity 目标值 1）⇒ 真玻璃预算的语义仍成立
        expect(
          find.byWidgetPredicate((Widget w) => w is AnimatedOpacity && w.opacity == 1),
          findsOneWidget,
        );

        // 每个 tab 的文案在树里出现两次（plain 层 + 玻璃片层，A2 的交叉淡入结构），
        // 两层同位置同尺寸 ⇒ 取 .first 即可，命中的就是这一项。
        await tester.tap(find.text('动态').first);
        await tester.pump();
        expect(tapped, 1, reason: '回调拿到 index');

        await tester.pumpWidget(_host(brightness: brightness, child: nav(1)));
        await tester.pumpAndSettle();
        final Finder lit = find.byWidgetPredicate(
          (Widget w) => w is AnimatedOpacity && w.opacity == 1,
        );
        expect(lit, findsOneWidget, reason: '仍然只有一片亮');
        expect(
          find.descendant(of: lit, matching: find.text('动态')),
          findsOneWidget,
          reason: '亮着的那片属于"动态"，不是别的项',
        );
        expect(find.byType(LiquidPressable), findsNWidgets(mockNavItems.length));
      });
    }

    testWidgets('底部留白叠加安全区（纪律 C2）', (tester) async {
      await tester.pumpWidget(
        _host(
          viewPaddingBottom: 24,
          child: const LiquidFloatingNav(items: mockNavItems, selectedIndex: 0),
        ),
      );
      await tester.pumpAndSettle();
      final Rect bar = tester.getRect(find.byType(LiquidGlassSurface).first);
      expect(
        _kScreenHeight - bar.bottom,
        closeTo(12 + 24, 0.01),
        reason: '12 + MediaQuery.viewPaddingOf(context).bottom',
      );
    });

    testWidgets('按下 tab 会缩小（pressedScale 0.92）', (tester) async {
      await tester.pumpWidget(
        _host(child: const LiquidFloatingNav(items: mockNavItems, selectedIndex: 0)),
      );
      final TestGesture gesture = await _pressDown(tester, find.byType(LiquidPressable).first);
      expect(_scaleOf(tester), closeTo(0.92, 0.001));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_scaleOf(tester), closeTo(1.0, 0.0001));
    });
  });

  // ══════════════════════════════════ LiquidVideoCard
  group('LiquidVideoCard', () {
    for (final Brightness brightness in Brightness.values) {
      // 本组一律用空 coverUrl 的 data：**widget test 不挂载真图**——
      // CachedNetworkImage（ce fork）在 fake-async 区会留下永久挂起操作、把
      // `flutter test` 吊死在 isolate 收尾（已实证：最小复现 + 15s 排水无效）。
      // 非空 coverUrl ⇒ NetworkImgLayer 的接线由 u24b_cover_wiring_test.dart
      // 源码绊线钉死；真实出图由双端目视验收截图兜底。
      final LiquidVideoCardData one = LiquidVideoCardData(
        title: mockVideos[0].title,
        coverUrl: '',
        author: mockVideos[0].author,
        playText: mockVideos[0].playText,
        danmakuText: mockVideos[0].danmakuText,
        durationText: mockVideos[0].durationText,
      );

      Widget card({VoidCallback? onTap, VoidCallback? onLongPress, VoidCallback? onMoreTap}) =>
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 180,
              child: LiquidVideoCard(
                data: one,
                onTap: onTap,
                onLongPress: onLongPress,
                onMoreTap: onMoreTap,
              ),
            ),
          );

      testWidgets('$brightness 冒烟：内容齐全 + 整卡包 LiquidPressable + solid 档', (tester) async {
        await tester.pumpWidget(_host(brightness: brightness, child: card()));
        expect(find.text(one.title), findsOneWidget);
        expect(find.text('好蛙TV'), findsOneWidget);
        expect(find.text('02:00:27'), findsOneWidget);
        expect(find.byType(LiquidPressable), findsOneWidget);
        // 纪律：列表卡片**永不真玻璃** ⇒ 容器必须是 solid 档
        final LiquidGlassSurface surface = tester.widget(
          find.descendant(
            of: find.byType(LiquidVideoCard),
            matching: find.byType(LiquidGlassSurface),
          ),
        );
        expect(surface.material, LiquidGlassMaterial.solid);
      });

      testWidgets('$brightness：onTap / onLongPress 各自工作（按压反馈不抢手势）', (tester) async {
        int taps = 0;
        int longs = 0;
        await tester.pumpWidget(
          _host(
            brightness: brightness,
            child: card(
              onTap: () {
                taps += 1;
              },
              onLongPress: () {
                longs += 1;
              },
            ),
          ),
        );
        // #24b 起卡片根是 Align(topCenter)：tight 约束（Scaffold body/网格 cell）下
        // 组件盒=整 cell、命中区=玻璃本体（顶部内容区）⇒ 点 byType 中心会落进
        // 透明余量（那本来就不该响应）⇒ 命中点取封面（必在玻璃内）。
        await tester.tap(_cardHit());
        await tester.pump();
        expect(taps, 1);
        expect(longs, 0);

        await tester.longPress(_cardHit());
        await tester.pumpAndSettle();
        expect(longs, 1);
        expect(taps, 1, reason: '长按不应附带触发点击');
      });

      testWidgets('$brightness：更多按钮契约（C1）—— onMoreTap 缺省回退 onLongPress', (tester) async {
        int longs = 0;
        await tester.pumpWidget(
          _host(
            brightness: brightness,
            child: card(
              onLongPress: () {
                longs += 1;
              },
            ),
          ),
        );
        await tester.tap(find.byIcon(LiquidIcons.more));
        await tester.pump();
        expect(longs, 1, reason: '只传 onLongPress 时点"更多"= 长按语义，杜绝死按钮');
      });

      testWidgets('$brightness：更多按钮契约（C1）—— 显式 onMoreTap 优先且不落到长按', (tester) async {
        int longs = 0;
        int moreTaps = 0;
        await tester.pumpWidget(
          _host(
            brightness: brightness,
            child: card(
              onLongPress: () {
                longs += 1;
              },
              onMoreTap: () {
                moreTaps += 1;
              },
            ),
          ),
        );
        await tester.tap(find.byIcon(LiquidIcons.more));
        await tester.pump();
        expect(moreTaps, 1);
        expect(longs, 0);
      });

      testWidgets('$brightness：封面渲染契约——空 coverUrl 不挂 NetworkImgLayer（连请求都不发），走 explore 占位', (tester) async {
        // #24b 验收实测发现：封面曾停留在暂存期"不发请求的占位" ⇒ 首页推荐流全卡无图。
        // 非空 coverUrl ⇒ NetworkImgLayer(src: data.coverUrl) 的接线由
        // u24b_cover_wiring_test.dart（S15 同款源码绊线）钉死——这里**故意不挂载**
        // 真图：CachedNetworkImage 在 widget test 的 fake-async 区会留下永久挂起
        // 操作、把 `flutter test` 吊死在 isolate 收尾（最小复现 + 15s 排水均实证）。
        const LiquidVideoCardData noCover = LiquidVideoCardData(
          title: 't',
          coverUrl: '',
          author: 'a',
        );
        await tester.pumpWidget(
          _host(
            brightness: brightness,
            child: const Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 180, child: LiquidVideoCard(data: noCover)),
            ),
          ),
        );
        expect(find.byType(NetworkImgLayer), findsNothing);
        expect(find.byIcon(LiquidIcons.explore), findsOneWidget);
      });

      testWidgets('$brightness：按下卡片缩到 0.96（联动动效反馈）', (tester) async {
        await tester.pumpWidget(_host(brightness: brightness, child: card()));
        expect(_scaleOf(tester), 1.0);
        final TestGesture gesture = await _pressDown(tester, _cardHit());
        expect(_scaleOf(tester), closeTo(0.96, 0.001), reason: '大卡用 0.96 的温和量级');
        await gesture.up();
        await tester.pumpAndSettle();
        expect(_scaleOf(tester), closeTo(1.0, 0.0001));
      });

      testWidgets('$brightness：徽标/日期前缀/搜索高亮分段三通道（#25 结果卡）', (tester) async {
        await tester.pumpWidget(
          _host(
            brightness: brightness,
            child: const Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 180,
                child: LiquidVideoCard(
                  data: LiquidVideoCardData(
                    title: '纯文本标题',
                    coverUrl: '',
                    author: '作者乙',
                    badgeText: '课堂',
                    dateText: '3天前',
                    titleSegments: [
                      (isEm: false, text: '测试'),
                      (isEm: true, text: '搜索'),
                      (isEm: false, text: '标题'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        // 徽标 chip（封面右上）
        expect(find.text('课堂'), findsOneWidget);
        // 作者行日期前缀（双空格分隔对齐上游 VideoCardH）
        expect(find.text('3天前  作者乙'), findsOneWidget);
        // 高亮分段：Text.rich 三段子文本，em 段带样式覆盖、普通段不带
        final Text title = tester.widget(
          find.byWidgetPredicate(
            (w) =>
                w is Text &&
                w.textSpan != null &&
                w.textSpan!.toPlainText() == '测试搜索标题',
          ),
        );
        final spans = (title.textSpan! as TextSpan).children!.cast<TextSpan>();
        expect(spans.length, 3);
        expect(spans[1].style?.color, isNotNull, reason: 'em 段必须有着色覆盖');
        expect(spans[0].style, isNull);
        expect(spans[2].style, isNull);
        // 有分段时纯文本标题不再出现（两路互斥）
        expect(find.text('纯文本标题'), findsNothing);
      });

      testWidgets('$brightness：三通道缺省 ⇒ 旧行为不变（#24b 回归闸）', (tester) async {
        await tester.pumpWidget(_host(brightness: brightness, child: card()));
        expect(find.text(one.title), findsOneWidget, reason: '纯文本标题路径不变');
        expect(find.text(one.author), findsOneWidget, reason: '作者行无日期前缀');
        expect(find.text('课堂'), findsNothing, reason: 'badgeText 缺省空串 ⇒ 无徽标');
      });
    }
  });

  // ══════════════════════════════════ LiquidTopBar / LiquidCommentTile
  group('LiquidTopBar 与 LiquidCommentTile', () {
    for (final Brightness brightness in Brightness.values) {
      testWidgets('$brightness：顶栏冒烟 + 三条热区回调', (tester) async {
        int hits = 0;
        await tester.pumpWidget(
          _host(
            brightness: brightness,
            child: LiquidTopBar(
              onSearchTap: () {
                hits += 1;
              },
              onNotificationTap: () {
                hits += 1;
              },
              onAvatarTap: () {
                hits += 1;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(LiquidGlassSurface), findsOneWidget);
        expect(find.text('搜索bilibili'), findsOneWidget);

        await tester.tap(find.text('搜索bilibili'));
        await tester.tap(find.byIcon(LiquidIcons.notifications));
        await tester.tap(find.byType(CircleAvatar));
        await tester.pump();
        expect(hits, 3, reason: '搜索 / 通知 / 头像都点得动');
      });

      testWidgets('$brightness：评论项冒烟 + 点赞/回复回调', (tester) async {
        int likes = 0;
        int replies = 0;
        await tester.pumpWidget(
          _host(
            brightness: brightness,
            child: ListView(
              children: <Widget>[
                for (final LiquidCommentData comment in mockComments)
                  LiquidCommentTile(
                    // 离线纪律（#26a 头像接线）：widget 测试只走 avatarUrl == null
                    // 的占位圆路径——非空头像会挂 NetworkImgLayer 真发请求，
                    // flutter_test 的 HttpClient 打回 400 且图片流不结束 ⇒
                    // pumpAndSettle 永久 loading（本套件曾因此 -1 + 12 分钟超时 ✗）。
                    // **非空头像的接线由源码绊线钉**：
                    // `test/own/u26a_avatar_wiring_test.dart` ✓（此处置空不是功能缺失）。
                    data: LiquidCommentData(
                      userName: comment.userName,
                      content: comment.content,
                      level: comment.level,
                      isUp: comment.isUp,
                      likeCount: comment.likeCount,
                      replyCount: comment.replyCount,
                      timeText: comment.timeText,
                      isLiked: comment.isLiked,
                      isDisliked: comment.isDisliked,
                    ),
                    onLike: () {
                      likes += 1;
                    },
                    onDislike: () {},
                    onReply: () {
                      replies += 1;
                    },
                  ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('好蛙TV'), findsWidgets);
        expect(find.textContaining('前排提示'), findsOneWidget);
        expect(find.text('UP'), findsOneWidget, reason: '第一条是 UP 主');

        await tester.tap(find.byIcon(LiquidIcons.like).first);
        await tester.tap(find.byIcon(LiquidIcons.message).first);
        await tester.pump();
        expect(likes, 1);
        expect(replies, 1);
      });
    }
  });

  // ══════════════════════════════════ showLiquidActionSheet
  group('showLiquidActionSheet', () {
    testWidgets('条目点击：先 pop 再回调', (tester) async {
      final _PopCounter counter = _PopCounter();
      int? popsAtCallback;
      await tester.pumpWidget(
        _host(
          observers: <NavigatorObserver>[counter],
          child: _SheetHost(
            onItemTap: () {
              popsAtCallback = counter.pops;
            },
          ),
        ),
      );
      await tester.tap(find.text('打开弹层'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('视频操作'), findsOneWidget);
      expect(find.text('稍后再看'), findsOneWidget);
      expect(find.text('不感兴趣'), findsOneWidget);

      await tester.tap(find.text('稍后再看'));
      await tester.pumpAndSettle();
      expect(popsAtCallback, 1, reason: '回调发生时 route 已经 pop（契约：先关层再回调）');
      expect(find.text('稍后再看'), findsNothing);
      expect(isLiquidActionSheetOpen, isFalse, reason: '关闭后守卫复位');
    });

    testWidgets('取消按钮：只关闭，不触发条目回调', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        _host(
          child: _SheetHost(
            onItemTap: () {
              tapped = true;
            },
          ),
        ),
      );
      await tester.tap(find.text('打开弹层'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('稍后再看'), findsNothing);
      expect(tapped, isFalse);
      expect(isLiquidActionSheetOpen, isFalse);
    });

    testWidgets('防重入：连开两次只出一层，第二次立刻返回', (tester) async {
      final List<Future<void>> futures = <Future<void>>[];
      await tester.pumpWidget(_host(child: _SheetHost(onFuture: futures.add)));

      // 弹层的模态遮罩会挡住"打开弹层"按钮 ⇒ 这里直接同步调 State 的方法，
      // 模拟"连续两次长按两张卡片"这条最真实的撞车路径。
      tester.state<_SheetHostState>(find.byType(_SheetHost)).open();
      expect(isLiquidActionSheetOpen, isTrue, reason: '第一次调用把守卫占住了');
      tester.state<_SheetHostState>(find.byType(_SheetHost)).open();

      expect(futures.length, 2);
      bool firstDone = false;
      bool secondDone = false;
      futures[0].whenComplete(() {
        firstDone = true;
      });
      expect(isLiquidActionSheetOpen, isTrue);
      futures[1].whenComplete(() {
        secondDone = true;
      });
      await tester.pump();
      expect(secondDone, isTrue, reason: '重入调用返回的是**已完成**的 Future');
      expect(firstDone, isFalse, reason: '第一层还挂着 ⇒ 它的 Future 不该完成');

      await tester.pumpAndSettle();
      expect(find.text('稍后再看'), findsOneWidget, reason: '只有一层 sheet ⇒ 条目不重复');
      expect(find.text('不感兴趣'), findsOneWidget);

      // 关掉后守卫必须放开 ⇒ 否则"以后再也弹不出来"是更难查的 bug
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(isLiquidActionSheetOpen, isFalse);
      await tester.tap(find.text('打开弹层'));
      await tester.pumpAndSettle();
      expect(find.text('稍后再看'), findsOneWidget, reason: '关闭后能再弹');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });

    // 每个 useRootNavigator 取值一个**独立用例**：不能在同一个 testWidgets 里
    // 循环 pumpWidget 换值 —— Navigator 元素会被复用，嵌套 Navigator 的
    // onGenerateRoute 闭包（捕获着上一轮的 useRoot）不会被重新调用，
    // 页面上的 _SheetHost 还带着旧参数，断言会测到假结论。
    for (final bool useRoot in <bool>[false, true]) {
      testWidgets('useRootNavigator=$useRoot：${useRoot ? "跳到根 Navigator" : "贴当前 Navigator"}', (tester) async {
        // 两个观察者分别挂在两层 Navigator 上：谁收到这次 push，
        // 就是 useRootNavigator 生效与否的直接读数。
        final _PushCounter nested = _PushCounter();
        final _PushCounter root = _PushCounter();
        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: <NavigatorObserver>[root],
            theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: _kSeed)),
            home: Navigator(
              observers: <NavigatorObserver>[nested],
              onGenerateRoute: (RouteSettings settings) => MaterialPageRoute<void>(
                builder: (context) => Scaffold(
                  body: _SheetHost(useRootNavigator: useRoot, labels: const <String>['稍后再看']),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('打开弹层'), findsOneWidget);
        // 各自基线：首页路由会各推一次（嵌套层 1 次；根层的计数以当前值为准）。
        final int nestedBase = nested.pushes;
        final int rootBase = root.pushes;

        await tester.tap(find.text('打开弹层'));
        await tester.pumpAndSettle();
        expect(find.text('稍后再看'), findsOneWidget);
        expect(
          nested.pushes - nestedBase,
          useRoot ? 0 : 1,
          reason: '嵌套层应收到 ${useRoot ? 0 : 1} 次 push',
        );
        expect(
          root.pushes - rootBase,
          useRoot ? 1 : 0,
          reason: '根层应收到 ${useRoot ? 1 : 0} 次 push',
        );

        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(isLiquidActionSheetOpen, isFalse, reason: '两种挂法都要复位守卫');
      });
    }

    testWidgets('键盘避让：viewInsets.bottom 叠加进底部 padding（P2）', (tester) async {
      await tester.pumpWidget(
        _host(keyboardInset: 300, child: const _SheetHost(labels: <String>['稍后再看'])),
      );
      await tester.tap(find.text('打开弹层'));
      await tester.pumpAndSettle();

      final Rect panel = tester.getRect(find.byType(LiquidGlassPanel));
      // 屏高 600 −（外边距 12 + 键盘 300）= 288：面板整体被顶到键盘上方。
      expect(panel.bottom, closeTo(_kScreenHeight - 12 - 300, 2));
      expect(find.text('稍后再看'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });

    testWidgets('无键盘时位置照旧（不因新 padding 偏移）', (tester) async {
      await tester.pumpWidget(_host(child: const _SheetHost(labels: <String>['稍后再看'])));
      await tester.tap(find.text('打开弹层'));
      await tester.pumpAndSettle();
      final Rect panel = tester.getRect(find.byType(LiquidGlassPanel));
      expect(panel.bottom, closeTo(_kScreenHeight - 12, 2));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });

    testWidgets('A3 纪律不回归：入场动画期间 solid，>85% 才切 thick', (tester) async {
      await tester.pumpWidget(_host(child: const _SheetHost(labels: <String>['稍后再看'])));
      await tester.tap(find.text('打开弹层'));
      await tester.pump(); // 滑入起始帧
      final LiquidGlassPanel early = tester.widget(find.byType(LiquidGlassPanel));
      expect(early.material, LiquidGlassMaterial.solid, reason: '动画期间零背景采样');

      await tester.pumpAndSettle();
      final LiquidGlassPanel settled = tester.widget(find.byType(LiquidGlassPanel));
      expect(settled.material, LiquidGlassMaterial.thick, reason: '落定后才挂真玻璃');

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });

    testWidgets('减弱动效开关下弹层仍能开关', (tester) async {
      GlassAccessibility.debugReduceMotion = true;
      await tester.pumpWidget(_host(child: const _SheetHost(labels: <String>['稍后再看'])));
      await tester.tap(find.text('打开弹层'));
      await tester.pumpAndSettle();
      expect(find.text('稍后再看'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(isLiquidActionSheetOpen, isFalse);
    });

    testWidgets('条目超出高度不溢出（P1-sheet 纪律仍在）', (tester) async {
      await tester.pumpWidget(
        _host(child: _SheetHost(labels: <String>[for (int i = 0; i < 12; i++) '条目$i'])),
      );
      await tester.tap(find.text('打开弹层'));
      await tester.pumpAndSettle();
      expect(find.text('条目0'), findsOneWidget);
      final Rect panel = tester.getRect(find.byType(LiquidGlassPanel));
      expect(panel.height, lessThanOrEqualTo(_kScreenHeight * 0.7 + 1));
      expect(tester.takeException(), isNull);
      // 12 条时"取消"被 0.7 屏高上限裁在滚动视口**外面**（正是这条纪律要的效果）
      // ⇒ 这里用遮罩点击关闭（barrierDismissible 默认 true），而不是去点看不见的按钮。
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('条目0'), findsNothing);
      expect(isLiquidActionSheetOpen, isFalse);
    });
  });

  // ══════════════════════════════════ 预览页（热区重叠的回归位）
  group('LiquidComponentsPreviewPage', () {
    for (final Brightness brightness in Brightness.values) {
      testWidgets('$brightness：整页冒烟 + 动效小节存在', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: _kSeed, brightness: brightness),
            ),
            home: const LiquidComponentsPreviewPage(),
          ),
        );
        await tester.pump(const Duration(seconds: 2)); // 有界 pump（**非修复**：真凶是 tearDownAll 裸 Hive.close ✓ 已修；留作"预览页将来加持续动画"的防御 ✓）
        expect(find.text('顶栏 LiquidTopBar'), findsOneWidget);
        expect(find.textContaining('动效 LiquidPressable'), findsOneWidget);
        // 三块不同 pressedScale 的示例（让用户目视果冻回弹）
        expect(find.text('微 0.99'), findsOneWidget);
        expect(find.text('标准 0.96'), findsOneWidget);
        expect(find.text('强 0.90'), findsOneWidget);
        expect(find.byType(LiquidPressable), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$brightness：明暗切换钮不与任何交互热区重叠（P2 回归）', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: _kSeed, brightness: brightness),
            ),
            home: const LiquidComponentsPreviewPage(),
          ),
        );
        await tester.pump(const Duration(seconds: 2)); // 有界 pump（**非修复**：真凶是 tearDownAll 裸 Hive.close ✓ 已修；留作"预览页将来加持续动画"的防御 ✓）

        final Finder toggle = find.byKey(const ValueKey<String>('preview-theme-toggle'));
        expect(toggle, findsOneWidget);
        final Rect toggleRect = tester.getRect(toggle);
        // 顶栏头像（原来被压住的那个热区）
        final Rect avatarRect = tester.getRect(
          find.descendant(
            of: find.byType(LiquidTopBar),
            matching: find.byType(CircleAvatar),
          ),
        );
        // 导航条本体的玻璃层（不是 Align 的整块占位——那层铺满全页高度）
        final Rect navRect = tester.getRect(
          find.descendant(
            of: find.byType(LiquidFloatingNav),
            matching: find.byType(LiquidGlassSurface),
          ).first,
        );
        final Rect searchRect = tester.getRect(find.text('搜索bilibili'));

        expect(toggleRect.overlaps(avatarRect), isFalse, reason: '不再压住顶栏头像');
        expect(toggleRect.overlaps(navRect), isFalse, reason: '在浮动导航上方，不压导航');
        expect(toggleRect.overlaps(searchRect), isFalse, reason: '不压搜索热区');
        expect(toggleRect.right, lessThanOrEqualTo(_kScreenWidth), reason: '仍在屏内');
        expect(toggleRect.bottom, lessThanOrEqualTo(_kScreenHeight));

        // 点得动：切一次主题不崩
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('LiquidPillBar.selectionGlass（#24b P-24b-1 案 A 执行件）', () {
    testWidgets('false ⇒ 选中片走 solid 档材质（玻璃预算合规路径）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LiquidPillBar(
              items: [
                LiquidPillBarItem(id: 'a', label: '甲'),
                LiquidPillBarItem(id: 'b', label: '乙'),
              ],
              selectedIndex: 0,
              selectionGlass: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final surfaces = tester
          .widgetList<LiquidGlassSurface>(find.byType(LiquidGlassSurface))
          .toList();
      expect(surfaces, isNotEmpty, reason: '选中片仍有 Surface 容器（solid 档）');
      expect(
        surfaces.every((s) => s.material == LiquidGlassMaterial.solid),
        isTrue,
        reason: 'selectionGlass=false 时不许出现 regular 真玻璃（预算纪律）',
      );
    });

    testWidgets('默认 true ⇒ 选中片仍是 regular（预览现状不回归）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LiquidPillBar(
              items: [
                LiquidPillBarItem(id: 'a', label: '甲'),
                LiquidPillBarItem(id: 'b', label: '乙'),
              ],
              selectedIndex: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<LiquidGlassSurface>(find.byType(LiquidGlassSurface))
            .every((s) => s.material == LiquidGlassMaterial.regular),
        isTrue,
      );
    });
  });
}
