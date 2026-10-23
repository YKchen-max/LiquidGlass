// SPDX-License-Identifier: GPL-3.0-or-later
//
// 图标集与字体的接线自检：族名、码点、字体文件是否真的随包发出。
// （穷尽校验由 tool/build_fonts.py --check 负责：清单 ↔ 字体 cmap ↔ 生成的 Dart 三方一致。）
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

void main() {
  group('字体族命名', () {
    test('族名常量与 pubspec 声明一致', () {
      expect(LiquidFontFamily.text, 'LiquidText');
      expect(LiquidFontFamily.icons, 'LiquidIcons');
      expect(LiquidFontFamily.lucide, 'LucideIcons');
    });

    test('图标常量都挂在包内字体族上（不是材料图标默认族）', () {
      expect(LiquidIcons.home.fontFamily, LiquidIcons.family);
      expect(LiquidIcons.play.fontFamily, LiquidIcons.family);
      expect(LucideIcons.home.fontFamily, LucideIcons.family);
      expect(LucideIcons.search.fontFamily, LucideIcons.family);
      // 关键红线：不能悄悄退回 MaterialIcons（否则等于没换图标集）
      expect(LiquidIcons.home.fontFamily, isNot('MaterialIcons'));
    });

    test('同一族内码点不重复（生成器回归守卫）', () {
      final seen = <int, String>{};
      void check(int codePoint, String name) {
        final prev = seen[codePoint];
        expect(prev, isNull, reason: '$name 与 $prev 的码点重复：0x$codePoint');
        seen[codePoint] = name;
      }

      check(LiquidIcons.home.codePoint, 'LiquidIcons.home');
      check(LiquidIcons.search.codePoint, 'LiquidIcons.search');
      check(LiquidIcons.live.codePoint, 'LiquidIcons.live');
      check(LiquidIcons.dynamic.codePoint, 'LiquidIcons.dynamic');
      check(LiquidIcons.profile.codePoint, 'LiquidIcons.profile');
      check(LiquidIcons.play.codePoint, 'LiquidIcons.play');
      check(LiquidIcons.danmaku.codePoint, 'LiquidIcons.danmaku');
      check(LiquidIcons.glass.codePoint, 'LiquidIcons.glass');
    });
  });

  group('字体文件随包发出', () {
    for (final entry in {
      'assets/fonts/LiquidIcons.ttf': 10 * 1024,
      'assets/fonts/LucideIcons.ttf': 5 * 1024,
      'assets/fonts/LiquidText-Regular.ttf': 512 * 1024,
    }.entries) {
      test('${entry.key} 存在且体积合理', () {
        final f = File(entry.key);
        expect(f.existsSync(), isTrue, reason: '缺少 ${entry.key}，请先跑 python tool/build_fonts.py');
        expect(f.lengthSync(), greaterThan(entry.value));
      });
    }

    test('许可证原文已随包入库（素材红线）', () {
      final dir = Directory('assets/fonts/LICENSES');
      expect(dir.existsSync(), isTrue);
      final names = dir.listSync().map((e) => e.path).toList();
      expect(names.any((p) => p.contains('MaterialSymbols')), isTrue);
      expect(names.any((p) => p.contains('NotoSansSC') || p.contains('MiSans')), isTrue);
      expect(names.any((p) => p.contains('Lucide')), isTrue);
    });
  });
}