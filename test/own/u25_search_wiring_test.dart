// SPDX-License-Identifier: GPL-3.0-or-later
//
// #25（U3 搜索页）接线绊线测试——源码文本层钉住关键接线，与
// s15_listener_wiring_test.dart 同族（教训：监听/接线删行在 analyze/单测
// 几乎无感，只能靠源码断言兜底）。
// 钉的不是"代码长什么样"，而是**行为契约的承重墙**：
//   ① 结果壳 pill 行：双向同步 listener 三处生命周期齐 + toTop 语义 + 案 A 档位；
//   ② 结果列表：LiquidVideoCard＋适配器三件套（数据/菜单/导航）＋触底加载；
//   ③ 中枢页：建议/热词走适配器、搜索条行为五要素在；
//   ④ 热搜榜：走同一适配器契约。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('① 结果壳 pill 行（search_result/view.dart）', () {
    final src = _read('lib/pages/search_result/view.dart');

    test('双向同步 listener 三处生命周期齐（S15 教训）', () {
      expect(src.contains('addListener(_sync)'), isTrue);
      expect(src.contains('removeListener(_sync)'), isTrue);
      expect(src.contains('didUpdateWidget'), isTrue,
          reason: 'controller 换实例时的换绑闸，缺它 = 旧 controller 泄漏监听');
    });

    test('点当前 tab 回顶语义（toTopIndex refresh/赋值两分支）＋滑动守卫', () {
      expect(src.contains('toTopIndex.refresh()'), isTrue);
      expect(src.contains('toTopIndex.value = i'), isTrue);
      expect(src.contains('indexIsChanging'), isTrue,
          reason: '滑动动画中途的点按不触发回顶——原 TabBar.onTap 的守卫语义');
      expect(src.contains('animateTo(i)'), isTrue,
          reason: 'pill 点击必须自己切页（原 TabBar 默认行为，pill 不自带）');
    });

    test('计数角标仍在 label 内插（99+ 封顶）＋案 A 档位', () {
      expect(src.contains("'99+'"), isTrue);
      expect(src.contains('selectionGlass: false'), isTrue,
          reason: '与首页频道行案 A 同族；翻真玻璃是有意决策不是默认');
    });
  });

  group('② 结果列表换卡（search_panel/video/view.dart）', () {
    final src = _read('lib/pages/search_panel/video/view.dart');

    test('LiquidVideoCard＋适配器三件套', () {
      expect(src.contains('liquidSearchCardData(item)'), isTrue);
      expect(src.contains('liquidSearchMenuItems('), isTrue);
      expect(src.contains('pushSearchVideoDetail(item)'), isTrue);
    });

    test('触底加载与移除回调语义在', () {
      expect(src.contains('controller.onLoadMore()'), isTrue);
      expect(src.contains('removeAt(index)'), isTrue);
    });

    test('竖卡几何：rcmd 同式 delegate＋竖版骨架', () {
      expect(src.contains('liquidGridDelegate'), isTrue);
      expect(src.contains('Pref.recommendCardWidth'), isTrue);
      expect(src.contains('VideoCardVSkeleton'), isTrue,
          reason: '竖卡网格配横版骨架 = 加载态观感翻车');
    });

    test('不再直接消费 VideoCardH', () {
      expect(src.contains('VideoCardH('), isFalse);
    });
  });

  group('③ 中枢页（search/view.dart）', () {
    final src = _read('lib/pages/search/view.dart');

    test('建议/热词走适配器契约', () {
      expect(src.contains('liquidSuggestItems('), isTrue);
      expect(src.contains('liquidSearchHotItems('), isTrue);
    });

    test('搜索条行为五要素在（视觉批不得动输入行为）', () {
      for (final needle in [
        'autofocus: true',
        '_searchController.searchFocusNode',
        '_searchController.onChange',
        '_searchController.submit()',
        'TextInputAction.search',
      ]) {
        expect(src.contains(needle), isTrue, reason: '缺 $needle');
      }
    });

    test('建议可见性门禁保持上游口径（首项 term 非空）', () {
      expect(src.contains('raw.first.term != null'), isTrue);
    });
  });

  group('④ 热搜榜（search_trending/view.dart）', () {
    final src = _read('lib/pages/search_trending/view.dart');

    test('走同一适配器契约', () {
      expect(src.contains('liquidSearchHotItems('), isTrue);
      expect(src.contains('item.keyword'), isTrue,
          reason: '跳搜索结果的参数名必须是 keyword（路由契约）');
    });
  });

  group('⑤ liquid 组件禁引 flutter/material（#25 真机取证发现的主题雷）', () {
    // 本 app 全树用 **material_ui fork**（自带 Theme/_InheritedTheme 类型，
    // main.dart:49）。组件若 import package:flutter/material.dart，其
    // Theme.of 会查找 flutter 的 Theme——fork 的 MaterialApp 从不安装它 ⇒
    // 静默落 ThemeData.fallback()（M3 基线**亮色**）⇒ 深色模式下
    // scheme.onSurface = #1D1B20 黑字糊在黑卡上（真机像素取证：
    // onSurface/onSurfaceVariant/primary 与亮色基线逐位吻合）。
    // widget test 打不出（测试宿主装的是 flutter Theme，解析"正常"）。
    test('lib/common/widgets/liquid 与 lib/ui_liquidglass 零 flutter/material 引用', () {
      final dirs = [
        Directory('lib/common/widgets/liquid'),
        Directory('lib/ui_liquidglass'),
      ];
      final offenders = <String>[];
      for (final dir in dirs) {
        for (final f in dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
          if (f.readAsStringSync().contains('package:flutter/material.dart')) {
            offenders.add(f.path);
          }
        }
      }
      expect(offenders, isEmpty,
          reason: '这些文件必须 import package:material_ui/material_ui.dart'
              '（app 全树约定）；flutter/material 的 Theme 在本 app 无人安装');
    });
  });
}
