// SPDX-License-Identifier: GPL-3.0-or-later
//
// 账号凭据落盘加密（排期文档阶段一 #5）。
//
// 背景：PiliPlus 上游把 cookie / accessKey / refresh_token 以**明文**存在 Hive 的 `account` box 里
// （接口清单 §2.5 的缺口）。本文件的做法是**不替换存储层**，只把该 box 换成 Hive 的 AES 加密 box，
// 密钥托管给平台安全存储：
//
//   Windows → DPAPI（flutter_secure_storage）  Android → Keystore   iOS/macOS → Keychain
//
// 这样 `Accounts`（accounts.dart）与 `LoginAccount`（account.dart）的既有读写路径**一行都不用改**，
// 对上游 rebase 的侵入面=1 个函数（`Accounts.init()`），也不存在"两套存储状态不一致"的风险。
//
// 迁移策略（首次启动自动完成，不需要用户操作）：
//   1. 没有 marker → 视为未加密状态：
//        a. box 文件不存在（全新安装）→ 直接生成密钥并以加密方式创建；
//        b. box 文件存在（老用户）→ 明文打开读取全部账号 → 从磁盘删除该 box → 用加密方式重建并回写；
//   2. 有 marker 但没有密钥 → **直接报错**，绝不静默按明文打开（那会让用户以为"账号丢了"，
//      也会把密文当明文解析出垃圾数据）。
//
// 失败降级：取不到平台安全存储时（例如 Linux 缺 libsecret）回退为不加密，并留下警告——
// 宁可功能可用，也不让用户卡在登录页。
import 'dart:convert';
import 'dart:math';

import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce/hive.dart';

/// 安全存储抽象：便于单测注入假实现（平台通道在单元测试里不可用）。
abstract interface class SecureKeyStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// 生产实现：落在平台安全存储里（Windows=DPAPI / Android=Keystore / iOS=Keychain）。
class PlatformSecureKeyStore implements SecureKeyStore {
  const PlatformSecureKeyStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    // v11 起 Android 侧默认即 EncryptedSharedPreferences（Keystore 托管密钥）
    aOptions: AndroidOptions.defaultOptions,
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

abstract final class SecureAccountBox {
  /// 与上游保持一致的 box 名（迁移必须用同一个名字）
  static const String boxName = 'account';

  /// 加密密钥（base64 的 32 字节）在安全存储中的键名
  static const String keyName = 'liquidglass.account.hiveKey';

  /// 迁移完成标记；存在即表示该 box 已是加密 box
  static const String markerName = 'liquidglass.account.encrypted';

  /// 可注入（测试用）
  static SecureKeyStore keyStore = const PlatformSecureKeyStore();

  /// 打开账号 box：优先加密，必要时自动迁移，取不到安全存储则降级为明文并告警。
  static Future<Box<LoginAccount>> open({String name = boxName}) async {
    final String? marker = await _tryRead(markerName);
    final String? storedKey = await _tryRead(keyName);

    if (marker == '1' && storedKey != null) {
      return Hive.openBox<LoginAccount>(
        name,
        encryptionCipher: HiveAesCipher(base64Decode(storedKey)),
      );
    }
    if (marker == '1' && storedKey == null) {
      // 加密过、密钥却没了：不能假装无事发生
      throw StateError(
        '账号数据是加密的，但安全存储里找不到密钥（$keyName）。'
        '请勿删除系统凭据后继续使用——否则只能重新登录。',
      );
    }

    final bool exists = await Hive.boxExists(name);
    if (!exists) {
      // 全新安装：能拿密钥就加密，拿不到就明文降级（并告警）
      final String? keyB64 = await _createKey();
      if (keyB64 == null) {
        _warnDegraded();
        return Hive.openBox<LoginAccount>(name);
      }
      return _openEncrypted(name, keyB64);
    }

    // 老用户：明文 box → 加密 box
    return _migrate(name);
  }

  static Future<Box<LoginAccount>> _openEncrypted(String name, String keyB64) async {
    final box = await Hive.openBox<LoginAccount>(
      name,
      encryptionCipher: HiveAesCipher(base64Decode(keyB64)),
    );
    await _tryWrite(markerName, '1');
    return box;
  }

  static Future<Box<LoginAccount>> _migrate(String name) async {
    debugPrint('[SecureAccountBox] 检测到未加密的账号 box，开始迁移…');
    final plain = await Hive.openBox<dynamic>(name);
    final snapshot = <String, Map<String, dynamic>>{};
    for (final key in plain.keys) {
      final value = plain.get(key);
      final json = switch (value) {
        final LoginAccount a => a.toJson(),
        final Map m => m.cast<String, dynamic>(),
        _ => null,
      };
      if (json != null) snapshot['$key'] = json;
    }
    await plain.close();
    await Hive.deleteBoxFromDisk(name);

    final String? keyB64 = await _createKey();          // null = 取不到安全存储
    if (keyB64 == null) {
      // 降级：仍然是明文 box（但账号不能丢）
      final box = await Hive.openBox<LoginAccount>(name);
      for (final e in snapshot.entries) {
        await box.put(e.key, LoginAccount.fromJson(e.value));
      }
      _warnDegraded();
      return box;
    }

    final box = await _openEncrypted(name, keyB64);
    for (final e in snapshot.entries) {
      await box.put(e.key, LoginAccount.fromJson(e.value));
    }
    debugPrint('[SecureAccountBox] 迁移完成：${snapshot.length} 个账号已加密落盘');
    return box;
  }

  /// 生成并托管密钥；取不到安全存储时返回 null（调用方决定降级还是报错）
  static Future<String?> _createKey() async {
    try {
      final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
      final b64 = base64Encode(bytes);
      await keyStore.write(keyName, b64);
      return b64;
    } catch (e) {
      debugPrint('[SecureAccountBox] 安全存储不可用：$e');
      return null;
    }
  }

  static Future<String?> _tryRead(String key) async {
    try {
      return await keyStore.read(key);
    } catch (e) {
      debugPrint('[SecureAccountBox] 读取安全存储失败（$key）：$e');
      return null;
    }
  }

  static Future<void> _tryWrite(String key, String value) async {
    try {
      await keyStore.write(key, value);
    } catch (e) {
      debugPrint('[SecureAccountBox] 写入安全存储失败（$key）：$e');
    }
  }

  static void _warnDegraded() {
    debugPrint(
      '[SecureAccountBox] ⚠️ 未能取得平台安全存储，账号将以明文保存。'
      '${kDebugMode ? '（调试构建：检查 flutter_secure_storage 平台实现）' : ''}',
    );
  }
}