// SPDX-License-Identifier: GPL-3.0-or-later
//
// LiquidGlassKit —— 液态玻璃设计系统的实现包。
//
// 本包在阶段一建立了骨架与素材层（图标集/字体）；材质 token、三级降级矩阵与能力探测
// 属于排期 #9（下面三个 export），真折射 shader 属于 #11。

export 'src/icons/liquid_icons.dart';
export 'src/materials/liquid_glass_capability.dart';
export 'src/materials/liquid_glass_refraction.dart';
export 'src/materials/liquid_glass_runtime.dart';
export 'src/materials/liquid_glass_surface.dart';
export 'src/materials/liquid_glass_tokens.dart';
// #11 / M1a：折射管线（预编译 .iplr 资产 + 键参数化 + uniform 布局 + 绘制顺序纪律）。
// **纯增量**：既有 FakeGlass 路径不引用这三个文件（M1b 才接线，见 .probe/m1-port/）。
export 'src/refraction/liquid_glass_paint_order.dart';
export 'src/refraction/liquid_glass_filter_pass.dart';
export 'src/refraction/liquid_glass_geometry_pass.dart';
export 'src/refraction/liquid_glass_refraction_pass.dart';
export 'src/refraction/liquid_glass_refraction_layer.dart';
export 'src/refraction/liquid_glass_refraction_shape.dart';
export 'src/refraction/liquid_glass_refraction_stage.dart';
export 'src/refraction/liquid_glass_refraction_assets.dart';
export 'src/refraction/liquid_glass_uniform_layout.dart';

/// 包版本，与 pubspec.yaml 保持一致。
///
/// 骨架期用它做最小可测断言，避免空包在 CI 里被判定为无内容。
const String liquidGlassKitVersion = '0.1.0';

/// 本包提供的字体族（供宿主 App 在 TextStyle 里引用）。
///
/// 说明：Flutter 中「包内声明的字体」在宿主里用的就是**不带前缀的族名**
/// （同 font_awesome_flutter 的做法），因此这里直接给出可用的族名常量。
abstract final class LiquidFontFamily {
  /// 正文字体（CJK 子集，GB2312 覆盖）
  static const String text = 'LiquidText';

  /// UI 主图标集（Material Symbols Rounded 子集）
  static const String icons = 'LiquidIcons';

  /// 线性图标集（Lucide 子集）
  static const String lucide = 'LucideIcons';
}