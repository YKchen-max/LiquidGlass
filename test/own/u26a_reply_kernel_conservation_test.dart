// SPDX-License-Identifier: GPL-3.0-or-later
//
// #26a ②b 守恒绊线（Lead 裁定 item 1）：钉住 `reply_item_grpc.dart` 的**内核面**
// —— 换装（顶层换 liquid 展示壳）**只许动展示层**，下面这些一律不许消失 ✗。
//
// 口径照项目绊线文化（u24b 封面 / u25 接线 / u26a 头像）：**源码文本扫描** ✓
// ——不渲染 widget（43 KB 内核跑不动也没必要 ✓），只钉"这些符号还在文件里"。
//
// 钉两类：
//   (a) **结构**：子评论树（`replies.mapIndexed`）＋ 长按菜单（`onLongPress: showMore`）
//       —— 这两条一旦被"最省的一刀"（整块顶替 `_buildContent`）切掉，当场红 ✓；
//   (b) **交互面**：构造参数/回调名逐个 contains ✓（`replyItem` / `replyLevel` /
//       `replyReply` / `onReply` / `onDelete` / `upMid` / `getTag` / `onCheckReply` /
//       `onToggleTop` / `heroTag`）—— 10 处回调守恒的机器可查版本 ✓。
//
// 为什么它必须在**换装前**就落地 ✓：换装那一刀要在 43 KB 文件里切三段，
// 有了本绊线，"切多了/切错了"会立刻变红，而不是等到手工比对才发现 ✗✓。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relative) {
  final candidates = <String>[relative, 'app/$relative'];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) return file.readAsStringSync();
  }
  fail('找不到 $relative（cwd=${Directory.current.path}）');
}

void main() {
  final source = _read('lib/pages/video/reply/widgets/reply_item_grpc.dart');

  group('#26a ②b 守恒绊线：reply_item_grpc 内核面不得被换装切掉', () {
    test('结构：子评论树与长按菜单仍在', () {
      expect(
        source.contains('replies.mapIndexed'),
        isTrue,
        reason: '子评论树的渲染入口（换装若整块顶替 _buildContent，这里会消失 ✗）',
      );
      expect(
        source.contains('onLongPress: showMore'),
        isTrue,
        reason: '长按菜单（more panel）入口必须保留',
      );
      expect(
        source.contains('onTap: () => replyReply?.call'),
        isTrue,
        reason: '回复入口（点整条评论 = 回复）必须保留',
      );
    });

    test('交互面：10 处回调/参数名逐个仍在', () {
      const names = <String>[
        'replyItem',
        'replyLevel',
        'replyReply',
        'onReply',
        'onDelete',
        'upMid',
        'getTag',
        'onCheckReply',
        'onToggleTop',
        'heroTag',
      ];
      final missing = names.where((n) => !source.contains(n)).toList();
      expect(
        missing,
        isEmpty,
        reason: '以下符号在 reply_item_grpc.dart 里找不到了 ⇒ 换装吃掉了内核面 ✗：$missing',
      );
    });

    test('子评论仍在同一文件内被渲染（而非被搬到别处/删除）', () {
      // 子评论段的存在性 + 数量提示：至少 3 处 replies 相关处理
      final hits = RegExp(r'replies').allMatches(source).length;
      expect(
        hits,
        greaterThanOrEqualTo(3),
        reason: 'replies 出现次数过少（$hits）⇒ 子评论逻辑疑似被削 ✗',
      );
    });
  });
}