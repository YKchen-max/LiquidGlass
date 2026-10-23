// SPDX-License-Identifier: GPL-3.0-or-later
//
// 折射 shader 提供方的类型声明（#11 接线，task-18）。
//
// 单独一个文件是为了**避免循环 import**：`liquid_glass_runtime.dart` 需要持有这个类型
// （provider 注册表），而 `liquid_glass_surface.dart` 已经 import runtime（取当前档位）；
// 类型放在这里，两边都能引，无需 runtime → surface 的反向依赖。
import 'dart:ui' as ui;

/// 折射 shader 的提供方。宿主在 #11 落地后实现它（例如用 FragmentProgram 加载
/// fake/liquid shader）。未提供 = 真折射档不可用。
///
/// 注入方式：`LiquidGlassRuntime.refractionShaderProvider = ...`，或单块玻璃用
/// `LiquidGlassSurface(shaderProvider: ...)` 局部覆盖（后者优先）。
abstract class LiquidGlassRefractionShaderProvider {
  /// 返回可用的 FragmentShader（每次调用返回新的实例或共享实例由实现决定）。
  ui.FragmentShader? createShader();

  /// shader 期望的 uniform 数量（用于填充）。
  int get uniformCount;
}
