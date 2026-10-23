import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/api_type.dart';
import 'package:PiliPlus/utils/error_reporter.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

List<SettingsModel> get privacySettings => [
  // #20（task-98）：错误报告 —— **本地默认开** ✓（保底判据：无网/无 DSN 也能留一份 ✓）
  SwitchModel(
    title: '错误报告（本地）',
    subtitle: '把崩溃与异常写入应用目录 errors/（按天滚动，已脱敏；不上传）',
    leading: const Icon(Icons.bug_report_outlined),
    setKey: SettingBoxKey.errorReportLocal,
    defaultVal: true,
    onChanged: (value) {
      // 立刻生效（不必重启）：同步给通道汇总 ✓
      ErrorChannels.localEnabled = value;
    },
  ),
  // #20：Sentry 上报 —— **默认关** ✓（且 `SENTRY_DSN` 为空时恒不生效 ✓）
  SwitchModel(
    title: '错误报告（Sentry 上报）',
    subtitle: '仅在构建时配置了 SENTRY_DSN 时可用；上报前统一脱敏（token/cookie/用户名不落盘不外传）',
    leading: const Icon(Icons.cloud_upload_outlined),
    setKey: SettingBoxKey.errorReportSentry,
    defaultVal: false,
    onChanged: (value) {
      ErrorChannels.sentryEnabled = value && ErrorChannels.sentry.enabled;
    },
  ),
  NormalModel(
    onTap: (context, setState) {
      if (!Accounts.main.isLogin) {
        SmartDialog.showToast('登录后查看');
        return;
      }
      Get.toNamed('/blackListPage');
    },
    title: '黑名单管理',
    subtitle: '已拉黑用户',
    leading: const Icon(Icons.block),
  ),
  NormalModel(
    onTap: (context, setState) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('账号模式详情'),
          content: SelectionArea(
            child: SingleChildScrollView(
              child: _getAccountDetail(context),
            ),
          ),
          actions: [
            TextButton(
              onPressed: Get.back,
              child: const Text('确认'),
            ),
          ],
        ),
      );
    },
    leading: const Icon(Icons.flag_outlined),
    title: '了解账号模式',
    subtitle: '查看各个账号模式作用的API列表',
  ),
];

Widget _getAccountDetail(BuildContext context) {
  final children = <Widget>[];
  final theme = TextTheme.of(context);
  for (final i in AccountType.values) {
    final url = ApiType.apiTypeSet[i];
    if (url == null) continue;

    children
      ..add(Center(child: Text(i.title, style: theme.titleMedium)))
      ..add(Text(url.join('\n')));
  }
  return Column(
    spacing: 8,
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    children: children,
  );
}
