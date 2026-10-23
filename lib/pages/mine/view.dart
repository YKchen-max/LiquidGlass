import 'dart:async';

import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_menu_tile.dart';
import 'package:PiliPlus/common/widgets/liquid/liquid_solid_card.dart';
import 'package:PiliPlus/common/widgets/player_bar.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/models_new/fav/fav_folder/list.dart';
import 'package:PiliPlus/pages/common/common_page.dart';
import 'package:PiliPlus/pages/home/view.dart';
import 'package:PiliPlus/pages/login/controller.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/mine/controller.dart';
import 'package:PiliPlus/pages/mine/widgets/item.dart';
import 'package:PiliPlus/utils/bili_utils.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key, this.showBackBtn = false});

  final bool showBackBtn;

  @override
  State<MinePage> createState() => _MediaPageState();
}

class _MediaPageState extends CommonPageState<MinePage>
    with AutomaticKeepAliveClientMixin {
  final MineController controller = Get.putOrFind(MineController.new);
  late final MainController _mainController = Get.find<MainController>();

  @override
  bool get wantKeepAlive => true;

  bool get checkPage =>
      _mainController.navigationBars[0] != NavigationBarType.mine &&
      _mainController.selectedIndex.value == 0;

  @override
  bool onNotificationType1(UserScrollNotification notification) {
    if (checkPage) {
      return false;
    }
    return super.onNotificationType1(notification);
  }

  @override
  bool onNotificationType2(ScrollNotification notification) {
    if (checkPage) {
      return false;
    }
    return super.onNotificationType2(notification);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.secondary;
    return Column(
      children: [
        Padding(
          padding: const .symmetric(vertical: 10),
          child: _buildHeaderActions,
        ),
        Expanded(
          child: Material(
            type: .transparency,
            child: refreshIndicator(
              onRefresh: controller.onRefresh,
              child: onBuild(
                ListView(
                  padding: const .only(bottom: 100),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    _buildUserInfo(theme, secondary),
                    // #27 menu group A: the 4 entries from controller.list + the favorites row
                    // (originally the L455 ListTile semantics: tap to jump to /fav / trailing refresh /
                    // folder count, all preserved), liquid menu rows, solid rows with no real glass.
                    _buildContentMenu(secondary),
                    // The horizontal scroll list of favorites folders is kept as-is (FavFolderItem zero changes),
                    // only the outer ListTile shell is removed (the row semantics have already moved into menu group A).
                    Obx(
                      () => controller.loadingState.value is Loading
                          ? const SizedBox.shrink()
                          : _buildFavBody(
                              theme,
                              secondary,
                              controller.loadingState.value,
                            ),
                    ),
                    // #27 menu group B: the 5 navigation-type entries originally in the header icon row
                    // (comment history / incognito / account switch / theme / settings) are moved down,
                    // callbacks zero-change; see _buildAccountMenu.
                    _buildAccountMenu(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// #27 menu group A (content entries): the 4 items from controller.list are carried over
  /// **as-is** (icon/title/onTap zero changes, including the isLogin gate inside onTap),
  /// plus the favorites row——the original `_buildFav` L455 ListTile semantics decomposed and preserved:
  /// tap to jump to `/fav` (+_autoRefresh), trailing refresh button, folder count (suffix),
  /// chevron. The count was originally driven by the same Obx (loadingState and
  /// favFolderCount are written together), here we keep the same dependency.
  Widget _buildContentMenu(Color secondary) {
    return LiquidMenuGroup(
      children: [
        for (final e in controller.list)
          LiquidMenuTile(icon: e.icon, label: e.title, onTap: e.onTap),
        Obx(() {
          controller.loadingState.value; // subscription: refresh triggers count update
          return LiquidMenuTile(
            icon: Icons.star_border,
            label: '我的收藏',
            suffix: controller.favFolderCount != null
                ? Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      '${controller.favFolderCount}',
                      style: TextStyle(fontSize: 13, color: secondary),
                    ),
                  )
                : null,
            trailing: IconButton(
              tooltip: '刷新',
              onPressed: controller.onRefresh,
              icon: const Icon(Icons.refresh, size: 20),
            ),
            onTap: () => Get.toNamed('/fav')?.whenComplete(_autoRefresh),
          );
        }),
      ],
    );
  }

  /// #27 menu group B (account and settings): the 5 navigation-type entries from the original header icon row
  /// are **moved down as-is** (wireframe ⑥ slim top bar: only search/message badge remain in the top bar).
  /// Callbacks zero-change; the two reactive entries, incognito/theme, keep their Obx
  /// (icon and read-screen label follow state, same semantics as the original tooltip);
  /// switch-type rows do not draw chevron (they are not jumps).
  Widget _buildAccountMenu() {
    return LiquidMenuGroup(
      children: [
        if (GStorage.reply != null)
          LiquidMenuTile(
            icon: Icons.message_outlined,
            label: '评论记录',
            onTap: () => Get.toNamed('/myReply'),
          ),
        Obx(() {
          final anonymity = MineController.anonymity.value;
          return LiquidMenuTile(
            icon: anonymity ? MdiIcons.incognito : MdiIcons.incognitoOff,
            label: '无痕模式',
            semanticLabel: "${anonymity ? '退出' : '进入'}无痕模式",
            chevron: false,
            onTap: MineController.onChangeAnonymity,
          );
        }),
        LiquidMenuTile(
          icon: Icons.switch_account_outlined,
          label: '切换账号',
          onTap: () => LoginPageController.switchAccountDialog(context),
        ),
        Obx(
          () => LiquidMenuTile(
            // ThemeType.icon is an Icon widget; here we take its IconData and re-wrap it
            // with the menu row's unified caliber (same glyph as the original top bar).
            icon: controller.themeType.value.icon.icon ?? MdiIcons.themeLightDark,
            label: '切换至${controller.nextThemeType.label}主题',
            chevron: false,
            onTap: controller.onChangeTheme,
          ),
        ),
        LiquidMenuTile(
          icon: Icons.settings_outlined,
          label: '设置',
          onTap: () => Get.toNamed('/setting', preventDuplicates: false),
        ),
      ],
    );
  }

  Widget get _buildHeaderActions {
    const iconSize = 22.0;
    const padding = EdgeInsets.all(8);
    const style = ButtonStyle(tapTargetSize: .shrinkWrap);
    return PlayerBar(
      children: [
        if (widget.showBackBtn)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: BackButton(),
          )
        else
          const SizedBox.shrink(),
        Row(
          spacing: 5,
          mainAxisSize: .min,
          children: [
            if (!_mainController.hasHome) ...[
              IconButton(
                iconSize: iconSize,
                padding: padding,
                style: style,
                tooltip: '搜索',
                onPressed: () => Get.toNamed('/search'),
                icon: const Icon(Icons.search),
              ),
              msgBadge(_mainController),
            ],
            // #27: the 5 navigation-type entries——comment history / incognito / account switch / theme / settings——
            // have been moved to menu group B as liquid menu rows (_buildAccountMenu),
            // callbacks changed zero; the top bar keeps only search / message badge (wireframe ⑥ slim top bar).
            const SizedBox(width: 16),
          ],
        ),
      ],
    );
  }

  Widget _buildUserInfo(ThemeData theme, Color secondary) {
    // #27 profile card: liquid solid card shell (solid tier ⇒ this screen's real glass is 0 spots,
    // list/profile cards never use real glass §0.3). Avatar keeps NetworkImgLayer (T8 caliber,
    // no direct connection to cached_network_image), nickname/level badge/VIP pendant/coins·exp/
    // progress bar semantics preserved as-is; jelly press wraps the whole card,
    // inner tap/longPress/secondaryTap (login) contract unchanged.
    return LiquidSolidCard(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: _userInfoBody(theme, secondary),
      ),
    );
  }

  Widget _userInfoBody(ThemeData theme, Color secondary) {
    final style = TextStyle(
      fontSize: theme.textTheme.titleMedium!.fontSize,
      fontWeight: FontWeight.bold,
    );
    final labelStyle = theme.textTheme.labelMedium!.copyWith(
      color: theme.colorScheme.outline,
    );
    final coinLabelStyle = TextStyle(
      fontSize: theme.textTheme.labelMedium!.fontSize,
      color: theme.colorScheme.outline,
    );
    final coinValStyle = TextStyle(
      fontSize: theme.textTheme.labelMedium!.fontSize,
      fontWeight: FontWeight.bold,
      color: secondary,
    );
    return Obx(() {
      final userInfo = controller.userInfo.value;
      final levelInfo = userInfo.levelInfo;
      final hasLevel = levelInfo != null;
      final isVip = userInfo.vipStatus != null && userInfo.vipStatus! > 0;
      final userStat = controller.userStat.value;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: .opaque,
            onTap: controller.onLogin,
            onLongPress: () {
              Feedback.forLongPress(context);
              controller.onLogin(true);
            },
            onSecondaryTap: PlatformUtils.isMobile
                ? null
                : () => controller.onLogin(true),
            child: Row(
              mainAxisSize: .min,
              children: [
                const SizedBox(width: 20),
                userInfo.face != null
                    ? Stack(
                        clipBehavior: .none,
                        children: [
                          NetworkImgLayer(
                            src: userInfo.face,
                            type: .avatar,
                            width: 55,
                            height: 55,
                          ),
                          if (isVip)
                            Positioned(
                              right: -1,
                              bottom: -2,
                              child: SvgPicture.asset(
                                Assets.vipIcon,
                                height: 19,
                                semanticsLabel: "大会员",
                              ),
                            ),
                        ],
                      )
                    : ClipOval(
                        child: Image.asset(
                          width: 55,
                          height: 55,
                          cacheHeight: 55.cacheSize(context),
                          Assets.avatarPlaceHolder,
                          semanticLabel: "默认头像",
                        ),
                      ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: .min,
                    mainAxisAlignment: .center,
                    crossAxisAlignment: .start,
                    children: [
                      Row(
                        spacing: 6,
                        children: [
                          Flexible(
                            child: Text(
                              userInfo.uname ?? '点击登录',
                              style: theme.textTheme.titleMedium!.copyWith(
                                height: 1,
                                color: isVip && userInfo.vipType == 2
                                    ? theme.colorScheme.vipColor
                                    : null,
                              ),
                              maxLines: 1,
                              overflow: .ellipsis,
                            ),
                          ),
                          BiliUtils.levelPicture(
                            levelInfo?.currentLevel ?? 0,
                            isSeniorMember: userInfo.isSeniorMember == 1,
                            height: 10,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '硬币 ',
                              style: coinLabelStyle,
                            ),
                            TextSpan(
                              text: userInfo.money?.toString() ?? '-',
                              style: coinValStyle,
                            ),
                            TextSpan(
                              text: "      经验 ",
                              style: coinLabelStyle,
                            ),
                            TextSpan(
                              text: levelInfo?.currentExp?.toString() ?? '-',
                              style: coinValStyle,
                            ),
                            TextSpan(
                              text: "/${levelInfo?.nextExp ?? '-'}",
                              style: coinLabelStyle,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 225),
                        child: LinearProgressIndicator(
                          minHeight: 2.25,
                          value: hasLevel
                              ? levelInfo.currentExp! / levelInfo.nextExp!
                              : 0,
                          backgroundColor: theme.colorScheme.outline.withValues(
                            alpha: 0.4,
                          ),
                          valueColor: AlwaysStoppedAnimation<Color>(secondary),
                          stopIndicatorColor: Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: .spaceEvenly,
            children: [
              _btn(
                count: userStat.dynamicCount,
                countStyle: style,
                name: '动态',
                labelStyle: labelStyle,
                onTap: () => controller.push('memberDynamics'),
              ),
              _btn(
                count: userStat.following,
                countStyle: style,
                name: '关注',
                labelStyle: labelStyle,
                onTap: () => controller.push('follow'),
              ),
              _btn(
                count: userStat.follower,
                countStyle: style,
                name: '粉丝',
                labelStyle: labelStyle,
                onTap: () => controller.push('fan'),
              ),
            ],
          ),
        ],
      );
    });
  }

  Widget _btn({
    required int? count,
    required TextStyle countStyle,
    required String name,
    required TextStyle? labelStyle,
    required VoidCallback onTap,
  }) {
    return Flexible(
      child: InkWell(
        onTap: onTap,
        borderRadius: Style.mdRadius,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 80),
          child: AspectRatio(
            aspectRatio: 1,
            child: Column(
              spacing: 4,
              mainAxisSize: .min,
              mainAxisAlignment: .center,
              children: [
                Text(
                  count?.toString() ?? '-',
                  style: countStyle,
                ),
                Text(
                  name,
                  style: labelStyle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _autoRefresh() => Timer(
    const Duration(milliseconds: 150),
    () => controller.onRefresh(isManual: false),
  );

  // #27 dead-code note (not deleted, moved): the original `_buildFav` (Divider +
  // "My Favorites" ListTile + horizontal list) had its row semantics decomposed and moved into
  // `_buildContentMenu`'s favorites row (tap/refresh/count/chevron all preserved),
  // and the horizontal list body was promoted directly into the build list (_buildFavBody zero changes);
  // this method no longer has callers —— kept as a tombstone to prevent accidental recovery of the old shell.
  // Widget _buildFav(ThemeData theme, Color secondary) => see git history ui(#27).

  Widget _buildFavBody(
    ThemeData theme,
    Color secondary,
    LoadingState loadingState,
  ) {
    return switch (loadingState) {
      Loading() => const SizedBox.shrink(),
      Success(:final response) => Builder(
        builder: (context) {
          List<FavFolderInfo>? favFolderList = response.list;
          if (favFolderList == null || favFolderList.isEmpty) {
            return const SizedBox.shrink();
          }
          bool flag = (controller.favFolderCount ?? 0) > favFolderList.length;
          return SizedBox(
            height: 200,
            child: ListView.separated(
              controller: controller.scrollController,
              padding: const .only(left: 20, top: 10, right: 20),
              itemCount: response.list.length + (flag ? 1 : 0),
              itemBuilder: (context, index) {
                if (flag && index == favFolderList.length) {
                  return Padding(
                    padding: const .only(bottom: 35),
                    child: Center(
                      child: IconButton(
                        tooltip: '查看更多',
                        style: ButtonStyle(
                          padding: const WidgetStatePropertyAll(.zero),
                          backgroundColor: WidgetStatePropertyAll(
                            theme.colorScheme.secondaryContainer.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                        onPressed: () =>
                            Get.toNamed('/fav')?.whenComplete(_autoRefresh),
                        icon: Icon(
                          Icons.arrow_forward_ios,
                          size: 18,
                          color: secondary,
                        ),
                      ),
                    ),
                  );
                } else {
                  return FavFolderItem(
                    heroTag: Utils.generateRandomString(8),
                    item: response.list[index],
                    onPop: _autoRefresh,
                  );
                }
              },
              scrollDirection: .horizontal,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
            ),
          );
        },
      ),
      Error(:final errMsg) => SizedBox(
        height: 160,
        child: Center(
          child: Text(
            errMsg ?? '',
            textAlign: .center,
          ),
        ),
      ),
    };
  }
}
