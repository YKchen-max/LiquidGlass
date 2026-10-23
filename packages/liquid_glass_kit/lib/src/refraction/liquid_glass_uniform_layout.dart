// #11 / M1a：折射 uniform 的**索引布局与打包**（决策 4：必须有测试）。
//
// 为什么这一条被 Lead 单独点出来：上游的打包是"按 float 索引紧凑塞"的，
// **错位不会报错、只会画面错乱** ✗（移植清单 §7 的原话）。
// 所以这里把布局**写成常量 + 可断言**，并有对照素材文档 §4 索引表的测试。
//
// 权威依据（两处一致，已核对）：
//   * `docs/liquid-glass-素材.md` §4 Uniform 清单；
//   * 上游 `lib/src/rendering/liquid_glass_render_object.dart:102-121`
//     —— `renderShader.setFloatUniforms(initialIndex: 6, …)`：先 4 个颜色，
//     再 6 个（refractiveIndex / chromaticAberration / thickness / lightIntensity /
//     ambientStrength / saturation），最后 2 个（cos/sin 光角）⇒ 6+4+6+2 = 18 ✓。
//
// 索引表：
//   0-1   uSize（逻辑像素画布尺寸）
//   2-5   uGeometryOffset/Size（位移纹理在屏幕上的位置与尺寸，物理像素）
//   6-9   uGlassColor（RGBA，alpha=染色强度）
//   10-12 uOpticalProps（refractiveIndex / chromaticAberration / thickness）
//   13-15 uLightConfig（lightIntensity / ambientStrength / saturation）
//   16-17 uLightDirection（预计算 cos/sin）
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// 折射 uniform 的索引布局（**单一真相源**：打包与测试都读它，避免两处各写一份 ✗）。
@immutable
class LiquidGlassUniformLayout {
  const LiquidGlassUniformLayout._();

  /// uSize：2 floats。
  static const int sizeIndex = 0;
  static const int sizeFloats = 2;

  /// uGeometryOffset/Size：4 floats。
  static const int geometryIndex = 2;
  static const int geometryFloats = 4;

  /// uGlassColor：4 floats。
  static const int glassColorIndex = 6;
  static const int glassColorFloats = 4;

  /// uOpticalProps（3）：紧随颜色之后。
  static const int opticalPropsIndex = 10;
  static const int opticalPropsFloats = 3;

  /// uLightConfig（3）。
  static const int lightConfigIndex = 13;
  static const int lightConfigFloats = 3;

  /// uLightDirection（2：cos/sin）。
  static const int lightDirectionIndex = 16;
  static const int lightDirectionFloats = 2;

  /// 上游 `setFloatUniforms(initialIndex: 6, …)` 的起点 —— 与 [glassColorIndex] 必须一致 ✓。
  static const int settingsFloatIndex = glassColorIndex;

  /// 形状数组：`uShapeData[MAX_SHAPES * 6]`（sdf.glsl:2-3 的 `MAX_SHAPES 16`）。
  static const int maxShapes = 16;
  static const int floatsPerShape = 6;
  static const int shapeDataFloats = maxShapes * floatsPerShape;

  /// 静态 uniform 区总长度（= 18 floats = 72 bytes）。
  static const int staticFloats = lightDirectionIndex + lightDirectionFloats;

  /// 逐下标的人类可读表（截图/报告/测试都用它；也是自检的输出）。
  static const List<String> indexTable = <String>[
    'uSize.x', 'uSize.y',
    'uGeometryOffset.x', 'uGeometryOffset.y', 'uGeometrySize.x', 'uGeometrySize.y',
    'uGlassColor.r', 'uGlassColor.g', 'uGlassColor.b', 'uGlassColor.a',
    'uOpticalProps.refractiveIndex', 'uOpticalProps.chromaticAberration', 'uOpticalProps.thickness',
    'uLightConfig.lightIntensity', 'uLightConfig.ambientStrength', 'uLightConfig.saturation',
    'uLightDirection.cos', 'uLightDirection.sin',
  ];
}

/// 折射的输入参数子集（与 kit 既有 token 体系解耦；接线留到 M1b ✓）。
@immutable
class LiquidGlassRefractionParams {
  const LiquidGlassRefractionParams({
    required this.size,
    required this.geometryOffset,
    required this.geometrySize,
    required this.glassColor,
    this.refractiveIndex = 1.2,
    this.chromaticAberration = 0.01,
    this.thickness = 20,
    this.lightIntensity = 0.5,
    this.ambientStrength = 0,
    this.saturation = 1.5,
    this.lightAngle = math.pi / 2,
  });

  final ui.Size size;
  final ui.Offset geometryOffset;
  final ui.Size geometrySize;
  final ui.Color glassColor;
  final double refractiveIndex;
  final double chromaticAberration;
  final double thickness;
  final double lightIntensity;
  final double ambientStrength;
  final double saturation;

  /// 只改想改的那个参数（接线时按 token/动画逐项替换用得到 ✓）。
  ///
  /// 刻意把"未传 = 保持不变"写清楚，避免出现"漏传一个就回默认值"的隐式重置 ✗。
  LiquidGlassRefractionParams copyWith({
    ui.Size? size,
    ui.Offset? geometryOffset,
    ui.Size? geometrySize,
    ui.Color? glassColor,
    double? refractiveIndex,
    double? chromaticAberration,
    double? thickness,
    double? lightIntensity,
    double? ambientStrength,
    double? saturation,
    double? lightAngle,
  }) =>
      LiquidGlassRefractionParams(
        size: size ?? this.size,
        geometryOffset: geometryOffset ?? this.geometryOffset,
        geometrySize: geometrySize ?? this.geometrySize,
        glassColor: glassColor ?? this.glassColor,
        refractiveIndex: refractiveIndex ?? this.refractiveIndex,
        chromaticAberration: chromaticAberration ?? this.chromaticAberration,
        thickness: thickness ?? this.thickness,
        lightIntensity: lightIntensity ?? this.lightIntensity,
        ambientStrength: ambientStrength ?? this.ambientStrength,
        saturation: saturation ?? this.saturation,
        lightAngle: lightAngle ?? this.lightAngle,
      );
  final double lightAngle;

  /// **纯函数打包**：返回长度恒为 [LiquidGlassUniformLayout.staticFloats] 的 float 列表。
  ///
  /// 纯函数是刻意的：打包是"错位不报错"的高危区 ⇒ 必须能被单测逐下标断言 ✓。
  List<double> packStaticUniforms() {
    final out = List<double>.filled(LiquidGlassUniformLayout.staticFloats, 0);
    out[LiquidGlassUniformLayout.sizeIndex] = size.width;
    out[LiquidGlassUniformLayout.sizeIndex + 1] = size.height;
    out[LiquidGlassUniformLayout.geometryIndex] = geometryOffset.dx;
    out[LiquidGlassUniformLayout.geometryIndex + 1] = geometryOffset.dy;
    out[LiquidGlassUniformLayout.geometryIndex + 2] = geometrySize.width;
    out[LiquidGlassUniformLayout.geometryIndex + 3] = geometrySize.height;
    final c = glassColor;
    out[LiquidGlassUniformLayout.glassColorIndex] = c.r;
    out[LiquidGlassUniformLayout.glassColorIndex + 1] = c.g;
    out[LiquidGlassUniformLayout.glassColorIndex + 2] = c.b;
    out[LiquidGlassUniformLayout.glassColorIndex + 3] = c.a;
    out[LiquidGlassUniformLayout.opticalPropsIndex] = refractiveIndex;
    out[LiquidGlassUniformLayout.opticalPropsIndex + 1] = chromaticAberration;
    out[LiquidGlassUniformLayout.opticalPropsIndex + 2] = thickness;
    out[LiquidGlassUniformLayout.lightConfigIndex] = lightIntensity;
    out[LiquidGlassUniformLayout.lightConfigIndex + 1] = ambientStrength;
    out[LiquidGlassUniformLayout.lightConfigIndex + 2] = saturation;
    out[LiquidGlassUniformLayout.lightDirectionIndex] = math.cos(lightAngle);
    out[LiquidGlassUniformLayout.lightDirectionIndex + 1] = math.sin(lightAngle);
    return out;
  }

  /// 把静态区写进 [shader]（**按索引 0 起**；与上游"从 6 起写设置"的写法等价，
  /// 区别只是这里把 0-17 一次写全 ⇒ 少一次索引心智负担 ✓）。
  void applyTo(ui.FragmentShader shader) {
    final values = packStaticUniforms();
    for (var i = 0; i < values.length; i++) {
      shader.setFloat(i, values[i]);
    }
  }
}

/// 打包字节数（对照 impellerc/uniform 缓冲的口径）。
int packedStaticByteCount() => LiquidGlassUniformLayout.staticFloats * 4;

/// 打包 **顺序快照**：`下标=值` 的稳定字符串，供测试与日志做"顺序有没有变"的对照 ✓。
@visibleForTesting
String packOrderSnapshot(List<double> packed) {
  final sb = StringBuffer();
  for (var i = 0; i < packed.length; i++) {
    final name = i < LiquidGlassUniformLayout.indexTable.length
        ? LiquidGlassUniformLayout.indexTable[i]
        : '?';
    sb.write('$i:$name=${packed[i].toStringAsFixed(4)}');
    if (i != packed.length - 1) sb.write('|');
  }
  return sb.toString();
}