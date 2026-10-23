// SPDX-License-Identifier: GPL-3.0-or-later
//
// #25（U3 搜索页）prep 切片·接线适配器（数据层）：把搜索域既有模型翻译成
// `lib/common/widgets/liquid/` 组件的契约类型。**view 树未动**——与 #24b 的
// `liquid_rcmd_adapters.dart`（1f8ae5f）同打法：适配器＋单测先落，view 重排
// 等拍板后另批执行。
//
// 划界（docs/UI重构方案.md §0 纪律 2）：**controller 零改动**——本文件只读模型、
// 复用既有顶层函数，不碰任何 GetX controller。
//
// 覆盖搜索域三块（排期 #25 验收对应物）：
//   ① 热词卡「大家都在搜 / 搜索发现」（pages/search）＋ 热搜榜（search_trending）
//      —— 两者共用 SearchTrendingItemModel；
//   ② 结果列表视频卡（search_panel/video，现为 VideoCardH）→ LiquidVideoCardData；
//   ③ 搜索建议高亮段（pages/search 建议列表，现为 view 内联 Em.regTitle）。
import 'package:PiliPlus/common/widgets/liquid/liquid_action_sheet.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_rcmd_adapters.dart'
    show liquidVideoMenuItems;
import 'package:PiliPlus/common/widgets/liquid/liquid_video_card.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_h.dart'
    show pushVideoH;
import 'package:PiliPlus/models/horizontal_video_model.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/models/search/suggest.dart';
import 'package:PiliPlus/models_new/search/search_trending/list.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/em.dart' show Em;
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:flutter/widgets.dart' show BuildContext, VoidCallback;

/// 热词条目契约：热词卡（「大家都在搜」 chips）与热搜榜行共用。
///
/// 导航口径（页面侧负责）：`Get.toNamed('/searchResult', parameters:
/// {'keyword': keyword})`——与 search/view.dart、search_trending/view.dart
/// 现有行为一致，适配器不代跳。
class LiquidSearchHotItem {
  const LiquidSearchHotItem({
    required this.keyword,
    required this.label,
    this.iconUrl,
    this.showLiveIcon = false,
    this.reason,
  });

  /// 搜索关键词（跳转参数），恒非空（fromJson 里 keyword 是 required）。
  final String keyword;

  /// 展示文案（show_name，缺省时上游回退 keyword）。
  final String label;

  /// 角标图 URL（如「热」「新」角标）；空 ⇒ 不渲染。
  final String? iconUrl;

  /// 直播角标（show_live_icon）；与 iconUrl 互斥由上游数据保证，组件侧 icon 优先。
  final bool showLiveIcon;

  /// 推荐语（recommend_reason，上游已把前导 '·' 换成空格）；仅「搜索发现」有值。
  final String? reason;
}

/// 热搜/搜索发现模型列表 → 热词契约。null/空安全：null 进空列出。
List<LiquidSearchHotItem> liquidSearchHotItems(
  List<SearchTrendingItemModel>? items,
) =>
    <LiquidSearchHotItem>[
      if (items != null)
        for (final e in items)
          LiquidSearchHotItem(
            keyword: e.keyword,
            label: e.showName,
            iconUrl: e.icon?.isNotEmpty == true ? e.icon : null,
            showLiveIcon: e.showLiveIcon ?? false,
            reason: e.recommendReason,
          ),
    ];

/// 搜索结果视频模型 → 视频卡片契约。
///
/// 与 `liquidCardData`（推荐流）的差异口径：
/// - 标题含 `<em>` 高亮标记：纯文本在 `title`（fromJson 已 join），高亮分段
///   在 `titleList` ⇒ 两路都喂（卡片按 segments 渲染命中段 primary 色，
///   对齐 VideoCardH 的观感）；
/// - 徽标（课堂/直播/合作）透传 `badge`（上游 fromJson 已归好档）；
/// - 日期走 `DateFormatUtils.dateFormat`（与 VideoCardH 同函数同源；
///   pubdate 可空 ⇒ 空串，卡片不挂前缀）；
/// - 直播卡（isLive）按 VideoCardH 口径**不显示播放/弹幕计数与时长**
///   （video_card_h.dart:197 `if (videoItem.isLive != true)` 同源）；
/// - 时长是 int 秒（parseDuration 已解析，缺省/空串 ⇒ 0 ⇒ 空串，无鬼值）。
///   ⚠ 上游雷区同族记档：duration 字符串**格式非法**（非 "mm:ss" 形）时
///   `DurationUtils.parseDuration` 的 `int.parse` 无守卫直接抛
///   FormatException（duration_utils.dart:24）——与 rcmd 的 duration 键缺失
///   雷同族，适配器层不代兜。
LiquidVideoCardData liquidSearchCardData(SearchVideoItemModel item) {
  final isLive = item.isLive ?? false;
  return LiquidVideoCardData(
    title: item.title,
    coverUrl: item.cover ?? '',
    author: item.owner.name ?? '',
    playText:
        isLive || item.stat.view == null ? '' : NumUtils.numFormat(item.stat.view),
    danmakuText:
        isLive || item.stat.danmu == null ? '' : NumUtils.numFormat(item.stat.danmu),
    durationText:
        isLive || item.duration <= 0 ? '' : DurationUtils.formatDuration(item.duration),
    badgeText: item.badge ?? '',
    dateText: DateFormatUtils.dateFormat(item.pubdate),
    titleSegments: item.titleList?.isNotEmpty == true ? item.titleList : null,
  );
}

/// 搜索建议条目契约：[plainText] 为纯文本（em 标记已剥离），[segments] 保留
/// 高亮分段（`Em.regTitle` 同源输出，view 侧现状就是内联调它——收进适配器是
/// 让"建议高亮"可测，且未来组件不必 import Em）。
class LiquidSuggestItem {
  const LiquidSuggestItem({
    required this.term,
    required this.plainText,
    required this.segments,
  });

  /// 搜索词（点击建议后填入/跳转用）；上游 term 可空 ⇒ 回退 plainText。
  final String term;

  /// 纯文本（分段 join）。
  final String plainText;

  /// 高亮分段：isEm=true 的段应由组件以 primary 加粗渲染（现 view 的口径）。
  final List<({bool isEm, String text})> segments;
}

/// 搜索建议模型列表 → 建议契约。null/空安全：null 进空列出。
/// 调用点传 `SearchSuggestModel.tag`（controller 存的就是这个列表）。
/// term 空/缺 ⇒ 回退纯文本（上游 view 旧码对非首项 term==null 会 `!` 崩，
/// 契约层把这个崩溃面消掉；可见性门禁仍由页面侧按原口径判断）。
List<LiquidSuggestItem> liquidSuggestItems(List<SearchSuggestItem>? tag) =>
    <LiquidSuggestItem>[
      if (tag != null)
        for (final e in tag)
          () {
            final segments = Em.regTitle(e.textRich);
            final plain = segments.map((s) => s.text).join();
            return LiquidSuggestItem(
              term: e.term?.isNotEmpty == true ? e.term! : plain,
              plainText: plain,
              segments: segments,
            );
          }(),
    ];

/// 搜索卡长按/更多菜单：直接复用 #24b 的视频菜单契约（稍后再看/不感兴趣/
/// 保存封面/访问作者四项同序同源——结果卡与推荐卡的用户心智一致，
/// 不另造菜单）。imageSaveDialog 的标题/封面走搜索模型同名字段。
List<LiquidActionSheetItem> liquidSearchMenuItems(
  BuildContext? context,
  SearchVideoItemModel item, {
  VoidCallback? onRemoved,
}) {
  // liquidVideoMenuItems 收 BaseRcmdVideoItemModel；搜索模型不继承它，
  // 但菜单四项依赖的字段面（bvid/title/cover/owner.mid）两模型同构。
  // 这里做薄桥接而不是再造一份菜单，保证「不感兴趣」确认框等交互只有一份真相。
  return liquidVideoMenuItems(
    context,
    _SearchMenuShim(item),
    onRemoved: onRemoved,
  );
}

/// 菜单桥接：把 SearchVideoItemModel 适配成 liquidVideoMenuItems 的入参
/// （BaseRcmdVideoItemModel 是 abstract，此处落一个仅填字段的私有实现）。
/// 菜单函数实际只读 bvid/title/cover/owner.mid 四个字段面，逐一拷贝。
class _SearchMenuShim extends BaseRcmdVideoItemModel {
  _SearchMenuShim(SearchVideoItemModel inner) {
    bvid = inner.bvid;
    title = inner.title;
    cover = inner.cover;
    owner = inner.owner;
  }
}

/// 搜索结果卡导航：**直接委派 `pushVideoH`**（video_card_h.dart:214-260
/// 顶层函数，四分叉 pugv/live/pgc/默认 av）。与 #24b 的 pushRcmdVideoDetail
/// 不同——那边是逐字复制（源是组件实例方法拿不出来），这边源本就是可复用
/// 顶层函数，**复制即腐化**，故保持单一真相、薄壳委派。
Future<void> pushSearchVideoDetail(HorizontalVideoModel item) =>
    pushVideoH(item);
