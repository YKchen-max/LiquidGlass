// SPDX-License-Identifier: GPL-3.0-or-later
//
// 底部悬浮胶囊导航（UIdraft 线框全页底部：首页/动态/我的）。
// **T7 定案（2026-10-04 审查，2026-10-06 E1 回填）**：生产接线保留
// `floating_navigation_bar.dart`（与上游 NavigationBar 语义兼容、已集成
// hideBottomBar/barOffset/labelBehavior/dynCount Badge）；**本组件不删**——
// 定位＝预览页（/liquidPreview）的**设计参照**（悬浮胶囊造型的视觉样本），
// 非死代码、非接线候选。若将来产品要换悬浮胶囊造型：先补 badge 挂点与
// hide/offset 集成再谈替换（另立任务），不要直接接线 ✗。
import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_motion.dart';
import 'package:PiliPlus/utils/glass_accessibility.dart';

class LiquidFloatingNavItem {
  const LiquidFloatingNavItem({
    required this.id,
    required this.icon,
    required this.label,
  });

  final String id;
  final IconData icon;
  final String label;
}

/// 悬浮玻璃胶囊导航：自带底部对齐与留白，父级直接放进 Stack/Column 即可。
class LiquidFloatingNav extends StatelessWidget {
  const LiquidFloatingNav({
    super.key,
    required this.items,
    required this.selectedIndex,
    this.onSelected,
    this.height = 64,
  });

  final List<LiquidFloatingNavItem> items;
  final int selectedIndex;
  final ValueChanged<int>? onSelected;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 审视 C2 修复：底部留白叠加系统手势区/导航条安全区，全面屏不压手势条
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(bottom: 12 + bottomInset),
        child: LiquidGlassSurface(
          material: LiquidGlassMaterial.regular,
          borderRadius: BorderRadius.circular(height / 2),
          shadow: true,
          child: SizedBox(
            height: height,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < items.length; i++)
                  // 审视 P2 修复（按压反馈）：tab 目标小 ⇒ 缩得更狠（0.92）才看得见，
                  // 整卡 0.96 的量级放在 44pt 宽的图标上几乎无感。
                  LiquidPressable(
                    pressedScale: 0.92,
                    child: _NavItem(
                      item: items[i],
                      selected: i == selectedIndex,
                      scheme: scheme,
                      onTap: () => onSelected?.call(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.scheme,
    required this.onTap,
  });

  final LiquidFloatingNavItem item;
  final bool selected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 设计符合性（用户 2026-10-02 核查项）：选中 tab = 独立的**玻璃 tab 片**（glass-on-glass），
    // 与频道胶囊行的选中语义同语言；真玻璃预算内第 2 块（条=1 + 片=1，纪律 ≤2 达标）。
    // 选中/取消仍是双层交叉淡入（A2 修复保留），玻璃片随 AnimatedOpacity 淡入；
    // 嵌套 BackdropFilter 采样的是外层玻璃条的输出（模糊之上再模糊）——即 Apple 的 lens 观感，属预期。
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          children: <Widget>[
            _content(color: scheme.onSurfaceVariant, emphasized: false),
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: selected ? 1 : 0,
                // 审视 A2 的双层交叉淡入（200ms）保留；时长过无障碍钩子
                // （#18：减弱动效 ⇒ Duration.zero ⇒ 瞬时到位，不再"淡"）。
                duration: GlassAccessibility.motionDuration(
                  const Duration(milliseconds: 200),
                ),
                curve: Curves.easeOut,
                child: LiquidGlassSurface(
                  material: LiquidGlassMaterial.regular,
                  borderRadius: BorderRadius.circular(20),
                  shadow: false, // 导航条本体已有投影，tab 片不叠
                  child: _content(color: scheme.primary, emphasized: true),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content({required Color color, required bool emphasized}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(item.icon, size: 22, color: color),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 11,
              fontFamily: LiquidFontFamily.text,
              fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
