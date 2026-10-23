// #11 / M1b-4：**filter 趟**（`liquid_glass_filter`）—— backdrop ⇒ 模糊 + 位移采样。
//
// uniform 契约取自 **GLSL 原文**（`liquid_glass_filter.frag`，pinned commit）：
//   layout(location = 0) uniform vec2  uSize;                 → float 0-1（**物理像素**）
//   layout(location = 1) uniform vec4  uGlassColor;           → float 2-5
//   layout(location = 2) uniform vec4  uOpticalProps;         → float 6-9（refractiveIndex, chromaticAberration, thickness, blend）
//   layout(location = 3) uniform vec4  uLightConfig;          → float 10-13（angle, intensity, ambient, saturation）
//   layout(location = 4) uniform vec2  uLightDirection;       → float 14-15（cos, sin）
//   layout(location = 5) uniform float uNumShapes;            → float 16
//   layout(location = 6) uniform float uShapeData[16 * 6];     → float 17-112
//   uniform sampler2D uBlurredTexture;                        → sampler 0 = **模糊后的 backdrop**
//   ⇒ 共 **113 个 float + 1 个 sampler**。
//
// ⚠ 两个容易"不报错但结果错"的点（Lead 点名的防御风格：用显式日志/断言钉住 ✗）：
//   1. **filter 趟没有几何纹理 sampler** ⇒ 位移是它**自己**用 `uShapeData` 算的 ✓
//      ⇒ `uNumShapes` 必须与截断后的实际个数一致（与几何趟同一条纪律 ✓）；
//   2. **backdrop 的模糊是"我方"做的**（上游 `liquid_glass_filter.dart:274-278`：
//      `ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur)` ✓）⇒ 忘记模糊 ⇒ 画面只是"不糊的折射"
//      且**不会报错** ✗ ⇒ [blurBackdrop] 把这件事做成显式一步并把 sigma 打日志 ✓。
//
// 纹理生命周期（M1b-3 标的缺口 ✗）：本文件只管"渲染 + 返回 ui.Image" ✓；
// **所有权规则**写在 [LiquidGlassRefractionTextureCache] 上 ✓（谁建谁 dispose ✓）。
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'liquid_glass_refraction_shape.dart';
import 'liquid_glass_refraction_stage.dart';
import 'liquid_glass_uniform_layout.dart';

/// filter 趟的 uniform 布局（**单一真相源** ✓）。
@immutable
class LiquidGlassFilterUniformLayout {
  const LiquidGlassFilterUniformLayout._();

  static const int sizeIndex = 0;
  static const int sizeFloats = 2;
  static const int glassColorIndex = 2;
  static const int glassColorFloats = 4;
  static const int opticalPropsIndex = 6;
  static const int opticalPropsFloats = 4;
  static const int lightConfigIndex = 10;
  static const int lightConfigFloats = 4;
  static const int lightDirectionIndex = 14;
  static const int lightDirectionFloats = 2;
  static const int numShapesIndex = 16;

  /// `uShapeData[16 * 6]`：96 floats（复用 M1a 常量 ✓）。
  static const int shapeDataIndex = 17;
  static const int shapeDataFloats = LiquidGlassUniformLayout.shapeDataFloats;

  /// 总长度 = 17 + 96 = **113** ✓。
  static const int totalFloats = shapeDataIndex + shapeDataFloats;

  static const List<String> indexTable = <String>[
    'uSize.x', 'uSize.y',
    'uGlassColor.r', 'uGlassColor.g', 'uGlassColor.b', 'uGlassColor.a',
    'uOpticalProps.refractiveIndex', 'uOpticalProps.chromaticAberration',
    'uOpticalProps.thickness', 'uOpticalProps.blend',
    'uLightConfig.angle', 'uLightConfig.intensity',
    'uLightConfig.ambient', 'uLightConfig.saturation',
    'uLightDirection.cos', 'uLightDirection.sin',
    'uNumShapes',
  ];
}

/// filter 一趟的输入。
@immutable
class LiquidGlassFilterInput {
  const LiquidGlassFilterInput({
    required this.physicalSize,
    required this.shapes,
    required this.glassColor,
    this.refractiveIndex = 1.2,
    this.chromaticAberration = 0.01,
    this.thickness = 20,
    this.blend = 0,
    this.lightAngle = 1.5707963267948966, // π/2
    this.lightIntensity = 0.5,
    this.ambientStrength = 0,
    this.saturation = 1.5,
  });

  final ui.Size physicalSize;
  final List<LiquidGlassRefractionShape> shapes;
  final ui.Color glassColor;
  final double refractiveIndex;
  final double chromaticAberration;
  final double thickness;
  final double blend;
  final double lightAngle;
  final double lightIntensity;
  final double ambientStrength;
  final double saturation;

  /// 纯函数打包（长度恒为 [LiquidGlassFilterUniformLayout.totalFloats] ✓）。
  List<double> pack() {
    final out = List<double>.filled(LiquidGlassFilterUniformLayout.totalFloats, 0);
    out[LiquidGlassFilterUniformLayout.sizeIndex] = physicalSize.width;
    out[LiquidGlassFilterUniformLayout.sizeIndex + 1] = physicalSize.height;
    final c = glassColor;
    out[LiquidGlassFilterUniformLayout.glassColorIndex] = c.r;
    out[LiquidGlassFilterUniformLayout.glassColorIndex + 1] = c.g;
    out[LiquidGlassFilterUniformLayout.glassColorIndex + 2] = c.b;
    out[LiquidGlassFilterUniformLayout.glassColorIndex + 3] = c.a;
    out[LiquidGlassFilterUniformLayout.opticalPropsIndex] = refractiveIndex;
    out[LiquidGlassFilterUniformLayout.opticalPropsIndex + 1] = chromaticAberration;
    out[LiquidGlassFilterUniformLayout.opticalPropsIndex + 2] = thickness;
    out[LiquidGlassFilterUniformLayout.opticalPropsIndex + 3] = blend;
    out[LiquidGlassFilterUniformLayout.lightConfigIndex] = lightAngle;
    out[LiquidGlassFilterUniformLayout.lightConfigIndex + 1] = lightIntensity;
    out[LiquidGlassFilterUniformLayout.lightConfigIndex + 2] = ambientStrength;
    out[LiquidGlassFilterUniformLayout.lightConfigIndex + 3] = saturation;
    out[LiquidGlassFilterUniformLayout.lightDirectionIndex] = _cos(lightAngle);
    out[LiquidGlassFilterUniformLayout.lightDirectionIndex + 1] = _sin(lightAngle);

    final shapeData = packShapeData(shapes);
    for (var i = 0; i < shapeData.floats.length; i++) {
      out[LiquidGlassFilterUniformLayout.shapeDataIndex + i] = shapeData.floats[i];
    }
    out[LiquidGlassFilterUniformLayout.numShapesIndex] =
        shapeData.packedCount.toDouble(); // 与截断一致 ✓（否则 shader 读不存在的形状且不报错 ✗）
    return out;
  }
}

/// filter 趟。
abstract final class LiquidGlassFilterPass {
  /// 写 uniform（0-112 一次写全 ✓）+ 绑定 sampler 0 = 模糊后的 backdrop ✓。
  static void writeUniforms(
    ui.FragmentShader shader,
    LiquidGlassFilterInput input, {
    required ui.Image blurredBackdrop,
  }) {
    final values = input.pack();
    assert(values.length == LiquidGlassFilterUniformLayout.totalFloats);
    for (var i = 0; i < values.length; i++) {
      shader.setFloat(i, values[i]);
    }
    shader.setImageSampler(0, blurredBackdrop);
  }

  /// **模糊 backdrop**（上游同样由 Dart 侧做 ✓）。返回的 Image 由调用方 dispose ✓。
  ///
  /// 显式打日志：`blur` 为 0 时**不做**模糊（省一次离屏 ✓），但会说明原因 ✓。
  static Future<ui.Image> blurBackdrop(ui.Image backdrop, double blur) async {
    if (blur <= 0) {
      debugPrint('[LiquidGlassKit] filter 趟: blur=$blur ⇒ **跳过模糊**（直接用原 backdrop）✓');
      return backdrop;
    }
    debugPrint('[LiquidGlassKit] filter 趟: 模糊 backdrop sigmaX=sigmaY=$blur ✓');
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImage(
      backdrop,
      ui.Offset.zero,
      ui.Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(backdrop.width, backdrop.height);
    picture.dispose();
    return image;
  }

  /// 跑一趟 filter：backdrop（**已模糊**）⇒ 折射结果纹理 ✓。
  ///
  /// ⚠ 调用方必须在**帧外**调用（Impeller 下帧内 `toImage` 会死等 ✗，M1b-2 实测）。
  /// ⚠ 返回的 Image **由调用方 dispose** ✓（复用前先 dispose 旧的，见 cache ✓）。
  static Future<ui.Image> renderToImage(
    ui.FragmentProgram program,
    LiquidGlassFilterInput input, {
    required ui.Image blurredBackdrop,
  }) async {
    final width = input.physicalSize.width;
    final height = input.physicalSize.height;
    final shader = program.fragmentShader();
    writeUniforms(shader, input, blurredBackdrop: blurredBackdrop);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, width, height),
      ui.Paint()..shader = shader,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(width.ceil(), height.ceil());
    picture.dispose();
    return image;
  }

  /// 这一趟的就绪判定（reason 随事实更新 ✓）。
  static LiquidGlassPassAvailability availability({required bool programLoaded}) =>
      programLoaded
          ? const LiquidGlassPassAvailability(
              pass: LiquidGlassRefractionPass.filter,
              ready: true,
              reason: 'program 就位；输入是"已模糊的 backdrop 纹理"（模糊由 Dart 侧 '
                  'ImageFilter.blur 做 ✓）⇒ 真机页内只需提供 backdrop 纹理 ✓',
            )
          : const LiquidGlassPassAvailability(
              pass: LiquidGlassRefractionPass.filter,
              ready: false,
              reason: '还没拿到 liquid_glass_filter program（未加载或加载失败；失败一定有日志 ✓）',
            );
}

/// 折射纹理的**所有权与释放规则**（M1b-3 标的缺口 ✗ —— 这里写死 ✓）。
///
/// 规则：
///   * **谁建谁 release**：本缓存创建的 `ui.Image` 只由本缓存的 [releaseAll] 释放 ✓；
///   * **调用方塞进来的 backdrop** 不算本缓存所有 ⇒ **不由本缓存释放** ✗
///     （否则会把别人的图 dispo se 掉、后续帧静默画不出来 ✗）；
///   * 重新烘焙同一槽位时**先 release 旧的再换新的** ✓（漏了会稳定泄漏 GPU 纹理 ✗）。
class LiquidGlassRefractionTextureCache {
  final Map<String, ui.Image> _owned = <String, ui.Image>{};

  /// 当前拥有的纹理数（测试/日志用 ✓）。
  int get ownedCount => _owned.length;

  /// 放入/替换一个**由本缓存接管**的纹理 ✓。
  void put(String key, ui.Image image) {
    _owned[key]?.dispose(); // 先释放旧的 ✓（漏了就是泄漏 ✗）
    _owned[key] = image;
  }

  /// 取（不转移所有权 ✓）。
  ui.Image? get(String key) => _owned[key];

  /// 释放某一槽位 ✓。
  void releaseKey(String key) {
    _owned.remove(key)?.dispose();
  }

  /// 全部释放（组件 dispose 时调用 ✓）。
  void releaseAll() {
    for (final image in _owned.values) {
      image.dispose();
    }
    _owned.clear();
  }
}

// 光照方向：直接用 dart:math ✓（核心库零成本；手写三角展开是没必要的风险 ✗）。
double _cos(double x) => math.cos(x);
double _sin(double x) => math.sin(x);