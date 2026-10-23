// SPDX-License-Identifier: GPL-3.0-or-later
//
// #5 凭据加密的验收测试（不需要登录、不需要平台通道）：
//   * 全新安装 → 账号 box 以 AES 加密创建，密钥托管在"安全存储"里；
//   * 老用户明文 box → 自动迁移，账号不丢，且**磁盘上再也搜不到明文 cookie**；
//   * 有加密标记但密钥丢失 → 明确报错，绝不静默按明文打开。
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/accounts/account_adapter.dart';
import 'package:PiliPlus/utils/accounts/account_type_adapter.dart';
import 'package:PiliPlus/utils/accounts/cookie_jar_adapter.dart';
import 'package:PiliPlus/utils/accounts/secure_box.dart';
import 'package:PiliPlus/utils/set_int_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// 内存版安全存储（单元测试里没有平台通道）
class FakeKeyStore implements SecureKeyStore {
  FakeKeyStore({this.failOnWrite = false});

  final bool failOnWrite;
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    if (failOnWrite) throw StateError('模拟：平台安全存储不可用');
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async => data.remove(key);
}

const String secret = 'PLAINTEXT_SECRET_SESSDATA';

LoginAccount accountWith(String cookieValue, {String mid = '12345'}) => LoginAccount(
  BiliCookieJar.fromJson({
    'DedeUserID': mid,
    'SESSDATA': cookieValue,
    'bili_jct': 'csrf-token-$cookieValue',
    'access_key': 'access-$cookieValue',
  }),
  'access-key-$cookieValue',
  'refresh-token-$cookieValue',
  {AccountType.main},
);

void main() {
  late Directory dir;

  setUpAll(() {
    // 与 lib/utils/storage.dart 注册的一致：8=cookieJar 9=账号 10=账号类型 11=Set<int>
    if (!Hive.isAdapterRegistered(8)) Hive.registerAdapter(BiliCookieJarAdapter());
    if (!Hive.isAdapterRegistered(9)) Hive.registerAdapter(LoginAccountAdapter());
    if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(AccountTypeAdapter());
    if (!Hive.isAdapterRegistered(11)) Hive.registerAdapter(SetIntAdapter());
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('liquidglass_hive_');
    Hive.init(dir.path);
    SecureAccountBox.keyStore = FakeKeyStore();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  /// 直接把 box 文件按字节读出来，检查里面有没有明文线索
  List<int> diskBytes(String boxName) {
    final f = File('${dir.path}${Platform.pathSeparator}$boxName.hive');
    return f.existsSync() ? f.readAsBytesSync() : <int>[];
  }

  bool containsAscii(List<int> bytes, String needle) {
    final pattern = ascii.encode(needle);
    for (var i = 0; i + pattern.length <= bytes.length; i++) {
      var hit = true;
      for (var j = 0; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) {
          hit = false;
          break;
        }
      }
      if (hit) return true;
    }
    return false;
  }

  test('全新安装：box 加密创建，密钥与标记都进了安全存储', () async {
    final box = await SecureAccountBox.open();
    await box.put('12345', accountWith(secret));
    await box.flush();
    await box.close();

    final store = SecureAccountBox.keyStore as FakeKeyStore;
    expect(store.data[SecureAccountBox.keyName], isNotNull);
    expect(base64Decode(store.data[SecureAccountBox.keyName]!).length, 32);
    expect(store.data[SecureAccountBox.markerName], '1');

    // 磁盘上不该出现明文 cookie / access_key / refresh_token
    final bytes = diskBytes(SecureAccountBox.boxName);
    expect(bytes, isNotEmpty);
    expect(containsAscii(bytes, secret), isFalse, reason: '磁盘上出现了明文 SESSDATA');
    expect(containsAscii(bytes, 'access-key-$secret'), isFalse, reason: '磁盘上出现了明文 access_key');
    expect(containsAscii(bytes, 'refresh-token-$secret'), isFalse, reason: '磁盘上出现了明文 refresh_token');

    // 读回来仍然正常（加密不破坏登录态）
    final reopened = await SecureAccountBox.open();
    final restored = reopened.get('12345');
    expect(restored, isNotNull);
    expect(restored!.mid, 12345);
    expect(restored.cookieJar.domainCookies['bilibili.com']!['/']!['SESSDATA']!.cookie.value, secret);
  });

  test('老用户迁移：明文 box → 加密 box，账号不丢且磁盘不再有明文', () async {
    // 1) 造一个"上游版本留下的"明文 box
    final plain = await Hive.openBox<dynamic>(SecureAccountBox.boxName);
    await plain.put('12345', accountWith(secret));
    await plain.close();
    expect(containsAscii(diskBytes(SecureAccountBox.boxName), secret), isTrue,
        reason: '前置条件不成立：明文 box 里本应能搜到 cookie');

    // 2) 迁移
    final box = await SecureAccountBox.open();
    final migrated = box.get('12345');
    expect(migrated, isNotNull, reason: '迁移后账号丢失');
    expect(migrated!.mid, 12345);
    expect(migrated.accessKey, 'access-key-$secret');
    expect(migrated.refresh, 'refresh-token-$secret');
    expect(migrated.cookieJar.domainCookies['bilibili.com']!['/']!['SESSDATA']!.cookie.value, secret);
    expect((SecureAccountBox.keyStore as FakeKeyStore).data[SecureAccountBox.markerName], '1');

    // 3) 磁盘层面验证：明文已消失
    await box.flush();
    final bytes = diskBytes(SecureAccountBox.boxName);
    expect(containsAscii(bytes, secret), isFalse, reason: '迁移后仍能在磁盘上搜到明文 cookie');
    expect(containsAscii(bytes, 'access-key-$secret'), isFalse);
  });

  test('有加密标记但密钥丢失：明确报错，不静默按明文打开', () async {
    final store = SecureAccountBox.keyStore as FakeKeyStore;
    store.data[SecureAccountBox.markerName] = '1';
    // 故意不写 keyName
    await expectLater(
      SecureAccountBox.open(),
      throwsA(isA<StateError>()),
    );
  });

  test('平台安全存储不可用：降级为明文但账号仍可读写（不把用户挡在门外）', () async {
    final plain = await Hive.openBox<dynamic>(SecureAccountBox.boxName);
    await plain.put('12345', accountWith(secret));
    await plain.close();

    SecureAccountBox.keyStore = FakeKeyStore(failOnWrite: true);
    final box = await SecureAccountBox.open();
    expect(box.get('12345')?.mid, 12345, reason: '降级路径也必须保住账号');
    expect((SecureAccountBox.keyStore as FakeKeyStore).data[SecureAccountBox.markerName], isNull,
        reason: '降级时不能留下"已加密"的假标记');
  });
}