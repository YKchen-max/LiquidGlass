# LiquidGlassKit

LiquidGlass for Bilibili 的**液态玻璃材质层**（材质 token、折射 shader、三级降级策略）。

本包在阶段一（`docs/任务排期.md`）只建立骨架，实体实现分属后续任务：

| 里程碑任务 | 落到本包的内容 |
|---|---|
| #9 LiquidGlassKit v1 | 深浅双套材质 token、三级降级矩阵（真折射 → FakeGlass → 纯色）、GPU 探测/黑名单、`ThemeExtension` |
| #10 Windows FakeGlass 级增强 | blur + `TileMode.mirror`、`ColorFilter.matrix` 饱和度、Canvas 双描边高光 |
| #11 真折射 shader | 两遍管线（SDF/折射/色散/rim light），按素材文档 §5 十项清单过 Windows + Android |
| #12 shader 内容自适应染色 | shader 内求背景平均亮度 → mix 玻璃 tint |
| #19 玻璃强度滑杆 | 0-100% 映射 blur/折射/高光缩放 |

## 设计纪律

1. **零插件**：纯 Dart/Flutter 包，不引入任何 platform channel，避免抬高宿主 App 的构建面；平台相关能力（GPU 探测、窗口材质）后续另开可选 plugin 包。
2. **独立包**：玻璃层对外只暴露 `liquid_glass_kit`，业务代码通过它取材质，禁止在 `lib/` 里散落硬编码的玻璃参数——这是跟随上游 PiliPlus rebase 时控制冲突面的前提。
3. **降级优先**：任何玻璃组件都必须能在"无 shader 支持"的环境退化为半透明纯色，不允许出现"取不到 shader 就空白"的实现。

## 许可

GPL-3.0-or-later（与宿主项目一致，见 `LICENSE`）。本项目 fork 自 GPL-3.0 的 PiliPlus，整体必须 GPL-3.0 开源。
