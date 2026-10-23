// SPDX-License-Identifier: GPL-3.0-or-later
// ============================================================================
// UI 重构暂存组件（排期 #23）
//
// 本目录（lib/ui_liquidglass/）为暂存代码，当前不参与编译、不接入主工程。
// 主任务完成后，本文件将迁移到 lib/common/widgets/liquid/ 并完成接线
// （替换真实头像加载、点赞/点踩/回复回调对接等）。
//
// 组件：LiquidCommentTile —— 评论项（对照 UIdraft 线框④）
// 列表项纪律：整卡不套玻璃，纯布局实现。
// ============================================================================

import 'dart:math' as math;

import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/models/common/image_type.dart';
import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

/// 评论项数据模型。
///
/// 仅承载展示所需字段，暂存期与业务层解耦；接入时由调用方
/// 从评论接口模型转换而来。
class LiquidCommentData {
  const LiquidCommentData({
    required this.userName,
    required this.content,
    this.avatarUrl,
    this.level,
    this.isUp = false,
    this.likeCount = 0,
    this.replyCount = 0,
    this.timeText = '',
    this.isLiked = false,
    this.isDisliked = false,
  });

  /// 用户昵称。
  final String userName;

  /// 评论正文。
  final String content;

  /// 头像地址。
  ///
  /// 暂存期不加载网络图：渲染占位圆（profile 图标）；
  /// 接入时换 cached_network_image。
  final String? avatarUrl;

  /// 等级，如 6 → 徽章 "Lv6"；为 null 时不显示等级徽章。
  final int? level;

  /// UP 主标记徽章 "UP"。
  final bool isUp;

  /// 点赞数。
  final int likeCount;

  /// 回复数。
  final int replyCount;

  /// 时间文案，如 "3小时前"。
  final String timeText;

  /// 当前用户是否已点赞。
  final bool isLiked;

  /// 当前用户是否已点踩。
  final bool isDisliked;
}

/// 评论项组件（线框④）。
///
/// 布局：头像占位圆 + 名称行（昵称 / 等级徽章 / UP 徽章）
/// + 正文 + 操作行（时间、点赞、点踩、回复）。
/// 列表项纪律：不套玻璃容器，由外层列表统一负责背景。
class LiquidCommentTile extends StatelessWidget {
  const LiquidCommentTile({
    super.key,
    required this.data,
    this.onLike,
    this.onDislike,
    this.onReply,
  });

  /// 评论数据。
  final LiquidCommentData data;

  /// 点赞回调。
  final VoidCallback? onLike;

  /// 点踩回调。
  final VoidCallback? onDislike;

  /// 回复回调。
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头像：接线期换装（见文件头"接入时换真实头像加载"）——只改这一处插槽，
          // 其余布局/样式一字不动。
          //   * avatarUrl 有值 ⇒ NetworkImgLayer(type: avatar ⇒ 内部 ClipOval，
          //     圆形裁剪口径与占位圆一致，直径同为 34)；
          //   * 无值 ⇒ 原占位圆（保持原样式与语义）。
          data.avatarUrl?.isNotEmpty == true
              ? NetworkImgLayer(
                  src: data.avatarUrl!,
                  width: 34,
                  height: 34,
                  type: ImageType.avatar,
                )
              : CircleAvatar(
                  radius: 17, // 直径 34
                  backgroundColor: scheme.primaryContainer,
                  child: const Icon(LiquidIcons.profile, size: 18),
                ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 名称行：昵称 + 等级徽章 + UP 徽章
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      data.userName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: LiquidFontFamily.text,
                      ),
                    ),
                    if (data.level != null)
                      _Badge(
                        text: 'Lv${data.level}',
                        background: scheme.tertiaryContainer,
                        foreground: scheme.onTertiaryContainer,
                      ),
                    if (data.isUp)
                      _Badge(
                        text: 'UP',
                        background: scheme.errorContainer,
                        foreground: scheme.onErrorContainer,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                // 正文：最多 5 行，超出省略。
                Text(
                  data.content,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    fontFamily: LiquidFontFamily.text,
                  ),
                ),
                const SizedBox(height: 6),
                // 操作行：时间 / 点赞 / 点踩 / 回复
                Row(
                  children: [
                    Text(
                      data.timeText,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                        fontFamily: LiquidFontFamily.text,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ActionChip(
                      semanticLabel: '点赞',
                      selected: data.isLiked,
                      selectedColor: scheme.primary,
                      onTap: onLike,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LiquidIcons.like, size: 16),
                          const SizedBox(width: 2),
                          Text('${data.likeCount}'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _ActionChip(
                      semanticLabel: '点踩',
                      selected: data.isDisliked,
                      selectedColor: scheme.primary,
                      onTap: onDislike,
                      // 踩：复用 like 图标旋转 180°。
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Transform.rotate(
                            angle: math.pi,
                            child: const Icon(LiquidIcons.like, size: 16),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _ActionChip(
                      semanticLabel: '回复',
                      onTap: onReply,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LiquidIcons.message, size: 16),
                          const SizedBox(width: 2),
                          Text(
                            '回复${data.replyCount > 0 ? ' ${data.replyCount}' : ''}',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 小徽章：等级（Lv6）/ UP 主标记，统一样式。
class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.background,
    required this.foreground,
  });

  /// 徽章文本。
  final String text;

  /// 背景色。
  final Color background;

  /// 前景（文字）色。
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: text,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10,
            color: foreground,
            fontFamily: LiquidFontFamily.text,
          ),
        ),
      ),
    );
  }
}

/// 操作行内的小按钮（点赞 / 点踩 / 回复）。
///
/// 使用 InkWell + Semantics(button: true) 保证可访问性与水波纹反馈。
class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.semanticLabel,
    required this.child,
    this.onTap,
    this.selected = false,
    this.selectedColor,
  });

  /// 无障碍标签。
  final String semanticLabel;

  /// 按钮内容（图标 + 计数文本）。
  final Widget child;

  /// 点击回调。
  final VoidCallback? onTap;

  /// 是否处于选中（已赞 / 已踩）状态。
  final bool selected;

  /// 选中态着色。
  final Color? selectedColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? (selectedColor ?? scheme.primary) : scheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontFamily: LiquidFontFamily.text,
            ),
            child: IconTheme.merge(
              data: IconThemeData(size: 16, color: color),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
