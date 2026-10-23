import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart'
    show displacement, kIndicatorSize;
import 'package:PiliPlus/common/widgets/slotted_layout_helper.dart';
import 'package:flutter/rendering.dart' show BoxHitTestResult, ClipRectLayer;
import 'package:material_ui/material_ui.dart' hide RefreshIndicatorStatus;

enum RefreshType { indicator, body }

class RefreshLayout
    extends SlottedMultiChildRenderObjectWidget<RefreshType, RenderBox> {
  const RefreshLayout({
    super.key,
    required this.scale,
    required this.position,
    required this.indicator,
    required this.body,
    this.edgeOffset = 0.0,
  });

  final Animation<double> scale;
  final Animation<double> position;
  final Widget? indicator;
  final Widget body;

  /// 转圈行程起点距 child 顶边的距离（逻辑像素）。
  ///
  /// `0`（默认）= 与上游逐像素一致；首页漂浮式玻璃下由 `TopOverlayInset` 注入
  /// "顶栏展开高度"，让转圈落在玻璃之下、内容之上。**不改变 child 的布局。**
  final double edgeOffset;

  @override
  Iterable<RefreshType> get slots => RefreshType.values;

  @override
  Widget? childForSlot(slot) => switch (slot) {
    .indicator => indicator,
    .body => body,
  };

  @override
  RenderRefreshLayout createRenderObject(BuildContext context) {
    return RenderRefreshLayout(
      scale: scale,
      position: position,
      edgeOffset: edgeOffset,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderRefreshLayout renderObject) {
    renderObject.edgeOffset = edgeOffset;
  }
}

class RenderRefreshLayout extends RenderBox
    with SlottedContainerRenderObjectMixin<RefreshType, RenderBox> {
  RenderRefreshLayout({
    required this.scale,
    required this.position,
    double edgeOffset = 0.0,
  }) : _edgeOffset = edgeOffset {
    scale.addListener(_scaleListener);
    position.addListener(_positionListener);
  }

  final Animation<double> scale;

  final Animation<double> position;

  double _edgeOffset;
  double get edgeOffset => _edgeOffset;
  set edgeOffset(double value) {
    if (_edgeOffset == value) {
      return;
    }
    _edgeOffset = value;
    _layoutIndicator();
    markNeedsPaint();
  }

  double _heightFactor = 0;
  double get heightFactor => _heightFactor;
  set heightFactor(double value) {
    if (_heightFactor == value) {
      return;
    }
    _heightFactor = value;
    _layoutIndicator();
    markNeedsPaint();
  }

  double _scaleFactor = 0;
  double get scaleFactor => _scaleFactor;
  set scaleFactor(double value) {
    if (_scaleFactor == value) {
      return;
    }
    _scaleFactor = value;
    _layoutIndicator();
    markNeedsPaint();
  }

  void _scaleListener() {
    scaleFactor = scale.value;
  }

  void _positionListener() {
    heightFactor = position.value;
  }

  @override
  void dispose() {
    scale.removeListener(_scaleListener);
    position.removeListener(_positionListener);
    super.dispose();
  }

  RenderBox? get indicator => childForSlot(.indicator);
  RenderBox get body => childForSlot(.body)!;

  @override
  void performLayout() {
    final constraints = this.constraints;
    size = constraints.biggest;

    final body = this.body..layout(constraints);
    setOffset(body, .zero);

    _layoutIndicator();
  }

  void _layoutIndicator() {
    final indicator = this.indicator;
    if (indicator == null) return;
    final scaleSize = kIndicatorSize * scaleFactor;
    indicator.layout(
      BoxConstraints.tightFor(width: scaleSize, height: scaleSize),
    );
    setOffset(
      indicator,
      Offset(
        (constraints.maxWidth - scaleSize) / 2,
        // edgeOffset（默认 0）= 上游语义：整段行程下移，child 布局不受影响。
        edgeOffset +
            (kIndicatorSize + displacement) * heightFactor -
            kIndicatorSize +
            (kIndicatorSize - scaleSize) / 2,
      ),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    void doPaint(RenderBox child) {
      context.paintChild(child, getOffset(child) + offset);
    }

    doPaint(body);
    final indicator = this.indicator;
    if (indicator != null && heightFactor > 0 && scaleFactor > 0) {
      final indicatorOffset = getOffset(indicator);
      if (indicatorOffset.dy > 0) {
        context.paintChild(indicator, indicatorOffset + offset);
        layer = null;
      } else {
        layer = context.pushClipRect(
          needsCompositing,
          offset,
          Offset.zero & size,
          (context, offset) {
            context.paintChild(indicator, indicatorOffset + offset);
          },
          clipBehavior: .hardEdge,
          oldLayer: layer as ClipRectLayer?,
        );
      }
    } else {
      layer = null;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final body = this.body;
    return result.addWithPaintOffset(
      offset: getOffset(body),
      position: position,
      hitTest: (BoxHitTestResult result, Offset transformed) {
        return body.hitTest(result, position: transformed);
      },
    );
  }
}
