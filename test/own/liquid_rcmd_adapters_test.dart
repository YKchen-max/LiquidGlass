// SPDX-License-Identifier: GPL-3.0-or-later
//
// #24b 适配器单测：数据层翻译的同源断言（格式化不硬编码字面量，直接对比
// NumUtils/DurationUtils 的同函数输出——改格式化口径时这里不会假绿）。
// 模型一律走 fromJson 构造（类只有命名构造，无默认构造 ✓）。
import 'package:PiliPlus/common/widgets/liquid/liquid_rcmd_adapters.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_test/flutter_test.dart';

/// 菜单构建当前不读 context（留给未来扩展），测试传 null。
const BuildContext? _kNoContext = null;

RcmdVideoItemModel _model({Object? bvid = 'BV1test', Object? mid = 42}) {
  return RcmdVideoItemModel.fromJson(<String, dynamic>{
    'id': 1,
    'bvid': bvid,
    'pic': 'https://example.local/c.jpg',
    'title': '测试标题',
    'duration': 754,
    'owner': <String, dynamic>{'name': '作者甲', 'mid': mid},
    'stat': <String, dynamic>{'view': 12345, 'danmaku': 678},
  });
}

void main() {
  group('liquidCardData：模型 → 卡片契约', () {
    test('字段直译＋计数/时长走同源格式化', () {
      final data = liquidCardData(_model());
      expect(data.title, '测试标题');
      expect(data.coverUrl, 'https://example.local/c.jpg');
      expect(data.author, '作者甲');
      expect(data.playText, NumUtils.numFormat(12345));
      expect(data.danmakuText, NumUtils.numFormat(678));
      expect(data.durationText, DurationUtils.formatDuration(754));
      expect(data.durationText, '12:34');
    });

    test('缺字段不炸：cover/计数给空串、duration 非正给空串', () {
      // 注：duration **键缺失**这条路 fromJson 自己就炸（上游 model_rec_video_item.dart:23
      // 把 null 赋给 non-null int——上游雷区，适配器层不代兜，如实记录）；
      // 这里用 -1（基类缺省值同形）验证"非正不显示鬼值"。
      final data = liquidCardData(
        RcmdVideoItemModel.fromJson(<String, dynamic>{
          'title': '',
          'duration': -1,
          'owner': <String, dynamic>{},
          'stat': <String, dynamic>{},
        }),
      );
      expect(data.title, '');
      expect(data.coverUrl, '');
      expect(data.author, '');
      expect(data.playText, '');
      expect(data.danmakuText, '');
      expect(data.durationText, '', reason: '基类 duration 缺省 -1 ⇒ 不显示鬼值');
    });
  });

  group('liquidVideoMenuItems：三项可落地契约', () {
    test('标签与顺序（稍后再看/不感兴趣/保存封面/访问作者），拉黑不在列', () {
      final items = liquidVideoMenuItems(_kNoContext, _model());
      expect(
        items.map((e) => e.label),
        <String>['稍后再看', '不感兴趣', '保存封面', '访问作者'],
      );
      expect(items.any((e) => e.label.contains('拉黑')), isFalse);
      expect(items.every((e) => e.onTap != null), isTrue);
    });

    test('bvid 缺失 ⇒ 网络类/存图类条目 onTap 为 null（死按钮契约 C1 同源）', () {
      final items = liquidVideoMenuItems(_kNoContext, _model(bvid: null));
      expect(items[0].onTap, isNull);
      expect(items[1].onTap, isNull);
      expect(items[2].onTap, isNotNull); // 保存封面不依赖 bvid（imageSaveDialog 自处理空值）
      expect(items[3].onTap, isNotNull); // 访问作者不依赖 bvid
    });

    test('mid 缺失 ⇒ 访问作者 onTap 为 null', () {
      final items = liquidVideoMenuItems(_kNoContext, _model(mid: null));
      expect(items[3].onTap, isNull);
    });
  });

  test('liquidChannelItems：下标 id + label 直译', () {
    final items = liquidChannelItems(<String>['直播', '推荐', '热门']);
    expect(items.length, 3);
    expect(items[1].id, '1');
    expect(items[1].label, '推荐');
  });
}
