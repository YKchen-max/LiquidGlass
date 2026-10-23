// SPDX-License-Identifier: GPL-3.0-or-later
//
// #28b 全局主题注入绊线（2026-10-06，子代理主笔、Lead 批复第三条路＝simple_app_bar 零改动）。
// 五组针：(a) 零改反向 (b) 注入点正向 (c) 业务页零行 (d) S16 import (e) §0.3 预算。
// 口径＝源文本扫描（范本 u28_detail_quasi_close_test / u27_conservation_test）：
// 谁日后偷加"SimpleAppBar 内部注入"（双重皮肤）/拆全局钉/逐页包装长尾/引 flutter material/
// 在全局面加真玻璃 ⇒ 当场红 ✓。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String rel) {
  final candidates = <String>[rel, 'app/$rel'];
  for (final p in candidates) {
    final f = File(p);
    if (f.existsSync()) return f.readAsStringSync();
  }
  fail('找不到 $rel（cwd=${Directory.current.path}）');
}

void main() {
  final simpleAppBar = _read('lib/common/widgets/simple_app_bar.dart');
  final themeUtils = _read('lib/utils/theme_utils.dart');
  final style = _read('lib/common/style.dart');

  group('(a) 零改反向针：simple_app_bar 永不被内部注入（第三条路墓碑 ✓）', () {
    test('零 Theme( 读取（它本就全参数显式 ⇒ 内部注入＝死代码/双重皮肤）', () {
      expect(simpleAppBar.contains('Theme.of'), isFalse);
      expect(simpleAppBar.contains('Theme('), isFalse);
    });
    test('零 liquid import / 零 skin / 零 optOut 参数名', () {
      expect(simpleAppBar.contains('liquid_'), isFalse);
      expect(simpleAppBar.contains('LiquidAppBarSkin'), isFalse);
      expect(RegExp(r'optOut|opt_out|skin:').hasMatch(simpleAppBar), isFalse);
    });
  });

  group('(b) 注入点正向针：主题根钉面在位', () {
    test('appBarTheme foregroundColor = onSurface（与 LiquidAppBarSkin 同 token）', () {
      expect(themeUtils.contains('foregroundColor: colorScheme.onSurface'), isTrue);
    });
    test('cardTheme shape 走 DesignTokens.brMedium(16) / dialogTheme shape all-28', () {
      // 2026-10-23：卡片圆角改走设计 token（12 → 16），断针同步改成检查 token 引用，
      // 并额外钉住 token 值本身，防止有人直接改 token 绕过这条针。
      expect(themeUtils.contains('DesignTokens.brMedium'), isTrue);
      expect(themeUtils.contains('Radius.circular(28)'), isTrue);
      final tokens = _read('lib/common/design_tokens.dart');
      expect(tokens.contains('Radius.circular(16)'), isTrue);
    });
    test('style.bottomSheetRadius 走 DesignTokens.brSheet(24) 且不再含 18', () {
      // 2026-10-23：底部弹层 28 → 24（收一档，与卡片 16 形成 24/16/10 三级）。
      expect(style.contains('bottomSheetRadius = DesignTokens.brSheet'), isTrue);
      expect(style.contains('.circular(18)'), isFalse);
      final tokens = _read('lib/common/design_tokens.dart');
      expect(tokens.contains('Radius.circular(24)'), isTrue);
    });
  });

  group('(c) 业务页零行针：长尾没有被逐页包装（全局路线独占 ✓）', () {
    test('pages/** 引用 LiquidAppBarSkin|LiquidSheetShell 的文件数 = 1（仅 video/view.dart）', () {
      final offenders = <String>[];
      for (final f in Directory('lib/pages')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final s = f.readAsStringSync();
        if (s.contains('LiquidAppBarSkin') || s.contains('LiquidSheetShell')) {
          offenders.add(f.path.replaceAll('\\', '/'));
        }
      }
      expect(offenders, <String>['lib/pages/video/view.dart'],
          reason: '长尾换肤只走全局主题根；逐页包装＝路线回退，先过 Lead 拍板');
    });
  });

  group('(d) S16 import 纪律针（fork 主题雷 ✓）', () {
    test('simple_app_bar/style/theme_utils/本测试 四件零 flutter/material', () {
      // 拆串自避：本测试源码若含完整字面量会自指红（u25 范本同款手法 ✓）。
      final needle = 'package:flutter/material' + '.dart';
      for (final s in <String>[
        simpleAppBar,
        style,
        themeUtils,
        File('test/own/u28b_global_theme_test.dart').readAsStringSync(),
      ]) {
        expect(s.contains(needle), isFalse);
      }
    });
  });

  group('(e) §0.3 预算针：全局注入＝纯 solid token、零新增常驻真玻璃', () {
    test('theme_utils + style 零 BackdropFilter/LiquidGlassSurface/LiquidGlassPanel', () {
      for (final s in <String>[themeUtils, style]) {
        expect(s.contains('BackdropFilter('), isFalse);
        expect(s.contains('LiquidGlassSurface('), isFalse);
        expect(s.contains('LiquidGlassPanel('), isFalse);
      }
    });
  });
}
