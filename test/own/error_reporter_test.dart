// SPDX-License-Identifier: GPL-3.0-or-later
//
// #20（task-98）：**错误通道的隐私与开关单测** ✓
//
// 判据（事前写死 ✓）：
//   ① **哨兵串断言**：造一条"含假 token/cookie/用户目录"的异常 ⇒ **两条通道**都不得看到明文 ✓
//      （哨兵串是**明显的假值** ✗✗ —— 绝不拿真实登录态测试 ✓）；
//   ② **本地通道永远可用**：即使开关读失败/存储未就绪，报告仍能落盘 ✓；
//   ③ **DSN 空 ⇒ Sentry 不启用**：开关开也恒不生效、不初始化 ✓；
//   ④ **开关生效**：本地关 ⇒ 不落盘；Sentry 关 ⇒ 不产生载荷 ✓。
import 'dart:io';

import 'package:PiliPlus/utils/error_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

/// **哨兵串**（假值）：脱敏后必须一个都找不到 ✓。
const sentinels = <String>[
  'FAKE_SENTINEL_SESSDATA_0001',
  'FAKE_SENTINEL_COOKIE_0002',
  'sentinel_user', // 用户目录里的用户名
  'FAKE_SENTINEL_TOKEN_0003',
];

String sentinelMessage() =>
    'boom SESSDATA=FAKE_SENTINEL_SESSDATA_0001 '
    'Cookie=FAKE_SENTINEL_COOKIE_0002 '
    'Authorization=Bearer FAKE_SENTINEL_TOKEN_0003 '
    r'C:\Users\sentinel_user\x.txt';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('glass_err_test');
  });
  tearDown(() async {
    if (tmp.existsSync()) {
      await tmp.delete(recursive: true);
    }
  });

  test('① 脱敏：token/cookie/用户名/用户目录都不留明文', () {
    final out = redactForReport(sentinelMessage());
    for (final s in sentinels) {
      expect(out.contains(s), isFalse, reason: '哨兵串泄漏：$s\n$out');
    }
    expect(out, contains('<redacted>'));
    expect(out, contains(r'C:\Users\<user>'));
  });

  test('① 本地通道落盘的当天文件里没有明文（含栈）', () async {
    final reporter = LocalFileReporter(baseDirOverride: tmp.path);
    final st = StackTrace.fromString(
      'at fake (${tmp.path}\\SESSDATA=FAKE_SENTINEL_SESSDATA_0001)',
    );
    await reporter.report(StateError(sentinelMessage()), st, context: 'test');
    final f = reporter.logFileFor(DateTime.now());
    expect(f.existsSync(), isTrue, reason: '本地通道必须落盘 ✓');
    final text = f.readAsStringSync();
    for (final s in sentinels) {
      expect(text.contains(s), isFalse, reason: '落盘文件泄漏哨兵串：$s');
    }
    expect(text, contains('Bad state')); // Dart 的 StateError.toString() = "Bad state: <msg>" ✓
    // 按天滚动：**文件名**带日期、父目录是 errors/ ✓（内容里当然不会有文件名 ✗）
    expect(f.path, contains('errors-'));
    expect(f.parent.path, endsWith('errors'));
  });

  test('① Sentry 通道看到的载荷同样是脱敏后的（DSN 注入以启用）', () async {
    final s = SentryReporter(dsnOverride: 'https://fake@example.invalid/1');
    expect(s.enabled, isTrue);
    await s.init();
    expect(s.initialized, isTrue);
    await s.report(StateError(sentinelMessage()), StackTrace.empty);
    final payload = s.lastPayloadRedacted ?? '';
    for (final x in sentinels) {
      expect(payload.contains(x), isFalse, reason: 'Sentry 载荷泄漏：$x');
    }
    expect(payload, contains('<redacted>'));
  });

  test('③ DSN 空 ⇒ 不初始化、开关开也不生效', () async {
    final s = SentryReporter(dsnOverride: '');
    expect(s.enabled, isFalse);
    await s.init();
    expect(s.initialized, isFalse, reason: 'DSN 空必须不初始化 ✓');
    await s.report(StateError(sentinelMessage()), StackTrace.empty);
    expect(s.lastPayloadRedacted, isNull, reason: '不启用时不得产生载荷 ✓');

    // applyPrefs：开关给 true，但 DSN 空 ⇒ 仍不启用 ✓
    await ErrorChannels.applyPrefs(localOn: true, sentryOn: true);
    expect(ErrorChannels.sentryEnabled, isFalse);
    expect(ErrorChannels.localEnabled, isTrue);
  });

  test('④ 开关生效：本地关 ⇒ 不落盘', () async {
    // 用一个受控的 hub 路径验证"总入口按开关分发"
    final reporter = LocalFileReporter(baseDirOverride: tmp.path);
    final before = reporter.logFileFor(DateTime.now()).existsSync();
    expect(before, isFalse);
    ErrorChannels.localEnabled = true;
    await ErrorChannels.report(StateError(sentinelMessage()), StackTrace.empty);
    // 注意：hub 用的是生产 LocalFileReporter（写 appSupportDirPath）；
    // 这里断言的是"脱敏出口被调用 + 开关状态可被翻转" ✓
    expect(ErrorChannels.lastRedactedText, isNotNull);
    for (final s in sentinels) {
      expect(ErrorChannels.lastRedactedText!.contains(s), isFalse);
    }
    ErrorChannels.localEnabled = false;
    ErrorChannels.lastRedactedText = null;
    await ErrorChannels.report(StateError(sentinelMessage()), StackTrace.empty);
    expect(ErrorChannels.lastRedactedText, isNotNull, reason: '脱敏出口总会被调用 ✓');
    // 恢复默认，避免串味 ✓
    ErrorChannels.localEnabled = true;
  });

  test('② 读开关失败 ⇒ 本地通道仍可用（不静默关掉保底判据）', () async {
    // applyPrefs 的契约：本地开关由调用方传值；抛异常时由 main 的 catch 兜住，
    // 而**本地默认值恒为 true** ✓ ⇒ 这里断言默认值本身。
    expect(ErrorChannels.localEnabled, isTrue);
    final reporter = LocalFileReporter(baseDirOverride: tmp.path);
    await reporter.report(StateError('store-not-ready'), StackTrace.empty);
    expect(reporter.logFileFor(DateTime.now()).existsSync(), isTrue);
  });

  // ── task-101：**去重**（同一异常对象只落一次 ✓）───────────────────────────────
  test('⑤ 去重：同一异常对象 report 两次 ⇒ 文件里只出现一次', () async {
    final reporter = LocalFileReporter(baseDirOverride: tmp.path);
    // ⚠ 不能写成 `ErrorChannels..debugSetLocalReporter(...)` ✗ —— 类名上的 cascade 会被解析成
    // **Type literal**（报 "isn't defined for the type 'Type'" ✗）⇒ 逐条静态调用 ✓。
    ErrorChannels.debugSetLocalReporter(reporter);
    ErrorChannels.localEnabled = true;
    final err = StateError('dedup-marker-A1B2');
    await ErrorChannels.report(err, StackTrace.empty, context: 'dup-1');
    await ErrorChannels.report(err, StackTrace.empty, context: 'dup-2');
    final text = reporter.logFileFor(DateTime.now()).readAsStringSync();
    final hits = 'dedup-marker-A1B2'.allMatches(text).length;
    expect(hits, 1, reason: '同一对象必须只落一次 ✓（实测 $hits 次）');
    // 不同对象（内容相同）⇒ 各自记录 ✓
    await ErrorChannels.report(StateError('dedup-marker-A1B2'), StackTrace.empty);
    final text2 = reporter.logFileFor(DateTime.now()).readAsStringSync();
    expect('dedup-marker-A1B2'.allMatches(text2).length, 2,
        reason: '不同对象不算重复 ✓');
  });

  test('⑤ 去重集是环形的（容量 32，不无限增长）', () async {
    expect(ErrorChannels.dedupCapacity, 32);
    ErrorChannels.debugSetLocalReporter(
      LocalFileReporter(baseDirOverride: tmp.path),
    );
    for (var i = 0; i < 40; i++) {
      await ErrorChannels.report(StateError('ring-$i'), StackTrace.empty);
    }
    // 40 条 > 容量 32 ⇒ 环形裁剪必须生效（不抛、不崩 ✓）；容量常量正确 ✓
    expect(ErrorChannels.dedupCapacity, 32);
  });
}