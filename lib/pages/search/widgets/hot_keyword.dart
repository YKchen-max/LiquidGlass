import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_search_adapters.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/rendering.dart'
    show
        ContainerRenderObjectMixin,
        MultiChildLayoutParentData,
        RenderBoxContainerDefaultsMixin,
        BoxHitTestResult;
import 'package:liquid_glass_kit/liquid_glass_kit.dart';
import 'package:material_ui/material_ui.dart';

class SliverHotKeyword extends StatelessWidget {
  // #25 接线：消费适配器契约（LiquidSearchHotItem），不再直接吃上游模型。
  // 字段映射：label=showName、iconUrl=icon（空串已归 null）、reason=recommendReason
  //（前导 '·'→空格的加工在模型 fromJson，本组件渲染逻辑逐行未动）。
  final List<LiquidSearchHotItem> hotSearchList;
  final Function? onClick;
  const SliverHotKeyword({
    super.key,
    required this.hotSearchList,
    this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    late final style = TextStyle(
      fontSize: 14,
      color: ColorScheme.of(context).outline,
    );

    late final cacheHeight = (MediaQuery.devicePixelRatioOf(context) * 15.0)
        .round();

    final grid = _HotKeywordGrid(
      mainAxisSpacing: 5,
      crossAxisSpacing: 0.4,
      crossAxisCount: 2,
      children: hotSearchList
            .map(
              (i) => Material(
                type: .transparency,
                borderRadius: const .all(.circular(3)),
                child: InkWell(
                  borderRadius: const .all(.circular(3)),
                  onTap: () => onClick?.call(i.keyword),
                  child: Padding(
                    padding: const .only(left: 2, right: 10),
                    child: Tooltip(
                      message: i.label,
                      child: Row(
                        children: [
                          Flexible(
                            child: Padding(
                              padding: const .fromLTRB(6, 5, 0, 5),
                              child: Text(
                                i.label,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ),
                          if (i.iconUrl != null)
                            Padding(
                              padding: const .only(left: 4),
                              child: CachedNetworkImage(
                                height: 15,
                                memCacheHeight: cacheHeight,
                                imageUrl: ImageUtils.thumbnailUrl(i.iconUrl!),
                                placeholder: (_, _) => const SizedBox.shrink(),
                              ),
                            )
                          else if (i.showLiveIcon)
                            Padding(
                              padding: const .only(left: 4),
                              child: Image.asset(
                                Assets.livingRect,
                                width: 48,
                                height: 15,
                                cacheHeight: cacheHeight,
                              ),
                            )
                          else if (i.reason?.isNotEmpty == true)
                            Text(i.reason!, style: style),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
    );

    // 搜索页"热词卡" = **一整块**玻璃（不是每个词各糊一次：列表项/卡片一律不上玻璃）。
    // 纯色档返回上游结构（不套壳、不加 padding ⇒ 与上游逐像素一致）。
    if (!LiquidGlassRuntime.glassEnabled) {
      return SliverToBoxAdapter(child: grid);
    }
    return SliverToBoxAdapter(
      child: LiquidGlassSurface(
        material: LiquidGlassMaterial.regular,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        // 玻璃档给卡片一点内边距，让文字不贴边（这是玻璃档的设计，纯色档几何不变）。
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        shadow: false,
        child: grid,
      ),
    );
  }
}

class _HotKeywordGrid extends MultiChildRenderObjectWidget {
  const _HotKeywordGrid({
    required this.crossAxisCount,
    this.mainAxisSpacing = 0.0,
    this.crossAxisSpacing = 0.0,
    required super.children,
  }) : assert(crossAxisCount > 0),
       assert(mainAxisSpacing >= 0.0),
       assert(crossAxisSpacing >= 0.0);

  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderHotKeywordGrid(
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHotKeywordGrid renderObject,
  ) {
    renderObject
      ..crossAxisCount = crossAxisCount
      ..mainAxisSpacing = mainAxisSpacing
      ..crossAxisSpacing = crossAxisSpacing;
  }
}

class _RenderHotKeywordGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, MultiChildLayoutParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, MultiChildLayoutParentData> {
  _RenderHotKeywordGrid({
    required this._crossAxisCount,
    required this._mainAxisSpacing,
    required this._crossAxisSpacing,
  });

  int _crossAxisCount;
  int get crossAxisCount => _crossAxisCount;
  set crossAxisCount(int value) {
    if (_crossAxisCount == value) return;
    _crossAxisCount = value;
    markNeedsLayout();
  }

  double _mainAxisSpacing;
  double get mainAxisSpacing => _mainAxisSpacing;
  set mainAxisSpacing(double value) {
    if (_mainAxisSpacing == value) return;
    _mainAxisSpacing = value;
    markNeedsLayout();
  }

  double _crossAxisSpacing;
  double get crossAxisSpacing => _crossAxisSpacing;
  set crossAxisSpacing(double value) {
    if (_crossAxisSpacing == value) return;
    _crossAxisSpacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! MultiChildLayoutParentData) {
      child.parentData = MultiChildLayoutParentData();
    }
  }

  @override
  void performLayout() {
    final constraints = this.constraints;
    final childWidth =
        (constraints.maxWidth - mainAxisSpacing * (crossAxisCount - 1)) /
        crossAxisCount;
    final c = BoxConstraints(maxWidth: childWidth);
    var child = firstChild;
    double? childHeight;
    int index = 0;
    while (child != null) {
      if (childHeight == null) {
        childHeight = (child..layout(c, parentUsesSize: true)).size.height;
      } else {
        child.layout(c);
      }
      final parentData = child.parentData as MultiChildLayoutParentData
        ..offset = Offset(
          (childWidth + mainAxisSpacing) * (index % crossAxisCount),
          (childHeight + crossAxisSpacing) * (index ~/ crossAxisCount),
        );
      child = parentData.nextSibling;
      index++;
    }
    final row = (index / crossAxisCount).ceil();
    size = constraints.constrainDimensions(
      constraints.maxWidth,
      row * childHeight! + crossAxisSpacing * (row - 1),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}
