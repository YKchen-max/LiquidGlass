// SPDX-License-Identifier: GPL-3.0-or-later
//
// 凭证续期链（排期文档阶段二 #14）—— PiliPlus 上游未实现的**自建增强项**。
// 依据：docs/bilibili-接口清单.md §2.4、refs/bilibili-API-collect-master/docs/login/cookie_refresh.md
//
// 四步链（Web cookie 账号，登录时已持久化 refresh_token）：
//   ① GET  /x/passport-login/web/cookie/info      → data.refresh == true 才继续；
//      code = -101 表示登录态已死，直接走重登提示。
//   ② correspondPath = hex( RSA-OAEP(SHA-256, MGF1-SHA256)("refresh_${毫秒时间戳}") )
//      → GET  www.bilibili.com/correspond/1/{path} → 从 <div id="1-name"> 抠 refresh_csrf
//   ③ POST /x/passport-login/web/cookie/refresh   （旧 csrf + refresh_csrf + source + 旧 refresh_token）
//      → 新 SESSDATA/bili_jct 由 AccountManager 拦截器自动落盘（_saveCookies → onChange），
//        响应体里拿新 refresh_token 回写账号。
//   ④ POST /x/passport-login/web/confirm/refresh  （**新** csrf + **旧** refresh_token）作废旧凭证。
//
// 设计纪律（对齐 bili_ticket.dart）：
//   * 纯函数（加密、抠 csrf）与 IO（HTTP/存储）分离，前者离线单测，端到端走 tool/smoke_test.py；
//   * 失败分级：RefreshInvalid（凭证已死）toast 提示重登；RefreshFailed（瞬时）静默留待下轮巡检；
//   * 启动巡检 12h 节流 + 并发去重（挂载点 Request.setCookie()，见 lib/http/init.dart）；
//   * 范围说明：APP 端 access_key 的 oauth2 刷新接口未收录于接口快照，不在本任务范围——
//     现有所有登录方式都会产出 Web cookie，本链对全部账号生效。
import 'dart:async';
import 'dart:convert';

import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:pointycastle/asymmetric/api.dart' show RSAPublicKey;

abstract final class CredentialRefresher {
  /// 启动巡检节流窗口
  static const Duration checkInterval = Duration(hours: 12);

  /// B 站 correspond 加密的固定 RSA 公钥（1024 位，见接口清单 §2.4 / cookie_refresh.md）
  static const String bilibiliPublicKeyPem = '''-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDLgd2OAkcGVtoE3ThUREbio0Eg
Uc/prcajMKXvkCKFCWhJYJcLkcM2DKKcSeFpD/j6Boy538YXnR6VhcuUJOhH2x71
nzPjfdTcqMz7djHum0qSZA0AyCBDABUqCrfNgCiJ00Ra7GmRj+YCK1NJEuewlb40
JNrRuoEUXpabUzGB8QIDAQAB
-----END PUBLIC KEY-----''';

  static final RegExp _refreshCsrfExp = RegExp(r'<div id="1-name">([^<]+)</div>');

  static bool _inFlight = false;
  static final Set<int> _busyMids = {};

  // ---------------------------------------------------------------- 对外入口

  /// 启动巡检：对所有已登录账号按需执行续期链。12h 节流 + 并发去重，绝不抛异常。
  static void startupCheck() {
    if (_inFlight) return;
    final int lastCheck =
        GStorage.localCache.get(LocalCacheKey.accountRefreshLastCheck, defaultValue: 0) as int;
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - lastCheck < checkInterval.inMilliseconds) return;

    _inFlight = true;
    unawaited(() async {
      try {
        for (final account in Accounts.account.values.toList()) {
          try {
            await refreshAccount(account);
          } catch (e) {
            // 单账号失败不影响其余账号
            debugPrint('[CredentialRefresher] mid=${account.mid} 巡检异常：$e');
          }
        }
      } finally {
        try {
          await GStorage.localCache.put(
            LocalCacheKey.accountRefreshLastCheck,
            DateTime.now().millisecondsSinceEpoch,
          );
        } catch (_) {}
        _inFlight = false;
      }
    }());
  }

  /// 对单个账号执行四步续期链。
  static Future<RefreshOutcome> refreshAccount(LoginAccount account) async {
    if (!account.isLogin || _busyMids.contains(account.mid)) {
      return const RefreshSkipped();
    }
    _busyMids.add(account.mid);
    try {
      return await _refresh(account);
    } catch (e) {
      debugPrint('[CredentialRefresher] mid=${account.mid} 续期异常：$e');
      return const RefreshFailed();
    } finally {
      _busyMids.remove(account.mid);
    }
  }

  // ---------------------------------------------------------------- 四步链

  static Future<RefreshOutcome> _refresh(LoginAccount account) async {
    // ① 是否需要刷新（csrf 为非必要参数，缺省不带）
    final info = await Request().get(
      Api.cookieRefreshInfo,
      options: Options(extra: {'account': account}),
    );
    final Object? infoData = info.data;
    if (infoData is! Map) {
      return _transient(account, 'cookie/info 无响应体（网络/风控）');
    }
    final Object? infoCode = infoData['code'];
    if (infoCode == -101) {
      return _invalid(account, 'cookie/info -101：登录态已失效');
    }
    if (infoCode != 0) {
      return _transient(account, 'cookie/info code=$infoCode');
    }
    final Object? infoBody = infoData['data'];
    if (infoBody is! Map || infoBody['refresh'] != true) {
      return const RefreshUpToDate();
    }

    // 老会话可能没有 refresh_token（上游从不刷新的遗留状态）：链走不通，提示重登
    final String? oldRefresh = account.refresh;
    if (oldRefresh == null || oldRefresh.isEmpty) {
      return _invalid(account, '缺少 refresh_token（老版本会话），无法自动续期');
    }

    // ② correspondPath → refresh_csrf
    final int ts = DateTime.now().millisecondsSinceEpoch;
    final String path = correspondPath(ts);
    final html = await Request().get(
      '${Api.cookieRefreshCorrespond}$path',
      options: Options(
        extra: {'account': account},
        responseType: ResponseType.plain,
      ),
    );
    final String? refreshCsrf = extractRefreshCsrf(html.data?.toString() ?? '');
    if (refreshCsrf == null) {
      return _transient(account, 'correspond 页未取到 refresh_csrf（路径过期或算法失配）');
    }

    // ③ 刷新：新 cookie 由 AccountManager 拦截器在 onResponse 里自动落盘
    final String oldCsrf = account.csrf;
    final refreshResp = await Request().post(
      Api.cookieRefresh,
      data: {
        'csrf': oldCsrf,
        'refresh_csrf': refreshCsrf,
        'source': 'main_web',
        'refresh_token': oldRefresh,
      },
      options: Options(
        extra: {'account': account},
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    final Object? refreshData = refreshResp.data;
    if (refreshData is! Map || refreshData['code'] != 0) {
      final Object? code = refreshData is Map ? refreshData['code'] : null;
      // 86095：refresh_csrf 错误或 refresh_token 与 cookie 不匹配 → 凭证已死
      return code == 86095
          ? _invalid(account, 'cookie/refresh 86095：refresh_token 与 cookie 不匹配')
          : _transient(account, 'cookie/refresh code=$code');
    }
    final Object? refreshBody = refreshData['data'];
    final String? newRefresh = refreshBody is Map ? refreshBody['refresh_token'] as String? : null;
    if (newRefresh == null || newRefresh.isEmpty) {
      return _transient(account, 'cookie/refresh 未返回新 refresh_token');
    }

    // ④ 确认更新：**新** csrf（jar 里已是新值）+ **旧** refresh_token → 作废旧凭证
    final confirmResp = await Request().post(
      Api.cookieRefreshConfirm,
      data: {'csrf': account.csrf, 'refresh_token': oldRefresh},
      options: Options(
        extra: {'account': account},
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    final Object? confirmData = confirmResp.data;
    if (confirmData is! Map || confirmData['code'] != 0) {
      // 作废失败不影响新凭证已生效；留待下轮（服务端会因 refresh_token 失配重走 86095 分支）
      debugPrint('[CredentialRefresher] mid=${account.mid} confirm/refresh 未成功（新 cookie 已生效，忽略）');
    }

    account.refresh = newRefresh;
    await account.onChange();
    debugPrint('[CredentialRefresher] mid=${account.mid} 凭证已续期');
    return const RefreshSuccess();
  }

  // ---------------------------------------------------------------- 纯函数（离线单测覆盖）

  /// correspondPath = 小写 hex( RSA-OAEP(SHA-256, MGF1-SHA256)( "refresh_$tsMs" ) )。
  /// [publicKeyPem] 可注入测试密钥对做加解密往返与跨语言互操作验证。
  static String correspondPath(int tsMs, {String publicKeyPem = bilibiliPublicKeyPem}) {
    final cipher = enc.RSA(
      publicKey: enc.RSAKeyParser().parse(publicKeyPem) as RSAPublicKey,
      encoding: enc.RSAEncoding.OAEP,
      digest: enc.RSADigest.SHA256,
    );
    return cipher
        .encrypt(utf8.encode('refresh_$tsMs'))
        .bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// 从 correspond 中转页 HTML 里抠 refresh_csrf（32 位小写十六进制）。
  static String? extractRefreshCsrf(String html) {
    final match = _refreshCsrfExp.firstMatch(html);
    return match?.group(1);
  }

  // ---------------------------------------------------------------- 内部

  static RefreshOutcome _invalid(LoginAccount account, String reason) {
    debugPrint('[CredentialRefresher] mid=${account.mid} $reason');
    // 失效重登提示：每次巡检窗口至多出现一次（12h 节流由 startupCheck 保证）
    unawaited(
      SmartDialog.showToast('B 站登录已过期，请重新扫码登录（账号 mid=${account.mid}）'),
    );
    return const RefreshInvalid();
  }

  static RefreshOutcome _transient(LoginAccount account, String reason) {
    debugPrint('[CredentialRefresher] mid=${account.mid} $reason（下轮巡检重试）');
    return const RefreshFailed();
  }
}

/// 续期结果。Invalid = 凭证已死需重登；Failed = 瞬时失败，下轮巡检自然重试。
sealed class RefreshOutcome {
  const RefreshOutcome();
}

final class RefreshSuccess extends RefreshOutcome {
  const RefreshSuccess();
}

final class RefreshUpToDate extends RefreshOutcome {
  const RefreshUpToDate();
}

final class RefreshInvalid extends RefreshOutcome {
  const RefreshInvalid();
}

final class RefreshFailed extends RefreshOutcome {
  const RefreshFailed();
}

final class RefreshSkipped extends RefreshOutcome {
  const RefreshSkipped();
}
