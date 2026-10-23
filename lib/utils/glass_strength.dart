// SPDX-License-Identifier: GPL-3.0-or-later
//
// #19（task-94）：**玻璃强度滑杆**（0–100%）的解析与持久化。
//
// 与 #18 的关系（刻意分开文件，语义不同 ✗）：
//   * 「降低透明度」= 真的**降档**（封顶到 solid，见 `glass_accessibility.dart` + `cappedTier`）；
//   * 「玻璃强度」= **只缩放同一档位内部的旋钮**（不改档 ✗），0% = 最弱但仍在原档位 ✓。
//   ⇒ 两者可以同时开：降透明封顶 solid 后，强度滑杆**仍然作用于 solid 档** ✓（不打架 ✓）。
//
// 取值优先级与 #18 一致（同一套规矩，便于取证与排错）：
//   **环境变量 > 文件通道 > 测试接缝 > 设置项(Pref) > 出厂默认(100)**。
//   * 文件通道 **`/data/local/tmp/glass_strength.txt`**（内容 = 0..100 整数）**只用于 adb 取证** ✓：
//     与 policy 的同款通道（`liquid_glass_policy.dart:117-126` ✓）——**这不是产品功能** ✗，
//     **`!kReleaseMode` 门控** ✓，**读不到/非法一律静默回落** ✓（绝不许炸启动，§90 教训）。
//   `GLASS_STRENGTH=0|25|50|75|100` 只用于在同一份产物上跑对照图（只认 0..100 的整数，
//   非法值一律忽略 ⇒ 退回下一优先级 ✓）。
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart' show kReleaseMode, visibleForTesting;

import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';

abstract final class GlassStrength {
  /// 环境变量来源（可替换 ⇒ 单测不依赖真实进程环境）。
  static Map<String, String> environment = Platform.environment;

  /// 测试接缝（**生产恒为 null** ⇒ 走真实 Pref）。
  static int? debugStrengthPercent;

  static const int minPercent = 0;
  static const int maxPercent = 100;
  static const int defaultPercent = 100;

  /// 取证通道的文件路径（**非产品功能** ✗，`!kReleaseMode` 才读 ✓）。
  static const String evidenceFilePath = '/data/local/tmp/glass_strength.txt';

  /// 测试接缝：文件**原文**（生产恒为 null ⇒ 读真实文件 ✓；`''` 等价于"没有文件" ✓）。
  static String? debugFileRaw;

  /// 纯函数（可单测）：解析文件原文 ⇒ 百分比；非法/空/release 一律 `-1`（= 未提供 ✓）。
  @visibleForTesting
  static int parseFilePercent(String? raw, {required bool isRelease}) {
    if (isRelease) return -1; // release 恒不启用 ✓
    if (raw == null) return -1;
    final v = int.tryParse(raw.trim());
    if (v == null || v < minPercent || v > maxPercent) return -1;
    return v;
  }

  static int _fromFile() {
    try {
      final raw =
          debugFileRaw ??
          (kReleaseMode || !File(evidenceFilePath).existsSync()
              ? null
              : File(evidenceFilePath).readAsStringSync());
      return parseFilePercent(raw, isRelease: kReleaseMode);
    } catch (_) {
      // 读失败/权限/路径异常 ⇒ 静默回落（**不许炸启动** ✗）
      return -1;
    }
  }

  static int _fromEnv() {
    final raw = environment['GLASS_STRENGTH'];
    if (raw == null) return -1;
    final v = int.tryParse(raw.trim());
    if (v == null || v < minPercent || v > maxPercent) return -1;
    return v;
  }

  static int _fromPref() {
    try {
      return Pref.glassStrengthPercent;
    } catch (_) {
      // 存储未就绪 ⇒ 按出厂默认（100）。不抛：本解析在每帧路径上（surface）。
      return defaultPercent;
    }
  }

  /// 当前强度百分比（0–100，默认 100 = 出厂行为不变 ✓）。
  static int get percent {
    final env = _fromEnv();
    if (env >= 0) return env;
    // 文件通道（adb 取证 ✓）排在接缝与 Pref 之上：env 给 CI、文件给 adb、Pref 给用户 ✓
    final fromFile = _fromFile();
    if (fromFile >= 0) return fromFile;
    final seam = debugStrengthPercent;
    if (seam != null) return seam.clamp(minPercent, maxPercent);
    final pref = _fromPref();
    return pref.clamp(minPercent, maxPercent);
  }

  /// 交给 kit 的标量（0.0–1.0）。**1.0 ⇒ `forStrength` 直接返回原 token ⇒ 渲染不变** ✓。
  static double get strength => percent / 100.0;

  /// 把强度同步给 kit（与 #18 的 `syncRuntimeFlags()` 同一处调用 ✓ 单一收口）。
  static void syncRuntimeFlags() {
    LiquidGlassRuntime.strength = strength;
  }

  /// 滑杆值 → 各旋钮实际取值（五点对照表的**唯一来源** ✓：面板与单测都调它，
  /// 不会出现"文档写一套、界面显示另一套" ✗）。
  ///
  /// 返回 `[百分比, blur, tintOpacity, highlightOpacity, borderWidth, thickness,
  /// refractiveIndex, chromaticAberration]`，基于给定 token 计算 ✓。
  static List<double> sampleAt(LiquidGlassTokens base, int pct) {
    final t = base.forStrength(pct / 100.0);
    return <double>[
      pct.toDouble(),
      t.blur,
      t.tintOpacity,
      t.highlightOpacity,
      t.borderWidth,
      t.thickness,
      t.refractiveIndex,
      t.chromaticAberration,
    ];
  }

  /// 面板用：五点（0/25/50/75/100）对照表 ✓。
  static List<List<double>> fivePointTable(LiquidGlassTokens base) =>
      <int>[0, 25, 50, 75, 100].map((p) => sampleAt(base, p)).toList();

  /// 测试用：清空接缝与环保开关（避免用例之间串味）。
  static void debugReset() {
    debugStrengthPercent = null;
    debugFileRaw = null;
    environment = const <String, String>{};
    LiquidGlassRuntime.strength = 1.0;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// #20（task-98）**`thickness ≤ h/2` 已知洞的「地图」** —— **已接线 + 已夹取**（task-104 ✓）
//
// **洞是什么**：折射层的 `thickness` 若大于所在卡片高度的一半，SDF 归一
//   `n_cos = max(thickness + sd, 0) / thickness` 会让**整条都落在斜面上**（没有平坦光学中心）；
//   后果「**翻折 / 自交**」—— ⚠ **数学推测**（按截面 1/4 圆弧推的 ✓），**未逐帧验证** ✗。
//
// **该夹在哪（唯一同时持有「形状」与「光学参数」的那层 ✓）**：
//   `kit/lib/src/refraction/liquid_glass_refraction_layer.dart` 的**几何烘焙消费点** ✓
//   （`thickness:` 一行）—— 实现在**同文件的顶层纯函数**
//   `clampRefractionThickness(thickness, shapeHeight)` ✓（**单一收口** ✓，由 barrel 直接导出 ✓）。
//   pl_player 的 R1 传参处也调它 ⇒ 调用方与层内**同一条规则** ✓。
//
// **帧的选择（task-104 读码纠正 ✗✓ —— 初版地图在这里写错了半步）**：用**逻辑帧**
//   `widget.shape.size.height / 2` ✓；**不是** `cardPhysical.height / 2` ✗✗ ——
//   `cardPhysical = shape.size × devicePixelRatio`（`layer.dart:157-160` ✓，本机 dpr=3）
//   ⇒ 物理帧夹取**松 3 倍**、**守不住**它要守的不变量 ✗。
//   判据：`params.thickness` 与调用方 R1 的既有夹取（`view.dart:2603-2607`，
//   `math.min(tokens.thickness, h/2)`，`h` = 控制条**逻辑**高 ≈42）**同帧** ✓。
//   （历史：初版地图写 `cardPhysical.height/2` ✗ → dark-tokens 在 task-104 纠正 → Lead 亲验 ✓。）
//
// **不该夹在哪（三条都踩过 ✗✓）**：
//   * `geometry_pass.dart:74/85`、`filter_pass.dart:79/92` ✗ —— 只有 thickness 参数、**不知道 h**；
//   * `forStrength` token 层 ✗ —— token **不知道形状尺寸**；
//   * `surface.dart:471` 的 `(thickness / 20).clamp(0.6, 3.0)` ✗ —— 那是**笔画宽度**、量纲不同。
//
// **顺带的悬案（不动，仅留档 ✗）**：`layer.dart:152-156` 早已实证「两趟单位口径不同：
//   **几何烘焙＝物理、合成＝逻辑**」✓；若 shader 侧 `sd` 走物理帧而 `thickness` 走逻辑帧，
//   则实际 `thickness/sd` **比调用方以为的小 dpr 倍** —— 属该悬案的延伸（**推测 ✗**，
//   留「几何纹理导出判据」那轮查 ✓）。**本轮不动单位口径** ✗（动了就破「100% 逐字节等价」✓）。
