// SPDX-License-Identifier: GPL-3.0-or-later
//
// C1（综合 tab 混排区换卡）接线绊线——源码文本层钉住换卡结构与交互守恒：
//   ① 混排四件各挂 LiquidSolidCard（列表卡永不真玻璃 §0.3）；
//   ② all/view.dart 的两块 Divider 已除（卡 margin 承接分隔）；
//   ③ 各件的跳转/手势契约行仍在（换壳不得动内核）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('C1 混排四件各挂 LiquidSolidCard', () {
    for (final entry in {
      'lib/pages/search_panel/all/widgets/user.dart': 'SearchAllUserItem',
      'lib/pages/search_panel/all/widgets/activity.dart': 'SearchActivityItem',
      'lib/pages/search_panel/all/widgets/esports.dart': 'SearchEsportsItem',
      'lib/pages/search_panel/pgc/widgets/item.dart': 'SearchPgcItem',
    }.entries) {
      test('${entry.value}（${entry.key}）', () {
        final src = _read(entry.key);
        expect(
          src.contains('LiquidSolidCard('),
          isTrue,
          reason: '${entry.value} 未换液态 solid 卡壳',
        );
        expect(
          src.contains('package:flutter/material.dart'),
          isFalse,
          reason: 'S16 纪律：liquid 组件目录及接线件禁 flutter/material',
        );
      });
    }
  });

  group('C1 分隔与手势守恒', () {
    test('all/view.dart 两块 Divider 已除（卡 margin 承接）', () {
      final src = _read('lib/pages/search_panel/all/view.dart');
      expect(
        src.contains('Divider('),
        isFalse,
        reason: '混排区的两块 Divider 应已被卡 margin 取代',
      );
    });

    test('user：跳 member / 迷你视频列 pushVideoH 契约在', () {
      final src = _read('lib/pages/search_panel/all/widgets/user.dart');
      expect(src.contains("Get.toNamed('/member?mid="), isTrue);
      expect(src.contains('pushVideoH(video)'), isTrue);
    });

    test('activity：routePushFromUrl＋三手势在', () {
      final src = _read('lib/pages/search_panel/all/widgets/activity.dart');
      expect(src.contains('PiliScheme.routePushFromUrl(item.url)'), isTrue);
      expect(src.contains('onLongPress'), isTrue);
      expect(src.contains('onSecondaryTap'), isTrue);
    });

    test('pgc：viewPgc＋长按存图在；esports：matchInfo 跳转在', () {
      final pgc = _read('lib/pages/search_panel/pgc/widgets/item.dart');
      expect(pgc.contains('PageUtils.viewPgc(seasonId: item.seasonId)'), isTrue);
      expect(pgc.contains('imageSaveDialog('), isTrue);
      final esp = _read('lib/pages/search_panel/all/widgets/esports.dart');
      expect(esp.contains("Get.toNamed(\n            '/matchInfo'"), isTrue,
          reason: 'esports 详情跳转契约（matchInfo cid）');
    });
  });
}
