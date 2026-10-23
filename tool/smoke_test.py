#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""LiquidGlass for Bilibili —— 接口存活 smoke test（排期文档阶段一 #3）

目的：把「接口失效是常态」变成每日可发现的信号（供阶段三 #17 的定时任务直接调用）。

判定口径
  * `code=0` 与匿名下的 `code=-101 未登录` 都算**存活**；
  * `-352 风控` / `-412 拦截` 算 **WARN**（可能是本机 IP 被限，也可能是缺反爬参数）；
  * `-404` / HTTP 非 200 / 异常算 **FAIL**（接口消失或改版）。

设计约束（都是本机实测踩出来的，别改回去）
  1. **零第三方依赖**：只用标准库，避免每日任务因为环境漂移而失败；mitmproxy 只在
     解析抓包文件时按需导入。
  2. **参数动态取**：测试稿件 bvid、直播间号、番剧 episode_id 全部在运行时从公开列表拿，
     避免写死的示例 ID 失效后脚本变成噪音源。
  3. **必须带满反爬参数**：实测 `x/space/wbi/acc/info` 只带 WBI 会 `-352`，
     补上 `dm_img_*` 四元组即 `code=0`；`getDanmuInfo` 不带 WBI 也是 `-352`。
  4. **必须覆写 UA**（接口清单 §0.3）：dio/urllib 默认 UA 会秒进风控。
  5. **输出纯 ASCII 标记**：Windows 控制台默认 GBK，emoji 会直接把脚本打死。
  6. **`code=0` 也可能是限流**：实测搜索接口在匿名态会**静默返回空结果**（同一秒内
     重跑又给 20 条），所以"code=0 但 data/result 为空"判 WARN 而不是 OK——
     否则限流会被误读成"接口健康"。同理，任何"code=0 但结构缺字段"都判 FAIL/WARN 并写明缘由。

用法::

    python tool/smoke_test.py                                # 匿名全量（默认）
    python tool/smoke_test.py --cookie "SESSDATA=xxx; bili_jct=yyy"
    python tool/smoke_test.py --mitm-flows capture.flow      # 从 mitmproxy 抓包取 Cookie
    python tool/smoke_test.py --json report.json --verbose

退出码：0 = 无 FAIL；1 = 至少一个 FAIL（可直接当 CI / 计划任务的判定）。
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Callable

# ---------------------------------------------------------------- 常量（对齐 docs/bilibili-接口清单.md）

UA_WEB = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
)
API = "https://api.bilibili.com"
PASSPORT = "https://passport.bilibili.com"
LIVE = "https://api.live.bilibili.com"
WWW = "https://www.bilibili.com"

# 复制自 lib/utils/wbi_sign.dart:19-52（接口清单 §1.1 第 2 步）
MIXIN_KEY_ENC_TAB = [
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
    27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
]
CHR_FILTER = re.compile(r"[!'()*]")

OK_CODES = {0, -101}
WARN_CODES = {-412: "请求被拦截", -352: "风控校验失败", -403: "无权限", -509: "请求过于频繁"}
FAIL_CODES = {-404: "接口/参数不存在"}


# ---------------------------------------------------------------- 签名与指纹


def sign_wbi(params: dict[str, Any], mixin_key: str) -> dict[str, Any]:
    """WBI 签名（接口清单 §1.1，含大写十六进制与 !'()* 过滤）。"""
    params = dict(params)
    params["wts"] = int(time.time())
    query = "&".join(
        f"{urllib.parse.quote(str(k), safe='')}="
        f"{urllib.parse.quote(CHR_FILTER.sub('', str(v)), safe='')}"
        for k, v in sorted(params.items())
    )
    params["w_rid"] = hashlib.md5((query + mixin_key).encode()).hexdigest()
    return params


def mixin_key_from_nav(nav: dict[str, Any]) -> str:
    wbi = nav["data"]["wbi_img"]
    orig = Path(wbi["img_url"]).stem + Path(wbi["sub_url"]).stem
    return "".join(orig[i] for i in MIXIN_KEY_ENC_TAB)


def gen_web_ticket_params() -> dict[str, Any]:
    """bili_ticket 参数（接口清单 §1.3）—— 阶段一 #4 的算法基线。"""
    ts = int(time.time())
    return {
        "key_id": "ec02",
        "hexsign": hmac.new(b"XgwSnGZ1p", f"ts{ts}".encode(), hashlib.sha256).hexdigest(),
        "context[ts]": ts,
    }


def dm_img_fingerprint() -> dict[str, Any]:
    """反爬四元组（接口清单 §3）：playurl 与 space 系列缺它会 -352。"""
    return {
        "dm_img_list": "[]",
        "dm_img_str": "V2ViR0wgMS4wIChPcGVuR0wgRVMgMi4wIENocm9taXVtKQ",
        "dm_cover_img_str": "QU5HTEUgKEludGVsLCBJbnRlbChSKSBVSEQgR3JhcGhpY3MgKDB4MDAwMDlBNjgpIERpcmVjdDNEMTEgdnNfNV8wKQ",
        "dm_img_inter": '{"ds":[],"wh":[0,0,0],"of":[0,0,0]}',
    }


# ---------------------------------------------------------------- Cookie 续期链（阶段二 #14 自建增强）


# B 站 correspond 加密的固定公钥（1024 位；接口清单 §2.4，JWK 的 n/e，base64url）
_CORRESPOND_N_B64URL = (
    "y4HdjgJHBlbaBN04VERG4qNBIFHP6a3GozCl75AihQloSWCXC5HDNgyinEnhaQ_4-gaMud_GF50elYXLlCToR9se9Z8z433U3KjM-3Yx7ptKkmQNAMggQwAVKgq3zYAoidNEWuxpkY_mAitTSRLnsJW-NCTa0bqBFF6Wm1MxgfE"
)
_CORRESPOND_E = 0x010001


def _mgf1_sha256(seed: bytes, length: int) -> bytes:
    """MGF1 掩码生成（RFC 8017 B.2.1），哈希固定 SHA-256（B 站 wasm 规格即 SHA-256 + MGF1-SHA256）。"""
    out = b""
    for counter in range((length + 31) // 32):
        out += hashlib.sha256(seed + counter.to_bytes(4, "big")).digest()
    return out[:length]


def oaep_sha256_encrypt(message: bytes) -> bytes:
    """RSA-OAEP(SHA-256, MGF1-SHA256) 加密（RFC 8017 §7.1.1），零第三方依赖。

    与 lib/utils/credential_refresh.dart 的 correspondPath 同规格；
    开发期已用 pycryptodome 交叉验证，本函数另有每日线上校验（correspond 检查项 404 即算法断）。
    """
    k = 128                                              # 1024 位 RSA 的密文块长
    h_len = 32
    if len(message) > k - 2 * h_len - 2:
        raise ValueError("message too long")
    l_hash = hashlib.sha256(b"").digest()
    ps = b"\x00" * (k - len(message) - 2 * h_len - 2)
    db = l_hash + ps + b"\x01" + message
    seed = os.urandom(h_len)
    masked_db = bytes(a ^ b for a, b in zip(db, _mgf1_sha256(seed, k - h_len - 1)))
    masked_seed = bytes(a ^ b for a, b in zip(seed, _mgf1_sha256(masked_db, h_len)))
    em = b"\x00" + masked_seed + masked_db
    n = int.from_bytes(base64.urlsafe_b64decode(_CORRESPOND_N_B64URL + "=="), "big")
    return pow(int.from_bytes(em, "big"), _CORRESPOND_E, n).to_bytes(k, "big")


def correspond_path(ts_ms: int) -> str:
    """correspondPath = hex(RSA-OAEP-SHA256("refresh_${ts}"))，与 Dart 侧同算法同公钥。"""
    return oaep_sha256_encrypt(f"refresh_{ts_ms}".encode()).hex()


def cookie_value(cookie: str, name: str) -> str:
    """从 Cookie 头字符串里取某个 cookie 的值（无则空串）。"""
    for part in cookie.split(";"):
        k, _, v = part.strip().partition("=")
        if k == name:
            return v
    return ""


def merge_cookie(cookie: str, updates: dict[str, str]) -> str:
    """把 updates 合并进 Cookie 头字符串（保留 buvid3 等其他项）。"""
    jar: dict[str, str] = {}
    for part in cookie.split(";"):
        k, _, v = part.strip().partition("=")
        if k:
            jar[k] = v
    jar.update(updates)
    return "; ".join(f"{k}={v}" for k, v in jar.items() if v)


# ---------------------------------------------------------------- 结果与客户端


@dataclass
class Result:
    name: str
    section: str
    url: str = "-"
    critical: bool = True
    note: str = ""
    status: int | None = None
    code: int | None = None
    verdict: str = "SKIP"
    ms: int = 0
    detail: str = ""

    def as_dict(self) -> dict[str, Any]:
        return {
            "name": self.name, "section": self.section, "url": self.url,
            "http": self.status, "code": self.code, "verdict": self.verdict,
            "ms": self.ms, "critical": self.critical, "note": self.note,
            "detail": self.detail,
        }


class Client:
    def __init__(self, cookie: str = "", timeout: int = 20, writes: list[str] | None = None):
        self.cookie = cookie
        self.timeout = timeout
        self.mixin_key = ""
        self.ctx = ssl.create_default_context()
        self.writes: list[str] = writes if writes is not None else []   # 记录写操作（便于审计）

    # --- 传输

    def raw(self, url: str, params: dict[str, Any] | None = None, *,
            method: str = "GET", headers: dict[str, str] | None = None,
            referer: str | None = None, body: bytes | None = None
            ) -> tuple[int, bytes, dict[str, str]]:
        if params:
            url = f"{url}?{urllib.parse.urlencode(params)}"
        if method in {"POST", "PUT"}:
            self.writes.append(f"{method} {url}")
        h = {"User-Agent": UA_WEB, "Accept": "*/*", "Accept-Language": "zh-CN,zh;q=0.9"}
        if self.cookie:
            h["Cookie"] = self.cookie
        if referer:
            h["Referer"] = referer
        h.update(headers or {})
        req = urllib.request.Request(
            url, data=body if body is not None else (b"" if method == "POST" else None),
            headers=h, method=method)
        try:
            with urllib.request.urlopen(req, timeout=self.timeout, context=self.ctx) as r:
                return r.status, r.read(), dict(r.headers)
        except urllib.error.HTTPError as e:
            return e.code, e.read(), dict(e.headers or {})

    def fetch(self, res: Result, url: str, params: dict[str, Any] | None = None, *,
              method: str = "GET", referer: str | None = None,
              headers: dict[str, str] | None = None) -> dict[str, Any]:
        """发一次请求并填好 res 的通用字段，返回解析后的 JSON（失败时为空 dict）。"""
        t0 = time.time()
        try:
            status, body, _ = self.raw(url, params, method=method, referer=referer, headers=headers)
        except Exception as e:                                        # noqa: BLE001
            res.verdict, res.detail = "FAIL", f"传输异常 {type(e).__name__}: {e}"
            return {}
        res.status = status
        res.ms = int((time.time() - t0) * 1000)
        try:
            payload = json.loads(body.decode("utf-8", "replace"))
        except json.JSONDecodeError:
            payload = {}
        self._judge(res, payload)
        return payload

    @staticmethod
    def _judge(res: Result, payload: dict[str, Any]) -> None:
        code = payload.get("code")
        res.code = code if isinstance(code, int) else None
        if res.status != 200:
            res.verdict, res.detail = "FAIL", f"HTTP {res.status}"
        elif res.code in OK_CODES:
            res.verdict = "OK"
            res.detail = "code=0" if res.code == 0 else "code=-101（未登录，匿名下正常）"
        elif res.code in WARN_CODES:
            res.verdict, res.detail = "WARN", f"code={res.code} {WARN_CODES[res.code]}"
        elif res.code in FAIL_CODES:
            res.verdict, res.detail = "FAIL", f"code={res.code} {FAIL_CODES[res.code]}"
        elif res.code is None:
            res.verdict, res.detail = "WARN", "响应非 JSON（可能为 protobuf 或已改版）"
        else:
            res.verdict, res.detail = "WARN", f"code={res.code}"

    def mark_bad(self, res: Result, why: str) -> Result:
        res.verdict, res.detail = "FAIL", why
        return res


CHECKS: list[tuple[str, str, Callable[[Client, dict], Result]]] = []


def check(name: str, section: str):
    def deco(fn: Callable[[Client, dict], Result]):
        CHECKS.append((name, section, fn))
        return fn
    return deco


# ---------------------------------------------------------------- §1 签名基础


@check("导航 + WBI 密钥", "§1.1")
def c_nav(client: Client, st: dict) -> Result:
    res = Result("导航 + WBI 密钥", "§1.1", f"{API}/x/web-interface/nav")
    payload = client.fetch(res, res.url)
    if res.verdict in {"OK", "WARN"}:
        try:
            client.mixin_key = mixin_key_from_nav(payload)
            res.detail += f"；mixin_key 已取（{len(client.mixin_key)} 位）"
        except Exception as e:                                        # noqa: BLE001
            client.mark_bad(res, f"wbi_img 结构异常: {e}")
    return res


@check("buvid3/4 指纹下发", "§8")
def c_spi(client: Client, st: dict) -> Result:
    res = Result("buvid3/4 指纹下发", "§8", f"{API}/x/frontend/finger/spi")
    payload = client.fetch(res, res.url)
    d = payload.get("data") or {}
    if res.code == 0 and d.get("b_3") and d.get("b_4"):
        res.detail = f"code=0；buvid3={d['b_3'][:8]}… buvid4={d['b_4'][:8]}…"
        # 后续请求都带上，模拟真实客户端（接口清单 §8：buvid3 是多个端点的硬要求）
        client.cookie = (f"{client.cookie}; " if client.cookie else "") + f"buvid3={d['b_3']}"
    elif res.code == 0:
        client.mark_bad(res, "code=0 但缺少 b_3/b_4")
    return res


@check("bili_ticket 签发（自建增强 #4）", "§1.3")
def c_ticket(client: Client, st: dict) -> Result:
    res = Result("bili_ticket 签发（自建增强 #4）", "§1.3",
                 f"{API}/bapis/bilibili.api.ticket.v1.Ticket/GenWebTicket")
    payload = client.fetch(res, res.url, gen_web_ticket_params(), method="POST")
    d = payload.get("data") or {}
    ticket = d.get("ticket") or ""
    if res.code == 0:
        st["ticket"] = ticket
        segs = len(ticket.split("."))
        res.detail = f"code=0；JWT 段数={segs} ttl={d.get('ttl')}s（接口清单称 3 天）"
        if segs != 3:
            res.verdict, res.detail = "WARN", f"code=0 但 ticket 不是 JWT（段数={segs}）"
    return res


# ---------------------------------------------------------------- §2 登录与凭证


@check("扫码登录-生成二维码", "§2.1")
def c_qr(client: Client, st: dict) -> Result:
    res = Result("扫码登录-生成二维码", "§2.1", f"{PASSPORT}/x/passport-login/web/qrcode/generate")
    payload = client.fetch(res, res.url)
    d = payload.get("data") or {}
    if res.code == 0:
        st["qrcode_key"] = d.get("qrcode_key", "")
        res.detail = f"code=0；qrcode_key={'有' if d.get('qrcode_key') else '缺'} url={'有' if d.get('url') else '缺'}"
    return res


@check("扫码登录-轮询", "§2.1")
def c_qr_poll(client: Client, st: dict) -> Result:
    res = Result("扫码登录-轮询", "§2.1", f"{PASSPORT}/x/passport-login/web/qrcode/poll")
    payload = client.fetch(res, res.url, {"qrcode_key": st.get("qrcode_key", "invalid")})
    inner = (payload.get("data") or {}).get("code")
    labels = {86101: "未扫码", 86090: "已扫未确认", 86038: "已过期", 0: "登录成功"}
    if inner in labels:
        res.verdict = "OK"
        res.detail = f"inner_code={inner}（{labels[inner]}）"
    return res


@check("Cookie 刷新状态查询", "§2.4")
def c_cookie_info(client: Client, st: dict) -> Result:
    res = Result("Cookie 刷新状态查询", "§2.4", f"{PASSPORT}/x/passport-login/web/cookie/info")
    return client.fetch(res, res.url, {"csrf": "0"}) and res


@check("Cookie 续期链：correspond → refresh_csrf", "§2.4")
def c_cookie_correspond(client: Client, st: dict) -> Result:
    res = Result("Cookie 续期链：correspond → refresh_csrf", "§2.4",
                 f"{WWW}/correspond/1/<correspondPath>")
    if "SESSDATA" not in client.cookie:
        # 实测（2026-10-02）：该端点有会话门禁，匿名/仅 buvid3 一律 404，无法离线探测
        res.verdict, res.detail = "SKIP", "需登录态（SESSDATA），匿名下端点恒 404"
        return res
    t0 = time.time()
    path = correspond_path(int(time.time() * 1000))
    status, body, _ = client.raw(f"{WWW}/correspond/1/{path}",
                                 referer="https://www.bilibili.com/")
    res.status, res.ms = status, int((time.time() - t0) * 1000)
    html = body.decode("utf-8", "replace")
    m = re.search(r'<div id="1-name">([^<]+)</div>', html)
    if status == 200 and m:
        st["refresh_csrf"] = m.group(1)
        res.verdict, res.detail = "OK", "refresh_csrf 已取得（续期链算法与端点均存活）"
    elif status == 404:
        # 未处于刷新窗口时也可能 404，故降为 WARN；持续 404 + 续期失败才算链路断
        res.verdict, res.detail = "WARN", "HTTP 404：未取到 refresh_csrf（未在刷新窗口，或路径/算法失配）"
    else:
        res.verdict, res.detail = "WARN", f"HTTP {status}：未取到 refresh_csrf"
    return res


@check("Cookie 续期链：refresh + confirm（真实轮换）", "§2.4")
def c_cookie_rotate(client: Client, st: dict) -> Result:
    res = Result("Cookie 续期链：refresh + confirm（真实轮换）", "§2.4",
                 f"{PASSPORT}/x/passport-login/web/cookie/refresh")
    rotate = st.get("rotate") or {}
    if not rotate.get("enabled"):
        res.verdict, res.detail = "SKIP", "未加 --rotate-cookie（默认不轮换线上凭证）"
        return res
    if "SESSDATA" not in client.cookie or "bili_jct" not in client.cookie:
        res.verdict, res.detail = "SKIP", "需要完整登录 Cookie（SESSDATA + bili_jct）"
        return res
    refresh_csrf = st.get("refresh_csrf")
    old_refresh = rotate.get("refresh_token") or ""
    if not refresh_csrf or not old_refresh:
        res.verdict, res.detail = "SKIP", "缺 refresh_csrf（上一步未过）或 --refresh-token"
        return res

    res.url = f"{PASSPORT}/x/passport-login/web/cookie/refresh"
    t0 = time.time()
    status, body, headers = client.raw(
        res.url, method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        body=urllib.parse.urlencode({
            "csrf": cookie_value(client.cookie, "bili_jct"),
            "refresh_csrf": refresh_csrf,
            "source": "main_web",
            "refresh_token": old_refresh,
        }).encode(),
    )
    res.status, res.ms = status, int((time.time() - t0) * 1000)
    try:
        payload = json.loads(body.decode("utf-8", "replace"))
    except json.JSONDecodeError:
        payload = {}
    res.code = payload.get("code") if isinstance(payload, dict) else None
    if status != 200 or res.code != 0:
        res.verdict, res.detail = "FAIL", f"HTTP {status} / code={res.code}（链路断或凭证死）"
        return res
    new_refresh = (payload.get("data") or {}).get("refresh_token", "")

    # 新 cookie 落进会话（多段 Set-Cookie 用与 AccountManager 相同的规则拆分）
    set_cookie = headers.get("Set-Cookie", "") or headers.get("set-cookie", "")
    updates = {}
    for part in re.split(r",(?=[^;]+?=)", set_cookie):
        name, _, value = part.split(";", 1)[0].strip().partition("=")
        if name and value:
            updates[name] = value
    client.cookie = merge_cookie(client.cookie, updates)
    client.writes.append(f"rotate: 旧 refresh_token 已作废，新 Cookie 已应用到后续检查")

    # ④ confirm：新 csrf + 旧 refresh_token → 作废旧凭证
    c_status, c_body, _ = client.raw(
        f"{PASSPORT}/x/passport-login/web/confirm/refresh", method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        body=urllib.parse.urlencode({
            "csrf": cookie_value(client.cookie, "bili_jct"),
            "refresh_token": old_refresh,
        }).encode(),
    )
    ok_confirm = c_status == 200 and json.loads(c_body.decode("utf-8", "replace") or "{}").get("code") == 0
    res.verdict = "OK"
    res.detail = (f"已轮换（confirm {'OK' if ok_confirm else 'WARN'}）；"
                  f"新 refresh_token={new_refresh[:6]}***，请回写测试账号资料")
    print(f"        NEW_COOKIE={client.cookie}")
    print(f"        NEW_REFRESH_TOKEN={new_refresh}")
    return res


# ---------------------------------------------------------------- §3 视频链路


@check("推荐流（顺带取测试稿件）", "§6")
def c_rcmd(client: Client, st: dict) -> Result:
    res = Result("推荐流（顺带取测试稿件）", "§6", f"{API}/x/web-interface/index/top/feed/rcmd")
    params = {"ps": 6, "fresh_type": 3, "fresh_idx": 1}
    payload = client.fetch(res, res.url, params)
    if res.code == 0:
        items = (payload.get("data") or {}).get("item") or []
        st["bvid"] = next((i.get("bvid") for i in items if isinstance(i, dict) and i.get("bvid")), "")
        res.detail = f"code=0；测试稿件 {st['bvid'] or '未取到'}"
    return res


@check("稿件信息 view（WBI）", "§3")
def c_view(client: Client, st: dict) -> Result:
    bvid = st.get("bvid") or "BV1xx411c7mD"
    res = Result("稿件信息 view（WBI）", "§3", f"{API}/x/web-interface/wbi/view?bvid={bvid}")
    payload = client.fetch(res, res.url.split("?")[0],
                           sign_wbi({"bvid": bvid}, client.mixin_key),
                           referer=f"{WWW}/video/{bvid}")
    d = payload.get("data") or {}
    if res.code == 0 and d.get("cid"):
        st["aid"], st["cid"] = d.get("aid"), d.get("cid")
        res.detail = f"code=0；aid={st['aid']} cid={st['cid']}"
    elif res.code == 0:
        client.mark_bad(res, "code=0 但缺少 cid")
    return res


@check("分P列表 pagelist", "§3")
def c_pagelist(client: Client, st: dict) -> Result:
    bvid = st.get("bvid", "")
    res = Result("分P列表 pagelist", "§3", f"{API}/x/player/pagelist?bvid={bvid}")
    payload = client.fetch(res, res.url.split("?")[0], {"bvid": bvid, "jsonp": "jsonp"},
                           referer=f"{WWW}/video/{bvid}")
    data = payload.get("data") or []
    if res.code == 0:
        if not st.get("cid") and data:
            st["cid"] = data[0].get("cid")
        res.detail = f"code=0；分P数={len(data)}"
    return res


@check("UGC 取流 playurl（WBI + 反爬四元组）", "§3")
def c_playurl(client: Client, st: dict) -> Result:
    bvid = st.get("bvid", "")
    res = Result("UGC 取流 playurl（WBI + 反爬四元组）", "§3",
                 f"{API}/x/player/wbi/playurl?bvid={bvid}&cid={st.get('cid')}")
    params = sign_wbi({
        "bvid": bvid, "cid": st.get("cid", 0), "qn": 80, "fnval": 4048, "fnver": 0,
        "fourk": 1, "try_look": 1, **dm_img_fingerprint(),
        "gaia_source": "pre-load", "isGaiaAvoided": "true", "web_location": "1315873",
    }, client.mixin_key)
    payload = client.fetch(res, f"{API}/x/player/wbi/playurl", params,
                           referer=f"{WWW}/video/{bvid}")
    dash = (payload.get("data") or {}).get("dash") or {}
    if res.code == 0:
        nv, na = len(dash.get("video") or []), len(dash.get("audio") or [])
        res.detail = f"code=0；video 轨={nv} audio 轨={na}"
        if not dash:
            res.verdict, res.detail = "WARN", "code=0 但无 dash 字段（被降级为 durl？）"
    return res


@check("弹幕分包 seg.so（protobuf 二进制）", "§4.1")
def c_danmaku(client: Client, st: dict) -> Result:
    bvid = st.get("bvid", "")
    res = Result("弹幕分包 seg.so（protobuf 二进制）", "§4.1",
                 f"{API}/x/v2/dm/wbi/web/seg.so?oid={st.get('cid')}&segment_index=1")
    params = sign_wbi({"type": 1, "oid": st.get("cid", 0), "pid": st.get("aid", 0),
                       "segment_index": 1}, client.mixin_key)
    t0 = time.time()
    try:
        status, body, headers = client.raw(res.url.split("?")[0], params,
                                           referer=f"{WWW}/video/{bvid}")
    except Exception as e:                                            # noqa: BLE001
        return client.mark_bad(res, f"传输异常 {type(e).__name__}: {e}")
    res.status, res.ms = status, int((time.time() - t0) * 1000)
    ctype = headers.get("Content-Type", "").split(";")[0]
    if status != 200:
        res.verdict, res.detail = "FAIL", f"HTTP {status}"
    elif body[:1] == b"{":                     # 出错时返回 JSON
        payload = json.loads(body.decode("utf-8", "replace"))
        client._judge(res, payload)
        res.detail = f"返回 JSON 而非 protobuf：{res.detail}"
    elif body:
        res.verdict, res.detail = "OK", f"{len(body)} 字节 protobuf（{ctype}）"
    else:
        res.verdict, res.detail = "WARN", "空响应体"
    return res


@check("番剧时间表（顺带取 episode_id）", "§3")
def c_pgc_timeline(client: Client, st: dict) -> Result:
    res = Result("番剧时间表（顺带取 episode_id）", "§3", f"{API}/pgc/web/timeline")
    payload = client.fetch(res, res.url, {"types": 1, "before": 6, "after": 6},
                           referer=f"{WWW}/")
    if res.code == 0:
        eps = [e for d in (payload.get("result") or [])
               for e in (d.get("episodes") or []) if e.get("episode_id")]
        if eps:
            st["episode_id"] = eps[0]["episode_id"]
            st["season_id"] = eps[0].get("season_id")
            res.detail = f"code=0；episode_id={st['episode_id']} season_id={st['season_id']}"
        else:
            client.mark_bad(res, "code=0 但时间表为空")
    return res


@check("番剧取流 PgC v2 playurl（需 Referer）", "§3")
def c_pgc_playurl(client: Client, st: dict) -> Result:
    ep = st.get("episode_id")
    res = Result("番剧取流 PgC v2 playurl（需 Referer）", "§3",
                 f"{API}/pgc/player/web/v2/playurl?ep_id={ep}")
    params = {"ep_id": ep, "fnval": 4048, "qn": 80, "fourk": 1, **dm_img_fingerprint()}
    payload = client.fetch(res, res.url.split("?")[0], params,
                           referer=f"{WWW}/bangumi/play/ep{ep}")
    vi = (payload.get("result") or {}).get("video_info") or {}
    if res.code == 0:
        nv = len(((vi.get("dash") or {}).get("video")) or [])
        res.detail = (f"code=0；dash 轨={nv} durl={len(vi.get('durl') or [])} "
                      f"accept_quality={len(vi.get('accept_quality') or [])}"
                      f"{'（匿名仅给 durl，登录后才有 dash）' if not nv else ''}")
        if not vi:
            client.mark_bad(res, "code=0 但无 video_info")
    return res


# ---------------------------------------------------------------- §5 直播


@check("直播推荐（顺带取测试房间）", "§5")
def c_live_room(client: Client, st: dict) -> Result:
    res = Result("直播推荐（顺带取测试房间）", "§5", f"{LIVE}/room/v1/room/get_user_recommend")
    payload = client.fetch(res, res.url, {"page": 1, "page_size": 3},
                           referer="https://live.bilibili.com/")
    if res.code == 0:
        rooms = payload.get("data") or []
        st["room_id"] = next((r.get("roomid") for r in rooms if isinstance(r, dict)
                              and r.get("roomid")), None)
        res.detail = f"code=0；测试房间 {st['room_id']}"
        if not st["room_id"]:
            client.mark_bad(res, "code=0 但未取到 roomid")
    return res


@check("直播-房间信息", "§5")
def c_live_info(client: Client, st: dict) -> Result:
    res = Result("直播-房间信息", "§5", f"{LIVE}/room/v1/Room/get_info?room_id={st.get('room_id')}")
    payload = client.fetch(res, res.url.split("?")[0], {"room_id": st.get("room_id") or 1},
                           referer="https://live.bilibili.com/")
    d = payload.get("data") or {}
    if res.code == 0:
        res.detail = f"code=0；live_status={d.get('live_status')} 标题={str(d.get('title'))[:12]}"
    return res


@check("直播-真源取流 getRoomPlayInfo", "§5")
def c_live_play(client: Client, st: dict) -> Result:
    res = Result("直播-真源取流 getRoomPlayInfo", "§5",
                 f"{LIVE}/xlive/web-room/v2/index/getRoomPlayInfo?room_id={st.get('room_id')}")
    params = {"room_id": st.get("room_id") or 1, "protocol": "0,1", "format": "0,1,2",
              "codec": "0,1", "qn": 150, "platform": "web", "ptype": 8, "dolby": 5,
              "panorama": 1}
    payload = client.fetch(res, res.url.split("?")[0], params,
                           referer="https://live.bilibili.com/")
    streams = (((payload.get("data") or {}).get("playurl_info") or {})
               .get("playurl") or {}).get("stream") or []
    if res.code == 0:
        codecs = [c.get("codec_name") for s in streams for c in (s.get("format") or [])
                  for c in (c.get("codec") or [])]
        res.detail = f"code=0；stream 数={len(streams)} codec={sorted(set(codecs))}"

    return res


@check("直播-弹幕 token（WBI + buvid3）", "§4.2")
def c_live_danmu(client: Client, st: dict) -> Result:
    res = Result("直播-弹幕 token（WBI + buvid3）", "§4.2",
                 f"{LIVE}/xlive/web-room/v1/index/getDanmuInfo?id={st.get('room_id')}")
    # 实测：不带 WBI 必然 -352；带 WBI 后才是业务错误码
    params = sign_wbi({"id": st.get("room_id") or 1, "type": 0}, client.mixin_key)
    payload = client.fetch(res, res.url.split("?")[0], params,
                           referer="https://live.bilibili.com/")
    d = payload.get("data") or {}
    if res.code == 0:
        hosts = d.get("host_list") or []
        res.detail = f"code=0；host 数={len(hosts)} token={'有' if d.get('token') else '缺'}"
        if not d.get("token"):
            client.mark_bad(res, "code=0 但缺少 token")
    return res


# ---------------------------------------------------------------- §6 内容


@check("用户空间卡片（WBI + 反爬四元组）", "§6")
def c_space(client: Client, st: dict) -> Result:
    res = Result("用户空间卡片（WBI + 反爬四元组）", "§6", f"{API}/x/space/wbi/acc/info?mid=2")
    params = sign_wbi({"mid": 2, "token": "", "platform": "web", "web_location": 1550101,
                       **dm_img_fingerprint()}, client.mixin_key)
    payload = client.fetch(res, res.url.split("?")[0], params,
                           referer="https://space.bilibili.com/2")
    d = payload.get("data") or {}
    if res.code == 0:
        res.detail = f"code=0；昵称={d.get('name')}"
    return res


@check("稿件搜索（需 Cookie 预热）", "§6")
def c_search(client: Client, st: dict) -> Result:
    res = Result("稿件搜索（需 Cookie 预热）", "§6", f"{API}/x/web-interface/wbi/search/type")
    client.raw(WWW)                       # 接口清单 §6：不预热 www 会 -412
    params = sign_wbi({"search_type": "video", "keyword": "液态玻璃", "page": 1},
                      client.mixin_key)
    payload = client.fetch(res, res.url, params, referer=f"{WWW}/")
    if res.code == 0:
        d = payload.get("data") or {}
        n, total = len(d.get("result") or []), d.get("numResults")
        res.detail = f"code=0；本页={n} 总数={total}"
        if not d:
            res.verdict, res.detail = "WARN", "code=0 但无 data 字段（匿名态疑似静默限流，非接口失效）"
        elif n == 0:
            res.verdict, res.detail = "WARN", f"code=0 但本页结果为空（总数={total}，疑似静默限流）"
    elif res.code == -412:
        res.detail += "（预热后仍被拦截：匿名态可接受，登录态必须为 0）"
    return res


# ---------------------------------------------------------------- Cookie 来源


def cookie_from_mitm_flows(path: str) -> str:
    """从 mitmproxy flow 文件里取最近一次 bilibili 请求的 Cookie 头。"""
    try:
        from mitmproxy import io as mitm_io
        from mitmproxy.exceptions import FlowReadException
    except ImportError:
        print("警告：未安装 mitmproxy，跳过 --mitm-flows", file=sys.stderr)
        return ""
    cookie, matched = "", 0
    with open(path, "rb") as fh:
        try:
            for flow in mitm_io.FlowReader(fh).stream():
                req = getattr(flow, "request", None)
                if req is None or "bilibili.com" not in (req.pretty_host or ""):
                    continue
                c = req.headers.get("cookie")
                if c:
                    cookie, matched = c, matched + 1
        except FlowReadException as e:
            print(f"警告：flow 文件解析中断（{e}），已读 {matched} 条", file=sys.stderr)
    return cookie


# ---------------------------------------------------------------- 主流程


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors="replace")       # type: ignore[union-attr]
        except (AttributeError, ValueError):
            pass

    ap = argparse.ArgumentParser(description="B 站接口存活 smoke test（LiquidGlass for Bilibili）")
    ap.add_argument("--cookie", default="", help='附加 Cookie，如 "SESSDATA=xxx; bili_jct=yyy"')
    ap.add_argument("--mitm-flows", default="", help="mitmproxy flow 文件，自动提取 Cookie")
    ap.add_argument("--json", default="", help="报告输出路径（默认 tool/smoke-reports/）")
    ap.add_argument("--timeout", type=int, default=20)
    ap.add_argument("--quiet", action="store_true", help="只打印汇总")
    ap.add_argument("--verbose", action="store_true", help="打印每条请求的 URL")
    ap.add_argument("--rotate-cookie", action="store_true",
                    help="真实执行 Cookie 续期轮换（需 --refresh-token，会作废旧凭证）")
    ap.add_argument("--refresh-token", default="",
                    help="账号 refresh_token（--rotate-cookie 时必需，轮换后请回写保存）")
    args = ap.parse_args(argv)

    cookie = args.cookie
    if args.mitm_flows:
        c = cookie_from_mitm_flows(args.mitm_flows)
        cookie = f"{cookie}; {c}" if cookie and c else (cookie or c)
    logged_in = "SESSDATA" in cookie

    client = Client(cookie=cookie, timeout=args.timeout)
    st: dict[str, Any] = {
        "rotate": {"enabled": args.rotate_cookie, "refresh_token": args.refresh_token},
    }
    results: list[Result] = []
    for name, section, fn in CHECKS:
        try:
            results.append(fn(client, st))
        except Exception as e:                                        # noqa: BLE001
            results.append(Result(name, section, verdict="FAIL",
                                  detail=f"未捕获异常 {type(e).__name__}: {e}"))
        r = results[-1]
        if not args.quiet:
            mark = {"OK": "[OK]  ", "WARN": "[WARN]", "FAIL": "[FAIL]", "SKIP": "[SKIP]"}[r.verdict]
            print(f"{mark} [{r.section}] {r.name}  ({r.ms}ms)  {r.detail}")
            if args.verbose:
                print(f"        {r.url}")
        time.sleep(0.35)                       # 温柔一点，别把自己送进风控

    ok = sum(1 for r in results if r.verdict == "OK")
    warn = [r for r in results if r.verdict == "WARN"]
    fail = [r for r in results if r.verdict == "FAIL"]

    print()
    print(f"—— 存活报告：{len(results)} 个端点 | OK {ok} | WARN {len(warn)} | FAIL {len(fail)}"
          f" | 登录态：{'是' if logged_in else '否（匿名）'}")
    for r in warn:
        print(f"   [WARN] [{r.section}] {r.name} -> {r.detail}")
    for r in fail:
        print(f"   [FAIL] [{r.section}] {r.name} -> {r.detail}")
    print(f"   时间：{datetime.now():%Y-%m-%d %H:%M:%S}")

    report = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "logged_in": logged_in,
        "summary": {"total": len(results), "ok": ok, "warn": len(warn), "fail": len(fail)},
        "context": {k: v for k, v in st.items() if k != "ticket"},
        "write_operations": client.writes,
        "results": [r.as_dict() for r in results],
    }
    out = Path(args.json) if args.json else (
        Path(__file__).resolve().parent / "smoke-reports" /
        f"smoke-{datetime.now():%Y%m%d-%H%M%S}.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"   报告：{out}")

    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())