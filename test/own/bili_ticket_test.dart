// SPDX-License-Identifier: GPL-3.0-or-later
//
// bili_ticket 自建增强的单元测试（纯函数部分，不依赖 Hive / 网络）。
// 端到端验证由 tool/smoke_test.py 的「bili_ticket 签发」检查项负责（同一算法）。
import 'package:PiliPlus/utils/bili_ticket.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hexsign', () {
    test('与独立实现（Python hmac）逐位一致', () {
      // 期望值：hmac.new(b"XgwSnGZ1p", b"ts1700000000", sha256).hexdigest()
      expect(
        BiliTicket.hexsign(1700000000),
        'bb79f0d980ffbb51597aa1a3e8b55603025cc1322ac766f4c1a98852e6182514',
      );
      // 期望值：hmac.new(b"XgwSnGZ1p", b"ts0", sha256).hexdigest()
      expect(
        BiliTicket.hexsign(0),
        '327a306250398c2b527fea0bab19f76c30baaeb93ab30c69c429445f7b9e5534',
      );
    });

    test('输出恒为 64 位小写十六进制', () {
      final h = BiliTicket.hexsign(1790914593);
      expect(h.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(h), isTrue);
    });
  });

  group('needRefresh', () {
    const now = 1700000000;
    test('无票据 → 需要获取', () {
      expect(BiliTicket.needRefresh(null, 0, now), isTrue);
      expect(BiliTicket.needRefresh('', now + 100000, now), isTrue);
    });

    test('余额不足续期窗口 → 需要获取', () {
      expect(BiliTicket.needRefresh('t', now + 60, now), isTrue);
      expect(BiliTicket.needRefresh('t', now + BiliTicket.renewAheadSeconds, now), isTrue);
    });

    test('余额充足 → 不获取', () {
      expect(BiliTicket.needRefresh('t', now + BiliTicket.renewAheadSeconds + 1, now), isFalse);
      expect(BiliTicket.needRefresh('t', now + 259200, now), isFalse);
    });
  });

  group('cookieFor', () {
    const now = 1700000000;
    test('有效票据组装 Cookie 片段', () {
      expect(
        BiliTicket.cookieFor('abc.def.ghi', now + 100, now),
        'bili_ticket=abc.def.ghi; bili_ticket_expires=${now + 100}',
      );
    });

    test('缺失 / 已过期 → null（宁可不带，也不带过期票据）', () {
      expect(BiliTicket.cookieFor(null, now + 100, now), isNull);
      expect(BiliTicket.cookieFor('', now + 100, now), isNull);
      expect(BiliTicket.cookieFor('abc', now, now), isNull);
      expect(BiliTicket.cookieFor('abc', now - 1, now), isNull);
    });
  });
}