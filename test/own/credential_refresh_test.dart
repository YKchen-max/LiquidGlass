// SPDX-License-Identifier: GPL-3.0-or-later
//
// 凭证续期链纯函数单测（排期文档阶段二 #14）。
// 端到端验证由 tool/smoke_test.py 的「Cookie 续期链」检查项负责。
//
// 关键测试是 KAT（Known Answer Test）：用 pycryptodome（独立实现，SHA-256 + MGF1-SHA256）
// 加密的密文，Dart 侧必须解出同明文——证明 correspondPath 的 OAEP 参数与业界实现逐位一致，
// 单靠 Dart 自己的加解密往返无法发现"摘要算法配错"这类问题。
//
// ⚠️ 私钥不随仓库分发：
//   1024 位 RSA 私钥与 KAT 密文放在 `test/own/.credential_refresh_kat.json`（已 gitignore），
//   避免公开仓库触发 secret scanning 告警 / push protection。
//   本地缺少该文件时，依赖私钥的用例会自动 skip（skip 信息里会写明路径）。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/utils/credential_refresh.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/asymmetric/api.dart' show RSAPrivateKey;

/// 测试专用**公钥**（1024 位，仅存在于本测试，与 B 站线上公钥无关）。
/// 公钥可以随仓库分发；私钥见文件头说明。
const String testPubPem = '''-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCcDNy+B5wF4dEEeovkiPqnx6jj
EIGzX+yfvM0qeXDxrY+QFX+/87YmNn9xoxz1jGDaa+Ch1GjHkuIpo5OUreM81DS1
jQiHF9Q9JsMzzFzXjM/2v5mJtoZYn6Zo6AOhV1+DMFu4xbSAzcK4lbALnwN42MDp
ghNq3MiuZxXtNaWdxwIDAQAB
-----END PUBLIC KEY-----''';

/// 本地夹具路径（相对仓库根；`flutter test` 的工作目录即仓库根）。
const String _katPath = 'test/own/.credential_refresh_kat.json';

/// 读取本地夹具；不存在返回 null —— 对应用例 skip，不影响其余测试。
Map<String, String>? _loadKat() {
  final file = File(_katPath);
  if (!file.existsSync()) return null;
  final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return raw.map((key, value) => MapEntry(key, value.toString()));
}

Uint8List hexToBytes(String hex) => Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);

enc.RSA decrypterFor(String privPem) => enc.RSA(
      privateKey: enc.RSAKeyParser().parse(privPem) as RSAPrivateKey,
      encoding: enc.RSAEncoding.OAEP,
      digest: enc.RSADigest.SHA256,
    );

void main() {
  final kat = _loadKat();
  final Object skipPrivateKey =
      kat == null ? '缺少本地夹具 $_katPath（私钥不随仓库分发）' : false;

  group('correspondPath（RSA-OAEP-SHA256）', () {
    test('KAT：pycryptodome 加密的密文可解出原明文（跨实现互操作）', () {
      final plain = decrypterFor(kat!['privPem']!)
          .decrypt(enc.Encrypted(hexToBytes(kat['katCipherHex']!)));
      expect(utf8.decode(plain), 'refresh_1700000000000');
    }, skip: skipPrivateKey);

    test('加解密往返（Dart 自己加密 → 自己解密）', () {
      const ts = 1790914593123;
      final hex =
          CredentialRefresher.correspondPath(ts, publicKeyPem: testPubPem);
      final plain =
          decrypterFor(kat!['privPem']!).decrypt(enc.Encrypted(hexToBytes(hex)));
      expect(utf8.decode(plain), 'refresh_$ts');
    }, skip: skipPrivateKey);

    test('输出恒为 256 位小写十六进制（1024 位 RSA），且含随机性', () {
      final h = CredentialRefresher.correspondPath(
        DateTime.now().millisecondsSinceEpoch,
      );
      expect(h.length, 256);
      expect(RegExp(r'^[0-9a-f]{256}$').hasMatch(h), isTrue);
      // OAEP 带随机种子：同一明文两次加密密文必然不同
      final h2 = CredentialRefresher.correspondPath(
        DateTime.now().millisecondsSinceEpoch,
      );
      expect(h2, isNot(h));
    });

    test('明文消息体严格为 refresh_<毫秒时间戳>（时间戳位数变化不影响解密）', () {
      for (final ts in [1000, 999999999999, 1790914593123]) {
        final hex =
            CredentialRefresher.correspondPath(ts, publicKeyPem: testPubPem);
        final plain = decrypterFor(kat!['privPem']!)
            .decrypt(enc.Encrypted(hexToBytes(hex)));
        expect(utf8.decode(plain), 'refresh_$ts');
      }
    }, skip: skipPrivateKey);
  });

  group('extractRefreshCsrf', () {
    test('从 correspond 中转页抠出 refresh_csrf（真实样本）', () {
      const html = '''<!DOCTYPE html>
<html lang="zh-Hans">
<head><title>Correspond</title></head>
<body>
  <div id="1-name">b0cc8411ded2f9db2cff2edb3123acac</div>
  <div id="token-iframe-app"></div>
</body>
</html>''';
      expect(CredentialRefresher.extractRefreshCsrf(html),
          'b0cc8411ded2f9db2cff2edb3123acac');
    });

    test('路径过期/错误（404 页或任意其他 HTML）→ null', () {
      expect(
          CredentialRefresher.extractRefreshCsrf('<html>404 Page Not Found</html>'),
          isNull);
      expect(CredentialRefresher.extractRefreshCsrf(''), isNull);
      expect(
        CredentialRefresher.extractRefreshCsrf('<div id="1-name"></div>'),
        isNull,
      );
    });
  });
}
