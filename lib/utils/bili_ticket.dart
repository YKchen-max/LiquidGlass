// SPDX-License-Identifier: GPL-3.0-or-later
//
// bili_ticket（Web 票据）—— PiliPlus 上游未实现的**自建增强项**。
// 依据：docs/bilibili-接口清单.md §1.3 / §2.5、refs/bilibili-API-collect-master/docs/misc/sign/bili_ticket.md
//
//   hexsign = HMAC-SHA256(key = "XgwSnGZ1p", msg = "ts" + 秒级时间戳)
//   POST /bapis/bilibili.api.ticket.v1.Ticket/GenWebTicket
//        ?key_id=ec02&hexsign=<hexsign>&context[ts]=<ts>[&csrf=<bili_jct>]
//   → data.ticket 为 JWT，ttl 259200 秒（3 天）；随 Cookie 携带可降低风控概率。
//
// 挂载点（见 lib/http/init.dart setCookie()）：拦截器必须注册在 AccountManager **之前**——
// AccountManager 会把已存在的 cookie 头与 cookieJar 合并，因此这里的票据不会被覆盖。
//
// 纪律：票据只是加固项，任何失败都必须静默，绝不阻塞或打断正常请求。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:hive_ce/hive.dart';

abstract final class BiliTicket {
  /// HMAC 密钥（固定值，见接口清单 §1.3）
  static const String _appKey = 'XgwSnGZ1p';

  /// 固定的 key_id
  static const String _keyId = 'ec02';

  /// 提前续期窗口：避免"刚过期/临界过期"的请求被判为无票据
  static const int renewAheadSeconds = 3600;

  /// 服务端声明的有效期兜底值（3 天）
  static const int _fallbackTtl = 259200;

  static Box<dynamic> get _localCache => GStorage.localCache;

  static bool _fetching = false;

  /// hexsign = HMAC-SHA256("XgwSnGZ1p", "ts$ts")，十六进制小写。
  static String hexsign(int ts) =>
      Hmac(sha256, utf8.encode(_appKey)).convert(utf8.encode('ts$ts')).toString();

  static int get _nowSeconds => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// 本地缓存的票据（无则 null）
  static String? get ticket => _localCache.get(LocalCacheKey.biliTicket) as String?;

  /// 本地缓存的到期时间（秒级时间戳，无则 0）
  static int get expiresAt =>
      _localCache.get(LocalCacheKey.biliTicketExpires, defaultValue: 0) as int;

  /// 票据是否"够新鲜"（含提前续期窗口）——首帧/首次请求用它做同步判断。
  static bool get isFresh => !needRefresh(ticket, expiresAt, _nowSeconds);

  /// 纯函数：给定票据与到期时间，是否需要（重新）获取。便于脱离 Hive 单测。
  static bool needRefresh(String? ticket, int expiresAt, int nowSeconds) =>
      ticket == null ||
      ticket.isEmpty ||
      expiresAt - renewAheadSeconds <= nowSeconds;

  /// 纯函数：把票据组装成 Cookie 片段；已过期或缺失时返回 null。
  ///
  /// `bili_ticket_expires` 与浏览器侧行为保持一致（服务端不强制，但便于排查）。
  static String? cookieFor(String? ticket, int expiresAt, int nowSeconds) {
    if (ticket == null || ticket.isEmpty || expiresAt <= nowSeconds) return null;
    return 'bili_ticket=$ticket; bili_ticket_expires=$expiresAt';
  }

  /// 当前可用的 Cookie 片段（同步读缓存；无有效票据返回 null）。
  static String? get cookie => cookieFor(ticket, expiresAt, _nowSeconds);

  /// 确保本地有一张可用票据；失败静默。
  ///
  /// * 启动时调用一次（`Request.setCookie()`）；
  /// * 拦截器发现票据缺失/将过期时也会在后台调用（不阻塞当次请求）；
  /// * `_fetching` 兼作并发去重与递归保护。
  static Future<void> ensure({bool force = false}) async {
    if (_fetching) return;
    if (!force && !needRefresh(ticket, expiresAt, _nowSeconds)) return;
    _fetching = true;
    try {
      final int ts = _nowSeconds;
      final String csrf = _csrf();
      final Response resp = await Request().post(
        Api.genWebTicket,
        queryParameters: {
          'key_id': _keyId,
          'hexsign': hexsign(ts),
          'context[ts]': ts,
          if (csrf.isNotEmpty) 'csrf': csrf,
        },
        options: Options(extra: {skipExtraKey: true}),
      );
      if (resp.data case final Map data when data['code'] == 0) {
        if (data['data'] case final Map d when d['ticket'] is String) {
          final String t = d['ticket'] as String;
          if (t.isNotEmpty) {
            final int ttl = d['ttl'] is int ? d['ttl'] as int : _fallbackTtl;
            await _localCache.put(LocalCacheKey.biliTicket, t);
            await _localCache.put(LocalCacheKey.biliTicketExpires, ts + ttl);
          }
        }
      }
    } catch (_) {
      // 静默：网络异常、接口变更、未初始化存储都不应影响主流程
    } finally {
      _fetching = false;
    }
  }

  /// 取 csrf（bili_jct）；未登录或字段缺失时返回空串。
  static String _csrf() {
    try {
      return Accounts.main.isLogin ? Accounts.main.csrf : '';
    } catch (_) {
      return '';
    }
  }

  /// 请求级标记：带它的请求不挂票据（票据自身的请求用它避免自我引用）。
  static const String skipExtraKey = 'skipBiliTicket';
}

/// 把 bili_ticket 挂到发往 bilibili.com 的 Cookie 头上。
///
/// 必须注册在 `AccountManager` 之前（见 `Request.setCookie()`）。
class BiliTicketInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // 只作用于 B 站域；CDN（hdslb/biliimg）与第三方（SponsorBlock 等）一律不加
    if (options.extra[BiliTicket.skipExtraKey] != true &&
        options.uri.host.endsWith('bilibili.com')) {
      final String? c = BiliTicket.cookie;
      if (c != null) {
        final String? prev = options.headers[HttpHeaders.cookieHeader] as String?;
        options.headers[HttpHeaders.cookieHeader] =
            (prev == null || prev.isEmpty) ? c : '$c; $prev';
      } else {
        // 无票据：后台补一张，不阻塞当前请求（首次启动时通常由 setCookie() 触发）
        unawaited(BiliTicket.ensure());
      }
    }
    handler.next(options);
  }
}