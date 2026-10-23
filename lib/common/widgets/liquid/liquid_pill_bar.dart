// SPDX-License-Identifier: GPL-3.0-or-later
//
// 频道胶囊行（UIdraft 线框①顶部：直播/推荐/热门/分区/番剧/影视）。
// UI 重构暂存组件（排期 #23 / docs/UI重构方案.md U1）：本目录暂不编译、不接入主文件，
// 主任务完成后迁移到 lib/common/widgets/liquid/ 并接线 pages/home + pages/rcmd。
// 只消费 liquid_glass_kit 的稳定入口（Surface/Theme/token/icons）。
import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_motion.dart';
import 'package:PiliPlus/utils/glass_accessibility.dart';

/// 频道行单项。
class LiquidPillBarItem {
  const LiquidPillBarItem({required this.id, required this.label, this.icon});

  final String id;
  final String label;
  final IconData? icon;
}

/// 横向滚动的胶囊频道行：选中项套 glassRegular 玻璃，未选中为纯文本。
///
/// **B2 选中项自动可见**（治 打磨清单旗2 族根）：selectedIndex 变化（滑动切页/
/// 点击/首帧 initIndex 非 0）后自动 `Scrollable.ensureVisible`，把选中片滚回
/// 视口——胶囊内补宽于原生 TabBar ⇒ 末位 tab 会停在滚动缘被裁（动态页"UP"、
/// 搜索结果页"直播间"同族）。home/搜索结果/动态三处消费同受益（一处修）。
class LiquidPillBar extends StatefulWidget {
  const LiquidPillBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    this.onSelected,
    this.height = 40,
    this.selectionGlass = true,
  });

  final List<LiquidPillBarItem> items;
  final int selectedIndex;
  final ValueChanged<int>? onSelected;
  final double height;

  /// 选中片是否用真玻璃（glass-on-glass 的 lens 观感）。
  ///
  /// **玻璃预算**（问题文档 §4：一屏真玻璃 ≤2）：首页接线时 header 玻璃(1)＋
  /// 底导玻璃(2) 已满 ⇒ 频道行选中片传 **false** 退 solid 档高亮（纯色半透明＋
  /// 发丝描边，零背景采样）；预览页/单独使用保持 true（[docs/U2-首页接线计划-20261005]
  /// 拍板点 P-24b-1 案 A）。
  final bool selectionGlass;

  @override
  State<LiquidPillBar> createState() => _LiquidPillBarState();
}

class _LiquidPillBarState extends State<LiquidPillBar> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 首帧也可能选中项在视口外（如搜索结果页 initIndex 非 0）
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSelectedVisible());
  }

  @override
  void didUpdateWidget(LiquidPillBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _ensureSelectedVisible());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 估算单项宽度：文案实测宽（TextPainter，与环境同字体/同缩放 ⇒ 与渲染一致）
  /// ＋ 水平内边距 32（16×2）＋ icon（如有 22＝16 图标 + 6 间距）。
  double _itemExtent(int i) {
    final item = widget.items[i];
    final selected = i == widget.selectedIndex;
    final painter = TextPainter(
      text: TextSpan(
        text: item.label,
        style: TextStyle(
          fontSize: 14,
          fontFamily: LiquidFontFamily.text,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width + 32 + (item.icon != null ? 22 : 0);
  }

  /// B2 把选中片滚回视口：**两段式**——
  /// ① 粗滚（TextPainter 估算偏移）：ListView 懒构建，视口外选中项不在树上，
  ///    GlobalKey/ensureVisible 对它们必然空操作 ✗（实测踩过）；估算与渲染
  ///    同字体解析 ⇒ 误差只到"几十 px 级"，足够把选中项拉进视口/缓存区 ⇒ 被构建；
  /// ② 精调（`Scrollable.ensureVisible`）：选中项已在树 ⇒ 用**真实几何**居中，
  ///    消掉①的估算残差（3-4 px/项，长行会累积——只用作粗滚 ✓）。
  void _ensureSelectedVisible() {
    if (!_scrollController.hasClients || widget.items.isEmpty) {
      return;
    }
    final pos = _scrollController.position;
    final index = widget.selectedIndex.clamp(0, widget.items.length - 1);
    double target = 12; // ListView 水平 padding
    for (int i = 0; i < index; i++) {
      target += _itemExtent(i) + 8; // separator 8
    }
    final center = target + _itemExtent(index) / 2;
    final offset = (center - pos.viewportDimension / 2)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    final d = GlassAccessibility.motionDuration(
      const Duration(milliseconds: 300),
    );
    if ((pos.pixels - offset).abs() < 0.5) {
      _fineTuneSelected();
    } else {
      _scrollController
          .animateTo(offset, duration: d, curve: Curves.easeOut)
          .then((_) => _fineTuneSelected());
    }
  }

  /// 精调：选中项已被构建 ⇒ GlobalKey 有 context ⇒ 用真实几何居中。
  final GlobalKey _selectedKey = GlobalKey();

  void _fineTuneSelected() {
    if (!mounted) return;
    final ctx = _selectedKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: GlassAccessibility.motionDuration(
        const Duration(milliseconds: 200),
      ),
      alignment: 0.5,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: widget.height,
      child: ListView.separated(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: widget.items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final selected = i == widget.selectedIndex;
          final pill = Semantics(
            button: true,
            selected: selected,
            label: widget.items[i].label,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onSelected?.call(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (widget.items[i].icon != null) ...<Widget>[
                      Icon(
                        widget.items[i].icon,
                        size: 16,
                        color: selected ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      widget.items[i].label,
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: LiquidFontFamily.text,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          // 审视 A2 修复：选中/取消用交叉淡入淡出过渡（180ms），
          // 避免玻璃层（BackdropFilter 图层）瞬时挂载/卸载造成的硬切与掉帧观感。
          // 审视 P2 修复（按压反馈）：LiquidPressable 包在 AnimatedSwitcher **外层**——
          // ① 交叉淡入期间树上同时存在新旧两层 pill，包在里面会出现"两套按压状态"、
          //    选中切换时按压态还会被重建丢失；
          // ② 包在外面不动 AnimatedSwitcher 与 ValueKey('glass'/'plain') 的结构。
          return LiquidPressable(
            // B2 精调接缝：key 只挂选中项（AnimatedSwitcher 交换的是内层 child，
            // 外层元素跨档位/选中态稳定 ⇒ 构建后 context 恒在）。
            key: selected ? _selectedKey : null,
            pressedScale: 0.94,
            child: AnimatedSwitcher(
              // 时长过无障碍钩子（#18）：减弱动效 ⇒ Duration.zero ⇒ 交叉淡入退化为瞬时替换。
              duration: GlassAccessibility.motionDuration(
                const Duration(milliseconds: 180),
              ),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              // 审视 P2 修复（过渡期双重命中）：AnimatedSwitcher 默认布局里 outgoing
              // child 在 180ms 窗口内**仍在命中测试栈**（新旧两个 pill 同时可点，
              // 快速切换可能点中已取消的那项）。layoutBuilder 给非当前 child 包
              // IgnorePointer：视觉交叉淡入不变，命中只认当前项。
              // 注意 `AnimatedSwitcherLayoutBuilder` 的签名是
              // `(Widget? currentChild, List<Widget> previousChildren)`——没有 BuildContext。
              layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) => Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  for (final Widget old in previousChildren) IgnorePointer(child: old),
                  // 空感知元素（`?x`）：currentChild 为 null 时不往 children 里塞东西，
                  // 比 `if (currentChild != null) currentChild` 更直白也不会触发 lint。
                  ?currentChild,
                ],
              ),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: selected
                  ? LiquidGlassSurface(
                      // key 随档位变：solid↔regular 切换时 AnimatedSwitcher 视为新 child，
                      // 走交叉淡入而不是原地换材质（观感跳变 ✗）。
                      key: ValueKey<String>(widget.selectionGlass ? 'glass' : 'solid'),
                      material: widget.selectionGlass
                          ? LiquidGlassMaterial.regular
                          : LiquidGlassMaterial.solid,
                      borderRadius: BorderRadius.circular(widget.height / 2),
                      shadow: false, // 频道行贴内容层，不叠投影
                      child: pill,
                    )
                  : KeyedSubtree(
                      key: const ValueKey<String>('plain'),
                      child: pill,
                    ),
            ),
          );
        },
      ),
    );
  }
}
