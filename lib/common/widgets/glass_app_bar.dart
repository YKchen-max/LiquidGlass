import 'package:material_ui/material_ui.dart';

import 'package:PiliPlus/common/design_tokens.dart';

/// 「假玻璃」顶栏。
///
/// 视觉构成：半透明填充 + 自上而下的微渐变高光 + 1px 描边 + 底部 24 圆角。
///
/// **为什么不用 BackdropFilter / ImageFilter.blur：**
/// 实时高斯模糊是逐帧的离屏渲染，中低端安卓机（尤其 Adreno 6xx 段）在滚动列表时
/// 会明显掉帧，而一个顶栏换来的观感提升远不值这个代价。
/// 玻璃感靠「边」和「光」即可成立：描边给出材质边界，渐变给出受光方向。
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.showBottomDivider = false,
    this.height = 52,
  });

  final String? title;
  final Widget? leading;
  final List<Widget>? actions;

  /// 是否在底部额外画一条分隔线（默认关闭：描边已经提供了边界感）。
  final bool showBottomDivider;

  final double height;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final stroke = DesignTokens.glassStroke(isDark);

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: DesignTokens.radiusLarge,
        bottomRight: DesignTokens.radiusLarge,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          // 注意：color 与 gradient 同时存在于 BoxDecoration 是合法的，
          // 渐变会绘制在颜色之上，二者叠加得到「半透明底 + 顶部受光」。
          color: DesignTokens.glassFill(isDark),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              DesignTokens.glassHighlightTop(isDark),
              DesignTokens.glassHighlightBottom,
            ],
          ),
          border: Border.all(color: stroke, width: 1),
        ),
        child: SizedBox(
          height: height,
          child: Column(
            children: <Widget>[
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: <Widget>[
                      ?leading,
                      if (title != null)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              title!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      ...?actions,
                    ],
                  ),
                ),
              ),
              if (showBottomDivider)
                SizedBox(height: 1, width: double.infinity, child: ColoredBox(color: stroke)),
            ],
          ),
        ),
      ),
    );
  }
}

