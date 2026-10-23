// SPDX-License-Identifier: GPL-3.0-or-later
//
// 滚动降档（案 A）单测：滞回状态机＋调用点接线绊线。
import 'dart:io';

import 'package:PiliPlus/utils/glass_scroll_downgrade.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(GlassScrollDowngrade.instance.debugReset);

  group('GlassScrollDowngrade 滞回状态机', () {
    test('初始 false；心跳即 true（跳变沿）', () async {
      final d = GlassScrollDowngrade.instance;
      expect(d.scrolling.value, isFalse);
      d.noteActivity();
      expect(d.scrolling.value, isTrue);
    });

    test('滞回期内保持 true，静止超时后回 false', () async {
      final d = GlassScrollDowngrade.instance;
      d.noteActivity();
      expect(d.scrolling.value, isTrue);
      // 滞回 300ms 内仍 true
      await Future<void>.delayed(
        GlassScrollDowngrade.idleHysteresis - const Duration(milliseconds: 100),
      );
      expect(d.scrolling.value, isTrue, reason: '滞回窗口内不得提前回落');
      // 超过滞回 ⇒ false
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(d.scrolling.value, isFalse, reason: '静止超过滞回 ⇒ 恢复 regular');
    });

    test('滞回期内再次心跳 ⇒ 计时重置（连续滚动不回落）', () async {
      final d = GlassScrollDowngrade.instance;
      d.noteActivity();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      d.noteActivity(); // 距首心跳 200ms，重置计时
      await Future<void>.delayed(
        GlassScrollDowngrade.idleHysteresis - const Duration(milliseconds: 100),
      );
      expect(
        d.scrolling.value,
        isTrue,
        reason: '距上次心跳 < 滞回，不得回落',
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(d.scrolling.value, isFalse);
    });
  });

  group('调用点接线绊线（案 A 三处）', () {
    test('触发器：main/view.dart 的 NotificationListener 调 noteActivity', () {
      final src = File('lib/pages/main/view.dart').readAsStringSync();
      expect(src.contains('NotificationListener<ScrollNotification>'), isTrue);
      expect(
        src.contains('GlassScrollDowngrade.instance.noteActivity()'),
        isTrue,
        reason: '触发器被删 ⇒ 整条降档链失能（S15 族：删行 analyze 无感）',
      );
    });

    test('顶栏与底导：档位随 scrolling 切换＋交叉淡入 key 随档位变', () {
      for (final path in [
        'lib/pages/home/view.dart',
        'lib/common/widgets/floating_navigation_bar.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(
          src.contains('GlassScrollDowngrade.instance.scrolling'),
          isTrue,
          reason: '$path 未接降档信号',
        );
        expect(
          src.contains('LiquidGlassMaterial.solid'),
          isTrue,
          reason: '$path 缺 solid 降档分支',
        );
        expect(
          src.contains('ValueKey<bool>(scrolling)'),
          isTrue,
          reason: '$path key 不随档位变 ⇒ 原地换材质观感跳变（pill 同款教训）',
        );
      }
    });
  });
}
