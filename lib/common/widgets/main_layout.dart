import 'package:PiliPlus/common/widgets/slotted_layout_helper.dart';
import 'package:flutter/rendering.dart' show ChildLayoutHelper;
import 'package:material_ui/material_ui.dart';

enum MainType { sideBar, bottomNav, body }

class MainLayout
    extends SlottedMultiChildRenderObjectWidget<MainType, RenderBox> {
  const MainLayout({
    super.key,
    required this.sideBar,
    required this.bottomNav,
    required this.body,
    this.overlaySideBar = false,
  });

  final Widget? sideBar;
  final Widget? bottomNav;
  final Widget body;

  /// 覆盖式侧栏（U2-2）。
  ///
  /// `true` 时 body 按**全宽**布局（内容自己留出侧栏宽度，见 `OverlayInsets`），
  /// 且侧栏**改到最后绘制** —— 这是玻璃能采样到"背后内容"的**前提**（不是样式细节）：
  /// 原顺序是 sideBar → body → bottomNav，侧栏先画就没有可采样的背景。
  ///
  /// 默认 `false` = 上游并排布局，逐像素不变。
  final bool overlaySideBar;

  @override
  Iterable<MainType> get slots => MainType.values;

  @override
  Widget? childForSlot(slot) => switch (slot) {
    .sideBar => sideBar,
    .bottomNav => bottomNav,
    .body => body,
  };

  @override
  SlottedContainerRenderObjectMixin<MainType, RenderBox> createRenderObject(
    BuildContext context,
  ) {
    return _RenderMainLayout(overlaySideBar: overlaySideBar);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    SlottedContainerRenderObjectMixin<MainType, RenderBox> renderObject,
  ) {
    (renderObject as _RenderMainLayout).overlaySideBar = overlaySideBar;
  }
}

class _RenderMainLayout extends RenderBox
    with
        SlottedContainerRenderObjectMixin<MainType, RenderBox>,
        SlottedLayoutMixin {
  _RenderMainLayout({bool overlaySideBar = false})
    : _overlaySideBar = overlaySideBar;

  bool _overlaySideBar;
  bool get overlaySideBar => _overlaySideBar;
  set overlaySideBar(bool value) {
    if (_overlaySideBar == value) return;
    _overlaySideBar = value;
    markNeedsLayout();
  }

  RenderBox? get sideBar => childForSlot(.sideBar);
  RenderBox? get bottomNav => childForSlot(.bottomNav);
  RenderBox get body => childForSlot(.body)!;

  @override
  Iterable<MainType> get slots => MainType.values;

  @override
  void performLayout() {
    final constraints = this.constraints;
    size = constraints.biggest;

    final Offset bodyOffset;
    final BoxConstraints bodyConstraints;

    final sideBar = this.sideBar;
    if (sideBar != null) {
      final sideBarWidth = ChildLayoutHelper.layoutChild(
        sideBar,
        BoxConstraints.tightFor(height: constraints.maxHeight),
      ).width;
      setOffset(sideBar, .zero);

      if (_overlaySideBar) {
        // 覆盖式：body 全宽（内容自己用 OverlayInsets.left 让开侧栏宽度），
        // 侧栏仍固定在左上角、最后绘制 ⇒ 玻璃能采样到它背后的内容。
        bodyOffset = .zero;
        bodyConstraints = BoxConstraints.tightFor(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
        );
      } else {
        bodyOffset = Offset(sideBarWidth, 0);
        bodyConstraints = BoxConstraints.tightFor(
          width: constraints.maxWidth - sideBarWidth,
          height: constraints.maxHeight,
        );
      }
    } else {
      bodyOffset = .zero;
      bodyConstraints = BoxConstraints.tightFor(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
      );
    }

    // bottomNav **无条件布局**（2026-10-04 bug 扫描修复）：paint 的两条路径都会
    // doPaint(bottomNav)，原先它只在 sideBar==null 分支被 layout —— 两者并存时
    // debug 断言 "RenderBox was not laid out"、release 用陈旧 size 绘制 ✗。
    // 当前宿主二者互斥（useBottomNav ? bottomNav : sideBar）⇒ 本修复零行为变化 ✓，
    // 属拆哑弹（未来平板"侧栏+底导"并存布局不再踩雷 ✓）。
    final bottomNav = this.bottomNav;
    if (bottomNav != null) {
      final bottomNavSize = ChildLayoutHelper.layoutChild(
        bottomNav,
        constraints.loosen(),
      );
      setOffset(
        bottomNav,
        Offset(
          (constraints.maxWidth - bottomNavSize.width) / 2,
          constraints.maxHeight - bottomNavSize.height,
        ),
      );
    }

    final body = this.body..layout(bodyConstraints);
    setOffset(body, bodyOffset);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    void doPaint(RenderBox? child) {
      if (child != null) {
        context.paintChild(child, getOffset(child) + offset);
      }
    }

    // 覆盖式：侧栏最后绘制 —— 玻璃要采样到它背后的内容（这是前提，不是样式细节）；
    // 并排式：保持上游顺序（sideBar → body → bottomNav），逐像素不变。
    if (_overlaySideBar) {
      doPaint(body);
      doPaint(sideBar);
      doPaint(bottomNav);
    } else {
      doPaint(sideBar);
      doPaint(body);
      doPaint(bottomNav);
    }
  }
}
