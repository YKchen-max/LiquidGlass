// SPDX-License-Identifier: GPL-3.0-or-later
//
// 双列视频卡片（UIdraft 线框①主体：封面/时长/标题/播放量·弹幕/作者 + 长按挂点）。
// #24b 已接入首页推荐流（rcmd/view.dart）：data 由 liquid_rcmd_adapters 喂入、
// 菜单接 http/video.dart 既有接口；封面走 NetworkImgLayer（与上游 VideoCardV
// 同一渲染口径，见下 build 内注释），不再是不发请求的占位。
// 纪律（docs/问题与解决方案.md §4）：列表卡片**永不真玻璃**——容器用 solid 档
// （纯色半透明 + 发丝描边，零背景采样），真玻璃只留给导航/控制条/弹层。
import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_motion.dart';

class LiquidVideoCardData {
  const LiquidVideoCardData({
    required this.title,
    required this.coverUrl,
    required this.author,
    this.playText = '',
    this.danmakuText = '',
    this.durationText = '',
    this.badgeText = '',
    this.dateText = '',
    this.titleSegments,
  });

  final String title;
  final String coverUrl; // 空串 ⇒ 渲染内置占位（不发网络请求）
  final String author;
  final String playText;
  final String danmakuText;
  final String durationText;

  /// 封面右上角徽标（课堂/直播/合作等）；空串 ⇒ 不渲染（#24b 首页卡无此物）。
  final String badgeText;

  /// 发布日期文案（已格式化，如 "3天前"）；空串 ⇒ 作者行不挂日期前缀。
  final String dateText;

  /// 搜索高亮分段（搜索结果的 `<em>` 命中）：非 null 时标题按段渲染、
  /// 命中段着 primary 色；null ⇒ 纯文本 [title]（#24b 路径不变）。
  final List<({bool isEm, String text})>? titleSegments;
}

class LiquidVideoCard extends StatelessWidget {
  const LiquidVideoCard({
    super.key,
    required this.data,
    this.onTap,
    this.onLongPress,
    this.onMoreTap,
  });

  final LiquidVideoCardData data;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 右下角"更多"按钮回调（审视 C1 修复）：缺省回退 [onLongPress]。
  /// 调用方只传 onTap 时该按钮不再是个死按钮。
  final VoidCallback? onMoreTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(Radius.circular(12));
    // 审视 P2 修复（"卡片按压反馈"）：整卡包 LiquidPressable。
    // 它用 Listener 旁路收指针、**不进手势竞技场** ⇒ 下面的 Semantics 与
    // GestureDetector(onTap/onLongPress)、以及"更多按钮 onMoreTap ?? onLongPress"
    // 的契约（纪律 C1）逐字不动；列表卡 ripple=false（只要缩放、不要水波纹），
    // 按/弹两个时长都过 GlassAccessibility.motionDuration（减弱动效 ⇒ 阶跃）。
    final Widget card = Semantics(
      button: true,
      label: '${data.title}，${data.author}',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: LiquidGlassSurface(
          material: LiquidGlassMaterial.solid,
          borderRadius: radius,
          shadow: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // 封面（16:10）：与上游 VideoCardV 同一口径——LayoutBuilder 取
              // tight 约束尺寸喂 NetworkImgLayer（底层 cached_network_image_ce，
              // 带 lux 减色/暗色开关，见审查文档 T8）；空 coverUrl 退内置占位。
              // 加载中/失败也由 NetworkImgLayer 自己的占位兜（上游同款行为）。
              AspectRatio(
                aspectRatio: 16 / 10,
                child: LayoutBuilder(
                  builder: (context, boxConstraints) {
                    final double maxWidth = boxConstraints.maxWidth;
                    final double maxHeight = boxConstraints.maxHeight;
                    return ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      child: Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: data.coverUrl.isNotEmpty
                                ? NetworkImgLayer(
                                    src: data.coverUrl,
                                    width: maxWidth,
                                    height: maxHeight,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(12),
                                    ),
                                  )
                                : ColoredBox(
                                    color: scheme.surfaceContainerHighest,
                                    child: Center(
                                      child: Icon(
                                        LiquidIcons.explore,
                                        size: 36,
                                        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ),
                          ),
                          if (data.durationText.isNotEmpty)
                            Positioned(
                              right: 6,
                              bottom: 6,
                              child: _DurationChip(text: data.durationText),
                            ),
                          // 徽标 chip：对齐上游 PBadge 的落位（top:6/right:6，
                          // video_card_h.dart）与 primary 型配色。
                          if (data.badgeText.isNotEmpty)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: _BadgeChip(text: data.badgeText),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // 标题：搜索高亮分段（em→primary）或纯文本，两行省略不变。
                    if (data.titleSegments != null)
                      Text.rich(
                        TextSpan(
                          children: <InlineSpan>[
                            for (final seg in data.titleSegments!)
                              TextSpan(
                                text: seg.text,
                                style: seg.isEm
                                    ? TextStyle(color: scheme.primary)
                                    : null,
                              ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                          fontFamily: LiquidFontFamily.text,
                          color: scheme.onSurface,
                        ),
                      )
                    else
                      Text(
                        data.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                          fontFamily: LiquidFontFamily.text,
                          color: scheme.onSurface,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        _Stat(icon: LiquidIcons.play, text: data.playText, scheme: scheme),
                        const SizedBox(width: 8),
                        _Stat(icon: LiquidIcons.danmaku, text: data.danmakuText, scheme: scheme),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            // 日期前缀对齐上游 VideoCardH 的 "pubdate  author"
                            // 双空格分隔（date_utils 空值 ⇒ 空前缀 ⇒ 无前缀）。
                            '${data.dateText.isNotEmpty ? '${data.dateText}  ' : ''}${data.author}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                          ),
                        ),
                        // 更多按钮：与长按同义（线框①的操作菜单挂点）
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onMoreTap ?? onLongPress,
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              LiquidIcons.more,
                              size: 16,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Transform.scale 不改布局尺寸 ⇒ 双列网格里只有画面在"呼吸"，占位不变。
    // #24b：网格 cell 是 tight 高度（delegate extent 估算）——**余量留在玻璃外**：
    // Align 顶对齐 ⇒ 玻璃本体只包内容真实高度，extent 估大时多出的是透明区而不是
    // 玻璃内空缝；估小仍会裁（故 extent 取测量值+字体度量余量，见 rcmd/view.dart 注释）。
    return Align(
      alignment: Alignment.topCenter,
      child: LiquidPressable(
        pressedScale: 0.96,
        borderRadius: radius, // ripple=false 时仅作形状备忘，不裁剪 child
        child: card,
      ),
    );
  }
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: scheme.onPrimary,
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.text, required this.scheme});

  final IconData icon;
  final String text;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 12, color: scheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}
