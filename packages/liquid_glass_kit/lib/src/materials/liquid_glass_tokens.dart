// SPDX-License-Identifier: GPL-3.0-or-later
//
// 材质 token 层（排期 #9）：深浅双套 + 具名材质（glassRegular / glassThick / glassLens）。
//
// 设计依据（docs/liquid-glass-素材.md §8 的 HIG 映射表）：
//   * glassRegular —— 控件/导航功能层（底部导航、悬浮球）：bottom_bar 组合 thickness 30 / blur 8；
//   * glassThick   —— 侧栏/面板：thickness↑、blur↑、glassColor alpha↑；
//   * glassLens    —— 高曲率小控件（播放器进度手柄、滑块）：thickness<10、refractiveIndex↑、色散↑。
// 暗色模式（docs/问题与解决方案.md §1 方案 2）：glassColor 更暗、blur 更大、lightIntensity 更低。
// ⚠️ M1-B 实测补充：这条规则**有下限**——几个"降低"旋钮叠加后，玻璃会在深色背景上直接消失
// （真机 ZTE A2023 深色模式）。暗色档的取值因此带上了"深色背景可读性"的量化下限，
// 见下面 [dark] 的注释与 test/liquid_glass_materials_test.dart 的「暗色档可读性」组。
//
// 关于 thickness / refractiveIndex / chromaticAberration：它们是**真折射档**（#11）的参数，
// FakeGlass 档会忽略（与上游 FakeGlass 的语义一致：没有真实折射）。这里一并给出，
// 是为了让 #11 落地时不必再改 token 结构。
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/foundation.dart';

/// 具名材质。对应素材文档 §8 的 HIG 映射。
enum LiquidGlassMaterial {
  /// 控件/导航功能层（底部导航、悬浮球）。参数起点：thickness 30 / blur 8。
  regular,

  /// 侧栏/面板等大面积容器。厚度、模糊、染色 alpha 都更大。
  thick,

  /// 高曲率小控件（播放器进度手柄、滑块）。厚度小、折射率与色散高。
  lens,

  /// 纯色半透明兜底（最低档），不采样背景。
  solid,
}

/// 一套材质 token。所有字段都可插值（[lerp]），以支持深浅切换时 200ms 平滑过渡、不闪变。
@immutable
class LiquidGlassTokens {
  const LiquidGlassTokens({
    required this.blur,
    required this.saturation,
    required this.tint,
    required this.tintOpacity,
    required this.lightIntensity,
    required this.lightAngle,
    required this.highlightOpacity,
    required this.ambientStrength,
    required this.borderColor,
    required this.borderWidth,
    required this.shadowOpacity,
    required this.thickness,
    required this.refractiveIndex,
    required this.chromaticAberration,
    this.adaptiveLift = 0,
    this.adaptiveDarken = 0,
  });

  /// BackdropFilter 的模糊 sigma（Skia 与 Impeller 都支持）。
  final double blur;

  /// 饱和度倍率。>1 增强背景色彩（真折射档由 shader 做，FakeGlass 档由 ColorFilter.matrix 做）。
  final double saturation;

  /// 玻璃底色（叠加在模糊后的背景上）。
  final Color tint;

  /// 底色不透明度。0 = 完全靠背景，观感最"清透"。
  final double tintOpacity;

  /// 高光强度（0..1）。暗色模式要调低，否则玻璃会"发光过曝"。
  final double lightIntensity;

  /// 全 App 统一光角（建议 π/4 = 左上光源，素材文档 §8）。
  final double lightAngle;

  /// 沿光角的两道描边高光的不透明度。
  final double highlightOpacity;

  /// 环境光强度（0..1）：高光渐变中段的不透明度，**直接取用、不再乘 rim alpha**
  /// （task-7 与上游对齐：refs/flutter_liquid_glass-main/packages/liquid_glass_renderer/
  /// lib/src/fake_glass.dart:398-404 的 mid stop 就是 ambientStrength 本身）。
  /// 越大玻璃中段的余晖越强（暗色模式要调低）。
  ///
  /// ⚠️ 数值口径在 task-7 变过一次：旧实现写成 `color.a * ambientStrength`，把 rim alpha
  /// 又乘了一遍（暗色档的中段余晖因此被压到 0.026）。所以 light/dark 现在的取值是按**旧公式
  /// 反算**出来的精确 double，末尾的浮点零头不要手改——差 1 ULP 就会破坏
  /// 「浅色档截图逐字节不变」的严格比对（test/liquid_glass_materials_test.dart 有对应断言）。
  /// forMaterial 的 thick/lens 同理：它们按同一系数折算 ambient，与旧公式在 double 层可能差 1 ULP，
  /// 但光栅输出逐字节相同（task-7 用浅色/暗色三张截图的 sha256 相等证明过）。
  final double ambientStrength;

  final Color borderColor;
  final double borderWidth;
  final double shadowOpacity;

  // ── 以下三个是真折射档（#11）专用；FakeGlass 档忽略 ──
  /// 玻璃厚度（折射位移量）。glassRegular 起点 30，glassLens <10。
  final double thickness;

  /// 折射率。玻璃 1.2~1.52，水 1.33。
  final double refractiveIndex;

  /// 色散强度（RGB 三通道偏移缩放）。
  final double chromaticAberration;

  // ── 以下两个是自适应对比度保护（#12 / task-9）；FakeGlass 档用，真折射档忽略 ──
  /// 玻璃本体亮度下限（0 = 关闭）：在**暗背景**方向上把玻璃本体抬到不低于该值。
  /// 与 [adaptiveDarken] 一起把背景亮度 d 映射成「玻璃本体」亮度
  /// `r = lift + (1-lift)(1-darken)·d`（逐像素、由背景自身亮度驱动）。
  final double adaptiveLift;

  /// 亮背景压缩强度（0 = 关闭）：越接近 1，越把**亮背景**压暗（给玻璃上的白字留对比度余量），
  /// 而暗背景几乎不受影响（乘性压暗的量与背景亮度成正比）。
  final double adaptiveDarken;

  /// 浅色模式：低模糊、亮底、较高高光。
  static const LiquidGlassTokens light = LiquidGlassTokens(
    blur: 8,
    saturation: 1.5,
    tint: Color(0xFFFFFFFF),
    tintOpacity: 0.18,
    lightIntensity: 0.5,
    lightAngle: math.pi / 4,
    highlightOpacity: 0.55,
    ambientStrength: 0.18046875000000004,
    // task-12：浅色侧的边沿只能靠**深色**发丝——白描边铺在白页上物理上不可见
    // （旧值 #66FFFFFF 在 paper 档实测「深线索」CR 1.05）。α=0.5 是让「深线索」在
    // 浅页上稳过 3:1 的最小档（paper 3.16→4.4、mint 2.79→3.7）；再深会变成明显的分割线。
    // 代价：暗页上这根深线看不见（约 1.0），暗页的边沿改由未受影响的白色高光承担，
    // 实测 rim 峰值 10.48→5.27（仍 ≥3:1，见 task-12 报告的四象限表）。
    borderColor: Color(0x80000000),
    // 线宽 1.0 对齐暗色档/M1-B（0.8 在深色发丝上抗锯齿后覆盖率不足，实测会吃掉 ~0.4 CR）。
    borderWidth: 1.0,
    shadowOpacity: 0.10,
    // 亮色档的两个自适应旋钮（task-12 重新定值）：
    //   adaptiveLift   —— 暗背景方向：抬玻璃本体，否则深字压在暗玻璃上读不出
    //                     （task-9 前实测 light×暗背景下深字只有 2.01:1）；
    //   adaptiveDarken —— 亮背景方向：**近白页面必须把玻璃压下去**，否则玻璃与页面
    //                     几乎同亮（task-11 实测 max Δ8、>8/255 占 0.00%；本 bench 的
    //                     paper 档复现为 lift −4.7/255、rim CR 1.15）。
    // 0.371 是按「d∈[0.85,1.0] 上 |pane−page| ≥20/255」反解出来的（K=0.39，过零点
    // d≈0.72）；lift 保持 0.38 是因为再抬会抵消暗背景方向的抬升、把纯黑页面的深字余量吃掉。
    // 两者互相牵制是**结构性**的：合成是仿射映射 r = lift + (1-lift)(1-darken)·d，
    // 再叠白 tint 后 pane−page 必然在某处过零（本组参数 d≈0.78）——那条窄带里玻璃本体
    // 拉不开，靠下面的深色发丝描边保住「可辨」。
    adaptiveLift: 0.38,
    adaptiveDarken: 0.371,
    thickness: 30,
    refractiveIndex: 1.21,
    chromaticAberration: 0.01,
  );

  /// 暗色模式（M1-B 调优，2026-10-02）："更暗 + 光强更低"必须与"深色背景上仍读得出玻璃"共存。
  ///
  /// 问题不在"暗色不够暗"，而是三个旋钮被**叠加**衰减，把边缘高光压到看不见了：
  ///   * 旧值 lightIntensity 0.28 与 highlightOpacity 0.32 同时下调 →
  ///     painter 的有效 rim alpha = easeOut(0.28)×0.32×1.6 ≈ 0.21；上游的暗色档只把
  ///     lightIntensity 降到亮色的 0.7、并不再额外压 rim 的 alpha
  ///     （refs/flutter_liquid_glass-main/…/example/lib/widgets/bottom_bar.dart:96
  ///     `lightIntensity: isDark ? .7 : 1`，素材文档 §4 "实测调好的 TabBar 组合"）；
  ///   * ambientStrength 当时在本包 painter 里是 `color.withValues(alpha: color.a * ambient)`，
  ///     会被上面那个 0.21 再乘一次 → 中段余晖只剩 0.026（上游 fake_glass.dart:401 的
  ///     mid stop 直接就是 ambientStrength，约 0.2，不叠乘）。**task-7 已把 painter 改成上游语义**
  ///     （mid stop 直接取 ambientStrength），因此下面 dark 的取值是
  ///     `0.11396865987777713` = 旧公式反算的等效值——观感与 M1-B 逐位相同；
  ///   * 描边 alpha 0.2、线宽 0.8——上游描边线宽下限是 lerp(1,2) → 1.0（fake_glass.dart:419）。
  /// 调优方向依据问题台账 §1.1「暗背景 → 浅 tint + 提高光强」（自适应染色的静态近似），
  /// 同时守住"暗色对比亮色仍然克制"：lightIntensity / highlightOpacity / ambientStrength
  /// 三项都仍 < light 档。
  ///
  /// 量化标准（2026-10-02 实测：poc/glass_poc main_kit_bench，KIT_BENCH_BG=dark + Skia，
  /// 像素统计脚本 .probe/dt-bench/metrics.py；同背景同窗口 1920×1080，ROI 由 App 自画的品红标记标定）：
  ///   * 描边/边缘高光 vs 深色背景（底部导航实测）：1.82 → 4.23（WCAG 2.1 SC 1.4.11 非文本对比度 ≥3:1）；
  ///   * 边缘"光扫过玻璃"的层次：rim 峰值/中位 2.3 → 4.1；
  ///   * 玻璃板 vs 深色背景：由 −12/255（比背景更暗，糊成一片）变为 +5…+20/255（抬起）；
  ///     ⚠️ 暗端的 CR 比值不敏感（1.14 → 1.07），要看带符号的 luma 差；
  ///   * 边缘高光有效 alpha 0.21 → 0.41（低于 ~0.38 时深色背景上读不出边）。
  /// 已知取舍：暗色 tint 变浅后，压在**亮**内容上的白字对比度会略降（同一 bench 实测：白字 vs
  /// 亮背景下的玻璃 5.90 → 4.56，仍在 WCAG AA 4.5 之上但余量变小）。要同时满足亮/暗两种背景，
  /// 最终需要 §1.1 的 shader 内逐像素自适应染色（属 #11）；文字侧还有 §1.3 的阴影/scrim 兜底，不在本 token 层解决。
  static const LiquidGlassTokens dark = LiquidGlassTokens(
    blur: 12,
    saturation: 1.35,
    // 旧值 #0B0F14（computeLuminance≈0.006）在深色背景上没有"抬起"余量，比背景还暗一点。
    tint: Color(0xFF2E3A4A),
    tintOpacity: 0.42,
    // 上游 example 暗色档 = 亮色 × 0.7（bottom_bar.dart:96）→ 0.7 × light 的 0.5。
    lightIntensity: 0.35,
    lightAngle: math.pi / 4,
    highlightOpacity: 0.50,
    ambientStrength: 0.11396865987777713,
    borderColor: Color(0x5CFFFFFF),
    borderWidth: 1.0,
    shadowOpacity: 0.28,
    // 暗色主题的文字是**白色**：亮背景下必须把玻璃压暗（旧值实测白字 4.69:1，余量极小），
    // 同时把暗背景抬一点（保持 M1-B 的「玻璃板比背景亮」）。rim/描边不受这两个值影响。
    adaptiveLift: 0.10,
    adaptiveDarken: 0.45,
    thickness: 30,
    refractiveIndex: 1.21,
    chromaticAberration: 0.01,
  );

  /// 边缘高光的有效不透明度（painter 里的 rim alpha）：
  /// `easeOut(lightIntensity) × highlightOpacity × 1.6`，夹在 0..1。
  /// painter 与测试共用它，避免「测试里的公式」与「实现里的公式」各写一份后漂移。
  double get rimAlpha =>
      (Curves.easeOut.transform(lightIntensity.clamp(0.0, 1.0)) *
              highlightOpacity *
              1.6)
          .clamp(0.0, 1.0);

  /// 渐变中段（环境光余晖）的不透明度：**就是 ambientStrength 本身**，不乘 rim alpha
  /// （上游 fake_glass.dart:398-404 的写法，task-7 对齐）。
  double get midStopAlpha => ambientStrength.clamp(0.0, 1.0);

  /// tint 自身的 sRGB 亮度（0..1）。自适应合成在 sRGB 域做，用它与 [tintOpacity] 合成玻璃板亮度；
  /// `Color.computeLuminance()` 是线性域数值，不适用于这里的合成式。
  double get tintLuma => 0.2126 * tint.r + 0.7152 * tint.g + 0.0722 * tint.b;

  /// 自适应后的「玻璃本体」亮度（tint 之前的模糊背景）：`r = lift + (1-lift)(1-darken)·d`，
  /// d = 背景亮度。lift 抬暗背景、darken 压亮背景 —— 与 painter 里
  /// multiply(黑,α=darken) → screen(灰=lift) 两道混合的实际数学一致。
  /// 两个旋钮都是 0 时返回 d（关闭 = 与旧实现逐位一致）。
  double adaptiveBackdropLuma(double backdropLuma) {
    final d = backdropLuma.clamp(0.0, 1.0);
    final lift = adaptiveLift.clamp(0.0, 1.0);
    final darken = adaptiveDarken.clamp(0.0, 1.0);
    if (lift == 0 && darken == 0) return d;
    return lift + (1 - lift) * (1 - darken) * d;
  }

  /// 叠上 tint（srcOver）之后的玻璃板亮度：四象限文字对比度断言就量它。
  double glassLumaOver(double backdropLuma) {
    final alpha = tintOpacity.clamp(0.0, 1.0);
    return alpha * tintLuma + (1 - alpha) * adaptiveBackdropLuma(backdropLuma);
  }

  /// 按具名材质派生一套 token（在 given 的基础上调整参数）。
  LiquidGlassTokens forMaterial(LiquidGlassMaterial material) {
    switch (material) {
      case LiquidGlassMaterial.regular:
        return this;
      case LiquidGlassMaterial.thick:
        return copyWith(
          blur: blur * 1.6,
          tintOpacity: math.min(1, tintOpacity * 1.5),
          thickness: thickness * 1.5,
          highlightOpacity: highlightOpacity * 0.85,
          // 旧语义下 mid stop = rim alpha × ambient，被 highlightOpacity 连带缩放；
          // 新语义下 mid stop 只认 ambientStrength，所以这里同步折算，保证 thick 档渲染不变。
          ambientStrength: ambientStrength * 0.85,
          shadowOpacity: shadowOpacity * 1.2,
        );
      case LiquidGlassMaterial.lens:
        return copyWith(
          blur: blur * 0.6,
          thickness: 8,
          refractiveIndex: 1.35,
          chromaticAberration: 0.03,
          highlightOpacity: highlightOpacity * 1.15,
          // 同上：lens 的 rim ×1.15，mid stop 也要跟着 ×1.15（否则浅色档会变）。
          ambientStrength: ambientStrength * 1.15,
          borderWidth: borderWidth * 1.25,
        );
      case LiquidGlassMaterial.solid:
        return copyWith(
          blur: 0,
          saturation: 1,
          tintOpacity: math.min(1, tintOpacity + 0.35),
          highlightOpacity: 0,
          thickness: 0,
          chromaticAberration: 0,
        );
    }
  }

  /// #18 无障碍（task-93）：**增强对比** ⇒ 强制启用自适应对比度，并把发丝加粗到可辨下限。
  ///
  /// * 取值一律是**下限**（只抬不降）：已经强于下限的 token 保持原样 ⇒ 不会改坏 task-9/12 的取值；
  /// * 只由「增强对比」这一条路径调用（`LiquidGlassRuntime.increaseContrast` 或系统高对比度），
  ///   **默认关** ⇒ 调用方原样使用现有 token ⇒ 出厂渲染逐字节不变 ✓（锚点 6a87cd67… / ea15bc07…）；
  /// * 改前 → 改后（本轮取值，证据见报告 §task-93）：
  ///   light：adaptiveLift 0.38→0.38（本就高于 0.30）、adaptiveDarken 0.371→0.50、
  ///          borderWidth 1.0→1.2、borderColor α 0.50→0.55；
  ///   dark ：adaptiveLift 0.10→0.30、adaptiveDarken 0.45→0.50、
  ///          borderWidth 1.0→1.2、borderColor α 0.36→0.55。
  LiquidGlassTokens forIncreasedContrast() => copyWith(
    adaptiveLift: adaptiveLift < 0.30 ? 0.30 : adaptiveLift,
    adaptiveDarken: adaptiveDarken < 0.50 ? 0.50 : adaptiveDarken,
    borderWidth: borderWidth < 1.2 ? 1.2 : borderWidth,
    borderColor: borderColor.withValues(
      alpha: borderColor.a < 0.55 ? 0.55 : borderColor.a,
    ),
  );

  /// #19（task-94）：**玻璃强度**（0.0–1.0）⇒ 对可调旋钮做**标量缩放**。
  ///
  /// 语义（口径写死 ✓）：
  ///   * **不改档位** ✗ —— 强度只是同一档位内部的强弱（与「降低透明度」的真降档不同 ✗）；
  ///   * `strength >= 1` ⇒ **直接 `return this`** ✓（这是「出厂默认 100% ⇒ 渲染逐字节不变」
  ///     最便宜的强保证：同一个对象、同一个值，连 `copyWith` 都不走 ✓）；
  ///   * `0` ⇒ 最弱（几乎纯色，但**仍在原档位** ✓）：blur/tint/高光/环境光/阴影归零，
  ///     折射参数退回无折射（`refractiveIndex = 1.0`、色散 0），发丝保留最低可见度；
  ///   * 映射是**线性**的（公式即下表，无曲线）：
  ///
  /// | 旋钮 | 0% | 25% | 50% | 75% | 100% |
  /// |---|---|---|---|---|---|
  /// | blur | 0 | 0.25·b | 0.5·b | 0.75·b | b |
  /// | tintOpacity | 0 | 0.25·t | 0.5·t | 0.75·t | t |
  /// | highlightOpacity | 0 | 0.25·h | 0.5·h | 0.75·h | h |
  /// | ambientStrength | 0 | 0.25·a | 0.5·a | 0.75·a | a |
  /// | shadowOpacity | 0 | 0.25·s | 0.5·s | 0.75·s | s |
  /// | lightIntensity | 0 | 0.25·l | 0.5·l | 0.75·l | l |
  /// | borderWidth | 0.5（下限） | …线性… | | | w |
  /// | borderColor α | 0.25（下限） | …线性… | | | α |
  /// | saturation | 1.0（无增益） | …线性… | | | sat |
  /// | thickness | 0 | 0.25·d | 0.5·d | 0.75·d | d |
  /// | refractiveIndex | 1.0（无折射） | …线性… | | | n |
  /// | chromaticAberration | 0 | 0.25·c | 0.5·c | 0.75·c | c |
  ///
  /// **明确不缩放 `adaptiveLift` / `adaptiveDarken`** ✗ —— 那是 task-9/12/93 的**对比度保护**
  /// （无障碍语义，不是「强度」）；缩放它们会让「滑杆拉到 0」顺带把可读性保护撤掉 ✗✗。
  /// 同理 `lightAngle` 不缩放（它是方向，不是强度）。
  ///
  /// 与「增强对比」的组合顺序（单一收口在 `LiquidGlassSurface.build`）：
  /// `forMaterial → forStrength → forIncreasedContrast` ⇒ 强对比的**下限**最后落 ✓，
  /// 两个开关不会互相抵消 ✓。
  LiquidGlassTokens forStrength(double strength) {
    if (strength >= 1) return this;
    final s = strength <= 0 ? 0.0 : strength;
    return copyWith(
      blur: blur * s,
      saturation: 1 + (saturation - 1) * s,
      tintOpacity: tintOpacity * s,
      lightIntensity: lightIntensity * s,
      highlightOpacity: highlightOpacity * s,
      shadowOpacity: shadowOpacity * s,
      ambientStrength: ambientStrength * s,
      // 发丝留一个下限：0% 也保住「形状可辨」（与 task-12/93 的边沿可辨同向 ✓）
      borderWidth: borderWidth * s < 0.5 ? 0.5 : borderWidth * s,
      borderColor: borderColor.withValues(
        alpha: borderColor.a * s < 0.25 ? 0.25 : borderColor.a * s,
      ),
      thickness: thickness * s,
      refractiveIndex: 1 + (refractiveIndex - 1) * s,
      chromaticAberration: chromaticAberration * s,
    );
  }

  LiquidGlassTokens copyWith({
    double? blur,
    double? saturation,
    Color? tint,
    double? tintOpacity,
    double? lightIntensity,
    double? lightAngle,
    double? highlightOpacity,
    Color? borderColor,
    double? borderWidth,
    double? shadowOpacity,
    double? thickness,
    double? refractiveIndex,
    double? chromaticAberration,
    double? ambientStrength,
    double? adaptiveLift,
    double? adaptiveDarken,
  }) {
    return LiquidGlassTokens(
      blur: blur ?? this.blur,
      saturation: saturation ?? this.saturation,
      tint: tint ?? this.tint,
      tintOpacity: tintOpacity ?? this.tintOpacity,
      lightIntensity: lightIntensity ?? this.lightIntensity,
      lightAngle: lightAngle ?? this.lightAngle,
      highlightOpacity: highlightOpacity ?? this.highlightOpacity,
      ambientStrength: ambientStrength ?? this.ambientStrength,
      adaptiveLift: adaptiveLift ?? this.adaptiveLift,
      adaptiveDarken: adaptiveDarken ?? this.adaptiveDarken,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      shadowOpacity: shadowOpacity ?? this.shadowOpacity,
      thickness: thickness ?? this.thickness,
      refractiveIndex: refractiveIndex ?? this.refractiveIndex,
      chromaticAberration: chromaticAberration ?? this.chromaticAberration,
    );
  }

  /// 线性插值：深浅切换时用它做 200ms 过渡（避免颜色/模糊跳变造成的闪变）。
  static LiquidGlassTokens lerp(
    LiquidGlassTokens a,
    LiquidGlassTokens b,
    double t,
  ) {
    final k = t.clamp(0.0, 1.0);
    return LiquidGlassTokens(
      blur: _lerpDouble(a.blur, b.blur, k),
      saturation: _lerpDouble(a.saturation, b.saturation, k),
      tint: Color.lerp(a.tint, b.tint, k)!,
      tintOpacity: _lerpDouble(a.tintOpacity, b.tintOpacity, k),
      lightIntensity: _lerpDouble(a.lightIntensity, b.lightIntensity, k),
      lightAngle: _lerpDouble(a.lightAngle, b.lightAngle, k),
      highlightOpacity: _lerpDouble(a.highlightOpacity, b.highlightOpacity, k),
      ambientStrength: _lerpDouble(a.ambientStrength, b.ambientStrength, k),
      borderColor: Color.lerp(a.borderColor, b.borderColor, k)!,
      borderWidth: _lerpDouble(a.borderWidth, b.borderWidth, k),
      shadowOpacity: _lerpDouble(a.shadowOpacity, b.shadowOpacity, k),
      thickness: _lerpDouble(a.thickness, b.thickness, k),
      refractiveIndex: _lerpDouble(a.refractiveIndex, b.refractiveIndex, k),
      chromaticAberration: _lerpDouble(
        a.chromaticAberration,
        b.chromaticAberration,
        k,
      ),
      adaptiveLift: _lerpDouble(a.adaptiveLift, b.adaptiveLift, k),
      adaptiveDarken: _lerpDouble(a.adaptiveDarken, b.adaptiveDarken, k),
    );
  }

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

  @override
  bool operator ==(Object other) {
    return other is LiquidGlassTokens &&
        other.blur == blur &&
        other.saturation == saturation &&
        other.tint == tint &&
        other.tintOpacity == tintOpacity &&
        other.lightIntensity == lightIntensity &&
        other.lightAngle == lightAngle &&
        other.highlightOpacity == highlightOpacity &&
        other.ambientStrength == ambientStrength &&
        other.borderColor == borderColor &&
        other.borderWidth == borderWidth &&
        other.shadowOpacity == shadowOpacity &&
        other.thickness == thickness &&
        other.refractiveIndex == refractiveIndex &&
        other.chromaticAberration == chromaticAberration &&
        other.adaptiveLift == adaptiveLift &&
        other.adaptiveDarken == adaptiveDarken;
  }

  @override
  int get hashCode => Object.hash(
    blur,
    saturation,
    tint,
    tintOpacity,
    lightIntensity,
    lightAngle,
    highlightOpacity,
    ambientStrength,
    borderColor,
    borderWidth,
    shadowOpacity,
    thickness,
    refractiveIndex,
    chromaticAberration,
    adaptiveLift,
    adaptiveDarken,
  );

  @override
  String toString() =>
      'LiquidGlassTokens(blur: $blur, saturation: $saturation, '
      'tintOpacity: $tintOpacity, lightIntensity: $lightIntensity, thickness: $thickness)';
}

/// 饱和度矩阵（Rec.709 亮度系数）。FakeGlass 档在 Skia 上用它替代 shader 里的饱和度处理
/// （素材文档 §6 的 Skia 兜底写法）。
List<double> saturationMatrix(double s) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
  return <double>[
    sr + s, sg, sb, 0, 0, //
    sr, sg + s, sb, 0, 0, //
    sr, sg, sb + s, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}
