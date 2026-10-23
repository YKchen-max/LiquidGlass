// SPDX-License-Identifier: GPL-3.0-or-later
//
// #18 无障碍映射（task-93）：三个自建开关（Apple 语义）＋ Windows 高对比度主题
// ⇒ 汇入既有的三级降级矩阵（真折射 → FakeGlass → 纯色）与 kit 的自适应对比度。
//
// 为什么单开一个文件：三个开关是"矩阵的外部入口"，语义集中写清；调用点保持薄
// （策略文件只加一行封顶、播放器只把时长读成 0、kit 只多一个布尔输入）。
//
// 出厂默认：**三开关全关** ⇒ 本文件所有解析结果都返回"不变"（`capTier` 原样返回、
// `motionDuration` 原样返回、`increaseContrast` 为假）⇒ 渲染与行为逐字节一致 ✓。
//
// 取值优先级（写死，便于取证与排错）：**环境变量 > 测试接缝 > 设置项(Pref) > 出厂默认(关)**。
//   * 环境变量 `GLASS_A11Y_*` 只用于在同一份产物上跑 A/B 截图（与 kit bench 的 KIT_BENCH_* 同一约定）；
//     只认 "true"/"1" 两个字面量（与手册 §18.82 的 bool.fromEnvironment 规矩同源）；
//   * 测试接缝（`debugXxx`）生产恒为 null；
//   * **存储不可用时按"关"**：`GStorage` 未初始化也不允许抛 —— `effectiveTier` 每帧都会被调用，
//     而且 `test/own` 的既有测试根本不初始化存储 ✓。
import 'dart:io' show Platform;

import 'package:PiliPlus/utils/glass_strength.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/widgets.dart' show BuildContext, MediaQuery;
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

abstract final class GlassAccessibility {
  /// 环境变量来源（可替换 ⇒ 单测不依赖真实进程环境）。
  static Map<String, String> environment = Platform.environment;

  /// 测试接缝（**生产恒为 null** ⇒ 走真实 Pref）。
  static bool? debugReduceTransparency;
  static bool? debugReduceMotion;
  static bool? debugIncreaseContrastSwitch;

  static bool _env(String key) {
    final v = environment[key];
    // 与手册 §18.82 同规矩：只认 "true"/"1" 两个字面量，其余（含 "TRUE"/"yes"）一律当关。
    return v == 'true' || v == '1';
  }

  static bool _flag(String envKey, bool? seam, bool Function() read) {
    if (_env(envKey)) return true;
    if (seam != null) return seam;
    try {
      return read();
    } catch (_) {
      // 存储未就绪 ⇒ 按出厂默认（关）。不抛：调用点在每帧路径上（`effectiveTier`）。
      return false;
    }
  }

  /// 降低透明度（Reduce Transparency）⇒ 玻璃档位**封顶到 solid**。
  static bool get reduceTransparency => _flag(
    'GLASS_A11Y_REDUCE_TRANSPARENCY',
    debugReduceTransparency,
    () => Pref.glassReduceTransparency,
  );

  /// 减弱动效（Reduce Motion）⇒ 与玻璃相关的过渡时长归零（阶跃，无淡入）。
  static bool get reduceMotion => _flag(
    'GLASS_A11Y_REDUCE_MOTION',
    debugReduceMotion,
    () => Pref.glassReduceMotion,
  );

  /// 增强对比（Increase Contrast）——**仅自建开关**这一半。
  static bool get increaseContrastSwitch => _flag(
    'GLASS_A11Y_CONTRAST',
    debugIncreaseContrastSwitch,
    () => Pref.glassIncreaseContrast,
  );

  /// 生效中的「增强对比」＝自建开关 **或** 系统高对比度主题（Windows 高对比度 ✓，
  /// Flutter 通过 `MediaQueryData.highContrast` 直接给）。
  ///
  /// 优先级就是「或」：任一方为真即生效；系统主题**不提供关闭入口**（那是 OS 级无障碍设置，
  /// 用户在我们的设置里关不掉它 ⇒ 这样写才不会出现"系统开着、我们却画成普通"的分歧）。
  static bool increaseContrast(BuildContext context) =>
      increaseContrastSwitch ||
      (MediaQuery.maybeOf(context)?.highContrast ?? false);

  /// 过渡时长：减弱动效 ⇒ `Duration.zero`（**阶跃**）；否则原样返回 `base`。
  ///
  /// 为什么不把 `kTierFadeDuration` 改成变量：那是 `static const`，改成变量会让播放器的
  /// 常量折叠失效，还要动它两处读取点的语义 ⇒ 这里只做"读取时映射"，调用方两处 `duration:`
  /// 都走本方法即可 ✓（task-93 允许的唯一 pl_player 落点）。
  static Duration motionDuration(Duration base) =>
      reduceMotion ? Duration.zero : base;

  /// 档位**封顶**：降低透明度 ⇒ `solid`；否则原样返回。
  ///
  /// 语义纪律：只能**降级**（`refraction → fakeGlass → solid` 链上往下走），绝不抬档 ⇒
  /// 调用点必须放在能力夹取**之后**（`LiquidGlassPolicy.effectiveTier` 里正是那个位置 ✓），
  /// 从而不可能绕过 kit 的能力三闸门 ✗。
  static LiquidGlassTier capTier(LiquidGlassTier tier) =>
      reduceTransparency ? LiquidGlassTier.solid : tier;

  /// 把 kit 需要的那个开关同步过去（启动时与设置变更时各调一次）。
  ///
  /// 为什么 kit 需要宿主同步：kit 包不能 import app 的 `Pref`（保持独立、可测试）；
  /// 而 kit 自己能读到的只有 `MediaQuery.highContrast`（系统主题那条 ✓）。
  static void syncRuntimeFlags() {
    LiquidGlassRuntime.increaseContrast = increaseContrastSwitch;
    // **全局档位封顶**（task-93 实测补的那一步 ✓）：app chrome（侧栏/顶栏/底导）走的是
    // kit 的**全局** `LiquidGlassRuntime.tier` ✓，而 `LiquidGlassPolicy.effectiveTier`
    // 只覆盖播放器/直播两条路径 ✗ ⇒ **两处都要封** ✓，否则侧栏不受"降低透明度"影响 ✗。
    // **只降不抬** ✓（见 kit 侧 `tierCap` 的注释）。
    // #19（task-94）：强度与无障碍开关走**同一个同步入口** ✓（单一收口，避免漏读 ✗）。
    GlassStrength.syncRuntimeFlags();
    LiquidGlassRuntime.tierCap = reduceTransparency
        ? LiquidGlassTier.solid
        : null;
  }

  /// 测试用：清空所有接缝与环保开关（避免用例之间串味）。
  static void debugReset() {
    debugReduceTransparency = null;
    debugReduceMotion = null;
    debugIncreaseContrastSwitch = null;
    environment = const <String, String>{};
    LiquidGlassRuntime.increaseContrast = false;
    LiquidGlassRuntime.tierCap = null;
  }
}
