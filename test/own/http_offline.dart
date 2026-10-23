// SPDX-License-Identifier: GPL-3.0-or-later
//
// `test/own` 离线夹具（M3 提前启用；Lead 裁定：**先小爆炸半径证机制** ✓）。
//
// ## 用途
// 在需要渲染"会加载网络图"的组件/页面的套件里，于 `main()` 顶部调用
// [installOfflineHttp] —— 之后**任何真实 HTTP 请求立刻以 404 + 空体结束** ✓，
// 于是图片流马上进入错误/占位分支，`pumpAndSettle` 不再永久 loading ✓。
//
// ⚠️ **本夹具不是那次 12 分钟挂死的修复** ✗（Lead 裁定：写明以防后人误归因）：
//   真凶 = `liquid_ui_components_test.dart` 的 `tearDownAll` 里裸 `await Hive.close()` ✗
//   （判据：只跑预览页两组时**用例 4/4 全过**、卡的是 teardown ⇒ 与网络无关 ✓；已修 ✓）。
//   本夹具留作**未来真网络图组件的挂死防御层** ✓（请求抑制本身无害且合理 ✓）。
// ## 教训链（task-116 → 120 → 122）
// #26a 给 `LiquidCommentTile` 接上 `NetworkImgLayer` 后，组件套件出现
// **`+69 -2`**：一个断言红 ＋ 一个 **12 分钟 `tearDownAll` TimeoutException** ✗。
// 根因＝widget 测试里图片真发请求：flutter_test 默认 HttpClient 打回 400、而
// **图片流不结束** ⇒ `NetworkImage` 永远 loading ⇒ `pumpAndSettle` 永不稳定 ✗。
// 逐处给夹具去 URL 只能治本处（+61→+69 ✓）；残留挂死来自 `LiquidComponentsPreviewPage`
// （组件页、不在写范围 ✗）⇒ 结论：**离线是测试侧纪律，一次装、整套受益** ✓。
//
// ## 边界（为什么先只装在一个套件里）
// 上一轮我把它写成 `test/own/flutter_test_config.dart`（逐级向上覆盖**整个** test/own ✗），
// 结果与一处**编译错**叠加 ⇒ `+13 -3`、误归因 ✗。故本轮按 Lead 口径：
// **先在单个套件的 `main()` 里装、跑绿、再确认全 test/own 无外溢** ✓。
import 'dart:async';
import 'dart:io';

/// 装上离线 override（幂等；测试里只需在 `main()` 顶部调一次）。
void installOfflineHttp() {
  HttpOverrides.global = _OfflineHttpOverrides();
}

/// 恢复默认（需要真实网络的用例可在其内部临时 `HttpOverrides.runZoned` 覆盖）。
void uninstallOfflineHttp() {
  HttpOverrides.global = null;
}

class _OfflineHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _OfflineHttpClient();
}

/// 保底成员（Lead 圈定）：`getUrl/openUrl` → `close()` → 404 + `contentLength=0` + 空流 listen。
class _OfflineHttpClient implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Duration? connectionTimeout;

  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  int? maxConnectionsPerHost;

  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _OfflineRequest(url);

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('离线夹具：不允许真实网络（${invocation.memberName}）');
}

class _OfflineRequest implements HttpClientRequest {
  _OfflineRequest(this.uri);

  @override
  final Uri uri;

  @override
  final HttpHeaders headers = _OfflineHeaders();

  @override
  Future<HttpClientResponse> close() async => _OfflineResponse();

  @override
  Future<HttpClientResponse> get done async => _OfflineResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('离线夹具：不允许真实网络（${invocation.memberName}）');
}

class _OfflineResponse implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.notFound;

  @override
  String get reasonPhrase => 'Offline (test/own fixture)';

  @override
  int get contentLength => 0;

  @override
  HttpHeaders get headers => _OfflineHeaders();

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      const Stream<List<int>>.empty().listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('离线夹具：不允许真实网络（${invocation.memberName}）');
}

class _OfflineHeaders implements HttpHeaders {
  @override
  List<String>? operator [](String name) => null;

  @override
  String? value(String name) => null;

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('离线夹具：不允许真实网络（${invocation.memberName}）');
}