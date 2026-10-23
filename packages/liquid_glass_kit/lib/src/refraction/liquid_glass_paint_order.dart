// #11 / M1a：**绘制顺序纪律**（决策 3）。
//
// M0 的第二个真 bug 就是这条：`LiquidGlassLayer` 被放在 `Stack.children` 的**第 1 位**，
// 而不透明背景在第 2 位 —— Stack 里**后画的在上** ⇒ 背景把玻璃**整块盖住** ✗，
// 表现为"玻璃一直不画"，而我们为此白跑了 5 个实验臂 ✗。
//
// 所以端口把这条写成**纪律 + 可断言处**：
//   * 规则：**玻璃必须排在上游 backdrop 之后**（同一个 Stack/paint 序列里 index 更大）；
//   * 断言：[debugAssertBackdropBeforeGlass] 在 debug 下直接抛，把"顺序写反"挡在开发期 ✓。
library;

import 'package:flutter/foundation.dart';

/// 绘制顺序契约（**给接线人的一句话纪律**）：
///
/// > 折射玻璃**必须**在它的 backdrop **之后**绘制（同一 Stack 里 index 更大 / 同一
/// > paint 序列里更晚）。反了不会报错，只会"什么都看不见"——M0 的 5 个实验臂都栽在这上面 ✗。
@immutable
class LiquidGlassPaintOrder {
  const LiquidGlassPaintOrder._();

  /// 说明文本（日志与报告里引用同一份，避免各写一套）。
  static const String contract =
      '玻璃必须排在其 backdrop 之后（index 更大 / 更晚绘制）：反了不报错，只表现为"玻璃不可见"';

  /// 在 children 列表里检查顺序；顺序错误时**debug 下直接抛**、release 下打日志 ✓。
  ///
  /// [backdropIndex] / [glassIndex] 由调用方从实际列表取（例如 `children.indexOf(...)`），
  /// 这样它既能用在 widget 组装处的 debug 断言，也能被单测直接覆盖 ✓。
  static void debugAssertBackdropBeforeGlass({
    required int backdropIndex,
    required int glassIndex,
    String? context,
  }) {
    if (backdropIndex < glassIndex) return;
    final message = '[LiquidGlassKit] 绘制顺序违反契约：backdrop=$backdropIndex '
        'glass=$glassIndex${context == null ? '' : '（$context）'}。$contract';
    assert(false, message);
    debugPrint(message);
  }

  /// 便于在 widget 树上取下标后一行调用（`children` 为同一 Stack 的 children）。
  static void checkInChildren({
    required List<Object?> children,
    required Object backdrop,
    required Object glass,
    String? context,
  }) {
    final b = children.indexOf(backdrop);
    final g = children.indexOf(glass);
    if (b < 0 || g < 0) {
      debugPrint('[LiquidGlassKit] 绘制顺序检查跳过：backdrop/glass 不在同一 children 列表里'
          '${context == null ? '' : '（$context）'}');
      return;
    }
    debugAssertBackdropBeforeGlass(backdropIndex: b, glassIndex: g, context: context);
  }
}