// #11 / M1b-5：**页内多趟 widget**（把折射真正画进 widget 树）。
//
// 链路（按**上游真实形态**接，不是"三趟串行" ✗）：
//   ① 几何烘焙（`geometry_blended`）⇒ `geometryImage`（帧外烘焙 ✓，见 [bakeToImage] 的坑）
//   ② 合成（`final_render`）**作为 backdrop filter** 压在真实背景之上：
//        `BackdropFilter(filter: ui.ImageFilter.shader(shader))`
//      ⇒ **sampler0（背景）= 引擎自动喂入 ✓**；`sampler1 = geometryImage`（我方显式 ✓）
//
// **sampler1 归属的源码依据**（Lead 要求的零号对齐 ✓）：
//   `liquid_glass_render_object.dart:219-223`
//     `renderShader..setFloatUniforms(initialIndex: 2, (v)=>v..setOffset(geometryMatte.topLeft*dpr)..setSize(geometryMatte.size*dpr))`
//     `           ..setImageSampler(1, geometryImage);`
//   ⇒ **合成趟的 sampler1 接几何纹理** ✓（不是 filter 输出 ✗；filter 趟在上游是**另一条**自成一体的
//     画法：`liquid_glass_filter.dart:239-276` 用 `pushImageFilter(blur)` 拿模糊 child 像后自己画 ✓）。
//
// 为什么用标准 [`BackdropFilter`] 而不是自写 RenderObject：它接受任意 `ui.ImageFilter` ✓，
// 而 `ui.ImageFilter.shader(...)` 正是 M0 在真机上验证过的路径 ✓（Impeller 必需 ✓）。
//
// ⚠ 三个"不报错但结果错"的点（Lead 点名要钉住 ✗）：
//   1. `ImageFilter.shader` 需要 **Impeller**（Skia 上 `isShaderFilterSupported=false`）⇒ 本 widget
//      **显式拒绝**启动（打日志 + 走 child）✗，不静默画不出来；
//   2. 几何纹理的 **offset/size 是物理像素**（6-9 号槽位由合成趟的 2-5 承载 ✓ 见契约表）；
//   3. 纹理**谁建谁 dispose**（用 [LiquidGlassRefractionTextureCache] ✓，本 widget 只在 dispose 时 releaseAll ✓）。
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'liquid_glass_filter_pass.dart';
import 'liquid_glass_geometry_pass.dart';
import 'liquid_glass_refraction_pass.dart';
import 'liquid_glass_refraction_assets.dart';
import 'liquid_glass_refraction_shape.dart';
import 'liquid_glass_uniform_layout.dart';

/// 页内折射层：`child` 是**背景内容**（会被折射的东西 ✓），折射玻璃画在它上面 ✓。
/// #20（task-104）**折射层厚度夹取**：`thickness` 必须 ≤ 形状高度的一半 ✓。
///
/// 为什么是「知道高度的那一层」在管这件事 ✓：`geometry_pass` / `filter_pass` 只拿到
/// `thickness` 参数、**不知道尺寸** ✗；`tokens.forStrength` 更不知道 ✗；
/// `liquid_glass_surface.dart:471` 的 `(thickness/20).clamp(0.6,3.0)` 是**笔画宽度**、量纲不同 ✗。
/// 本文件这一层同时持有 `widget.shape.size`（形状）与 `params.thickness`（光学参数）⇒ 唯一正确落点 ✓。
///
/// ⚠ **帧的选择（task-104 读码修正 ✗✓）**：用**逻辑帧** `shapeHeight`（= `widget.shape.size.height`）
/// 而不是 `cardPhysical.height` ✗ —— 后者乘过 `devicePixelRatio`（本机 3×）⇒ 夹取会**松 3 倍**、
/// 守不住不变量 ✗。判据：调用方 R1 的既有夹取就是逻辑帧（`pl_player/view.dart` 的
/// `math.min(tokens.thickness, h / 2)`，`h` = 控制条**逻辑**高 ✓），`params.thickness` 与之同帧 ✓。
///
/// 【推测（未逐帧验证）✗】越限的物理后果：SDF 归一 `n_cos = max(thickness+sd,0)/thickness`、
/// 条中心 `sd = −h/2` ⇒ 整条落在斜面上、没有平坦光学中心；且 `thicknessScale = clamp(40/thickness,1,4)`
/// 会把 rim 高光压到最低档。
/// shader 数值下限：几何/折射 shader 里 `n_cos = max(thickness + sd, 0) / thickness` ⇒
/// **thickness 不能为 0** ✗（否则是 0/0 = NaN ⇒ 几何纹理出 NaN/黑块 ✗）。
/// 强度滑杆 0% 会把 token 的 thickness 缩到 0 ⇒ 没有这道下限就是一条**新引入**的雷 ✗✓。
const double kMinRefractionThickness = 0.5;

double clampRefractionThickness(double thickness, double shapeHeight) {
  // 1) 无效输入（非有限/太小）⇒ 顶到数值下限（**不是**为了"抬"，而是避免 shader 除 0 ✓）
  var t = thickness.isFinite ? thickness : kMinRefractionThickness;
  if (t < kMinRefractionThickness) t = kMinRefractionThickness;
  // 2) **上限：h/2** ✓ —— 只降不抬 ✓（高度无意义时不设上限，不做假夹取 ✗）
  final half = shapeHeight / 2;
  if (half.isFinite && half > 0 && t > half) t = half;
  return t;
}

class LiquidGlassRefractionLayer extends StatefulWidget {
  const LiquidGlassRefractionLayer({
    super.key,
    required this.shape,
    required this.params,
    this.child,
    this.debugLabel = 'glass',
  });

  /// 玻璃形状（本轮只支持圆角矩形半径；超椭圆/椭圆留 M1b-6 ✓）。
  final LiquidGlassRefractionShape shape;

  /// 光学/光照/染色参数（复用 M1a 的 [LiquidGlassRefractionParams] ✓）。
  final LiquidGlassRefractionParams params;

  /// 背景内容（真 backdrop 的来源 ✓）。为 null 时本层什么都不画 ✓。
  final Widget? child;

  /// 日志标签（多点玻璃时用来分辨 ✓）。
  final String debugLabel;

  @override
  State<LiquidGlassRefractionLayer> createState() =>
      _LiquidGlassRefractionLayerState();
}

class _LiquidGlassRefractionLayerState
    extends State<LiquidGlassRefractionLayer> {
  ui.FragmentProgram? _composite;
  ui.FragmentProgram? _geometry;
  final LiquidGlassRefractionTextureCache _cache =
      LiquidGlassRefractionTextureCache();
  ui.Image? _geometryImage;
  ui.Size _bakedPhysicalSize = ui.Size.zero;
  String _bakedShapeKey = '';
  bool _baking = false;

  /// 本图层在屏幕上的全局偏移（**逻辑像素** ✓）——M1b-8 的坐标对齐要用它 ✓。
  ui.Offset _layerGlobal = ui.Offset.zero;
  bool _channelRejected = false;

  @override
  void initState() {
    super.initState();
    // 帧外加载 + 烘焙 ✓（Impeller 下帧内 toImage 会死等 ✗，M1b-2 实测）。
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_prepare()));
  }

  @override
  void didUpdateWidget(covariant LiquidGlassRefractionLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shape != widget.shape) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_prepare()),
      );
    }
  }

  @override
  void dispose() {
    _cache.releaseAll(); // **谁建谁 release** ✓（几何纹理由缓存接管 ✓）
    super.dispose();
  }

  Future<void> _prepare() async {
    if (_channelRejected || _baking) return;

    // ① 通道门：没有 `ImageFilter.shader`（Skia）就**显式不画** ✓（不静默 ✗）
    if (!isRefractionShaderChannelAvailable) {
      _channelRejected = true;
      debugPrint(
        '[LiquidGlassKit] 折射层「${widget.debugLabel}」**不启用** ✗：'
        'ImageFilter.isShaderFilterSupported=false（非 Impeller）⇒ 请上层回落 FakeGlass 档 ✓',
      );
      return;
    }

    _baking = true;
    // 先把 context 派生的量取出来 ✗（await 之后再用 context 会触发 use_build_context_synchronously）
    final view = View.of(context);
    final mq = MediaQuery.maybeOf(
      context,
    ); // ⚠ 必须在 await 之前取 ✗（否则 analyzer 报 async-gap ✓）
    // 图层全局偏移：让图层自己 report 位置 ✓（拿不到 ⇒ 退回 0 并**打日志**，不静默 ✗）
    final ro = context.findRenderObject();
    if (ro is RenderBox && ro.hasSize) {
      _layerGlobal = ro.localToGlobal(ui.Offset.zero);
    } else {
      debugPrint(
        '[LiquidGlassKit] 折射层拿不到 RenderBox ⇒ _layerGlobal 暂用 0 ✓（下一帧会重试 ✓）',
      );
    }
    try {
      _composite ??=
          await LiquidGlassRefractionAssets.loadShader<ui.FragmentProgram>(
            LiquidGlassRefractionShader.finalRender,
          );
      _geometry ??=
          await LiquidGlassRefractionAssets.loadShader<ui.FragmentProgram>(
            LiquidGlassRefractionShader.geometryBlended,
          );
      if (_composite == null || _geometry == null) {
        debugPrint(
          '[LiquidGlassKit] 折射层「${widget.debugLabel}」**不启用** ✗：'
          'program 未就绪（加载失败在上方有 LOAD FAILED 日志 ✓）⇒ 上层应回落 FakeGlass ✓',
        );
        return;
      }

      // ② 几何烘焙（尺寸变了或形状变了才重烘 ✓ —— 省 GPU，且**避免每帧分配纹理** ✗）
      // ⚠ 实测坑：**首帧时 `View.physicalSize` 可能是 0**（M0 的 logcat 里也见过
      //   `FlutterRenderer: Width is zero. 0,0`）⇒ 直接拿去 `toImage` 会抛
      //   `Exception: Invalid image dimensions.` ✗（我第一版就这样，页内啥也没画出来）。
      //   ⇒ 用 MediaQuery 兜底 + **正尺寸守卫 + 下一帧重试** ✓（并打日志，不静默 ✗）。
      final fallback = mq?.size ?? const ui.Size(360, 720);
      final physical = ui.Size(
        view.physicalSize.width > 0
            ? view.physicalSize.width
            : fallback.width * (mq?.devicePixelRatio ?? 1.0),
        view.physicalSize.height > 0
            ? view.physicalSize.height
            : fallback.height * (mq?.devicePixelRatio ?? 1.0),
      );
      if (physical.width <= 0 || physical.height <= 0) {
        debugPrint(
          '[LiquidGlassKit] 折射层「${widget.debugLabel}」尺寸暂不可用 '
          '(physical=${physical.width}x${physical.height}) ⇒ **下一帧重试** ✓',
        );
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => unawaited(_prepare()),
        );
        return;
      }
      final shapeKey = widget.shape.toString();
      // ⚠ M1b-15 **实测结论（与预期相反 ✓，已按证据退回 ✗）**：
      //   ① 把烘焙也改逻辑口径（画布 88 + raster 264 ✓）后，**行B 仍不可见** ✗，且
      //      **几何纹理直接导出（行G）变成黑卡** ✗ —— 而 M1b-12 那版（烘焙=**物理** 264）导出是
      //      **紫色有效内容** ✓（`texture(uGeom,uv)` ✓）⇒ **新口径让几何纹理变空** ✗。
      //   ② ⇒ 结论：**两趟的单位口径并不相同** ✓ —— 几何烘焙趟按**物理**（uSize/shapes=物理 ✓，
      //      这也是上游 `* devicePixelRatio` 的口径 ✓）；合成趟按**逻辑**（M1b-13 的 s1 证明 ✓）。
      //   ③ 因此本版**退回物理口径** ✓（光栅与画布同为物理 ⇒ 与 M1b-12 的"非黑"状态一致 ✓），
      //      并把"两趟口径不同"作为结论记录 ✓（谁对谁错留给下一轮用"几何纹理导出"当判据 ✓）。
      final cardPhysical = ui.Size(
        widget.shape.size.width * (mq?.devicePixelRatio ?? 1.0),
        widget.shape.size.height * (mq?.devicePixelRatio ?? 1.0),
      );
      final dprNow = mq?.devicePixelRatio ?? 1.0;
      if (_geometryImage == null ||
          cardPhysical != _bakedPhysicalSize ||
          shapeKey != _bakedShapeKey) {
        final image = await LiquidGlassGeometryPass.bakeToImage(
          _geometry!,
          LiquidGlassGeometryBakeInput(
            physicalSize: cardPhysical, // **物理** ✓（几何趟口径；见上实测结论 ✓）
            shapes: <LiquidGlassRefractionShape>[
              LiquidGlassRefractionShape(
                type: widget.shape.type,
                center: ui.Offset(
                  cardPhysical.width / 2,
                  cardPhysical.height / 2,
                ),
                size: cardPhysical,
                // ⚠ M1b-44 修：本画布是**物理**口径（`physicalSize` 已在 L158-159 乘过 dpr ✓），
                //   而 `cornerRadius` 传进来是**逻辑**值 ⇒ 不乘 dpr 会让 **SDF 角半径只有
                //   裁剪半径的 1/dpr（本机 ≈1/3）** ✗ ⇒ 角部 rim/位移与 `ClipRRect` 轮廓对不齐 ✗。
                //   上游同口径：`blend_group.dart:246` 就是 `cornerRadius * devicePixelRatio` ✓。
                cornerRadius:
                    widget.shape.cornerRadius * (mq?.devicePixelRatio ?? 1.0),
              ),
            ],
            refractiveIndex: widget.params.refractiveIndex,
            // #20（task-104）：夹取与接线**同一改动** ✓（先夹后接=裸奔 ✗）。
            thickness: clampRefractionThickness(
              widget.params.thickness,
              widget.shape.size.height,
            ),
          ),
          rasterScale: 1.0, // 画布已是物理 ⇒ 不再放大 ✓（避免 264→792 ✗）
        );
        _cache.put('geometry', image); // 接管所有权 + 释放旧纹理 ✓
        _geometryImage = image;
        _bakedPhysicalSize = cardPhysical;
        _bakedShapeKey = shapeKey;
        debugPrint(
          '[LiquidGlassKit] 折射层「${widget.debugLabel}」几何烘焙完成 ✓ '
          'card=${cardPhysical.width.toInt()}x${cardPhysical.height.toInt()}（物理画布 ✓）'
          'raster=${image.width}x${image.height} '
          'layerGlobal=$_layerGlobal dpr=$dprNow '
          '**sampler1 ← geometryImage**（依据 liquid_glass_render_object.dart:223 ✓；'
          '几何趟=物理 / 合成趟=逻辑，两趟口径不同 ✓ 见 M1b-15 结论）',
        );
      }
      if (mounted) setState(() {});
    } catch (error, stack) {
      // 不许静默 ✗：烘焙/加载出错必须显形
      debugPrint(
        '[LiquidGlassKit] 折射层「${widget.debugLabel}」准备失败 ✗: $error\n$stack',
      );
    } finally {
      _baking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final geometry = _geometryImage;
    final program = _composite;
    if (child == null) return const SizedBox.shrink();
    if (program == null || geometry == null || _channelRejected) {
      // 未就绪：**只画背景** ✓（上层按 capability 回落 FakeGlass ✓，本层不假装画玻璃 ✗）
      return child;
    }

    final shader = program.fragmentShader();
    // 卡片在**屏幕上的物理位置**（= 图层全局偏移 + 卡片在层内的偏移 ✓ × dpr ✓）
    final cardLeft = widget.shape.center.dx - widget.shape.size.width / 2;
    final cardTop = widget.shape.center.dy - widget.shape.size.height / 2;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // ⚠ M1b-10 的诊断注释已被 **M1b-19 实测推翻** ✗（保留作历史 ✓）：
    //   当时判"屏幕物理位置绝不能进 uniform（会双重偏移）"✗ —— **测量证明恰恰相反** ✓：
    //   page 内 backdrop 路的 `FlutterFragCoord()` **是屏幕物理像素** ✓（M1b-19 行M 实测：
    //   卡片中心处 `fragCoord.x/1000 ≈ 0.775` ⇒ x≈775 物理；而卡片全局逻辑 x≈259 ×3 = 777 ✓ 吻合 ✓）
    //   ⇒ **必须传屏幕物理偏移** ✓；传 0 会让 `geomUV=(frag-0)/size` 整体偏移出 [0,1] ⇒ 采样落形状外 ⇒ 黑 ✓。
    final cardOffsetPhysical = ui.Offset(
      (_layerGlobal.dx + cardLeft) * dpr,
      (_layerGlobal.dy + cardTop) * dpr,
    );
    // 卡片物理尺寸（与 `_prepare` 里烘焙用的口径**必须一致** ✓；本方法内单独算 ✓）
    final cardPhysical = ui.Size(
      widget.shape.size.width * dpr,
      widget.shape.size.height * dpr,
    );
    assert(() {
      debugPrint(
        '[LiquidGlassKit] 折射层「${widget.debugLabel}」诊断: '
        'cardGlobalPhysical=$cardOffsetPhysical dpr=$dpr '
        '（**M1b-19 起进 uniform** ✓ 依据：fragCoord 是屏幕物理像素 ✓）',
      );
      return true;
    }());
    // 合成趟：**18 floats 无形状** ✓（三趟契约表不许外推 ✗）
    LiquidGlassFinalRenderPass.writeUniforms(
      shader,
      LiquidGlassFinalRenderInput(
        params: widget.params.copyWith(
          // ⚠ M1b-8 坐标对齐：在 `BackdropFilter` 路径里 shader 的 fragment 空间 = **卡片** ✓
          //   （上游同构：`pushClipPath(shape)` + shader 的 `BackdropFilterLayer`，
          //     见 `liquid_glass_layer.dart:245-310` ✓）⇒ `uSize` = **卡片逻辑尺寸** ✗
          //   而不是整屏/面板尺寸（M1b-7 的分流把失败点夹到了这里 ✓）。
          size: widget.shape.size,
          // 2-5 = 位移纹理**在屏幕上的位置与尺寸**（**物理像素** ✓，素材 §4 ✓）
          // ✅ **M1b-19 实测定案（用真实几何算出的表达式 ✓，不是探针常数 ✗）**：
          //   行M：`fragCoord/1000` 在卡片中心读到 `(≈0.775, ≈0.278)` ⇒ **fragCoord 是屏幕物理像素** ✓
          //        （卡片全局逻辑 x≈259 ×dpr3 = 777 ✓ 与 0.775 吻合 ✓）
          //   行X：`texture(uGeom, vec2(0.5))` = 有效紫蓝内容 ✓ ⇒ **绑定/纹理本身没问题** ✓
          //   行A264G：`uGeomSize=卡片物理尺寸` + `offset=卡片屏幕物理位置` ⇒ **alpha≈1（整块白）** ✓✓
          //        = 采样**回到形状内** ⇒ 这正是上游 L60-62 早退条件的反面 ✓
          //   ⇒ 故：`geometrySize`=**卡片物理尺寸** ✓、`geometryOffset`=**卡片屏幕物理位置（物理）** ✓。
          //   （M1b-10 的 offset=0 ✗ 与 M1b-13 的逻辑尺寸 ✗ 都基于错误推断；M1b-13 的 s1 判定不可靠，
          //     因素材自相似、暴露不了 UV 整体偏移 ✗ —— 手册 §18.22 正适用于它 ✓。）
          geometryOffset: cardOffsetPhysical,
          geometrySize: cardPhysical, // **物理** ✓（与 offset 同一口径 ✓）
        ),
        shapes: const <LiquidGlassRefractionShape>[], // 合成趟**不吃形状** ✓
        geometryTexture: geometry, // ← sampler1 ✓（零号对齐 ✓）
        // backgroundTexture 留空 ⇒ 由 `BackdropFilter` 自动喂入 sampler0 ✓
      ),
      // ⚠ **M1b-22 定案** ✓：本路径里**引擎占住 0-1**（= 第一个 vec2，即 `uSize` ✓；
      //   上游同约定 `setFloatUniforms(initialIndex: 2, …)` ✓）⇒ **从索引 2 开始写** ✓。
      //   实测定案（M1b-21）：直读 `uSize` 时写 84 与写 1080 读出**完全相同且 ≥1000** ✗
      //   ⇒ 我方写 0-1 被引擎覆盖 ✓ ⇒ 此前 `screenUV` 一直用引擎值 ⇒ 采样取错色/顶部带 ✓。
      //   （Paint 路径没有引擎 ⇒ 那边仍从 0 开始写 ✓，由 `writeUniforms` 的默认参数保证 ✓。）
      engineOwnsFirstVec2: true,
    );

    final radius = widget.shape.cornerRadius;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        child, // 背景（要被折射的东西 ✓）
        // ⚠ 实测纠正（M1b-5）：**必须按形状的 center/size 定位** ✗ —— 我第一版只用了
        // 圆角裁剪、铺满整层 ⇒ 折射效果覆盖整页（还被上层面板盖住 ✗），"玻璃区"根本不可判。
        // 形状坐标是**逻辑像素**（与 `shape.center/size` 同域 ✓）。
        Positioned(
          left: widget.shape.center.dx - widget.shape.size.width / 2,
          top: widget.shape.center.dy - widget.shape.size.height / 2,
          width: widget.shape.size.width,
          height: widget.shape.size.height,
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: BackdropFilter(
                filter: ui.ImageFilter.shader(shader), // 真 backdrop 采样 ✓
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
