// SPDX-License-Identifier: GPL-3.0-or-later
//
// 能力探测与三级降级矩阵（排期 #9）。
//
// 三级：真折射（#11 落地后可用）→ FakeGlass（BackdropFilter，Skia 兼容）→ 纯色半透明。
//
// 为什么需要"落盘"：探测结果与**运行期失败latch**都要跨启动记住，否则用户每次启动都会
// 再撞一次同样的崩溃。落盘用 dart:io 直接写文件（由宿主 App 传入目录），
// 从而本包保持"无插件"（见 pubspec 顶部说明）。
//
// 判定顺序（自上而下，第一个命中者生效）：
//   1. 宿主强制指定（设置里的"渲染档位"开关）——**强制也过最终守卫**（见 _guardRefraction）；
//   2. 上次 latch 的失败结论（例如真折射档崩过 → 永久降到 FakeGlass/纯色）；
//   3. 黑名单命中（平台 + 系统版本子串，用于已知雷区：虚拟显示/远程桌面、老核显驱动等）；
//   4. 平台与能力规则：Windows/Linux v1 固定 FakeGlass（实测真折射在 Windows 上不可用，
//      见 docs/Impeller实测结论.md）；移动/桌面 Apple 平台在 shader filter 可用且提供了
//      折射 shader 时走真折射，否则 FakeGlass；其它平台纯色。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// 渲染档位（由高到低）。
enum LiquidGlassTier {
  /// 真折射（需要 Impeller 的 ImageFilter.shader + 折射 shader；#11 落地后才真正可用）。
  refraction,

  /// FakeGlass：BackdropFilter(blur) + 饱和度矩阵 + Canvas 高光描边。Skia 与 Impeller 都可用。
  fakeGlass,

  /// 纯色半透明兜底：不采样背景，零风险。
  solid;

  /// 降一档（用于 latch 与黑名单）。
  LiquidGlassTier get downgraded => switch (this) {
        LiquidGlassTier.refraction => LiquidGlassTier.fakeGlass,
        LiquidGlassTier.fakeGlass => LiquidGlassTier.solid,
        LiquidGlassTier.solid => LiquidGlassTier.solid,
      };
}

/// 黑名单条目：命中即钉死到某个档位。
@immutable
class LiquidGlassBlacklistEntry {
  const LiquidGlassBlacklistEntry({
    required this.platform,
    required this.osVersionContains,
    required this.tier,
    required this.reason,
  });

  /// dart:io 的 Platform.operatingSystem 值，如 'windows' / 'android'。
  final String platform;

  /// 系统版本号里的子串（大小写不敏感）。'*' 表示该平台全命中。
  final String osVersionContains;

  /// 命中后钉死的档位。
  final LiquidGlassTier tier;

  /// 记录原因，便于日志与用户反馈。
  final String reason;

  bool matches(String platform, String osVersion) {
    if (this.platform.toLowerCase() != platform.toLowerCase()) return false;
    if (osVersionContains == '*') return true;
    return osVersion.toLowerCase().contains(osVersionContains.toLowerCase());
  }
}

/// 探测结果（含判定依据，便于排查与上报）。
@immutable
class LiquidGlassCapability {
  const LiquidGlassCapability({
    required this.tier,
    required this.platform,
    required this.osVersion,
    required this.shaderFilterSupported,
    required this.reason,
    this.matchedBlacklist,
    this.latched = false,
    this.forced = false,
  });

  final LiquidGlassTier tier;
  final String platform;
  final String osVersion;

  /// ImageFilter.isShaderFilterSupported 的结果（真折射的硬门禁，素材文档 §5.1）。
  final bool shaderFilterSupported;

  /// 人类可读的判定依据。
  final String reason;

  final LiquidGlassBlacklistEntry? matchedBlacklist;

  /// 是否来自上次的失败 latch。
  final bool latched;

  /// 是否由宿主强制指定。
  final bool forced;

  /// 是否允许真折射（shader filter + 折射 shader 都在）。
  bool get refractionUsable =>
      shaderFilterSupported && tier == LiquidGlassTier.refraction;

  Map<String, Object?> toJson() => <String, Object?>{
        'schema': 1,
        'tier': tier.name,
        'platform': platform,
        'osVersion': osVersion,
        'shaderFilterSupported': shaderFilterSupported,
        'reason': reason,
        'latched': latched,
        'forced': forced,
        'matchedBlacklist': matchedBlacklist?.reason,
      };

  @override
  String toString() => 'LiquidGlassCapability(${tier.name}, $reason)';
}

/// 探测结果的持久化接口。宿主 App 用真实目录实现；测试用内存实现。
abstract class LiquidGlassProbeStore {
  Future<Map<String, Object?>> read();
  Future<void> write(Map<String, Object?> data);

  /// 清掉 latch（例如用户在设置里手动"重试真折射"）。
  Future<void> clear();
}

/// 内存实现（测试与无持久化环境用）。
class LiquidGlassMemoryProbeStore implements LiquidGlassProbeStore {
  Map<String, Object?> _data = <String, Object?>{};

  @override
  Future<Map<String, Object?>> read() async => Map<String, Object?>.from(_data);

  @override
  Future<void> write(Map<String, Object?> data) async => _data = Map<String, Object?>.from(data);

  @override
  Future<void> clear() async => _data = <String, Object?>{};
}

/// 文件实现（dart:io，无插件）。宿主传 app support 目录下的路径即可。
class LiquidGlassFileProbeStore implements LiquidGlassProbeStore {
  LiquidGlassFileProbeStore(this.file);

  final File file;

  @override
  Future<Map<String, Object?>> read() async {
    try {
      if (!await file.exists()) return <String, Object?>{};
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, Object?>.from(decoded) : <String, Object?>{};
    } catch (error) {
      // 文件坏了不该影响启动：当作没有探测记录。
      debugPrint('[LiquidGlass] 读取探测记录失败（忽略）：$error');
      return <String, Object?>{};
    }
  }

  @override
  Future<void> write(Map<String, Object?> data) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    } catch (error) {
      debugPrint('[LiquidGlass] 写入探测记录失败（忽略）：$error');
    }
  }

  @override
  Future<void> clear() async {
    try {
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('[LiquidGlass] 清除探测记录失败（忽略）：$error');
    }
  }
}

/// 探测入口。
abstract final class LiquidGlassProbe {
  /// 已知雷区黑名单。命中即钉死档位。
  ///
  /// **默认留空是刻意的**：我们没有"某型号 GPU 有问题"的一手证据，不该凭空写条目
  /// （写了会误伤正常机器）。真正兜底的是两条：① 远程/虚拟显示会话规则（见下）；
  /// ② 运行期失败 latch —— 真出过问题的机器会被记住，比"猜"更可靠。
  /// 后续拿到确凿案例（例如某个驱动版本必崩）时，往这里加条目即可，格式见
  /// [LiquidGlassBlacklistEntry]。
  static const List<LiquidGlassBlacklistEntry> defaultBlacklist = <LiquidGlassBlacklistEntry>[];

  /// 是否为远程桌面/虚拟显示会话。
  ///
  /// 判定依据：Windows 的远程会话会把 `SESSIONNAME` 设成 `RDP-Tcp#N`；
  /// 这类会话下 BackdropFilter 的行为在历史上出过问题（见问题台账 §3），
  /// 因此一律降一档。纯 Dart 可读环境变量，不需要插件。
  static bool detectRemoteSession({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final session = env['SESSIONNAME'] ?? '';
    return session.toUpperCase().startsWith('RDP');
  }

  /// 执行探测。所有外部依赖都可注入，便于测试。
  static Future<LiquidGlassCapability> resolve({
    LiquidGlassProbeStore? store,
    LiquidGlassTier? forcedTier,
    List<LiquidGlassBlacklistEntry>? blacklist,
    String? platformOverride,
    String? osVersionOverride,
    bool? shaderFilterSupportedOverride,
    bool? remoteSessionOverride,
    bool refractionShaderAvailable = false,
  }) async {
    final platform = platformOverride ?? Platform.operatingSystem;
    final osVersion = osVersionOverride ?? Platform.operatingSystemVersion;
    final shaderSupported =
        shaderFilterSupportedOverride ?? ui.ImageFilter.isShaderFilterSupported;
    final entries = blacklist ?? defaultBlacklist;

    // 1) 宿主强制
    if (forcedTier != null) {
      final capability = LiquidGlassCapability(
        tier: forcedTier,
        platform: platform,
        osVersion: osVersion,
        shaderFilterSupported: shaderSupported,
        reason: '由宿主强制指定（设置项）',
        forced: true,
      );
      // 强制 ≠ 免检：shader filter 不支持时，强制 refraction 必须降为 fakeGlass。
      final guarded = _guardRefraction(capability);
      await _persist(store, guarded);
      return guarded;
    }

    // 2) 上次 latch
    if (store != null) {
      final cached = await store.read();
      final latchedTier = cached['latchedTier'];
      if (latchedTier is String) {
        LiquidGlassTier? tier;
        for (final candidate in LiquidGlassTier.values) {
          if (candidate.name == latchedTier) {
            tier = candidate;
            break;
          }
        }
        if (tier != null && tier != LiquidGlassTier.refraction) {
          return LiquidGlassCapability(
            tier: tier,
            platform: platform,
            osVersion: osVersion,
            shaderFilterSupported: shaderSupported,
            reason: '上次运行 latch：${cached['latchedReason'] ?? '未知原因'}',
            latched: true,
          );
        }
      }
    }

    // 3) 黑名单
    for (final entry in entries) {
      if (entry.matches(platform, osVersion)) {
        final capability = LiquidGlassCapability(
          tier: entry.tier,
          platform: platform,
          osVersion: osVersion,
          shaderFilterSupported: shaderSupported,
          reason: '黑名单命中：${entry.reason}',
          matchedBlacklist: entry,
        );
        final guarded = _guardRefraction(capability);
        await _persist(store, guarded);
        return guarded;
      }
    }

    // 4) 平台与能力规则
    final platformTier = switch (platform) {
      'windows' || 'linux' => LiquidGlassTier.fakeGlass,
      'android' || 'ios' || 'macos' => (shaderSupported && refractionShaderAvailable)
          ? LiquidGlassTier.refraction
          : LiquidGlassTier.fakeGlass,
      _ => LiquidGlassTier.solid,
    };
    var tier = platformTier;
    var reason = switch (platformTier) {
      LiquidGlassTier.refraction => 'shader filter 可用且已提供折射 shader',
      LiquidGlassTier.fakeGlass => platform == 'windows' || platform == 'linux'
          ? 'Windows/Linux v1 固定 FakeGlass（真折射在 Windows 上实测崩溃，见 docs/Impeller实测结论.md）'
          : (!shaderSupported
              ? 'shader filter 不可用 → FakeGlass'
              : 'shader filter 可用但未提供折射 shader → FakeGlass（#11 接线点未就位）'),
      LiquidGlassTier.solid => '未知平台，取最保守档位',
    };

    // 5) 远程/虚拟显示会话再降一档（这类会话下 BackdropFilter 行为在历史 issue 里出过问题）
    final remote = remoteSessionOverride ?? detectRemoteSession();
    if (remote && tier != LiquidGlassTier.solid) {
      reason = '$reason；远程/虚拟显示会话 → 再降一档';
      tier = tier.downgraded;
    }

    final capability = _guardRefraction(LiquidGlassCapability(
      tier: tier,
      platform: platform,
      osVersion: osVersion,
      shaderFilterSupported: shaderSupported,
      reason: reason,
    ));
    await _persist(store, capability);
    return capability;
  }

  /// 运行期失败 latch：真折射/玻璃渲染炸了之后调用它，把结论落盘，下次启动直接降档。
  static Future<LiquidGlassCapability> latchFailure({
    required String reason,
    LiquidGlassProbeStore? store,
    LiquidGlassTier failedTier = LiquidGlassTier.refraction,
    LiquidGlassTier? fallbackTier,
    String? platformOverride,
    String? osVersionOverride,
    bool? shaderFilterSupportedOverride,
  }) async {
    final platform = platformOverride ?? Platform.operatingSystem;
    final osVersion = osVersionOverride ?? Platform.operatingSystemVersion;
    final tier = fallbackTier ?? failedTier.downgraded;
    final data = <String, Object?>{
      'schema': 1,
      'latchedTier': tier.name,
      'latchedReason': reason,
      'latchedFrom': failedTier.name,
      'latchedAt': DateTime.now().toIso8601String(),
      'platform': platform,
      'osVersion': osVersion,
    };
    await store?.write(data);
    debugPrint('[LiquidGlass] latch 失败降档：$failedTier → $tier（$reason）');
    // 同一道不变量：这里若被传入 fallbackTier=refraction，也不能返回一个
    // "shader filter 不支持却声称 refraction" 的结果（调用方通常传 downgraded）。
    return _guardRefraction(LiquidGlassCapability(
      tier: tier,
      platform: platform,
      osVersion: osVersion,
      shaderFilterSupported:
          shaderFilterSupportedOverride ?? ui.ImageFilter.isShaderFilterSupported,
      reason: '运行期失败 latch：$reason',
      latched: true,
    ));
  }

  /// 选档阶段的**最终守卫**：`refraction` 是唯一带硬前置条件的档位——它需要 Impeller 的
  /// `ImageFilter.shader`（素材文档 §5.1）。任何通向 refraction 的路径都必须过这里。
  ///
  /// 为什么必须拦在**选档阶段**（而不是指望渲染器兜底）：
  ///   * 渲染侧 `Glassify`（poc/liquid_glass_renderer_local/lib/src/glassify.dart:58-67）在
  ///     `!isShaderFilterSupported` 时是 `assert(...) + return child` —— **debug 直接崩、
  ///     release 静默没有玻璃且没有任何日志**，两条路都不可接受；
  ///   * 而 `forcedTier` 分支原本是**立即返回**、不校验 `shaderFilterSupported` ⇒ 用户一开
  ///     "真折射档"，在 Skia 设备上就会拿到 `tier=refraction` 并撞上上面那条 assert。
  ///     守卫放在这里，"设置项能选什么"与"渲染器实际能跑什么"就不会分叉。
  ///   * 黑名单若被误配置成 `refraction` 也走同一道守卫（同一条不变量，只写一次）。
  ///
  /// 只守 shader filter、**不**守"折射 shader 是否已提供"：后者在渲染层有安全的自动回落
  /// （`LiquidGlassSurface` 未拿到 shader 时退 FakeGlass 并打日志），不会崩；
  /// [LiquidGlassCapability.refractionUsable] 是第二道保险（即便 tier 对了也不代表可用）。
  static LiquidGlassCapability _guardRefraction(LiquidGlassCapability capability) {
    if (capability.tier != LiquidGlassTier.refraction || capability.shaderFilterSupported) {
      return capability;
    }
    debugPrint('[LiquidGlass] refraction 档在本设备不可用（shader filter 不支持）→ 回落 fakeGlass');
    return LiquidGlassCapability(
      tier: LiquidGlassTier.fakeGlass,
      platform: capability.platform,
      osVersion: capability.osVersion,
      shaderFilterSupported: false,
      reason: '${capability.reason}；设备不支持 shader filter，已回落 → fakeGlass',
      matchedBlacklist: capability.matchedBlacklist,
      latched: capability.latched,
      forced: capability.forced,
    );
  }

  static Future<void> _persist(LiquidGlassProbeStore? store, LiquidGlassCapability capability) async {
    if (store == null) return;
    final existing = await store.read();
    // 保留 latch 字段（如果有）
    final merged = <String, Object?>{...existing, ...capability.toJson()};
    await store.write(merged);
  }
}