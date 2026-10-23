// SPDX-License-Identifier: GPL-3.0-or-later
//
// 运行时单例（排期 #9）：宿主启动时探测一次，全 App 复用；渲染出问题时可以 latch 降档。
//
// 为什么用静态单例而不是 InheritedWidget：档位是"整机能力"，不随路由/子树变化；
// 层层透传会把上游几百个页面都改一遍（与"玻璃层独立、少侵入"的纪律冲突）。
// 需要局部覆盖时，[LiquidGlassSurface.capability] 参数仍然优先。
import 'package:flutter/foundation.dart';

import 'liquid_glass_capability.dart';
import 'liquid_glass_refraction.dart';

/// 全局能力状态。
abstract final class LiquidGlassRuntime {
  static LiquidGlassCapability? _capability;

  /// #11 接线点：折射 shader 的提供方。宿主在启动时注入（本包**不自带** shader 资产）；
  /// 未注入时 [refractionShaderAvailable] 为 false，能力矩阵按平台规则退 FakeGlass。
  /// 有它才允许选 refraction —— 这是渲染侧的 shader 门禁（与能力侧的 shader filter
  /// 门禁是两道独立的闸，见 LiquidGlassProbe._guardRefraction 与本文件的注释）。
  static LiquidGlassRefractionShaderProvider? refractionShaderProvider;

  /// 折射 shader 是否已就位（能力探测的输入之一，也是渲染层二次校验的依据）。
  static bool get refractionShaderAvailable => refractionShaderProvider != null;

  /// #18 无障碍（task-93）：**增强对比**是否生效。
  ///
  /// 由宿主在启动/切换设置时同步（app 侧 `GlassAccessibility.syncRuntimeFlags()`）；
  /// kit 另外**自己**读 `MediaQuery.highContrast`（Windows 高对比度主题 ⇒ 无需宿主接线即生效）；
  /// 两者是**或**关系（见 `LiquidGlassSurface.build`）。**默认 false ⇒ 出厂渲染不变** ✓。
  static bool increaseContrast = false;

  /// 当前能力（未初始化时为 null）。
  static LiquidGlassCapability? get capability => _capability;

  /// #18 无障碍（task-93）：宿主可设的**档位封顶**（**只降不抬** ✗）。
  ///
  /// 语义：`tier` 取"能力档位"与"封顶"中**更弱**的那个 ✓ ⇒ 调用方只能把档位往下压，
  /// **不可能抬回** ✗（能力三闸门仍在它之前 ✓）；`null` = 不封顶（**出厂默认 ⇒ 渲染不变** ✓）。
  ///
  /// 为什么需要它：**app chrome（侧栏/顶栏/底导）走的是本类的全局 `tier`** ✓，
  /// 而 `LiquidGlassPolicy.effectiveTier` 只覆盖播放器/直播两条路径 ✗ ——
  /// task-93 实测发现：把"降低透明度"的封顶只加在后者时，**侧栏不受影响** ✗。
  static LiquidGlassTier? tierCap;

  /// #19（task-94）：**玻璃强度**（0.0–1.0，默认 **1.0** = 出厂/当前默认）。
  ///
  /// 它**不改档位** ✗ —— 档位仍由能力矩阵 + 策略 + 无障碍封顶（[tierCap]）决定；
  /// 强度只是把同一档位内部的旋钮按比例缩放（见 `LiquidGlassTokens.forStrength`）。
  /// **默认 1.0 ⇒ `forStrength` 直接返回原 token ⇒ 渲染逐字节不变** ✓（锚点 6a87cd67…/ea15bc07…）。
  ///
  /// 宿主同步方式：`GlassAccessibility.syncRuntimeFlags()`（与 [increaseContrast]/[tierCap] 同一处 ✓）——
  /// 单一收口，避免「某条路径忘了读它」✗（task-93 的教训 ✓）。
  static double strength = 1.0;

  /// 把**任意**档位按当前 [tierCap] 封顶（**只降不抬** ✓）。
  ///
  /// 语义（口径写死 ✓）：**[tierCap] = 允许的"最强"档位** ⇒ 结果**不能比它更强** ✓。
  /// 枚举声明顺序 `refraction → fakeGlass → solid` 是**由强到弱** ⇒ "更强" = **index 更小** ✓，
  /// 故取 `index` **更大**（更弱）的那个：`tier.index >= cap.index ? tier : cap` ✓。
  /// ⇒ `tierCap = solid` 等价于**强制纯色** ✓（比 solid 强的一律降为 solid ✓）——
  /// 这正是"降低透明度"要的语义 ✓（`GlassAccessibility.capTier` 用的也是"直接给 solid" ✓）。
  ///
  /// 为什么要有这个函数：光在 [tier] getter 里封顶**不够** ✗ ——
  /// `LiquidGlassSurface` 是 `cap = capability ?? LiquidGlassRuntime.capability`
  /// 之后再取 `cap?.tier`（**原始**能力档位 ✓）⇒ 它**绕过** getter ✗。
  /// 故"封顶"必须做成**单一收口**：凡是拿档位去渲染的地方都走本函数 ✓。
  ///
  /// ⚠ 踩过的坑 ✗✓：本函数第一版把比较写成 `<=`（把"更强"与"更大 index"对调了 ✗），
  /// 结果"封顶到 solid"时 `fakeGlass` **原样返回** ✗ ⇒ **两条单测当场抓住** ✓
  /// （`Expected solid, Actual fakeGlass`）⇒ 教训：**封顶类代码必须写"方向"用例** ✓。
  static LiquidGlassTier cappedTier(LiquidGlassTier tier) {
    final cap = tierCap;
    if (cap == null) return tier;
    return tier.index >= cap.index ? tier : cap;
  }

  /// 当前档位；未初始化时保守取 FakeGlass（Skia 兼容，不需要 shader）。
  ///
  /// 受 [tierCap] 封顶（只降不抬 ✓）；枚举声明顺序为 `refraction → fakeGlass → solid`
  /// （**由强到弱** ✓）⇒ "更弱" = **index 更大** ✓。
  static LiquidGlassTier get tier =>
      cappedTier(_capability?.tier ?? LiquidGlassTier.fakeGlass);

  /// 是否值得挂玻璃层（纯色档就别挂了，直接用上游原样式，避免无谓的合成开销）。
  static bool get glassEnabled => tier != LiquidGlassTier.solid;

  /// 启动时调用。参数与 [LiquidGlassProbe.resolve] 一致，便于测试注入。
  static Future<LiquidGlassCapability> initialize({
    LiquidGlassProbeStore? store,
    LiquidGlassTier? forcedTier,
    List<LiquidGlassBlacklistEntry>? blacklist,
    String? platformOverride,
    String? osVersionOverride,
    bool? shaderFilterSupportedOverride,
    bool? remoteSessionOverride,
    bool? refractionShaderAvailable,
  }) async {
    final capability = await LiquidGlassProbe.resolve(
      store: store,
      forcedTier: forcedTier,
      blacklist: blacklist,
      platformOverride: platformOverride,
      osVersionOverride: osVersionOverride,
      shaderFilterSupportedOverride: shaderFilterSupportedOverride,
      remoteSessionOverride: remoteSessionOverride,
      // 默认跟随 provider 注册表：宿主接上 provider 才会选到 refraction，
      // 不接就与接线前完全一致（FakeGlass）。
      refractionShaderAvailable:
          refractionShaderAvailable ??
          LiquidGlassRuntime.refractionShaderAvailable,
    );
    _capability = capability;
    debugPrint('[LiquidGlass] ${describeCapability(capability)}');
    return capability;
  }

  /// 渲染真出问题了就调它：落盘 latch + 立刻降档（本次会话内立即生效）。
  static Future<LiquidGlassCapability> reportFailure(
    String reason, {
    LiquidGlassProbeStore? store,
  }) async {
    final failedTier = tier;
    final capability = await LiquidGlassProbe.latchFailure(
      reason: reason,
      store: store,
      failedTier: failedTier,
    );
    _capability = capability;
    return capability;
  }

  /// 测试用：直接覆盖当前能力。
  @visibleForTesting
  static void overrideForTest(LiquidGlassCapability? capability) =>
      _capability = capability;
}

/// 便于日志与上报的一行摘要（转发到 capability 的实现，避免调用方两处 import）。
String describeCapability(LiquidGlassCapability capability) =>
    'tier=${capability.tier.name} platform=${capability.platform} '
    'shaderFilter=${capability.shaderFilterSupported} reason=${capability.reason}';
