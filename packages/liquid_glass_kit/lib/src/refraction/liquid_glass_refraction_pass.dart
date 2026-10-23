// #11 / M1b：三趟编排（`final_render` 已通；几何烘焙 / filter **结构就位**）。
//
// 状态与**真机已纠正的事实**（M1b-2，2026-10-03 —— 以下每条都来自设备实测，不是推测）：
//   1. 【已通 · 真机 PASS】`final_render` 一趟：uniform 块**只有 18 个 float**
//      （= 素材 §4 的 0-17 + 2 个 sampler）。
//      ⚠️ 曾错误地把形状数组（`MAX_SHAPES×6 = 96`）也写进这一趟 ⇒ 真机直接抛
//      `RangeError (index): Index out of range: index should be less than 18: 18` ✗。
//      **形状数组属于几何烘焙趟 `geometry_blended`**（见 `sdf.glsl:2-3`）：它把位移烘成**纹理**，
//      合成趟只用 sampler 1 去读 ✓ ⇒ 本文件已**不再写形状段**（形状只打包给几何趟用）。
//   2. 【结构就位】`geometry_blended`（几何位移烘焙）与 `filter`（模糊/位移）两趟：
//      接口、顺序、依赖与"需设备"的**显式原因**都在这里写死 ✓，
//      真正的实现在 M1b-3（需要 Impeller 离屏 pass + `ImageFilter.shader` 的 backdrop 采样）。
//
// 三层各能验证到什么（实测结论，别照旧假设 ✗）：
//   * uniform 侧：纯 Dart ⇒ 可在 `flutter test` 里断言顺序 / 字节数 / 几何相关性 ✓；
//   * 资产侧：⚠️ **这 4 支 shader 在 `flutter test` 里永远加载不了** ✗ —— headless 引擎只有
//     **SkSL 后端**，而我们的 `.iplr` 按设计只带 gles+gles3+vulkan（SkSL 目标在 Windows 必失败，
//     见 #8）⇒ 报错原文 `does not contain appropriate runtime stage data for current backend (SkSL)` ✓。
//     **首次真实加载发生在真机上**（M1b-2 B-1：kit 默认根 4/4 ✓ + Impeller/Vulkan ✓）。
//   * 像素侧：**只能在真机 Impeller 上做** ✗（headless 不可行，别再试 ✗）；
//     真机离屏闭环已 PASS ✓：合成背景 + 合成几何纹理 ⇒ A（厚度 20）唯一色 **34** / std **73.0**
//     vs B（厚度 60）唯一色 **20** / std **51.4**，**A≠B 像素占比 0.719** ✓。
//
// harness 两条坑（实测踩过，别再踩）：
//   * **首帧构建期间调 `Picture.toImage()` / `toByteData()` 会死等** ✗ —— Impeller 下表现为
//     **无异常、日志停住、进度条一直转**（本次跑了 3 轮才定位）⇒ 必须放进 `addPostFrameCallback` ✓；
//   * `ui.Gradient.linear` 给 **3 个颜色时必须配 `colorStops`** ✗（否则
//     `colors must have length 2 if colorStops is omitted`）。
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'liquid_glass_filter_pass.dart';
import 'liquid_glass_geometry_pass.dart';
import 'liquid_glass_refraction_assets.dart';
import 'liquid_glass_refraction_shape.dart';
import 'liquid_glass_refraction_stage.dart';
import 'liquid_glass_uniform_layout.dart';

/// `final_render` 一趟所需的**全部**输入（刻意保持"数据进 / 像素出"的形态，便于 harness 与测试 ✓）。
@immutable
class LiquidGlassFinalRenderInput {
  const LiquidGlassFinalRenderInput({
    required this.params,
    required this.shapes,
    this.geometryTexture,
    this.backgroundTexture,
  });

  /// 静态段参数（尺寸/染色/光学/光照）——打包交给 M1a 的 [LiquidGlassRefractionParams.packStaticUniforms] ✓。
  final LiquidGlassRefractionParams params;

  /// 形状列表（超 `MAX_SHAPES` 会被**显式截断** ✓）。
  final List<LiquidGlassRefractionShape> shapes;

  /// sampler 1：几何位移纹理（第二趟产出；harness 里可用合成纹理替代 ✓）。
  final ui.Image? geometryTexture;

  /// sampler 0：背景（真机上由 `BackdropFilter` 自动喂入；harness 里用合成背景 ✓）。
  final ui.Image? backgroundTexture;
}

/// uniform 赋值结果（供测试断言"喂进去的就是 layout 说的那些下标" ✓）。
@immutable
class LiquidGlassUniformWriteResult {
  const LiquidGlassUniformWriteResult({
    required this.staticCount,
    required this.shapeData,
    required this.totalFloats,
    required this.samplerCount,
  });

  final int staticCount;
  final LiquidGlassShapeData shapeData;
  final int totalFloats;
  final int samplerCount;
}

/// 一趟 `final_render`（M1b-1 已通的那一趟）。
abstract final class LiquidGlassFinalRenderPass {
  /// 把输入写进 [shader]：**完全按 M1a 的 layout**（不另起一套 ✗）。
  ///
  /// 顺序：静态 0-17 ⇒ 形状 18..113 ⇒ sampler 0/1。
  static LiquidGlassUniformWriteResult writeUniforms(
    ui.FragmentShader shader,
    LiquidGlassFinalRenderInput input, {
    /// ⚠ **M1b-22 定案（关键 ✓）**：在 `BackdropFilter` / `ImageFilter.shader` 路径里，
    /// **引擎占住 0-1**（= shader 的第一个 `vec2`，即 `uSize` ✓）—— 上游同约定：
    /// `setFloatUniforms(initialIndex: 2, …)` ✓（`liquid_glass_render_object.dart:219` ✓）。
    /// ⇒ 传 `true` 时**从索引 2 开始写**（`i → i` ✓：`uGeometryOffset`→2-3、
    ///   `uGeometrySize`→4-5、`uGlassColor`→6-9、`uOpticalProps`→10-12、
    ///   `uLightConfig`→13-15、`uLightDirection`→16-17 ✓），`uSize` 交给引擎 ✓。
    /// **Paint 路径没有引擎** ⇒ 传 `false`（默认 ✓），从 0 开始写（**必须**含 `uSize` ✗）。
    /// 实测定案依据（M1b-21）：直读 `uSize` 时写 84 与写 1080 **读出完全相同且 ≥1000** ✗
    /// ⇒ 我方写 0-1 被引擎覆盖 ✓；而 kit 一直把 `uSize` 写在 0-1 ⇒ `screenUV` 一直用引擎值 ✓。
    bool engineOwnsFirstVec2 = false,
  }) {
    final staticValues = input.params.packStaticUniforms();
    assert(staticValues.length == LiquidGlassUniformLayout.staticFloats,
        '静态段长度必须等于 ${LiquidGlassUniformLayout.staticFloats}（M1a layout）');
    final startIndex = firstWrittenFloatIndex(engineOwnsFirstVec2: engineOwnsFirstVec2);
    // ⚠ **M1b-27（A）**：**仅 debug** 打印整段 18 floats ✓（与探针同名义值逐项比 ✓；
    //   §18.38：只与**同批**日志比，不跨行/跨区域比 ✗）
    assert(() {
      debugPrint('[LiquidGlassKit] final_render uniforms '
          'engineOwns=$engineOwnsFirstVec2 start=$startIndex '
          'values=${staticValues.map((v) => v.toStringAsFixed(3)).join(",")}');
      return true;
    }());
    for (var i = startIndex; i < staticValues.length; i++) {
      shader.setFloat(i, staticValues[i]);
    }

    final shapeData = packShapeData(input.shapes);

    // ⚠ **实测纠正（M1b-2 真机）**：`final_render` 的 uniform 块**只有 18 个 float**
    // （= `LiquidGlassUniformLayout.staticFloats`），**不含形状数组** ✗ ——
    // 在设备上写 index 18 直接抛：
    //   `RangeError (index): Index out of range: index should be less than 18: 18` ✓
    // ⇒ 形状数组（`MAX_SHAPES × 6 = 96`，`sdf.glsl:2-3`）属于**几何烘焙趟** `geometry_blended`，
    //   它把位移烘成纹理 ⇒ 合成趟只用 sampler 1 读那张纹理 ✓。
    // （M1b-1 把形状算进这一趟是**错误假设**，本轮被设备打掉 ✓ —— 这里只打包、不写入 ✓。）
    // 需要说明的是：`packShapeData` 仍然被调用（几何趟要用 ✓），只是**不写进这个 shader** ✗。

    var samplers = 0;
    final bg = input.backgroundTexture;
    if (bg != null) {
      shader.setImageSampler(0, bg);
      samplers++;
    }
    final geo = input.geometryTexture;
    if (geo != null) {
      shader.setImageSampler(1, geo);
      samplers++;
    }

    return LiquidGlassUniformWriteResult(
      staticCount: staticValues.length,
      shapeData: shapeData,
      totalFloats: staticValues.length, // final_render：18 ✓（形状 96 归几何烘焙趟）
      samplerCount: samplers,
    );
  }

  /// 第一条被我们写入的浮点索引（**可单测 ✓ 不需要 FragmentShader** ✗）：
  /// * `engineOwnsFirstVec2 = true`（页内 backdrop 路 ✓）⇒ **2** ✓（0-1 是引擎的 `uSize` ✓）；
  /// * `false`（Paint 路 ✓）⇒ **0** ✓（`uSize` 由我们写 ✓）。
  /// 这条断言就是"**0-1 留给引擎**"的防回归点 ✓（M1b-22 ✓）。
  static int firstWrittenFloatIndex({bool engineOwnsFirstVec2 = false}) =>
      engineOwnsFirstVec2 ? LiquidGlassUniformLayout.geometryIndex : 0;

  /// 这一趟的就绪判定（**显式说明为什么** ✓）。
  static LiquidGlassPassAvailability availability({
    required bool programLoaded,
    bool? shaderFilterSupported,
  }) {
    final channel = shaderFilterSupported ?? isRefractionShaderChannelAvailable;
    if (!programLoaded) {
      return const LiquidGlassPassAvailability(
        pass: LiquidGlassRefractionPass.finalRender,
        ready: false,
        reason: '还没拿到 final_render program（未加载或加载失败；加载失败一定有日志 ✓）',
      );
    }
    if (!channel) {
      // 关键：Skia（无 shader filter）上**不许**假装能渲染 ✗ —— 与上游同一判据。
      return const LiquidGlassPassAvailability(
        pass: LiquidGlassRefractionPass.finalRender,
        ready: false,
        reason: 'ImageFilter.isShaderFilterSupported=false（非 Impeller）⇒ 只能走 FakeGlass 档 ✗',
      );
    }
    return const LiquidGlassPassAvailability(
      pass: LiquidGlassRefractionPass.finalRender,
      ready: true,
      reason: 'program 就位 + shader filter 可用',
    );
  }
}

/// 三趟**编排**（结构就位）：把"谁先谁后、各自依赖什么"写死，实现在 M1b-2 ✓。
abstract final class LiquidGlassRefractionPipeline {
  /// 三趟的固定顺序（**也是绘制顺序纪律的一部分**：几何烘焙必须在合成之前 ✓）。
  static const List<LiquidGlassRefractionPass> order = <LiquidGlassRefractionPass>[
    LiquidGlassRefractionPass.geometryBake,
    LiquidGlassRefractionPass.filter,
    LiquidGlassRefractionPass.finalRender,
  ];

  /// 当前三趟的就位状态（**reason 随事实更新** ✓：M1b-4 起几何与 filter 两趟都已落地 ✓）。
  static List<LiquidGlassPassAvailability> availability({
    bool finalRenderProgramLoaded = false,
    bool geometryProgramLoaded = false,
    bool filterProgramLoaded = false,
    bool? shaderFilterSupported,
  }) {
    final channel = shaderFilterSupported ?? isRefractionShaderChannelAvailable;
    return <LiquidGlassPassAvailability>[
      LiquidGlassGeometryPass.availability(programLoaded: geometryProgramLoaded),
      // ⚠ filter 趟**自带形状数组**（17-112）∴ 形状"两趟都要" ✓ —— 别把
      //   "形状只属几何趟"外推（那句只在 `final_render` 的 18-float 语境下成立 ✗）。
      LiquidGlassFilterPass.availability(programLoaded: filterProgramLoaded),
      LiquidGlassFinalRenderPass.availability(
        programLoaded: finalRenderProgramLoaded,
        shaderFilterSupported: channel,
      ),
    ];
  }

  /// 用一句话报告三趟状态（日志/报告复用 ✓）。
  static String describe({
    bool finalRenderProgramLoaded = false,
    bool geometryProgramLoaded = false,
    bool filterProgramLoaded = false,
    bool? shaderFilterSupported,
  }) {
    final list = availability(
      finalRenderProgramLoaded: finalRenderProgramLoaded,
      geometryProgramLoaded: geometryProgramLoaded,
      filterProgramLoaded: filterProgramLoaded,
      shaderFilterSupported: shaderFilterSupported,
    );
    return '[LiquidGlassKit] 折射三趟: '
        '${list.map((a) => '${a.pass.logTag}=${a.ready ? 'ready' : 'pending'}').join(' → ')}';
  }
}
