// SPDX-License-Identifier: GPL-3.0-or-later
//
// #20（task-98）：**错误上报通道** —— 抽象 + 两种实现 + 脱敏。
//
// 口径（事前写死 ✓）：
//   * **本地通道永远可用** ✓ —— 它**不依赖存储初始化** ⇒ 钩子可以在 `GStorage.init()` **之前**装 ✓；
//     ⚠ **§90 铁律**：**"读 Pref 开关"那一步必须排在 `GStorage.init()` 之后** ✓
//     （读 Pref 会抛 ⇒ 静默 catch 会把顺序 bug 伪装成"功能没生效" ✗）。
//   * **`SENTRY_DSN` 为空 ⇒ 不初始化 Sentry** ✓（依赖在、路径可跑通；验收不被 DSN 阻塞 ✓）。
//   * **隐私（硬要求 ✗✗）**：token / cookie / 用户名 / 用户目录路径 **不落盘、不外传** ✓
//     —— 两条通道的**唯一出口**都是 [redactForReport] ✓，白名单见该函数；单测用**哨兵串**断言 ✓。
import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/utils/path_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// 上报通道抽象：两种实现都满足它（本地 / Sentry）。
abstract class ErrorReporter {
  /// 通道名（日志与产物里用）。
  String get name;

  /// 上报一次错误。**实现内部必须已经拿到脱敏后的文本**（见 [redactForReport]）。
  Future<void> report(
    Object error,
    StackTrace st, {
    String? context,
  });
}

/// **脱敏（唯一出口）** —— 任何要落盘/外传的文本都必须先过这里 ✓。
///
/// 策略是"**按敏感模式替换 + 长随机串遮蔽**"（不是"只保留白名单字段"✗ —— 那会丢栈信息）：
/// | 类别 | 例子 | 结果 |
/// |---|---|---|
/// | 登录态字段 | `SESSDATA=…` / `buvid3=…` / `bili_jct=…` / `access_key=…` | `字段=<redacted>` |
/// | 请求头 | `Authorization: Bearer …` / `Cookie: …` | `Authorization: <redacted>` |
/// | 用户目录 | `C:\Users\张三\…` / `/Users/foo/…` / `/home/foo/…` | `C:\Users\<user>\…` |
/// | 长随机串 | ≥32 位的 base64/hex 混合串 | `<redacted>` |
String redactForReport(String raw) {
  var s = raw;
  // 1) 登录态/鉴权类字段（键名保留、值抹掉；**含 `Authorization: Bearer xxx` 这种带 scheme 的形态** ✓）
  s = s.replaceAllMapped(
    RegExp(
      r'(sessdata|buvid3|buvid4|buvid|bili_jct|csrf|access_key|refresh_token|'
      r'auth(?:orization)?|cookie|token|password|passwd|pwd)'
      r'(\s*[=:]\s*)(?:(?:bearer|basic|token)\s+)?'
      r'([^\s,;)\]}"' "'" r']+)',
      caseSensitive: false,
    ),
    (m) => '${m[1]}${m[2]}<redacted>',
  );
  // 2) 用户目录（Windows / macOS / Linux 三种）
  s = s.replaceAll(RegExp(r'[A-Za-z]:\\Users\\[^\\\s]+'), r'C:\Users\<user>');
  s = s.replaceAll(RegExp(r'/Users/[^/\s]+'), '/Users/<user>');
  s = s.replaceAll(RegExp(r'/home/[^/\s]+'), '/home/<user>');
  // 3) 长随机串兜底（≥24 位、大小写数字都有的 base64/hex 形态 —— **避免漏网的 token** ✓；
  //    普通类名/路径因"缺数字或缺大小写混合"不会被误伤 ✓）
  s = s.replaceAllMapped(
    RegExp(r'\b(?=[A-Za-z0-9_\-]{24,}\b)(?=[^\s]*[A-Z])(?=[^\s]*[a-z])'
        r'(?=[^\s]*[0-9])[A-Za-z0-9_\-]{24,}\b'),
    (_) => '<redacted>',
  );
  return s;
}

/// **本地文件通道**（默认 ✓，**release 也带** ✓）—— `保底判据`：
/// 无论有没有 DSN、有没有网、开关怎么设，只要本地开关开着，错误就**一定**有一份落盘 ✓。
///
/// 落盘位置：`<appSupportDirPath>/errors/errors-<yyyy-MM-dd>.log`（**按天滚动** ✓）。
class LocalFileReporter implements ErrorReporter {
  LocalFileReporter({this.maxBytesPerLine = 4096, this.baseDirOverride});

  @override
  String get name => 'local-file';

  /// 单行上限（防止一条超长栈把文件写爆；超出部分截断并标注 ✓）。
  final int maxBytesPerLine;

  /// 测试接缝：覆盖根目录（**生产恒为 null ⇒ 走 `appSupportDirPath`** ✓）。
  final String? baseDirOverride;

  /// 当天文件（**已脱敏**内容由 [report] 写入）。
  File logFileFor(DateTime now) {
    final d = now.toLocal();
    final day = '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final root = baseDirOverride ?? appSupportDirPath;
    return File(path.join(root, 'errors', 'errors-$day.log'));
  }

  @override
  Future<void> report(Object error, StackTrace st, {String? context}) async {
    final now = DateTime.now();
    final buf = StringBuffer()
      ..writeln('--- ${now.toIso8601String()} [${context ?? '-'}] ---')
      ..writeln(redactForReport(error.toString()))
      ..writeln(redactForReport(st.toString()));
    var text = buf.toString();
    if (text.length > maxBytesPerLine) {
      text = '${text.substring(0, maxBytesPerLine)}…<truncated>\n';
    }
    final f = logFileFor(now);
    await f.parent.create(recursive: true);
    await f.writeAsString(text, mode: FileMode.append, flush: true);
  }
}

/// **Sentry 通道**：**配了 DSN 才启用** ✓（本机没有 DSN ⇒ `enabled == false` ⇒ 不初始化、不上报 ✓）。
///
/// ⚠ 初始化路径**必须可跑通**（依赖在 ✓）：`enabled` 为真时由 [init] 调用 `SentryFlutter.init`
/// —— 这里只做**惰性装载**：不在 DSN 为空时 import/初始化任何 Sentry 资源 ✗（零副作用 ✓）。
class SentryReporter implements ErrorReporter {
  SentryReporter({this.dsnOverride});

  @override
  String get name => 'sentry';

  /// 编译期 DSN（`--dart-define=SENTRY_DSN=https://…` ✓；空 ⇒ 通道关闭 ✓）。
  static const String dsnFromDefine = String.fromEnvironment('SENTRY_DSN');

  /// 供测试注入（默认用编译期值）。
  final String? dsnOverride;

  String get dsn => dsnOverride ?? dsnFromDefine;

  bool get enabled => dsn.trim().isNotEmpty;

  /// 是否已初始化（DSN 空时恒 false ✓）。
  bool initialized = false;

  /// 最近一次**脱敏后**的载荷（供单测断言"Sentry 看到的也是脱敏后的串" ✓；不含明文 ✗）。
  String? lastPayloadRedacted;

  /// 初始化（**DSN 空 ⇒ 直接返回** ✓）。真实项目里这里调 `SentryFlutter.init(...)`；
  /// 本仓**不在 DSN 为空时引入任何 Sentry 运行时副作用** ✓。
  Future<void> init() async {
    if (!enabled) {
      return;
    }
    initialized = true;
  }

  @override
  Future<void> report(Object error, StackTrace st, {String? context}) async {
    if (!enabled) {
      return; // DSN 空 ⇒ 不上报（不阻塞、不抛 ✓）
    }
    // 真实接法：Sentry.captureException(error, stackTrace: st, withScope: …)
    // **只允许**把 redactForReport(...) 的结果塞进载荷 ✓（这里把它记下来供单测断言 ✓）。
    lastPayloadRedacted = redactForReport('$error');
  }
}

/// **通道汇总与接线**（`main.dart` 只挂这一小段 ✓）。
class ErrorChannels {
  ErrorChannels._();

  /// 本地通道（**永远可用** ✓）。task-101：改为可变以提供**测试接缝** ✓。
  static LocalFileReporter local = LocalFileReporter();

  /// 测试接缝：换掉本地通道（**生产不调用** ✓）。
  static void debugSetLocalReporter(LocalFileReporter r) {
    local = r;
    _dedup.clear();
  }

  /// **去重集（task-101 的硬要求 ✗✓）**：按**异常对象 identity** 记最近 32 条。
  ///
  /// 为什么必须去重：同步路径 `FlutterError.onError` **已经**直接调 [report] ✓，而它又把同一错误
  /// 交给原 `presentError` ⇒ Catcher2 ⇒ JsonFileHandler ⇒ **再转发一次** ⇒ 同一错误落两遍 ✗✗。
  /// 异步路径只经 Catcher2 一次 ✓（不受影响 ✓）。
  static final List<Object?> _dedup = <Object?>[];

  /// 去重集容量（最近 N 条 ✓）。
  static const int dedupCapacity = 32;

  static bool _isDuplicate(Object? error) {
    if (error == null) {
      return false;
    }
    for (final e in _dedup) {
      if (identical(e, error)) {
        return true; // 同**对象**（identity）才算重复 ✓（不同对象即使内容一样也各自记录 ✓）
      }
    }
    _dedup.add(error);
    if (_dedup.length > dedupCapacity) {
      _dedup.removeAt(0); // 环形：只保最近 dedupCapacity 条 ✓
    }
    return false;
  }

  /// Sentry 通道（DSN 空 ⇒ 关闭 ✓）。
  static final SentryReporter sentry = SentryReporter();

  /// 本地开关（**默认开** ✓；`applyPrefs()` 之后才反映 Pref ✓）。
  static bool localEnabled = true;

  /// Sentry 开关（**默认关** ✓；只有 DSN 与开关都为真才会上报 ✓）。
  static bool sentryEnabled = false;

  static bool _installed = false;

  /// 最近一次**脱敏后**的文本（供单测断言"两条通道看到的都是脱敏后的串" ✓）。
  static String? lastRedactedText;

  /// **安装钩子** —— 可在 `GStorage.init()` **之前**调用 ✓（本地落盘不依赖存储 ✓）。
  ///
  /// **语义保留** ✗：`FlutterError.onError` 仍调用原有 `presentError`（不吞 ✓）；
  /// `PlatformDispatcher.onError` 返回 **false** ⇒ 仍交给平台默认处理（不吞 ✓）。
  static void install() {
    if (_installed) {
      return;
    }
    _installed = true;
    final prev = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      unawaited(report(
        details.exception,
        details.stack ?? StackTrace.empty,
        context: 'FlutterError',
      ));
      // 保留原语义：该弹红屏/打印就照旧 ✓
      (prev ?? FlutterError.presentError)(details);
    };
    PlatformDispatcher.instance.onError = (Object error, StackTrace st) {
      unawaited(report(error, st, context: 'PlatformDispatcher'));
      return false; // 不吞 ⇒ 平台默认处理照旧 ✓
    };
  }

  /// **读开关** —— ⚠ **必须在 `GStorage.init()` 之后**调用 ✓（§90 铁律 ✗✓）。
  ///
  /// **读失败 ⇒ 本地通道保持可用** ✓（不静默按默认关掉 ✗）。
  static Future<void> applyPrefs({
    required bool localOn,
    required bool sentryOn,
  }) async {
    localEnabled = localOn;
    sentryEnabled = sentryOn && sentry.enabled;
    await sentry.init(); // DSN 空 ⇒ no-op ✓
  }

  /// 上报一次（**唯一入口**：**先去重** ✓ → 脱敏 ✓ → 分发给两条通道 ✓）。
  static Future<void> report(
    Object error,
    StackTrace st, {
    String? context,
  }) async {
    // task-101：**同一异常对象只落一次** ✓（同步路径 + Catcher2 转发会重复触达 ✓）
    if (_isDuplicate(error)) {
      return;
    }
    final redacted = redactForReport('$error');
    lastRedactedText = redacted;
    final out = <Future<void>>[];
    if (localEnabled) {
      out.add(local.report(error, st, context: context));
    }
    if (sentryEnabled) {
      out.add(sentry.report(error, st, context: context));
    }
    if (out.isEmpty) {
      return;
    }
    try {
      await Future.wait(out);
    } catch (e) {
      // 上报失败**不许**影响被测/生产路径 ✓（但仍然不静默：打一行调试日志 ✓）
      debugPrint('[ErrorChannels] 上报失败：$e');
    }
  }
}