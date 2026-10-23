// SPDX-License-Identifier: GPL-3.0-or-later
//
// #26a 接线适配器（数据层）：把视频评论区既有的 gRPC 模型翻译成
// `lib/common/widgets/liquid/` 的评论项契约（`LiquidCommentData`）。
//
// 划界（docs/UI重构方案.md §0 纪律 2）：**controller 零改动**——本文件只读模型、
// 不碰任何 GetX controller；view 树换装时由页面侧调用这里。
//
// 口径说明（都抄存量 `reply_item_grpc.dart`，不新造）：
//   * 计数：`like`/`count` 是 `$fixnum.Int64` ⇒ `.toInt()`（与 `replyItem.count.toInt()`
//     同源，见 reply_item_grpc.dart:398/569/700）；
//   * 时间：顶层评论（`replyLevel == 0`）用 `DateFormatUtils.format(ctime, format:
//     DateFormatUtils.longFormatDs)`；子评论用 `DateFormatUtils.dateFormat(ctime)`
//     ——与 reply_item_grpc.dart:224-229 的分支逐字一致；
//   * 等级：`member.level.toInt()`（存量在 reply_item_grpc.dart:193-194 交给
//     `BiliUtils.levelPicture` 画等级图；本组件契约只承载 `int? level`，由
//     `LiquidCommentTile` 自行渲染 "Lv{n}" 徽章）；
//   * 头像：gRPC `Member` 里的头像字段叫 **`face`**（不是 `avatar`）；
//   * UP 标记：与存量 `ReplyItemGrpc` 同一口径——拿页面侧的 `upMid` 与
//     `member.mid` 比对（存量是把 `upMid` 传进 item 内部比对）；
//   * 点赞/点踩的"当前用户"状态在 gRPC `ReplyInfo` 里没有直接字段 ⇒ 由调用方
//     以命名参数传入（默认 false），不在适配器里猜。
import 'package:PiliPlus/common/widgets/liquid/liquid_comment_tile.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart';
import 'package:PiliPlus/utils/date_utils.dart';

/// gRPC 评论模型 → 评论项契约（线框④）。
///
/// [upMid]：页面侧的上传者 mid；与 `member.mid` 相等时置 `isUp`。
/// [replyLevel]：0 = 顶层评论（时间用长格式），其余走短格式——同存量分支。
/// [isLiked] / [isDisliked]：当前用户的点赞/点踩态（模型里没有，由调用方给）。
LiquidCommentData liquidCommentData(
  ReplyInfo item, {
  int? upMid,
  int replyLevel = 0,
  bool isLiked = false,
  bool isDisliked = false,
}) {
  final member = item.member;
  return LiquidCommentData(
    userName: member.name,
    content: item.content.message,
    avatarUrl: member.face,
    level: member.level.toInt(),
    isUp: upMid != null && member.mid.toInt() == upMid,
    likeCount: item.like.toInt(),
    replyCount: item.count.toInt(),
    timeText: replyLevel == 0
        ? DateFormatUtils.format(
            item.ctime.toInt(),
            format: DateFormatUtils.longFormatDs,
          )
        : DateFormatUtils.dateFormat(item.ctime.toInt()),
    isLiked: isLiked,
    isDisliked: isDisliked,
  );
}

/// 一批评论 → 一批契约（列表接线用；保持入参顺序，不排序、不过滤）。
List<LiquidCommentData> liquidCommentList(
  List<ReplyInfo> items, {
  int? upMid,
  int replyLevel = 0,
}) =>
    <LiquidCommentData>[
      for (final item in items)
        liquidCommentData(item, upMid: upMid, replyLevel: replyLevel),
    ];