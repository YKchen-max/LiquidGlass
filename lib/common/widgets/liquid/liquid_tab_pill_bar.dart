// SPDX-License-Identifier: GPL-3.0-or-later
//
// #27 U5（动态页接线）：[TabController] ↔ [LiquidPillBar] 双向同步包装。
//
// 来源：#24b 首页成功模式（pages/home/view.dart 的 `_LiquidChannelRow`）的
// **公共化**版本——首页那份是页内私有 widget，动态页要同一套语义但不回改
// 首页（每屏一个提交串、可单屏回滚），故落一个新文件（新组件可加新文件的
// 既定口径），结构逐字对齐首页：
//   * 滑页 → 选中 pill 跟随：TabController listener（initState /
//     didUpdateWidget / dispose 三处生命周期齐）；
//   * pill 点 → 切页：本组件内部 `controller.animateTo(i)`（首页是页面侧
//     onSelected 里调，语义等价；这里收进组件，页面侧 onSelected 只保留
//     「回顶/触感」这类页面语义，同原 TabBar.onTap）；
//   * 材质档位不由本 widget 决定：玻璃预算由页面侧 [selectionGlass] 给定
//     （动态页传 false，案 A：本屏真玻璃预算＝主底导 1 处已占，与首页同口径）。
//
// import 纪律（S16 教训）：只引 material_ui（fork），**不引 flutter/material**
// ——u25 绊线组⑤扫本目录零 flutter/material 引用。
import 'package:material_ui/material_ui.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_pill_bar.dart';

/// 横向胶囊 tab 行：与 [TabController] 双向同步（滑页跟随 / 点 pill 切页）。
class LiquidTabPillBar extends StatefulWidget {
  const LiquidTabPillBar({
    super.key,
    required this.controller,
    required this.labels,
    this.onSelected,
    this.height = 40,
    this.selectionGlass = false,
  });

  /// 被同步的 TabController（页面/TabBarView 共用同一个实例）。
  final TabController controller;

  /// 与 controller.length 对齐的标签文案（顺序即 index）。
  final List<String> labels;

  /// pill 被点时回调（**在** animateTo 之前触发，语义同原 TabBar.onTap：
  /// 此时 `indexIsChanging` 尚为假，页面侧据此做回顶/触感等附加语义）。
  final ValueChanged<int>? onSelected;

  /// 条高（与 [LiquidPillBar.height] 同值透传）。
  final double height;

  /// 选中片是否真玻璃（玻璃预算口径，见 [LiquidPillBar.selectionGlass]）。
  final bool selectionGlass;

  @override
  State<LiquidTabPillBar> createState() => _LiquidTabPillBarState();
}

class _LiquidTabPillBarState extends State<LiquidTabPillBar> {
  late int _selected = widget.controller.index;

  void _sync() {
    final index = widget.controller.index;
    if (_selected != index) {
      setState(() => _selected = index);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
  }

  @override
  void didUpdateWidget(LiquidTabPillBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
      _selected = widget.controller.index;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: LiquidPillBar(
        items: <LiquidPillBarItem>[
          for (int i = 0; i < widget.labels.length; i++)
            LiquidPillBarItem(id: 'tab-$i', label: widget.labels[i]),
        ],
        selectedIndex: _selected,
        onSelected: (i) {
          widget.onSelected?.call(i);
          if (widget.controller.index != i) {
            widget.controller.animateTo(i);
          }
        },
        selectionGlass: widget.selectionGlass,
        height: widget.height,
      ),
    );
  }
}
