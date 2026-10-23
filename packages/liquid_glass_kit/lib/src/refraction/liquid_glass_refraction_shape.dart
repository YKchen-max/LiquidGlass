// #11 / M1b-1：折射**形状模型与形状数组打包**。
//
// 权威依据（`sdf.glsl:1-3` 原文，pinned commit `0968d9e6…`）：
//   // Shape array uniforms - 6 floats per shape
//   //   (type, centerX, centerY, sizeW, sizeH, cornerRadius)
//   // Reduced from 64 to 16 shapes to fit Impeller's uniform buffer limit (16 * 6 = 96 floats)
//   #define MAX_SHAPES 16
//   type: 1 = squircle, 2 = ellipse, 3 = rounded rectangle, 其它 = none(1e9)
//
// 硬约束（Lead 指定）：**MAX_SHAPES 超限必须显式**——截断 + 日志，不许静默 ✗。
// 打包**复用 M1a 的 `LiquidGlassUniformLayout`**（`maxShapes` / `floatsPerShape` / `shapeDataFloats`）✓，
// 不另起一套常量 ✗。
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'liquid_glass_uniform_layout.dart';

/// 形状类型（与 shader 里的 `type` 常量一一对应）。
enum LiquidGlassShapeType {
  /// `type == 1.0`：超椭圆（squircle）。
  squircle(1),

  /// `type == 2.0`：椭圆。
  ellipse(2),

  /// `type == 3.0`：圆角矩形。
  roundedRect(3);

  const LiquidGlassShapeType(this.shaderValue);

  /// 写进 `uShapeData` 的 type 值。
  final double shaderValue;
}

/// 一块参与折射的形状（M1b-1 只支持静态形状；动画/树形留给后续）。
@immutable
class LiquidGlassRefractionShape {
  const LiquidGlassRefractionShape({
    required this.type,
    required this.center,
    required this.size,
    this.cornerRadius = 0,
  });

  final LiquidGlassShapeType type;

  /// 逻辑像素中心（形状空间，与 shader 的 `p - center` 一致）。
  final ui.Offset center;

  /// 逻辑像素尺寸（shader 内部会除以 2 得到半尺寸）。
  final ui.Size size;

  /// 圆角半径（squircle / roundedRect 用；ellipse 忽略）。
  final double cornerRadius;

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassRefractionShape &&
      other.type == type &&
      other.center == center &&
      other.size == size &&
      other.cornerRadius == cornerRadius;

  @override
  int get hashCode => Object.hash(type, center, size, cornerRadius);

  @override
  String toString() =>
      'LiquidGlassRefractionShape(${type.name}, center=$center, size=$size, r=$cornerRadius)';
}

/// 形状数组打包结果（含**显式**的截断信息）。
@immutable
class LiquidGlassShapeData {
  const LiquidGlassShapeData({
    required this.floats,
    required this.packedCount,
    required this.droppedCount,
  });

  /// 长度恒为 [LiquidGlassUniformLayout.shapeDataFloats]（= 96）✓。
  final Float32List floats;

  /// 实际写进去的形状数（≤ [LiquidGlassUniformLayout.maxShapes]）。
  final int packedCount;

  /// 被**显式截断**丢弃的形状数（>0 时一定有日志 ✓）。
  final int droppedCount;

  bool get truncated => droppedCount > 0;
}

/// 打包形状数组；**超过 `MAX_SHAPES` 时截断并打日志**（不许静默 ✗）。
///
/// 说明：静默截断在这里尤其危险 —— 画面只会"少几块玻璃"，没人会想到是上限 ✗。
LiquidGlassShapeData packShapeData(List<LiquidGlassRefractionShape> shapes) {
  final maxShapes = LiquidGlassUniformLayout.maxShapes;
  final perShape = LiquidGlassUniformLayout.floatsPerShape;
  final out = Float32List(LiquidGlassUniformLayout.shapeDataFloats);
  final take = shapes.length <= maxShapes ? shapes.length : maxShapes;

  for (var i = 0; i < take; i++) {
    final s = shapes[i];
    final base = i * perShape;
    out[base] = s.type.shaderValue;
    out[base + 1] = s.center.dx;
    out[base + 2] = s.center.dy;
    out[base + 3] = s.size.width;
    out[base + 4] = s.size.height;
    out[base + 5] = s.cornerRadius;
  }

  final dropped = shapes.length - take;
  if (dropped > 0) {
    debugPrint('[LiquidGlassKit] 形状数 ${shapes.length} 超过 MAX_SHAPES=$maxShapes ⇒ '
        '**显式截断**掉最后 $dropped 个（前 $take 个已打包；被丢弃的: '
        '${shapes.skip(take).map((s) => s.toString()).join(', ')}）\n'
        '  提示: 这是 Impeller uniform buffer 上限（sdf.glsl:2-3：64→16 就是为了塞进去）；'
        '要画更多形状必须拆层（多个 pass/多块 backdrop），或按桌面端放宽 MAX_SHAPES 并**同步改 shader**✗');
  }
  return LiquidGlassShapeData(floats: out, packedCount: take, droppedCount: dropped);
}

/// 静态段（0-17）之后就是形状数组 ⇒ 形状数组起点。
///
/// 这是**假设**：素材 §4 只列到 17；`sdf.glsl` 里 `uShapeData[MAX_SHAPES*6]` 紧随其后
/// ⇒ 起点 = [LiquidGlassUniformLayout.staticFloats] = 18 ✓。
/// harness 会断言总 float 数 = 18 + 96 = 114 ✓；**真机确认留 M1b-2** ✓（不装作已证）。
int get shapeDataFloatIndex => LiquidGlassUniformLayout.staticFloats;

/// uniform 块总长度（静态 18 + 形状 96 = 114 floats）。
int get refractionUniformFloatCount =>
    LiquidGlassUniformLayout.staticFloats + LiquidGlassUniformLayout.shapeDataFloats;