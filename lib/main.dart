import 'dart:io';

import 'package:PiliPlus/build_config.dart';
import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/common/widgets/back_detector.dart';
import 'package:PiliPlus/common/widgets/custom_toast.dart';
import 'package:PiliPlus/common/widgets/route_aware_mixin.dart';
import 'package:PiliPlus/common/widgets/scale_app.dart';
import 'package:PiliPlus/common/widgets/scroll_behavior.dart';
import 'package:PiliPlus/debug/glass_frame_timing.dart';
import 'package:PiliPlus/utils/error_reporter.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/models/common/theme/theme_color_type.dart';
import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';
import 'package:PiliPlus/router/app_pages.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/services/logger.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/utils/cache_manager.dart';
import 'package:PiliPlus/utils/glass_accessibility.dart';
import 'package:PiliPlus/utils/calc_window_position.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/extension/core_palettes_ext.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/font_utils.dart';
import 'package:PiliPlus/utils/json_file_handler.dart';
import 'package:PiliPlus/utils/max_screen_size.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/request_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/theme_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:catcher_2/catcher_2.dart';
import 'package:collection/collection.dart';
import 'package:dynamic_color/dynamic_color.dart' show DynamicColorPlugin;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    as flutter_l10n;
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_kit/liquid_glass_kit.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:window_manager/window_manager.dart' hide calcWindowPosition;

WebViewEnvironment? webViewEnvironment;

EdgeInsets? tmpPadding;

Future<void> _initDownPath() async {
  if (PlatformUtils.isDesktop) {
    final customDownPath = Pref.downloadPath;
    if (customDownPath != null && customDownPath.isNotEmpty) {
      try {
        final dir = Directory(customDownPath);
        if (!dir.existsSync()) {
          await dir.create(recursive: true);
        }
        downloadPath = customDownPath;
      } catch (e) {
        downloadPath = defDownloadPath;
        await GStorage.setting.delete(SettingBoxKey.downloadPath);
        if (kDebugMode) {
          debugPrint('download path error: $e');
        }
      }
    } else {
      downloadPath = defDownloadPath;
    }
  } else if (Platform.isAndroid) {
    final externalStorageDirPath = (await getExternalStorageDirectory())?.path;
    downloadPath = externalStorageDirPath != null
        ? path.join(externalStorageDirPath, PathUtils.downloadDir)
        : defDownloadPath;
  } else {
    downloadPath = defDownloadPath;
  }
}

Future<void> _initTmpPath() async {
  tmpDirPath = (await getTemporaryDirectory()).path;
}

Future<void> _initAppPath() async {
  appSupportDirPath = (await getApplicationSupportDirectory()).path;
}

/// 玻璃档位探测（排期 #9）。
///
/// * 结果落盘到 app support 目录：下次启动直接复用，真出过问题的机器会被 latch 记住；
/// * `LIQUID_GLASS_TIER` 环境变量可强制档位（refraction / fakeGlass / solid），
///   便于不重编译就验证三档表现（例：`$env:LIQUID_GLASS_TIER='solid'`）。
Future<void> _initLiquidGlass() async {
  LiquidGlassTier? forced;
  final env = Platform.environment['LIQUID_GLASS_TIER'];
  if (env != null) {
    for (final tier in LiquidGlassTier.values) {
      if (tier.name.toLowerCase() == env.toLowerCase()) {
        forced = tier;
        break;
      }
    }
  }
  await LiquidGlassRuntime.initialize(
    forcedTier: forced,
    // #11 接线（task-18）：折射 shader 是否就位，取决于有没有宿主注入的 provider。
    // 这里读注册表而不是写死 false —— 一旦 `LiquidGlassRuntime.refractionShaderProvider`
    // 被注册（资产/移植就位后），能力矩阵才会在支持的平台上选到 refraction；
    // 今天没注册 ⇒ 与接线前完全一致（Windows/Android 都走 FakeGlass）。
    // 双闸保护：能力侧还要求 shaderFilterSupported（task-13 的守卫），渲染侧
    // LiquidGlassSurface 再用 resolveRenderTier 复核一次 shader 是否真的在手上。
    refractionShaderAvailable: LiquidGlassRuntime.refractionShaderAvailable,
    store: LiquidGlassFileProbeStore(
      File(path.join(appSupportDirPath, 'liquid_glass_probe.json')),
    ),
  );
  // #18 无障碍（task-93）：把运行时开关同步给 kit。
  // ⚠ 启动顺序修正（task-95 查出并定位根因，Lead 修 ✓✗）：**此处先不动** ——
  //   `GStorage.init()` 还没跑，这里读 Pref 会抛 ⇒ `_flag()` 的 catch 静默按"关" ⇒
  //   `tierCap` 永远保持 null ⇒ **设置项"重启后失效"**（env 路线与当次会话都正常 ✗ 唯独重启坏）。
  //   真正的同步在 `GStorage.init()` **之后**那一次（见 main() 里的第二次调用）。
  GlassAccessibility.syncRuntimeFlags();
}

void main() async {
  ScaledWidgetsFlutterBinding.ensureInitialized();
  GlassFrameTiming.install(); // task-85 §0.1.31：门控（kDebugMode && --dart-define），release 零行为
  MediaKit.ensureInitialized();
  await _initAppPath();
  // #20（task-98）：**错误通道挂接（一小段 ✓）** —— 钩子**可以**装在 `GStorage.init()` 之前 ✓
  // （本地落盘不依赖存储 ✓，且 `appSupportDirPath` 此时已就绪 ✓）；
  // ⚠ **读 Pref 开关**那一步必须排到 init 之后（见下面紧跟 §90 注释块之后的那次 applyPrefs ✓）。
  ErrorChannels.install();
  // 玻璃能力探测：失败不能拦住启动（内部已 try/catch，写盘失败也只是不落盘）
  try {
    await _initLiquidGlass();
  } catch (e) {
    debugPrint('[LiquidGlass] 能力探测失败，按默认档位继续：$e');
  }
  try {
    await GStorage.init();
  } catch (e) {
    await Utils.copyText(e.toString(), needToast: false);
    if (kDebugMode) debugPrint('GStorage init error: $e');
    exit(0);
  }
  // ⚠ task-95 真 bug 修复（⑥ 持久化失效）：**存储就绪之后再同步一次** ✓ ——
  // `_initLiquidGlass()` 里那次跑在 `GStorage.init()` 之前，读 Pref 必抛、被静默按"关" ✗。
  // 这一次才让"设置项重启后生效"成立（降低透明 ⇒ `tierCap`；增强对比 ⇒ kit 标志）。
  // 若将来加新的"启动期同步"类开关（如 #19 的强度），**一律挂在这里**，别再放前面 ✗。
  GlassAccessibility.syncRuntimeFlags();
  ScaledWidgetsFlutterBinding.instance.scaleFactor = Pref.uiScale;
  await Future.wait([
    _initDownPath(),
    _initTmpPath(),
    CacheManager.ensureInitialized(),
    ?FontUtils.init(),
  ]);
  // #20（task-98）：**存储就绪之后**才读"错误报告"开关 ✓（§90 同一条铁律 ✗✓）。
  // 读失败 ⇒ **本地通道保持可用** ✓（不静默按"关"把保底判据掐掉 ✗）。
  try {
    await ErrorChannels.applyPrefs(
      localOn: Pref.errorReportLocal, // 默认 true ✓
      sentryOn: Pref.errorReportSentry, // 默认 false ✓；且 `SENTRY_DSN` 空 ⇒ 恒不生效 ✓
    );
  } catch (e) {
    debugPrint('[ErrorChannels] 读开关失败，本地通道保持可用：$e');
  }
  // #20 自检探针（**只在 `--dart-define=GLASS_ERROR_PROBE=throw` 时** ✓；不设 ⇒ 零行为 ✓）：
  // 抛一个真实的**未捕获异步异常**（走 `PlatformDispatcher.onError` ✓），消息里故意夹带
  // **哨兵串**（假 token/cookie/用户目录）⇒ 落盘文件必须看不到它们（脱敏的**真机**证据 ✓）。
  if (const String.fromEnvironment('GLASS_ERROR_PROBE') == 'throw') {
    Future<void>.delayed(const Duration(seconds: 4), () {
      throw StateError(
        'GLASS_ERROR_PROBE 自检 SESSDATA=FAKE_SENTINEL_SESSDATA_0001 '
        'Cookie=FAKE_SENTINEL_COOKIE_0002 C:\\Users\\sentinel_user\\x.txt',
      );
    });
  }
  Get
    ..lazyPut(AccountService.new)
    ..lazyPut(DownloadService.new);
  HttpOverrides.global = _CustomHttpOverrides();

  if (PlatformUtils.isMobile) {
    if (Platform.isAndroid) MaxScreenSize.init();
    await Future.wait([
      if (Pref.horizontalScreen) ?fullMode() else ?portraitUpMode(),
      setupServiceLocator(),
    ]);
  } else if (Platform.isWindows) {
    if (await WebViewEnvironment.getAvailableVersion() != null) {
      webViewEnvironment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          userDataFolder: path.join(appSupportDirPath, 'flutter_inappwebview'),
        ),
      );
    }
  } else if (Platform.isMacOS) {
    await setupServiceLocator();
  }

  Request();
  Request.setCookie();
  RequestUtils.syncHistoryStatus();

  SmartDialog.config.toast = SmartConfigToast(displayType: .onlyRefresh);

  if (PlatformUtils.isMobile) {
    SystemChrome.setEnabledSystemUIMode(.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
    );
    if (Platform.isAndroid) {
      FlutterDisplayMode.supported.then((mode) {
        final String? storageDisplay = GStorage.setting.get(
          SettingBoxKey.displayMode,
        );
        DisplayMode? displayMode;
        if (storageDisplay != null) {
          displayMode = mode.firstWhereOrNull(
            (e) => e.toString() == storageDisplay,
          );
        }
        FlutterDisplayMode.setPreferredMode(displayMode ?? DisplayMode.auto);
      });
    } else {
      ScreenBrightnessPlatform.instance.setAutoReset(false);
    }
  } else if (PlatformUtils.isDesktop) {
    FocusManager.instance.addEarlyKeyEventHandler(_onKeyEvent);

    await windowManager.ensureInitialized();

    final windowOptions = WindowOptions(
      minimumSize: const Size(400, 720),
      skipTaskbar: false,
      titleBarStyle: Pref.showWindowTitleBar
          ? TitleBarStyle.normal
          : TitleBarStyle.hidden,
      title: Constants.appName,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      final windowSize = Pref.windowSize;
      await windowManager.setBounds(
        await calcWindowPosition(windowSize) & windowSize,
      );
      if (Pref.isWindowMaximized) await windowManager.maximize();
      await windowManager.show();
      await windowManager.focus();
    });
  }

  if (Pref.dynamicColor) {
    await MyApp.initPlatformState();
  }

  if (Pref.enableLog) {
    // 异常捕获 logo记录
    final customParameters = {
      'Build Time': DateFormatUtils.format(
        BuildConfig.buildTime,
        format: DateFormatUtils.longFormatDs,
      ),
      'Commit Hash': BuildConfig.commitHash,
      'MPV Api Version':
          '${NativePlayer.apiVersion >> 16}.${NativePlayer.apiVersion & 0xFFFF}',
    };
    final fileHandler = await JsonFileHandler.init();

    Catcher2(
      [?fileHandler, const ConsoleHandler()],
      const MyApp(),
      logger: logger,
      customParameters: customParameters,
    );
  } else {
    runApp(const MyApp());
  }
}

KeyEventResult _onKeyEvent(KeyEvent event) {
  if (event.logicalKey == .escape && event is KeyDownEvent) {
    _onBack();
    return .handled;
  }
  return .ignored;
}

void _onBack() {
  if (SmartDialog.checkExist()) {
    SmartDialog.dismiss();
    return;
  }

  final route = Get.routing.route;
  if (route is GetPageRoute) {
    if (route.popDisposition == .doNotPop) {
      route.onPopInvokedWithResult(false, null);
      return;
    }
  }

  final navigator = Get.key.currentState!;
  if (navigator.canPop()) {
    navigator.pop();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static ColorScheme? _light, _dark;

  static (ThemeData, ThemeData) getAllTheme() {
    final dynamicColor = _light != null && _dark != null && Pref.dynamicColor;

    final ColorScheme lightScheme, darkScheme;
    if (dynamicColor) {
      lightScheme = _light!;
      darkScheme = _dark!;
    } else {
      final customColor = Pref.customColor;
      final brandColor =
          colorThemeTypes.elementAtOrNull(customColor)?.color ??
          Color(customColor);
      final variant = Pref.schemeVariant;

      lightScheme = brandColor.asColorSchemeSeed(variant, .light);
      darkScheme = brandColor.asColorSchemeSeed(variant, .dark);
    }

    return (
      ThemeUtils.lightTheme = ThemeUtils.getThemeData(
        colorScheme: lightScheme,
        isDynamic: dynamicColor,
      ),
      ThemeUtils.darkTheme = ThemeUtils.getThemeData(
        isDark: true,
        colorScheme: darkScheme,
        isDynamic: dynamicColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (light, dark) = getAllTheme();
    return GetMaterialApp(
      title: Constants.appName,
      theme: light,
      darkTheme: dark,
      themeMode: ThemeUtils.themeMode = Pref.themeMode,
      // #24b：material_ui 是 fork，自声明了自己的 MaterialLocalizations 类型；
      // 仅配 material_ui 委托时，import flutter/material 的组件（如
      // liquid_action_sheet 的 showModalBottomSheet）按 flutter 键查找会失败。
      // 追加 flutter_localizations 的 GlobalMaterial 委托，双键并存。
      localizationsDelegates: const [
        ...GlobalMaterialLocalizations.delegates,
        flutter_l10n.GlobalMaterialLocalizations.delegate,
      ],
      locale: const Locale("zh", "CN"),
      fallbackLocale: const Locale("zh", "CN"),
      supportedLocales: const [Locale("zh", "CN"), Locale("en", "US")],
      initialRoute: '/',
      getPages: Routes.getPages,
      defaultTransition: Pref.pageTransition,
      builder: FlutterSmartDialog.init(
        toastBuilder: CustomToast.new,
        loadingBuilder: LoadingWidget.new,
        notifyStyle: const FlutterSmartNotifyStyle(
          warningBuilder: NotifyWarning.new,
        ),
        builder: _builder,
      ),
      navigatorObservers: [
        routeObserver,
        FlutterSmartDialog.observer,
      ],
      scrollBehavior: PlatformUtils.isDesktop
          ? const CustomScrollBehavior()
          : null,
    );
  }

  static Widget _builder(BuildContext context, Widget? child) {
    final uiScale = Pref.uiScale;
    final mediaQuery = MediaQuery.of(context);
    final textScaler = TextScaler.linear(Pref.defaultTextScale);
    if (uiScale != 1.0) {
      child = MediaQuery(
        data: mediaQuery.copyWith(
          textScaler: textScaler,
          size: mediaQuery.size / uiScale,
          padding: tmpPadding ?? mediaQuery.padding / uiScale,
          viewInsets: mediaQuery.viewInsets / uiScale,
          viewPadding: tmpPadding ?? mediaQuery.viewPadding / uiScale,
          devicePixelRatio: mediaQuery.devicePixelRatio * uiScale,
        ),
        child: child!,
      );
    } else {
      child = MediaQuery(
        data: mediaQuery.copyWith(
          textScaler: textScaler,
          padding: tmpPadding,
          viewPadding: tmpPadding,
        ),
        child: child!,
      );
    }
    if (PlatformUtils.isDesktop) {
      return BackDetector(
        onBack: _onBack,
        child: _wrapLiquidGlassTheme(context, child),
      );
    }
    return _wrapLiquidGlassTheme(context, child);
  }

  /// 把玻璃主题挂到整棵树的上层（排期 #9）。
  ///
  /// 明暗取值刻意**不走 Theme.of(context).brightness**：MaterialApp 的 theme 变化自带
  /// 200ms AnimatedTheme，而 brightness 是非插值属性、在中点才翻转，会让玻璃过渡晚 ~100ms
  /// 才开始（叠成"两段式"动画）。这里直接用应用自身的 themeMode（system 时读平台亮度，
  /// 同样是瞬时值），玻璃的 200ms 插值就与用户的切换操作同拍。
  static Widget _wrapLiquidGlassTheme(BuildContext context, Widget child) {
    final brightness = switch (Pref.themeMode) {
      ThemeMode.dark => Brightness.dark,
      ThemeMode.light => Brightness.light,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    return LiquidGlassTheme(brightness: brightness, child: child);
  }

  /// from [DynamicColorBuilderState.initPlatformState]
  static Future<bool> initPlatformState() async {
    if (_light != null || _dark != null) return true;
    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      final colors = await DynamicColorPlugin.channel.invokeMethod(
        DynamicColorPlugin.methodName,
      );

      if (colors != null) {
        final corePalettes = CorePalettesExt.fromList(colors.toList());
        if (kDebugMode) {
          debugPrint('dynamic_color: Core palette detected.');
        }
        _light = corePalettes.toColorScheme();
        _dark = corePalettes.toColorScheme(brightness: Brightness.dark);
        return true;
      }
    } on PlatformException {
      if (kDebugMode) {
        debugPrint('dynamic_color: Failed to obtain core palette.');
      }
    }

    try {
      final Color? accentColor = await DynamicColorPlugin.getAccentColor();

      if (accentColor != null) {
        if (kDebugMode) {
          debugPrint('dynamic_color: Accent color detected.');
        }
        final variant = Pref.schemeVariant;
        _light = accentColor.asColorSchemeSeed(variant, .light);
        _dark = accentColor.asColorSchemeSeed(variant, .dark);
        return true;
      }
    } on PlatformException {
      if (kDebugMode) {
        debugPrint('dynamic_color: Failed to obtain accent color.');
      }
    }
    if (kDebugMode) {
      debugPrint('dynamic_color: Dynamic color not detected on this device.');
    }
    GStorage.setting.put(SettingBoxKey.dynamicColor, false);
    return false;
  }
}

class _CustomHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    // ..maxConnectionsPerHost = 32
    /// The default value is 15 seconds.
    //   ..idleTimeout = const Duration(seconds: 15);
    if (kDebugMode || Pref.badCertificateCallback) {
      client.badCertificateCallback = (cert, host, port) => true;
    }
    return client;
  }
}
