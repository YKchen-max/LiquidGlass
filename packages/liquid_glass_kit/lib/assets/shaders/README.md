# liquid_glass_kit / 折射 `.iplr` 资产说明（生成物 + 复现配方）

这 4 个 `.iplr` 是**生成物**（不是手写资产）。为什么把它们**提交进库**：

- 折射 shader **不能**放进本包的 `flutter: shaders:` 构建期块 ✗ —— 那 4 个 `.frag` 的
  **SkSL 目标在 Windows 上必然编译失败**（#8 期实测），一旦放进去，**Windows 构建会整块坏掉** ✗✗；
- 也**不能**指望消费方去编译它们（消费方可能只是 Windows 构建 ✗）；
- ⇒ 因此改为：**由我方在受控环境预编译**出 Android 需要的目标阶段（`gles3 + vulkan`），
  作为**普通 asset** 打包；运行时 Android/Impeller 走 `FragmentProgram.fromAsset`；
  **Windows 永不选到折射档**（既有平台门），SkSL 路径**永不被触碰** ✓。

## 复现配方（本机已验证，task-25 / task-30 / M1a）

上游源码：`github.com/whynotmake-it/flutter_liquid_glass` →
`packages/liquid_glass_renderer/lib/assets/shaders/`
**固定 commit：`0968d9e63ec232f5ac1c915a4c4bd6a71aba8a0f`**（tag `liquid_glass_renderer-v0.2.0-dev.4`）
—— **不要用 `main`**（会漂移：`liquid_glass_final_render.frag` 在两者间就不同，4,420 vs 4,537 B）。

```powershell
# 关键三条（漏一条就失败）：
#   1) --include 必须同时给 SDK 的 shader_lib（提供 flutter/runtime_effect.glsl）
#                        和 shaders 目录（提供 shared.glsl / sdf.glsl / displacement_encoding.glsl）
#   2) 参数名是 --input= / --sl=（不是 --in/--out）
#   3) --spirv= 文档写可选，实际必填
$sdk   = 'E:\dev\flutter\bin\cache\artifacts\engine\windows-x64'
$shaders = '<上游 shaders 目录（含 4 个 .frag 与 render/sdf/shared/displacement_encoding.glsl）>'
& "$sdk\impellerc.exe" `
  --input="$shaders\liquid_glass_geometry_blended.frag" `
  --sl="$PWD\lib\assets\shaders\liquid_glass_geometry_blended.iplr" `
  --spirv="$PWD\.build\liquid_glass_geometry_blended.spirv" `
  --iplr `
  --include="$sdk\shader_lib" --include="$shaders" `
  --runtime-stage-gles --runtime-stage-gles3 --runtime-stage-vulkan
# 另 3 个同理：liquid_glass_filter / liquid_glass_arbitrary / liquid_glass_final_render
```

**自检（判断是否同源的最快方式）**：编出的 `.iplr` 尺寸/哈希与既有资产逐个对照 ——
> ⚠ **该行已于 2026-10-04 更正**：现行四份为 **51,272 / 68,384 / 14,880 / 37,952 B**
> （顺序：geometry_blended / filter / final_render / arbitrary ✓；`17,640 / 68,400 / 38,312` 是 M0 时代的旧值 ✗）。
> 原行（旧值）保留如下仅供对照：
> ~~本库当前 3 阶段产物尺寸为 **51,272 / 68,400 / 17,640 / 38,312 B**（顺序：geometry_blended /
filter / final_render / arbitrary）；`geometry_blended`、`filter`、`arbitrary` 三者与上游
"main 基线"资产**逐字节相同** ✓，`final_render` **不同**（正是 pinned 与 main 的源码差异 ✓）。
`.iplr` 的魔术字节是 `IPLR`、**不是** ASCII 的 `//` 或 `#version`（后者说明拿到的其实是源码 ✓）。

## 附：三条"玻璃不画"的首选探针（M0 结论，移植期直接沿用）

```
layer branch=…（确认走 shader 分支、widget.fake=false、isShaderFilterSupported=true）
shader assetKey=… loaded=true type=FragmentShader（键是否解析到、program 是否就绪）
renderObject attached=true backdropKey=null（渲染对象是否真的 attach；backdropKey 为 null 也能画 ✓）
```

**资产键的坑**（M0 根因）：同一个包**当依赖用**（资产挂 `packages/<name>/…`）与**当根用**
（裸 `lib/assets/…`）键**完全不同**，且解析失败是**静默**的 ✗ ⇒ 本包的键由
`lib/src/refraction/liquid_glass_refraction_assets.dart` **参数化**（默认本包名，可注入），
加载失败**必定打日志** ✓。

---

## ⚠ M1b-38（#11 移植期）对 `final_render` 资产做过的**唯一**改动

**改动**：删掉 `liquid_glass_final_render.frag` 里 **`screenUV` 的那一对 y 翻转**（上游 L44-46）：

```glsl
#ifdef IMPELLER_TARGET_OPENGLES
    screenUV.y = 1.0 - screenUV.y;   // ← 这一段被删除（连同 #ifdef/#endif）
#endif
```

**`geometryUV` 的那一对（上游 L49-51）保持原样未动** ✓。

> ### 🚨 2026-10-04 更正（受控编译实验 ✓，`docs/着色器分支普查与风险登记.md` + `.probe/m1b46/REPORT.md`）
>
> 本节的**旧指纹表**与**旧复现配方**都不再成立 ✗✓，务必按下面读：
>
> | | 尺寸 | sha256（前 16） | 状态 |
> |---|---|---|---|
> | M0 原件（地雷件 ✓） | 17,640 B | `8A24B132CB5F9852…` | 已被替换 ✗ |
> | M1b-38 那份（"只删 screenUV 一对" ✓） | 15,400 B | `A45F48A2CA0A5D89…` | 已被替换 ✗ |
> | **本库现用（M1b-43 条件式 ✓）** | **14,880 B** | **`371599370F071F03…`** | **现行 ✓** |
> | `geometry_blended` | 51,272 B | `C3C8DDE1BB9CDA43…` | 现行 ✓（**与 M0 的 `AAC7DE66…` 不同** ✗） |
> | `filter` | 68,384 B | `E773324B35D549B7…` | 现行 ✓（M0 是 68,400/`9D6DE2E0…` ✗） |
> | `arbitrary` | 37,952 B | `D09FB39503772219…` | 现行 ✓（M0 是 38,312/`0135FEC4…` ✗） |
>
> ⇒ **旧表"其余三份与 M0/上游逐字节相同"是错的** ✗；**尺寸/sha 只能说明"不同"，不能说明"同源"** ✓；
> 判同源要用**逐段三指纹**（vulkan 段 sha / GLES3 段 sha / GLES2 段 sha 全等 ✓）。
>
> **⚠ 旧配方是自毁路径** ✗✗：受控编译实验证明，**"仓库旗标 + `poc/shaders-src`（pristine）"重编** ⇒
> 产物 **15,128 B / `DB1E6F4E4D83126F…` / GLES3+GLES2 各 2 处翻转** ⇒ **与旧地雷件逐字节相同** ✗；
> 而且**没有任何旗标能救** ✓（impellerc **没有** `--target-platform` ✓；给了会被静默忽略 ✗；
> `--opengl-es` 直接编不过 ✗；`--define` 改不动 `#ifdef` ✗）⇒
> **唯一自变量 = 源里那 8 处 `#ifdef IMPELLER_TARGET_OPENGLES` 是否为真** ✓。
> **症状**：这回不是"变黑"，而是 **`geometryUV` 镜像 ⇒ α 落到形状外 ⇒ 早退 `vec4(0)` ⇒ 玻璃整块透明** ✗。
>
> **host 侧宏金丝雀**（零设备 ✓，与真机双通道 `R=1 G=1` 同口径 ✓）：
> 仓库配方产物的 GLES3 段读出 `fragColor = vec4(0.9375, 0.875, 0.375, 0.0625);` ⇒
> **`IMPELLER_TARGET_OPENGLES` = DEFINED 且 `IMPELLER_OPENGLES_UNFLIPPED_DEPRECATED` = DEFINED** ✓。

**复现配方（2026-10-04 更正版 ✓ —— 源码必须是"已改宏"的那份 ✗ 不是 pristine）**：

```powershell
$sdk = 'E:\dev\flutter\bin\cache\artifacts\engine\windows-x64'
# ⚠ 源必须是**已把 8 处 `#ifdef IMPELLER_TARGET_OPENGLES` 改成**
#    `#if defined(IMPELLER_TARGET_OPENGLES) && !defined(IMPELLER_OPENGLES_UNFLIPPED_DEPRECATED)`
#    的那一份（等价写法 `#if 0` 亦可 ✓）；**用 pristine `poc/shaders-src` 会编回地雷** ✗✗
$src = '<已改宏的源目录>'      # 含 shared.glsl / render.glsl / sdf.glsl / displacement_encoding.glsl
& "$sdk\impellerc.exe" `
  --input="$src\liquid_glass_final_render.frag" `
  --sl="$PWD\lib\assets\shaders\liquid_glass_final_render.iplr" `
  --spirv="$PWD\.build\liquid_glass_final_render.spirv" `
  --iplr --include="$sdk\shader_lib" --include="$src" `
  --runtime-stage-gles --runtime-stage-gles3 --runtime-stage-vulkan
# 自检（三条都要过 ✓）：
#   ① 产物应为 14,880 B / sha256 371599370F071F03…（= 现行件 ✓）
#   ② 若得到 15,128 B / DB1E6F4E…（= 旧地雷件）⇒ 说明源不是"已改宏"的那份 ✗
#   ③ 重编后**必须跑门禁**：`app\tool\preflight.ps1` 的 `shader asset scan` 步
#      （flip 文本扫描要求 0 命中 ＋ 四份 sha 金标准基线 4/4 ＋ 地雷件识别 ✓）
```

**为什么必须删（证据，真机 ZTE A2023 / Android 13 / arm64 / Impeller-Vulkan）**：

1. **那条 `#ifdef` 在我们的 Vulkan 构建里是"成立"的** ✗（与"Vulkan 下会被编译掉"的直觉相反 ——
   凡 `#ifdef` 是否成立**必须实测或静态验证，别按平台名猜**）；
2. 翻转后的 `screenUV` 指向**黑区** ⇒ 折射三采样全黑 ⇒ `refractColor ≈ 0` ⇒
   `finalColor.rgb = uGlassColor.rgb*a + refractColor.rgb*(1-a) = 0.102` ⇒ **整卡均匀 `(26,26,26)`**
   （`0.102 × 255 = 26`，逐位吻合）；
3. 同 body 对照：采样 `vec2(x, 1-y)` 的行只有签名绿 `(0,38,0)` ✓＝黑；采样 `screenUV`（不翻转）的行
   是素材 `(81,190.7,177.5)` ✓；**删掉翻转的整支**则出玻璃 `(69.7,154.6,176.3)`，唯一色 **4 → 135**；
4. **落进 kit 后复跑 `LiquidGlassRefractionLayer` 那一行**：`(26.2,26.2,26.2)/4 色` ⇒
   **`(78.1,148.4,169.9)/77 色`** ✓（探针一行未改 ⇒ 唯一变量就是本资产 ✓）。

**复现配方**：⚠ **本节这段旧配方已作废** ✗ —— 它写的"源码用 `poc/shaders-src/`（pristine）"**会逐字节编回旧地雷件** ✗✗
（见上方 **2026-10-04 更正** 里的更正版配方与三条自检 ✓）。旧原文保留在此仅供对照：

> ~~`--input=poc/shaders-src/liquid_glass_final_render.frag` + `--runtime-stage-gles/-gles3/-vulkan`；
> 自检：产物应为 15,400 B（sha256 `A45F48A2…`）~~ ⇒ **已作废** ✗（现行应为 **14,880 B / `371599370F071F03…`** ✓，
> 且**必须**是"已改宏"的源 ✓）

**遗留（M2 待办，勿当成已解决 ✗）**：
- `geometryUV` 的翻转**未动**，而几何采样目前是**正确**的 ✓（α 实测 = 1.000）⇒ 说明
  "`geometryUV` 翻转 + 现有 `bakeToImage` 产物"这一对是**自洽**的 ✓；但**两者中到底哪一侧"该翻"**
  尚未单独验证 ✗ —— 未来若改 `bakeToImage` 的朝向，**必须重测这一对** ✓。
- 顶部带 / 左边缘残影**未在移植期复验** ✗（探针里不出现该现象 ⇒ 需在真机 app 页面复验）。

---

## ⚠⚠ M1b-43（task-83）：**上一节的"删掉翻转"做法与"根因"结论都已被推翻并替换** ✗✓

**上一节（M1b-38）的问题**：它的基线是**上一轮实验件**（`port_clamped`，带 M1b-24 的 clamp ✗），
不是**原始上游源** ✗ ⇒ 那份"修复资产"里其实有**两处改动**（删翻转 ＋ 保留 clamp ✓），**不是单变量** ✗。
⇒ **教训（硬）**：**改动前必须确认基线是"原始件"还是"上一轮实验件"✓；确认方法是与原始件做 diff 并逐行解释，
不能靠 `#ifdef` 计数** ✗（计数看不出 clamp 差异 ✓）；并且**"编译配方"本身就是一个自变量** ✓ —— 换配方
必须与改源码**分别对照** ✓（本次 `orig_asis` 15,080 vs 条件式 14,880 的 Δ−200 B 才是同配方单变量账 ✓）。

### 现在落盘的四份（**原始上游源 + 只做上游那一处条件式宏改动** ✓）

| 资产 | 旧（本节之前） | **新（现行 ✓）** |
|---|---|---|
| `final_render` | 15,400 / `A45F48A2` | **14,880 / `37159937`** |
| `geometry_blended` | 51,272 / `AAC7DE66`（M0 原件） | **51,272 / `C3C8DDE1`** |
| `filter` | 68,400 / `9D6DE2E0`（M0 原件） | **68,384 / `E773324B`** |
| `arbitrary` | 38,312 / `0135FEC4`（M0 原件） | **37,952 / `D09FB395`** |

**改动内容（源 diff = 6 文件 × 14 行 = 7 处 × 2 行 ✓，其它文件 sha 与 pristine 相同 ✓）**：
把 `#ifdef IMPELLER_TARGET_OPENGLES` 换成上游写法
`#if defined(IMPELLER_TARGET_OPENGLES) && !defined(IMPELLER_OPENGLES_UNFLIPPED_DEPRECATED)` ✓
（7 处：`final_render` 的 `screenUV` ＋ `geometryUV` ✓、`geometry_blended` ✓、`filter` ✓、`arbitrary` ✓、
`render.glsl` 与 `shared.glsl` 的 `computeY()` ✓）。**不含 clamp** ✓（除非另行声明为第二自变量 ✓）。

**复现**：源在本仓库 `.probe/m1b43/src/**`（pristine 副本 + 仅改宏那一行 ✓）；
```powershell
$sdk = 'E:\dev\flutter\bin\cache\artifacts\engine\windows-x64\shader_lib'
$src = 'E:\Project\BILIBILI\.probe\m1b43\src'
& 'E:\dev\flutter\bin\cache\artifacts\engine\windows-x64\impellerc.exe' `
  --input="$src\liquid_glass_final_render.frag" --sl="$PWD\lib\assets\shaders\liquid_glass_final_render.iplr" `
  --spirv="$PWD\.build\fr.spirv" --iplr --include=$sdk --include=$src `
  --runtime-stage-gles --runtime-stage-gles3 --runtime-stage-vulkan
# 自检：应为 14,880 B / sha 37159937…；另三份 51,272（C3C8DDE1）/ 68,384（E773324B）/ 37,952（D09FB395）
```

### **为什么必须用这个条件式（= "为何需要新宏"）** ✓✓ —— 两条引擎事实（读数原文）

1. **本机运行时后端是 `OpenGLES3`** ✓ —— 引擎自己的报错原文：
   `Asset '…' does not contain appropriate runtime stage data for current backend (OpenGLES3).`
   （⇒ **"设备后端" ≠ "着色器阶段"** ✗：logcat 里的 "Impeller rendering backend (Vulkan)" 与着色器后端是两码事 ✓）；
2. **两个宏在本机都成立** ✓ —— 双通道金丝雀读数 `平均色=[207. 207. 64.9]` ⇒ **R=1**（`IMPELLER_TARGET_OPENGLES` ✓）
   **G=1**（`IMPELLER_OPENGLES_UNFLIPPED_DEPRECATED` ✓）⇒ ⇒ **条件式在本机等价于"删掉翻转"** ✓✓。

### **真因（代码级证据 ✓✓）**：GLES3 段里的那两行翻转

把资产里的 `#version 300 es` 文本段切出来对比（脚本 `.probe/diff_glsl_sections.py` ✓）：
- **黑资产（旧 `final_render` / M0 17,640）** 的运行段里有：
  `_191.y = 1.0 - _190;` ＋ `_203.y = 1.0 - _203.y;`（**两处翻转** ✓），采样用翻转后的坐标 ✓；
- **新资产（14,880）** 的同一段：`highp vec2 _115 = vec2(_fragCoord.x / uSize.x, _fragCoord.y / uSize.y);`（**无翻转** ✓）。
⇒ **"y 翻转 ⇒ 采样落到镜像位置 ⇒ 采到黑"在编译代码层面成立** ✓✓；`filter` / `arbitrary` 的旧件同样带翻转 ✓（新件已去掉 ✓）；
`geometry_blended` 两侧**无差异** ✓（该处改动在本机是**惰性的** ✓，如实记 ✓）。

### ⚠ 方法论教训（本轮代价最大的一条 ✓✓）

**"并排对比"必须在同一屏幕位置（同一行/同一 slot）进行** ✗ —— 否则**翻转后的镜像落点不同**，
"亮/黑"取决于**那一行的镜像位置有没有内容** ✓ ⇒ 我此前据此得出的**三次"翻转被否掉"结论全部是位置混淆造成的** ✗✓
（例：屏上 y≈350 的行 ⇒ 镜像 ≈2050 ⇒ 落在页面外的黑区；y≈1286 的行 ⇒ 镜像 ≈1114 ⇒ 落在有内容的区域 ✓）。
**⇒ 换件 A/B 的判据必须写死"同位置"，并且"验证编译产物（切 GLSL 段）"比"猜机制"省得多** ✓✓。