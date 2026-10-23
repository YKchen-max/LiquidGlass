// #11 / M1b-3：**几何烘焙趟**（`geometry_blended`）—— 形状树 ⇒ 位移纹理。
//
// uniform 契约来自 **GLSL 原文**（`liquid_glass_geometry_blended.frag`，pinned commit）：
//   layout(location = 0) uniform vec2  uSize;                → float 0-1（**物理像素**）
//   layout(location = 1) uniform vec4  uOpticalProps;        → float 2-5（x=refractiveIndex, z=thickness, w=blend）
//   layout(location = 2) uniform float uNumShapes;           → float 6   ← **必须显式给个数** ✓
//   layout(location = 3) uniform float uShapeData[16 * 6];   → float 7-102
//   ⇒ 共 **103 个 float**（= 2 + 4 + 1 + 96）。
//
// 与上游 Dart 侧的实现对齐（`render_liquid_glass_geometry.dart:258-261`）：
//   `geometryShader.setFloatUniforms((v) => v..setFloat(width)..setFloat(height));`
//   —— 那里只写了 size，随后由 `updateGeometryShaderShapes(shapes)` 写形状段 ✓；
//   本文件把 0-102 **一次写全**（便于单测逐下标断言 ✓，也是"错位不报错"的防线 ✓）。
//
// 三条**真机/上游教训**写在这里（避免后人重踩）：
//   1. **`uNumShapes` 必须与截断后的实际个数一致** ✗ —— 写 96 个 float 但报数 19，
//      会让 shader 去读不存在的形状（画面错乱且不报错 ✗）；
//   2. **`Picture.toImage()` / `Image.toByteData()` 不能在首帧构建期间调用** ✗
//      —— Impeller 下表现为"无异常、日志停住"（M1b-2 实测，跑了 3 轮才定位 ✓）
//      ⇒ 本模块的 [bakeToImage] 明确要求调用方在**帧外**调用（例如 `addPostFrameCallback` 之后 ✓）；
//   3. **纹理生命周期由调用方负责** ✗ —— 上游用三态缓存 + `matte.dispose` ✓；
//      本模块只做"渲染 + 返回 `ui.Image`"，**不缓存**（缓存留给接线层按同样规则做 ✓），
//      但把"必须 dispose"写在返回值文档里 ✓（漏 dispose 会稳定泄漏 GPU 纹理 ✗）。
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'liquid_glass_refraction_shape.dart';
import 'liquid_glass_refraction_stage.dart';
import 'liquid_glass_uniform_layout.dart';

/// 几何烘焙趟的 uniform 布局（**单一真相源**：写入与测试都读它 ✓）。
@immutable
class LiquidGlassGeometryUniformLayout {
  const LiquidGlassGeometryUniformLayout._();

  /// `uSize`（物理像素宽高）：2 floats。
  static const int sizeIndex = 0;
  static const int sizeFloats = 2;

  /// `uOpticalProps`：4 floats（x=refractiveIndex, y=未用, z=thickness, w=blend）。
  static const int opticalPropsIndex = 2;
  static const int opticalPropsFloats = 4;

  /// `uNumShapes`：1 float —— **必须显式给**（见文件头教训 1 ✓）。
  static const int numShapesIndex = 6;

  /// `uShapeData[16 * 6]`：96 floats（复用 [LiquidGlassUniformLayout] 的常量 ✓）。
  static const int shapeDataIndex = 7;
  static const int shapeDataFloats = LiquidGlassUniformLayout.shapeDataFloats;

  /// 总长度 = 2 + 4 + 1 + 96 = 103 ✓。
  static const int totalFloats = shapeDataIndex + shapeDataFloats;

  /// 逐下标表（测试/日志共用 ✓）。
  static const List<String> indexTable = <String>[
    'uSize.x', 'uSize.y',
    'uOpticalProps.refractiveIndex', 'uOpticalProps.y(未用)',
    'uOpticalProps.thickness', 'uOpticalProps.blend',
    'uNumShapes',
    // 7..102 是 uShapeData[96]（按下标 6 个一组，不逐条列名 ✓）
  ];
}

/// 烘焙一趟所需的输入。
@immutable
class LiquidGlassGeometryBakeInput {
  const LiquidGlassGeometryBakeInput({
    required this.physicalSize,
    required this.shapes,
    this.refractiveIndex = 1.2,
    this.thickness = 20,
    this.blend = 0,
  });

  /// **物理像素**尺寸（上游按 `bounds * devicePixelRatio` 取整 ✓）。
  final ui.Size physicalSize;

  /// 形状列表（超 `MAX_SHAPES` 会被**显式截断**，且 `uNumShapes` 同步 ✓）。
  final List<LiquidGlassRefractionShape> shapes;

  final double refractiveIndex;
  final double thickness;

  /// 混合量（上游 BlendGroup 的值；单块玻璃用 0 ✓）。
  final double blend;

  /// 纯函数打包（长度恒为 [LiquidGlassGeometryUniformLayout.totalFloats]）✓。
  List<double> pack() {
    final out = List<double>.filled(LiquidGlassGeometryUniformLayout.totalFloats, 0);
    out[LiquidGlassGeometryUniformLayout.sizeIndex] = physicalSize.width;
    out[LiquidGlassGeometryUniformLayout.sizeIndex + 1] = physicalSize.height;
    out[LiquidGlassGeometryUniformLayout.opticalPropsIndex] = refractiveIndex;
    out[LiquidGlassGeometryUniformLayout.opticalPropsIndex + 2] = thickness;
    out[LiquidGlassGeometryUniformLayout.opticalPropsIndex + 3] = blend;

    // 形状段：复用 M1b-1 的打包（含超限截断 + 日志 ✓）
    final shapeData = packShapeData(shapes);
    for (var i = 0; i < shapeData.floats.length; i++) {
      out[LiquidGlassGeometryUniformLayout.shapeDataIndex + i] =
          shapeData.floats[i];
    }
    // **个数与截断后的实际值一致** ✓（教训 1）
    out[LiquidGlassGeometryUniformLayout.numShapesIndex] =
        shapeData.packedCount.toDouble();
    return out;
  }
}

/// 几何烘焙趟。
abstract final class LiquidGlassGeometryPass {
  /// 把输入写进 [shader]（0-102 一次写全 ✓）。
  static void writeUniforms(
    ui.FragmentShader shader,
    LiquidGlassGeometryBakeInput input,
  ) {
    final values = input.pack();
    assert(values.length == LiquidGlassGeometryUniformLayout.totalFloats);
    for (var i = 0; i < values.length; i++) {
      shader.setFloat(i, values[i]);
    }
  }

  /// 把形状烘成**位移纹理**（返回的 `ui.Image` **由调用方负责 `dispose`** ✓）。
  ///
  /// ⚠ 调用方必须在**帧外**调用（`addPostFrameCallback` 之后 ✓）—— 见文件头教训 2 ✗。
  static Future<ui.Image> bakeToImage(
    ui.FragmentProgram program,
    LiquidGlassGeometryBakeInput input, {
    /// **光栅像素倍率**（一般传 dpr ✓）：`toImage` 的像素尺寸 = 画布逻辑尺寸 × 此值 ✓
    /// ⇒ "画布坐标逻辑 + 光栅像素物理" ✓（M1b-15 ✓）。
    double rasterScale = 1.0,
  }) async {
    final width = input.physicalSize.width;
    final height = input.physicalSize.height;
    final shader = program.fragmentShader();
    writeUniforms(shader, input);

    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, width, height),
      ui.Paint()..shader = shader,
    );
    final picture = recorder.endRecording();
    // ⚠ **口径分家（M1b-15 的实现约束 ✓）**：
    //   * **画布坐标 = 逻辑**（`input.physicalSize` 现在传逻辑尺寸 ✓，形状也用逻辑坐标 ✓，
    //     几何 shader 的 `uSize` 因此也是逻辑 ✓ —— 与页内 `FlutterFragCoord()` 的逻辑口径一致 ✓）；
    //   * **光栅像素 = 物理**（`toImage` 的 w/h 乘 `rasterScale`=dpr ✓）⇒ 纹理仍有 dpr 3 的清晰度 ✓。
    //   ⇒ 这是 Flutter 的标准做法（逻辑坐标绘制 + 物理像素光栅化 ✓），两边别搞混 ✗。
    final image = await picture.toImage(
      (width * rasterScale).ceil(),
      (height * rasterScale).ceil(),
    );
    picture.dispose();
    return image;
  }

  /// 这一趟的就绪判定（**原因随事实更新** ✓ —— 不再是 M1b-1 的"结构就位"口径 ✓）。
  static LiquidGlassPassAvailability availability({required bool programLoaded}) =>
      programLoaded
          ? const LiquidGlassPassAvailability(
              pass: LiquidGlassRefractionPass.geometryBake,
              ready: true,
              reason: 'program 就位；本趟是**离屏烘焙**（形状 ⇒ 位移纹理），不需要 backdrop ✓ '
                  '（调用方须在帧外调 bakeToImage ✓，返回的 Image 由调用方 dispose ✓）',
            )
          : const LiquidGlassPassAvailability(
              pass: LiquidGlassRefractionPass.geometryBake,
              ready: false,
              reason: '还没拿到 geometry_blended program（未加载或加载失败；失败一定有日志 ✓）',
            );
}