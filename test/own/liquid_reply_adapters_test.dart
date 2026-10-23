// SPDX-License-Identifier: GPL-3.0-or-later
//
// #26a 单测：`liquid_reply_adapters`（gRPC 评论模型 → 评论项契约）。
//
// 口径纪律（抄存量 reply_item_grpc.dart，见适配器文件头的说明）：
//   * 头像字段是 `Member.face`（不是 avatar）；
//   * 时间按 `replyLevel` 分支，且**直接与 `DateFormatUtils` 同源比对**（不写死字符串，
//     避免把 locale/格式细节固化成脆断言）；
//   * UP 标记 = `member.mid == upMid`（与存量把 upMid 传进 item 内比对同口径）。
import 'package:PiliPlus/common/widgets/liquid/liquid_reply_adapters.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

ReplyInfo _reply({
  int mid = 1001,
  String name = '测试用户',
  String face = 'https://i0.hdslb.com/bfs/face/x.jpg',
  int level = 6,
  String message = '这是一条评论',
  int like = 12,
  int count = 3,
  int ctime = 1700000000,
}) =>
    ReplyInfo(
      member: Member(
        mid: Int64(mid),
        name: name,
        face: face,
        level: Int64(level),
      ),
      content: Content(message: message),
      like: Int64(like),
      count: Int64(count),
      ctime: Int64(ctime),
    );

void main() {
  group('liquidCommentData：模型 → 评论项契约', () {
    test('字段逐项对齐（含 face → avatarUrl）', () {
      final data = liquidCommentData(_reply());
      expect(data.userName, '测试用户');
      expect(data.content, '这是一条评论');
      expect(data.avatarUrl, 'https://i0.hdslb.com/bfs/face/x.jpg');
      expect(data.level, 6);
      expect(data.likeCount, 12);
      expect(data.replyCount, 3);
      expect(data.isLiked, isFalse);
      expect(data.isDisliked, isFalse);
    });

    test('UP 标记：mid 与 upMid 相等才为真', () {
      final item = _reply(mid: 42);
      expect(liquidCommentData(item, upMid: 42).isUp, isTrue);
      expect(liquidCommentData(item, upMid: 43).isUp, isFalse);
      // 未提供 upMid ⇒ 不猜（恒 false）
      expect(liquidCommentData(item).isUp, isFalse);
    });

    test('点赞/点踩态由调用方传入（模型里没有该字段）', () {
      final data = liquidCommentData(_reply(), isLiked: true);
      expect(data.isLiked, isTrue);
      expect(data.isDisliked, isFalse);
    });

    test('时间文案与存量同源：replyLevel==0 走长格式，其余走短格式', () {
      final item = _reply(ctime: 1700000000);
      expect(
        liquidCommentData(item).timeText,
        DateFormatUtils.format(
          1700000000,
          format: DateFormatUtils.longFormatDs,
        ),
      );
      expect(
        liquidCommentData(item, replyLevel: 1).timeText,
        DateFormatUtils.dateFormat(1700000000),
      );
    });

    test('计数为 0 时不抛、原样给 0（不造占位文案）', () {
      final data = liquidCommentData(_reply(like: 0, count: 0));
      expect(data.likeCount, 0);
      expect(data.replyCount, 0);
    });
  });

  group('liquidCommentList：批量适配', () {
    test('保持入参顺序、逐项映射', () {
      final list = liquidCommentList([
        _reply(mid: 1, name: 'A'),
        _reply(mid: 2, name: 'B'),
      ]);
      expect(list.map((e) => e.userName).toList(), ['A', 'B']);
    });

    test('空列表 ⇒ 空结果', () {
      expect(liquidCommentList(const []), isEmpty);
    });

    test('upMid 透传到每一项', () {
      final list = liquidCommentList(
        [_reply(mid: 7), _reply(mid: 8)],
        upMid: 8,
      );
      expect(list.map((e) => e.isUp).toList(), [false, true]);
    });
  });
}