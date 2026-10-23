// SPDX-License-Identifier: GPL-3.0-or-later
// ============================================================================
// UI 重构暂存组件（排期 #23 / README「动画与交互纪律」第 7 条 P2 的
// "卡片按压反馈"一项的落地件）
//
// 本目录（lib/ui_liquidglass/）为暂存代码，当前不参与编译、不接入主工程。
// 主任务完成后，本文件随其余 components/ 一起迁移到 lib/common/widgets/liquid/。
//
// 组件：LiquidPressable —— "果冻按压"动效原语（缩放 + 回弹曲线）
//      kLiquidSpringCurve —— 回弹曲线常量（本目录所有按压回弹共用）
//
// 只消费 liquid_glass_kit 的稳定入口（本文件其实不需要玻璃层，纯动效）；
// 时长一律过 GlassAccessibility.motionDuration（#18 无障碍：减弱动效 ⇒ 阶跃）。
// ============================================================================

import 'package:material_ui/material_ui.dart';
import 'package:PiliPlus/utils/glass_accessibility.dart';

/// 液态"果冻回弹"曲线：CSS `ease-out-back` 的同款三次贝塞尔
/// （与 `Curves.easeOutBack` 同一组控制点，这里单独起名字是为了让"回弹"这件事
/// 在本目录里有唯一的出处 —— 想调手感只改这一行）。
///
/// 为什么它能做出"果冻"：三次贝塞尔的第二个控制点 y = 1.56 **超过 1.0**，
/// 所以曲线尾段会先冲到 1.0 以上再回落（`transform(t)` 在 t ≈ 0.6–0.9 区间 > 1）。
///
/// ⚠️ 但**不要**把它直接当 [CurvedAnimation.reverseCurve] 用（见
/// [kLiquidSpringReleaseCurve] 的说明）：反向时 `CurvedAnimation` 算的是
/// `reverseCurve.transform(parent.value)`，而 `parent.value` 此时是从 1 **递减**到 0，
/// 中段冲到 1 以上 ⇒ 缩放在回弹途中会**再缩一次**（0.8 → 0.78 → 1.0），
/// 手感是"又压一下"，不是"弹回来"。
const Curve kLiquidSpringCurve = Cubic(0.34, 1.56, 0.64, 1.0);

/// 抬手回弹曲线：[kLiquidSpringCurve] 的翻转版（等价于 `ease-in-back`）。
///
/// 为什么用它才有"弹过静止值"：翻转后曲线在**小 t 端为负**
/// （`flipped(t) = 1 - spring(1 - t)`，t 小的时候落到 0 以下）。
/// 反向动画里 `parent.value` 正是从 1 递减到 0，于是回弹末段
/// `_curve.value` 短暂为负 ⇒ 缩放 `1.0 + (pressedScale - 1.0) * v` 里
/// `(pressedScale - 1.0)` 为负、`v` 为负 ⇒ 尺寸**冲过 1.0 再落回**，即果冻感。
///
/// 只能是 `final`：`Curve.flipped` 不是 const 构造（返回 `FlippedCurve`）。
final Curve kLiquidSpringReleaseCurve = kLiquidSpringCurve.flipped;

/// "果冻按压"反馈：把任意 child 包起来，按下缩到 [pressedScale]，抬手带过冲弹回。
///
/// ## 为什么用 [Listener] 而不是 GestureDetector
/// 按压反馈是**旁路观察**，不是竞争手势：[GestureDetector] 的 onTap 家族会往手势竞技场
/// 里塞识别器，与 child 自己的 `onTap`/`onLongPress` 打架（谁赢取决于竞技场规则，
/// 轻则 child 回调丢、重则父级吃掉点击）。[Listener] 只收裸指针事件、**不进竞技场** ⇒
/// 与 child 的手势完全共存，卡片的 tap/long-press 契约原样不动。
///
/// 另一个常被担心的点——"手指滑出组件后抬手，回弹会不会卡住不触发"：不会。
/// Flutter 的指针事件分发在 down 时就把命中路径缓存进 `GestureBinding._hitTests`，
/// 同一 pointer 的 move/up/cancel **复用这份路径**投递 ⇒ 只要 down 落在本组件内，
/// up/cancel 一定回到这里（[onPointerCancel] 再兜一层系统/滚动抢走指针的情形）。
///
/// ## child 必须"自己可命中"（behavior = `HitTestBehavior.deferToChild`）
/// `deferToChild` 的含义是**只有 child 被点到时**本组件才收到指针 ⇒ 一个裸
/// [SizedBox]（有尺寸但既不绘制也不接手势，`hitTestSelf` 为 false）是**不可命中**的，
/// 按下去不会有任何反馈。这是刻意的：不给透明空白区添加命中，就不改变 child
/// 之外区域的事件语义。接线时 child 通常是卡片容器 / [InkWell] / [Text] 这类
/// 本来就可命中的东西；单测里特意用 [ColoredBox] 冒充卡片，就是为了钉住这条约定。
///
/// ## 为什么自己搭 Transform 而不用 AnimatedScale
/// [AnimatedScale] 是整棵子树重建的隐式动画，而按压发生在每一帧的滚动/列表场景里；
/// 这里用 [AnimatedBuilder] + `child:` 缓存参数，只有最外那层 [Transform.scale] 重建，
/// child（玻璃层/图文）不参与重建（对齐纪律 A1「别整棵子树每帧重建」）。
///
/// ## 减弱动效（#18）
/// [pressDuration]/[releaseDuration] 都过 [GlassAccessibility.motionDuration]：
/// 开关打开 ⇒ 时长为 [Duration.zero] ⇒ 直接给 `controller.value` 赋值（阶跃，
/// 不起 Ticker，也不留"动画尾巴"）。
///
/// ## 无障碍
/// 本组件**不新增任何 Semantics**（只是缩放变换），child 自己的语义原样透传；
/// 缩放会被 Flutter 带进语义节点的包围盒，不影响命中与读屏顺序。
class LiquidPressable extends StatefulWidget {
  /// 构造按压容器。
  const LiquidPressable({
    super.key,
    required this.child,
    this.pressedScale = 0.96,
    this.enabled = true,
    this.ripple = false,
    this.borderRadius,
    this.pressDuration = const Duration(milliseconds: 90),
    this.releaseDuration = const Duration(milliseconds: 380),
  });

  /// 被包裹的内容（保持它原有的手势与语义）。
  final Widget child;

  /// 按到底时的缩放比例。**建议区间 0.85–0.98**：
  /// 大卡 0.96、导航项 0.92、胶囊 0.94 —— 目标越小、单位面积位移越大，
  /// 缩得越狠反而越像"按下去一个面"而不是"缩小一张图"。
  final double pressedScale;

  /// 关闭时完全不响应指针（也不接子级以外的任何手势），用于禁用态。
  final bool enabled;

  /// 是否额外叠一层 [InkWell] 水波纹。默认 **false**：
  /// 列表卡片只要缩放就够（水波纹要 Material 载体、还会多一次 saveLayer）；
  /// 大面积按钮类可开。
  ///
  /// ⚠️ 已知取舍：child 自带 tap 识别器时，父级这块 InkWell 会**输掉竞技场**，
  /// 于是水波纹不画（缩放反馈仍生效）—— 这正是"列表卡 ripple=false"的原因。
  final bool ripple;

  /// 仅用于 [ripple] 时裁剪水波纹的形状；**不裁剪 child**
  /// （玻璃本体自带 ClipRRect，再套一层等于多一次裁剪层，白花钱）。
  final BorderRadius? borderRadius;

  /// 按下时长（easeOut 进）。
  final Duration pressDuration;

  /// 抬手回弹时长（[kLiquidSpringReleaseCurve] 出，比按下去长 = "弹"而不是"缩"）。
  final Duration releaseDuration;

  @override
  State<LiquidPressable> createState() => _LiquidPressableState();
}

class _LiquidPressableState extends State<LiquidPressable>
    with SingleTickerProviderStateMixin {
  /// 静止态进度值（0 = 静止，1 = 按到底）。
  static const double _idle = 0.0;

  /// 0 = 静止，1 = 按到底。
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.pressDuration,
    value: _idle,
  );

  /// 进场 easeOut（干脆）、出场 [kLiquidSpringReleaseCurve]（过冲回弹）。
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
    reverseCurve: kLiquidSpringReleaseCurve,
  );

  /// 当前计价的指针 id（多点触控只认第一根手指，避免第二根按下又抬起时抖动）。
  int? _trackingPointer;

  @override
  void didUpdateWidget(LiquidPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 运行中被禁用 ⇒ 指针回调不会再进来，得手动把已有的按压态归位。
    // 用 `.value =` 赋值：AnimationController 的 setter 内部先 `stop()` ⇒
    // 不会留下一个还在往 1 走的 Ticker。
    if (!widget.enabled && _trackingPointer != null) {
      _trackingPointer = null;
      _controller.value = _idle;
    }
    // pressedScale / 两个 duration 的变化不需要特殊处理：缩放值每帧从 widget 现读
    // （见 [_scaleOf]），时长在每次 _press/_release 里现取 ⇒ 下一次按压即生效。
  }

  @override
  void dispose() {
    // 先解绑 CurvedAnimation 对 parent 的监听，再释放 controller。
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  // ─────────────────────────── 指针事件（旁路，不进竞技场）

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enabled || _trackingPointer != null) return;
    _trackingPointer = event.pointer;
    _press();
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_trackingPointer != event.pointer) return;
    _trackingPointer = null;
    _release();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_trackingPointer != event.pointer) return;
    _trackingPointer = null;
    _release();
  }

  // ─────────────────────────── 时长与状态

  /// 按下：缩到 pressedScale。减弱动效 ⇒ 时长为 0 ⇒ **阶跃**（不起 Ticker）。
  void _press() {
    final duration = GlassAccessibility.motionDuration(widget.pressDuration);
    if (duration == Duration.zero) {
      _controller.value = 1.0;
      return;
    }
    _controller
      ..duration = duration
      ..forward();
  }

  /// 抬起/取消：弹回静止值。
  void _release() {
    final duration = GlassAccessibility.motionDuration(widget.releaseDuration);
    if (duration == Duration.zero) {
      _controller.value = _idle;
      return;
    }
    _controller
      ..duration = duration
      ..reverse();
  }

  /// 进度 → 缩放：0 ⇒ 1.0，1 ⇒ [LiquidPressable.pressedScale]；
  /// 回弹段进度会短暂为负 ⇒ 缩放略大于 1.0（过冲）。
  double _scaleOf() => 1.0 + (widget.pressedScale - 1.0) * _curve.value;

  @override
  Widget build(BuildContext context) {
    Widget content = widget.child;
    if (widget.ripple) {
      // Material(transparency) 只是给水波纹一个绘制载体；borderRadius 只裁剪水波。
      content = Material(
        type: MaterialType.transparency,
        borderRadius: widget.borderRadius,
        child: InkWell(
          // 空回调只为拿到水波纹；真实点击仍由 child 的手势处理。
          onTap: () {},
          borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
          child: content,
        ),
      );
    }
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: AnimatedBuilder(
        animation: _curve,
        // content 走 child: 参数 ⇒ 每帧只重建 Transform 这一层。
        child: content,
        builder: (context, child) =>
            Transform.scale(scale: _scaleOf(), child: child),
      ),
    );
  }
}
