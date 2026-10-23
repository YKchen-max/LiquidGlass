import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/services/logger.dart';
import 'package:PiliPlus/utils/error_reporter.dart';
import 'package:catcher_2/catcher_2.dart';

class JsonFileHandler extends ReportHandler {
  final bool enableDeviceParameters;
  final bool enableApplicationParameters;
  final bool enableStackTrace;
  final bool enableCustomParameters;
  final bool printLogs;
  final bool handleWhenRejected;

  static Future<RandomAccessFile> _future = LoggerUtils.getLogsPath()
      .then((file) => file.open(mode: FileMode.writeOnlyAppend))
      .then((raf) => raf.writeFrom(const []))
      .then(_flush);

  JsonFileHandler._({
    this.enableDeviceParameters = true,
    this.enableApplicationParameters = true,
    this.enableStackTrace = true,
    this.enableCustomParameters = true,
    this.printLogs = false,
    this.handleWhenRejected = false,
  });

  static Future<JsonFileHandler?> init({
    bool enableDeviceParameters = true,
    bool enableApplicationParameters = true,
    bool enableStackTrace = true,
    bool enableCustomParameters = true,
    bool printLogs = false,
    bool handleWhenRejected = false,
  }) async {
    try {
      await _future;
      return JsonFileHandler._(
        enableDeviceParameters: enableDeviceParameters,
        enableApplicationParameters: enableApplicationParameters,
        enableStackTrace: enableStackTrace,
        enableCustomParameters: enableCustomParameters,
        printLogs: printLogs,
        handleWhenRejected: handleWhenRejected,
      );
    } catch (e, s) {
      logger.e('Init log file', error: e, stackTrace: s);
      return null;
    }
  }

  static Future<RandomAccessFile> _flush(RandomAccessFile raf) => raf.flush();

  static Future<RandomAccessFile> add(
    Future<RandomAccessFile> Function(RandomAccessFile) onValue,
  ) {
    return _future = _future.then(onValue).then(_flush);
  }

  @override
  Future<bool> handle(Report report) async {
    // #20（task-101）：**lgr/Catcher2 → ErrorChannels 的接线** ✓
    //   为什么在这里：`Catcher2`（`main.dart` 里 `Catcher2([fileHandler, ConsoleHandler()], …)`）
    //   才是**真正吃掉未捕获异步异常**的那一层（task-100 实证：探针异常被它的 handlers 报走 ✗，
    //   而同步路径的 `FlutterError.onError` 早已直接进 `ErrorChannels` ✓）。
    //   `ReportHandler.handle` 是它的**共同下游** ⇒ 在这里转发一行即可覆盖异步路径 ✓。
    //   ⚠ 去重由 `ErrorChannels` 收口负责 ✓（同步路径会经 `presentError` → 这里 ⇒ 同一对象**只能落一次** ✓）。
    unawaited(
      ErrorChannels.report(
        report.error,
        // ⚠ `Report.stackTrace` 的静态类型是 `Object` ✗ ⇒ 先判型再兜底（别丢栈信息 ✓）
        report.stackTrace is StackTrace
            ? report.stackTrace as StackTrace
            : StackTrace.fromString('${report.stackTrace}'),
        context: 'catcher2',
      ),
    );
    try {
      await _processReport(report);
      return true;
    } catch (exc, stackTrace) {
      logger.e(
        'Write Json Exception occurred',
        error: exc,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<void> _processReport(Report report) {
    if (printLogs) {
      logger.d('Writing report to file');
    }
    final json = report.toJson(
      enableDeviceParameters: enableDeviceParameters,
      enableApplicationParameters: enableApplicationParameters,
      enableStackTrace: enableStackTrace,
      enableCustomParameters: enableCustomParameters,
    );
    return add((raf) => raf.writeString('${jsonEncode(json)}\n'));
  }
}
