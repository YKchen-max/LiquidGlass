// SPDX-License-Identifier: GPL-3.0-or-later
//
// #25（U3 搜索页）prep 切片·适配器单测：与 #24b 适配器测试同口径——
// 格式化断言走同源函数（NumUtils/DurationUtils），不硬编码字面量；
// 模型一律走 fromJson 构造。
import 'package:PiliPlus/common/widgets/liquid/liquid_rcmd_adapters.dart'
    show liquidVideoMenuItems;
import 'package:PiliPlus/common/widgets/liquid/liquid_search_adapters.dart';
import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/models/search/suggest.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/models_new/search/search_trending/list.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_test/flutter_test.dart';

/// 菜单构建当前不读 context（留给未来扩展），测试传 null。
const BuildContext? _kNoContext = null;

SearchTrendingItemModel _hot({
  String keyword = '关键词甲',
  String? showName = '展示名甲',
  String? icon = 'https://example.local/icon.png',
  bool? showLiveIcon,
  String? reason,
}) {
  return SearchTrendingItemModel.fromJson(<String, dynamic>{
    'keyword': keyword,
    if (showName != null) 'show_name': showName,
    'icon': icon,
    'show_live_icon': showLiveIcon,
    if (reason != null) 'recommend_reason': reason,
  });
}

SearchVideoItemModel _video({
  Object? bvid = 'BV1search',
  Object? mid = 42,
  String? type,
  String title = '测试<em class="keyword">搜索</em>标题',
}) {
  return SearchVideoItemModel.fromJson(<String, dynamic>{
    'id': 7,
    'aid': 7,
    'bvid': bvid,
    'pic': 'https://example.local/s.jpg',
    'title': title,
    'description': '简介',
    'duration': '12:34',
    'pubdate': 1700000000,
    'mid': mid,
    'author': '作者乙',
    'upic': 'https://example.local/f.jpg',
    'play': 54321,
    'danmaku': 321,
    'favorite': 10,
    'review': 5,
    'like': 99,
    if (type != null) 'type': type,
    if (type == 'live_room') 'roomid': 123,
  });
}

void main() {
  group('liquidSearchHotItems：热搜/搜索发现 → 热词契约', () {
    test('null/空安全：null 进空列出', () {
      expect(liquidSearchHotItems(null), isEmpty);
      expect(liquidSearchHotItems(const []), isEmpty);
    });

    test('字段直译：keyword/label/icon/live 角标/推荐语', () {
      final items = liquidSearchHotItems([
        _hot(showLiveIcon: true, reason: '·热度上升'),
      ]);
      expect(items, hasLength(1));
      final it = items.single;
      expect(it.keyword, '关键词甲');
      expect(it.label, '展示名甲');
      expect(it.iconUrl, 'https://example.local/icon.png');
      expect(it.showLiveIcon, isTrue);
      // recommend_reason 的前导 '·' 由上游 fromJson 换成空格，适配器不再加工
      expect(it.reason, ' 热度上升');
    });

    test('降级路径：show_name 缺省回退 keyword；空 icon 归 null；live 缺省 false', () {
      final it = liquidSearchHotItems([
        _hot(showName: null, icon: '', showLiveIcon: null),
      ]).single;
      expect(it.label, '关键词甲', reason: '上游 show_name 缺省回退 keyword');
      expect(it.iconUrl, isNull, reason: '空串 icon 视为无角标');
      expect(it.showLiveIcon, isFalse);
      expect(it.reason, isNull);
    });
  });

  group('liquidSearchCardData：搜索结果 → 视频卡契约', () {
    test('字段直译＋计数/时长同源格式化＋标题 em 已剥离为纯文本', () {
      final data = liquidSearchCardData(_video());
      expect(data.title, '测试搜索标题', reason: 'fromJson 已 join titleList');
      expect(data.coverUrl, 'https://example.local/s.jpg');
      expect(data.author, '作者乙');
      expect(data.playText, NumUtils.numFormat(54321));
      expect(data.danmakuText, NumUtils.numFormat(321));
      expect(data.durationText, DurationUtils.formatDuration(754));
      expect(data.durationText, '12:34');
    });

    test('直播卡（type=live_room）：计数与时长全空——VideoCardH 同源口径', () {
      final data = liquidSearchCardData(_video(type: 'live_room'));
      expect(data.playText, '');
      expect(data.danmakuText, '');
      expect(data.durationText, '');
      expect(data.title, '测试搜索标题'); // 标题/作者/封面不受 live 影响
    });

    test('缺字段不炸：cover/计数给空串、duration 缺失给空串', () {
      // 注：duration 字符串**无法解析**（如 "abc"）这条路 parseDuration 自己就
      // 炸（int.parse 无守卫，duration_utils.dart:24——上游雷区，与 rcmd 的
      // duration 键缺失雷同族，适配器层不代兜，如实记录）；这里用空串验证
      // "解析为 0 ⇒ 不显示鬼值"。
      final data = liquidSearchCardData(
        SearchVideoItemModel.fromJson(<String, dynamic>{
          'title': '无字段卡',
          'duration': '',
        }),
      );
      expect(data.coverUrl, '');
      expect(data.author, '');
      expect(data.playText, '');
      expect(data.danmakuText, '');
      expect(data.durationText, '', reason: '空串解析为 0 ⇒ 不显示鬼值');
      expect(data.badgeText, '');
      expect(data.dateText, '', reason: 'pubdate 缺失 ⇒ 空串，卡片不挂前缀');
    });

    test('徽标/日期/高亮分段三通道透传', () {
      final data = liquidSearchCardData(_video(type: 'ketang'));
      expect(data.badgeText, '课堂');
      // 同源断言：不硬编码日期字面量，直接对比同函数输出
      expect(data.dateText, DateFormatUtils.dateFormat(1700000000));
      expect(data.dateText, isNotEmpty);
      final segs = data.titleSegments!;
      expect(segs.map((s) => s.text).join(), data.title,
          reason: '分段 join 必等纯文本 title（fromJson 同源）');
      expect(segs.any((s) => s.isEm), isTrue,
          reason: 'fixture 标题含 <em> 命中 ⇒ 至少一个高亮段');
    });

    test('合作稿徽标（is_union_video=1）＋直播徽标与统计互斥', () {
      final coop = liquidSearchCardData(
        SearchVideoItemModel.fromJson(<String, dynamic>{
          'title': '合作稿',
          'duration': '1:00',
          'is_union_video': 1,
        }),
      );
      expect(coop.badgeText, '合作');
      final live = liquidSearchCardData(_video(type: 'live_room'));
      expect(live.badgeText, '直播', reason: '直播徽标仍展示');
      expect(live.playText, '', reason: '统计对直播隐藏——两条规则不打架');
    });
  });

  group('liquidSuggestItems：搜索建议 → 高亮段契约', () {
    test('null 列表进空列出', () {
      expect(liquidSuggestItems(null), isEmpty);
      expect(liquidSuggestItems(const []), isEmpty);
      expect(
        SearchSuggestModel.fromJson(<String, dynamic>{}).tag,
        isNull,
        reason: '模型 tag 缺省即 null ⇒ 调用点传 null 走上一断言',
      );
    });

    test('em 高亮分段与纯文本拼接；term 缺省回退纯文本', () {
      final items = liquidSuggestItems(
        SearchSuggestModel.fromJson(<String, dynamic>{
          'tag': <Map<String, dynamic>>[
            <String, dynamic>{
              'term': '',
              'name': '测试<em class="keyword">搜索</em>标题',
            },
          ],
        }).tag,
      );
      expect(items, hasLength(1));
      final it = items.single;
      expect(it.plainText, '测试搜索标题');
      expect(it.term, '测试搜索标题', reason: 'term 空串 ⇒ 回退 plainText');
      expect(it.segments, hasLength(3));
      expect(it.segments[1].isEm, isTrue);
      expect(it.segments[1].text, '搜索');
      expect(it.segments[0].isEm, isFalse);
    });
  });

  group('liquidSearchMenuItems：与 #24b 菜单同序同源', () {
    test('标签与顺序和推荐卡菜单逐项一致', () {
      final search = liquidSearchMenuItems(_kNoContext, _video());
      // 同源断言：直接对比推荐卡菜单的标签列——改一边不改另一边这里会红
      final rcmdLabels = liquidVideoMenuItems(
        _kNoContext,
        RcmdVideoItemModel.fromJson(<String, dynamic>{
          'id': 1,
          'bvid': 'BV1rcmd',
          'pic': 'https://example.local/c.jpg',
          'title': '对照组',
          'duration': 60,
          'owner': <String, dynamic>{'name': '作者甲', 'mid': 42},
          'stat': <String, dynamic>{'view': 1, 'danmaku': 1},
        }),
      ).map((e) => e.label).toList();
      expect(search.map((e) => e.label).toList(), rcmdLabels);
      expect(search.every((e) => e.onTap != null), isTrue);
    });

    test('bvid 缺失 ⇒ 稍后再看/不感兴趣 onTap 为 null（桥接不吞字段缺失）', () {
      final items = liquidSearchMenuItems(_kNoContext, _video(bvid: null));
      expect(items[0].onTap, isNull);
      expect(items[1].onTap, isNull);
      expect(items[3].onTap, isNotNull); // 访问作者只依赖 mid
    });

    test('mid 缺失 ⇒ 访问作者 onTap 为 null', () {
      final items = liquidSearchMenuItems(_kNoContext, _video(mid: null));
      expect(items[3].onTap, isNull);
    });
  });
}
