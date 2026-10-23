// #11 / M1a：折射 shader 的**资产键**与**加载器**（从 M0 的 PoC 落进 kit）。
//
// 两个必须遵守的设计约束（都来自 M0 的真实验训，不是风格偏好）：
//
// 1. **键必须参数化，不能硬编码包名** ✗ —— M0 里"玻璃一直不画"的**根因**就是键前缀：
//    上游把键写成 `packages/liquid_glass_renderer/…`，而当同一个包**被当作 app 根**用时，
//    Flutter 不会给它的资产加 `packages/<name>/` 前缀 ⇒ 键解析不到 ⇒
//    `FragmentProgram.fromAsset` **静默不就绪**（不抛错、不打日志）⇒ 玻璃整块不画 ✗。
//    ⇒ 这里 [assetRoot] 默认为**本 kit 自己的包名**，且**可注入**（测试/宿主可覆盖）。
//
// 2. **加载失败必须打日志，不许静默** ✗ —— M0 的"静默不就绪"让我们付出了整整一轮排查代价。
//    ⇒ [loadShader] 的每个失败分支都 `debugPrint` 明确原因（键、异常），并且 [loadAll] 汇总。
//
// 另注：`.iplr` 是**普通资产**（不是 `shaders:` 构建期块）—— 见 pubspec 里的说明：
// 那 4 个 .frag 的 SkSL 目标在 Windows 上必失败，放进 `shaders:` 会炸掉 Windows 构建。
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

/// 四支折射 shader 的角色（对应上游 `ShaderKeys` 的四条资产）。
enum LiquidGlassRefractionShader {
  /// 几何位移烘焙（先跑一趟，把"位移"编码进纹理）。
  geometryBlended('liquid_glass_geometry_blended.iplr'),

  /// 模糊纹理 + 光学属性合成。
  filter('liquid_glass_filter.iplr'),

  /// 最终合成（`ShaderKeys.liquidGlassRender` 对应的那一支）。
  finalRender('liquid_glass_final_render.iplr'),

  /// 任意形状（Glassify/Stretch 路径）。
  arbitrary('liquid_glass_arbitrary.iplr');

  const LiquidGlassRefractionShader(this.fileName);

  /// 资产文件名（不含目录）。
  final String fileName;
}

/// 资产键构造 + 加载（**唯一入口**：不要在别处硬编码键 ✗）。
abstract final class LiquidGlassRefractionAssets {
  static const String _defaultPackageName = 'liquid_glass_kit';

  /// 资产根。默认 `packages/liquid_glass_kit/lib/assets/shaders/`
  /// （作为**被依赖的包**时 Flutter 给依赖资产加的前缀 ✓）。
  ///
  /// **另一种消费形态（实测）**：当本包被当作 **app 根**（`flutter test`、或本地外壳直接依赖源码）时，
  /// 资产在资产包里位于 `lib/assets/shaders/…`，**没有** `packages/<name>/` 前缀 ✓。
  /// 依据：`flutter test` 的 `build/unit_test_assets/` 里我们的 4 个 `.iplr` 就在该路径下 ✓；
  /// 用默认根加载会得到
  /// `Exception: Asset 'packages/liquid_glass_kit/lib/assets/shaders/…' not found` ✗。
  /// ⇒ 那种形态请用 [appRootConsumptionRoot]（**去掉的是包前缀、保留目录**，不是空串 ✗）。
  static const String appRootConsumptionRoot = 'lib/assets/shaders/';

  /// 可注入：宿主若以其它形态消费（例如把 kit 当 app 根做本地测试），把它设成 `''` 即可 ✓。
  /// 测试里也用它验证"键确实随根变化"（决策 2 的可断言处）。
  static String assetRoot =
      'packages/$_defaultPackageName/lib/assets/shaders/';

  /// 给定角色的完整资产键。
  static String keyFor(LiquidGlassRefractionShader shader) =>
      '$assetRoot${shader.fileName}';

  /// 全部键（顺序固定，便于测试与日志）。
  static List<String> get allKeys => LiquidGlassRefractionShader.values
      .map(keyFor)
      .toList(growable: false);

  /// 加载单支 shader；**失败一定打日志**（不静默 ✗）。
  ///
  /// 泛型 [T] 的存在理由：`ui.FragmentProgram` 是 `base class`，**无法在测试里造假** ✗
  /// ⇒ 若签名写死 `FragmentProgram`，成功分支就永远测不到 ✓。所以让调用方指定程序类型：
  /// 生产写 `loadShader<ui.FragmentProgram>(...)`，测试写 `loadShader<Object>(..., loader: 替身)` ✓。
  static Future<T?> loadShader<T>(
    LiquidGlassRefractionShader shader, {
    Future<T> Function(String assetKey)? loader,
  }) async {
    final key = keyFor(shader);
    try {
      final program = await (loader ??
          ((String k) => ui.FragmentProgram.fromAsset(k) as Future<T>))(key);
      debugPrint('[LiquidGlassKit] refraction shader loaded: ${shader.name} <- $key');
      return program;
    } catch (error, stack) {
      // 关键：这里**不能静默**。M0 的"玻璃不画"就是静默不就绪造成的 ✗。
      debugPrint(
        '[LiquidGlassKit] refraction shader LOAD FAILED: ${shader.name} <- $key\n'
        '  原因: $error\n'
        '  排查提示: 键前缀是否与"资产的消费形态"一致（被依赖的包 ⇒ packages/<name>/…；'
        '被当 app 根 ⇒ 无前缀）；当前 assetRoot="${LiquidGlassRefractionAssets.assetRoot}"\n$stack',
      );
      return null;
    }
  }

  /// 一次加载全部四支；返回成功数量（**失败已逐个打过日志**）。
  static Future<int> loadAll<T>({
    Future<T> Function(String assetKey)? loader,
  }) async {
    var ok = 0;
    for (final shader in LiquidGlassRefractionShader.values) {
      if (await loadShader<T>(shader, loader: loader) != null) ok++;
    }
    if (ok != LiquidGlassRefractionShader.values.length) {
      debugPrint('[LiquidGlassKit] refraction shaders: $ok/'
          '${LiquidGlassRefractionShader.values.length} 加载成功 —— '
          '折射档必须据此**保持不可用**（不要拿半套 shader 去画 ✗）');
    }
    return ok;
  }
}

/// 平台/能力门：折射只在**支持 `ImageFilter.shader` 的运行时**（Impeller）可用。
///
/// 与既有 `LiquidGlassRuntime` 的分工：这里只回答"shader 通道在不在"，
/// 档位决策仍由 kit 既有的 capability/黑名单体系负责（M1a 不改那条链 ✓）。
bool get isRefractionShaderChannelAvailable =>
    // 与上游同一判据（liquid_glass_layer.dart:130）：Skia 上为 false ⇒ 必须降级 ✗。
    isShaderFilterSupportedOnThisRuntime;

/// 抽成顶层 getter 便于测试替身（单测里不想真的去问引擎）。
bool isShaderFilterSupportedOnThisRuntime = _probeShaderFilter();

bool _probeShaderFilter() {
  try {
    return ui.ImageFilter.isShaderFilterSupported;
  } catch (error) {
    // iOS/部分嵌入式运行时可能直接抛 UnsupportedError ⇒ 一律当"不可用"处理（保守 ✓）。
    debugPrint('[LiquidGlassKit] isShaderFilterSupported 探测失败（按不可用处理）: $error');
    return false;
  }
}

/// 便于测试与宿主排查：把当前键与通道状态打成一行。
String describeRefractionAssets() =>
    '[LiquidGlassKit] refraction assets: root="${LiquidGlassRefractionAssets.assetRoot}" '
    'channel=${isRefractionShaderChannelAvailable ? 'available' : 'unavailable'} '
    'keys=${LiquidGlassRefractionAssets.allKeys.length}';

/// 仅供测试：把平台异常类型也暴露出来，便于断言"失败分支真的会被走到"。
Type get refractionPlatformExceptionType => PlatformException;