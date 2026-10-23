// SPDX-License-Identifier: GPL-3.0-or-later
//
// #28a 详情页主题级准收官绊线（源码文本扫描式，范本 u27_conservation_test.dart）。
//
// 背景（真折射移植计划 §0.1.66 案 4）：详情页**主树冻结**——#28a 只许做
// 「import＋包装两行式」的主题注入换肤（3 处 appbar 包 LiquidAppBarSkin、
// 5 处弹层内容包 LiquidSheetShell），**除此之外 pages/video/view.dart 零改动** ✗✗。
// 文本层绊线钉三面：
//   (a) 主树结构针：removeAppBar 签名 / headerControl 装配 / s15 监听行三针在
//       ⇒ 主树没被结构动（三针任缺一 = 有人越过冻结令改结构 ✗）；
//   (b) 正向针：LiquidAppBarSkin 计数 = 3、LiquidSheetShell 计数 = 5、
//       SimpleAppBar 仍是 3（全被包住、一个没丢）、showBottomSheet 调用点仍是 5
//       ⇒ 换肤面不多不少（多 = 越界包装；少 = 包装被回退）；
//   (c) 新 liquid 两件 import 纪律（S16 教训：零 flutter/material、必引
//       material_ui）＋ appbar skin 的「不加真玻璃」预算针（§0.3：详情页常驻
//       真玻璃 = 顶栏＋底栏 2 处已满，skin 必须是纯主题注入）＋ sheet 壳的
//       A3 纪律针（>85% 才挂玻璃，照 liquid_action_sheet 现成实现）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relative) {
  final candidates = <String>[relative, 'app/$relative'];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) return file.readAsStringSync();
  }
  fail('找不到 $relative（cwd=${Directory.current.path}）');
}

int _count(String source, String pattern) =>
    RegExp(pattern, dotAll: true).allMatches(source).length;

void main() {
  final view = _read('lib/pages/video/view.dart');
  final playerView = _read('lib/plugin/pl_player/view/view.dart');
  final skin = _read('lib/common/widgets/liquid/liquid_appbar_skin.dart');
  final shell = _read('lib/common/widgets/liquid/liquid_sheet_shell.dart');

  group('#28a 绊线(a)：详情页主树结构针（案 4 冻结令）', () {
    test('针1 removeAppBar(bool isFullScreen) 签名在', () {
      expect(
        view.contains('bool removeAppBar(bool isFullScreen) =>'),
        isTrue,
        reason:
            'removeAppBar 签名消失/被改 ⇒ 主树被动了结构 ✗（案 4 冻结令：'
            'pages/video/view.dart 除 8 处包装＋import 外零改动）',
      );
    });

    test('针2 headerControl: HeaderControl( 装配在', () {
      expect(
        view.contains('headerControl: HeaderControl('),
        isTrue,
        reason:
            'headerControl 装配点消失 ⇒ 播放器控制条接线被结构改动 ✗'
            '（#26b task-124 的 GlobalKey<TimeBatteryMixin> 契约依赖该装配）',
      );
    });

    test('针3 s15 监听注册行在（pl_player/view/view.dart，6cb8665 教训）', () {
      expect(
        playerView.contains(
          '_controlsListener = plPlayerController.showControls.listen(',
        ),
        isTrue,
        reason:
            's15 监听行消失 ⇒ 嵌入态控制条整条不可见（P0 回归）✗；'
            '与 s15_listener_wiring_test.dart 同源双保险',
      );
    });
  });

  group('#28a 绊线(b)：换肤正向针（3 appbar + 5 sheet，不多不少）', () {
    test('LiquidAppBarSkin 计数 = 3 且全部是包装式（child: SimpleAppBar）', () {
      expect(
        _count(view, r'LiquidAppBarSkin\('),
        3,
        reason: 'LiquidAppBarSkin 包装数 ≠ 3 ⇒ 换肤面被扩（越界 ✗）或被回退 ✗',
      );
      expect(
        _count(view, r'LiquidAppBarSkin\(\s*child:\s*SimpleAppBar\('),
        3,
        reason:
            '存在不是「两行式包装 SimpleAppBar」的 LiquidAppBarSkin ⇒ '
            '接线形态被改 ✗（#28 口径：import＋包装两行式）',
      );
      // SimpleAppBar 一个没丢（3 处全在、全被包住）。
      expect(
        _count(view, r'SimpleAppBar\('),
        3,
        reason: 'SimpleAppBar 计数 ≠ 3 ⇒ 共享件的调用点被动了（全局零改口径 ✗）',
      );
    });

    test('LiquidSheetShell 计数 = 5 且 showBottomSheet 调用点仍 = 5', () {
      expect(
        _count(view, r'LiquidSheetShell\('),
        5,
        reason: 'LiquidSheetShell 包装数 ≠ 5 ⇒ 弹层换肤面被扩或被回退 ✗',
      );
      expect(
        _count(view, r'LiquidSheetShell\(\s*child:'),
        5,
        reason: '存在不是「child: 内容透传」形态的 LiquidSheetShell ✗',
      );
      expect(
        _count(view, r'currentState\?\.showBottomSheet\('),
        5,
        reason: 'showBottomSheet 调用点数 ≠ 5 ⇒ 弹层入口被增删（结构改动 ✗）',
      );
    });

    test('import 两行在位（liquid_appbar_skin + liquid_sheet_shell）', () {
      expect(
        view.contains(
          "import 'package:PiliPlus/common/widgets/liquid/liquid_appbar_skin.dart';",
        ),
        isTrue,
      );
      expect(
        view.contains(
          "import 'package:PiliPlus/common/widgets/liquid/liquid_sheet_shell.dart';",
        ),
        isTrue,
      );
      // 共享件全局零改：simple_app_bar.dart 不许被 view.dart 之外的手段替换。
      expect(
        view.contains(
          "import 'package:PiliPlus/common/widgets/simple_app_bar.dart';",
        ),
        isTrue,
        reason: 'SimpleAppBar 的 import 被删 ⇒ 共享件接线被改 ✗',
      );
    });
  });

  group('#28a 绊线(c)：新 liquid 两件纪律针（S16 + §0.3 + A3）', () {
    test('import 纪律：零 flutter/material、必引 material_ui＋kit', () {
      for (final entry in {
        'liquid_appbar_skin.dart': skin,
        'liquid_sheet_shell.dart': shell,
      }.entries) {
        expect(
          entry.value.contains('package:flutter/material.dart'),
          isFalse,
          reason:
              '${entry.key} 引了 flutter/material ⇒ S16 黑字糊黑卡雷 ✗'
              '（目录级扫描另由 u25 组⑤兜底）',
        );
        expect(
          entry.value.contains('package:material_ui/material_ui.dart'),
          isTrue,
          reason: '${entry.key} 未引 fork material_ui ✗',
        );
        expect(
          entry.value.contains(
            'package:liquid_glass_kit/liquid_glass_kit.dart',
          ),
          isTrue,
          reason: '${entry.key} 未走 kit 稳定入口 ✗',
        );
      }
    });

    test('appbar skin = solid 档主题注入，不加真玻璃（预算 §0.3）', () {
      // 常驻真玻璃预算已满（顶栏＋底栏 2 处）⇒ skin 源码不许出现挂玻璃的构造。
      expect(
        skin.contains('LiquidGlassSurface('),
        isFalse,
        reason: 'appbar skin 挂了 LiquidGlassSurface ⇒ 常驻真玻璃变 3 处 ✗ 超预算',
      );
      expect(
        skin.contains('LiquidGlassPanel('),
        isFalse,
        reason: 'appbar skin 挂了 LiquidGlassPanel ⇒ 超预算 ✗',
      );
      expect(
        skin.contains('BackdropFilter('),
        isFalse,
        reason: 'appbar skin 出现 BackdropFilter ⇒ 背景采样 ✗',
      );
      // solid 档注入面：surface 系背景 token + 液态字阶 + 图标色。
      expect(
        skin.contains('backgroundColor: scheme.surface'),
        isTrue,
        reason: '背景 token 未落在 colorScheme.surface 系 ✗',
      );
      expect(
        skin.contains('LiquidFontFamily.text'),
        isTrue,
        reason: '液态字阶（LiquidText 族）注入缺失 ✗',
      );
      expect(
        skin.contains(
          'iconTheme: theme.iconTheme.copyWith(color: scheme.onSurface)',
        ),
        isTrue,
        reason: '图标色（onSurface 系）注入缺失 ✗',
      );
      // 透传面：preferredSize 必须走子件（PreferredSizeWidget 判定在源）。
      expect(
        skin.contains('is PreferredSizeWidget'),
        isTrue,
        reason: 'preferredSize 透传判定被改 ✗',
      );
    });

    test('sheet 壳 = glassThick + A3 纪律（>85% 才挂玻璃，照现成实现）', () {
      expect(
        shell.contains('LiquidGlassMaterial.thick'),
        isTrue,
        reason: 'settle 档不是 glassThick ✗（home 弹层先例口径）',
      );
      expect(
        shell.contains('LiquidGlassMaterial.solid'),
        isTrue,
        reason: 'solid 降级档缺失 ✗（过渡期/降低透明度必须可渲染）',
      );
      expect(
        shell.contains('> 0.85'),
        isTrue,
        reason: 'A3 阈值 0.85 被改 ✗（liquid_action_sheet.dart 同款判据）',
      );
      expect(
        shell.contains('ModalRoute.of(context)?.animation'),
        isTrue,
        reason: 'A3 驱动动画来源被改 ✗（route 动画判据照抄现成实现）',
      );
      expect(
        shell.contains('IgnorePointer'),
        isTrue,
        reason: '把手必须 IgnorePointer（装饰件不抢手势，内容交互零改）✗',
      );
    });
  });
}
