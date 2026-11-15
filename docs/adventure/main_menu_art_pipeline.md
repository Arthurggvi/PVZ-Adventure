# 主菜单母图与受光管线｜维护、调参、复现

> 本文保留已认可的 S3 局部样板。当前全景制作入口已转到 [全景静态受光与时段管线](main_menu_fullscene_pipeline.md)，其静态预览已完成待审。不要把下方历史样板范围当作当前全景进度。

更新：2026-11-12。主交接入口：`PVZ_Adventure_Project_Handoff.md` §5.1。本文只记录当前可执行的方法；源码优先，未实现的全景扩展不得写成已完成。

## 0｜权威入口与已完成边界

- 原生工具入口 **A**：`D:\Dev\Tools\ArtControl`；`config.json` 保存 Python/GIMP/Godot 路径，`artctl.py` 调用原生进程并保留日志。当前无新增付费软件、无额外常驻 MCP 服务。
- 母图与 UI 工作副本 **S2**：`A\runs\main-menu-master-stage2-20261112`。`MainMenu_Master_Working_v01.xcf` 是下一阶段 XCF 构建输入；`layer_profile_proposed.png`、`layer_console_proposed.png`、`layer_toolbar_expanded.png` 供整图占位预览读取。不可当作临时文件删除。
- 已批准的研究室样板 **S3**：`A\runs\main-menu-stage3-lab-20261112`。原图、结构数据、脚本、技术贴图与实际渲染结果均在此；`MainMenu_Lab_Lighting_Working_v02.xcf` 为分层查看/编辑工作文件。
- **唯一母图**：`S3\master_original.png`，1672×941；SHA256 `71ed1970fb89c206a4b97fd6dde9cca1c3792b23e3f6f574d0839b6dfdc2ed02`。1920×1080 是设计画布/预览规格，不能据此拉伸或改写母图坐标。
- 当前完成：研究室及有限邻近地面的灰度权重、大面法线、窗灯/溢光、同源昼夜参数与移动光向样板；用户已认可局部观感。其余区域仍保持原图。没有完成全景昼夜、船体动画、本机时钟绑定或正式菜单替换。
- 这些仓外路径属于**制作环境**。正式实装时只能使用仓内资源与配置，不能让游戏依赖 `D:\Dev\Tools`、生成脚本或某台机器的绝对路径。

## 1｜从源数据到预览的唯一链路

`master_original.png + annotations.json → build_maps.py → working_base.png / maps/*.png → presets.json + relight.gdshader → capture_lab.gd → renders/*.png / sweep/*.png → build_previews.py → previews/*`

`S2 的原生 XCF + 上述派生图 → build_lab_xcf.py → S3 的 v02.xcf → 保存后重新打开，检查原图和原生蒙版`

`test_acceptance.py` 是已有样板验收入口；执行须遵守工程 AGENTS 的授权要求。它不会替代人工检查边缘、色温、画面层级与 UI 可读性。

**来源纪律**：AI 只参与初始母图候选。锁定母图后，调色、遮罩、法线、灯光和预览均由原图及结构数据派生。不能使用另外生成的日/暮/夜图替代此链路；不能把生成图称作引擎渲染。所有需要运动并露出背面的对象，必须另外准备真实独立部件与缺失背景。

## 2｜想调整什么，应改哪里

下表路径均相对于 S3。A=重建贴图，B=Godot 渲染，C=重建 XCF，D=整理预览；对应命令见 §4。

| 调整目标 | 权威修改点 | 后续步骤 |
|---|---|---|
| 建筑边界、漏色、窗口覆盖不准 | `annotations.json` 的 `surfaces[].points`、`curved[].points/box`、`windows`、`foliage`、`ground`、`cast_shadow` | A→B→C→D |
| 某面受光方向 | `surfaces[].normal`；曲面形状由 `curved[].box/points` 和 `build_maps.py` 的曲面法线公式决定 | A→B→C→D |
| 某个建筑表面的受光权重 | `surfaces[].response` / `curved[].response`；植被、地面等系数仍在 `build_maps.py` | A→B→C→D |
| 白天/黄昏/夜间整体光色与强度 | `presets.json` 中对应状态的 `ambient`、`key`、`light` | B→C→D |
| 法线强度或开关 | `presets.json` 的 `normals`（0～1）；对应 shader `normal_strength`；`enabled=false` 完全返回原始母图 | B→C→D |
| 窗灯与近处溢光强度 | `presets.json` 的 `windows` / `spill`，对应 `window_energy` / `spill_energy` | B→C→D |
| 灯光颜色 | `relight.gdshader` 的 `light_added` 常量：窗灯 `(1,0.49,0.11)`、溢光 `(1,0.46,0.12)`；当前尚未外置参数 | B→C→D |
| 原图投影弱化、亮面压制、基础色明暗 | `build_maps.py` 的 `gain`、`bright`、`repair`；改的是可重建工作底图，不改母图 | A→B→C→D |
| 羽化宽度、玻璃/植被颜色筛选、溢光形状 | `build_maps.py` 的 `inside_feather` 调用、`green/blue`、`blur/spill/spot`；作用仍限定在标注多边形内 | A→B→C→D |
| 光向扫描路径/帧数 | `capture_lab.gd` 的 24 帧循环及 direction；帧数变更时同步 `build_previews.py` 的帧数断言、时长和报告 | B→D；截图组变化时 C |
| 局部裁切、对照板标题、GIF 速度 | `build_previews.py` 的 `box`、排版与 `duration=180`；`annotations.crop` 目前只是元数据，并未自动驱动裁切 | D |
| XCF 图层组织与默认可见性 | `build_lab_xcf.py`；原图保护组必须保留 | C |

**不能声称样板已完全配置化**：地面/投影羽化当前为 22/5 像素；窗光模糊 sigma=13、溢光系数=1.8；门前光斑中心 `(976,461)` 与范围 `65×20`；基础修整和颜色筛选系数仍在 `build_maps.py`，灯光颜色与溢光总系数在 shader。它们是明确可找的样板调整点，扩展全景时先提为区域配置，禁止为每栋建筑复制脚本。

## 3｜贴图、数值与分层约定

### 3.1 几何与法线

原图标注坐标为像素，X 向右、Y 向下。当前 shader 法线空间为 X 向右、Y 向上、Z 朝向观察者，RGB=`(N+1)/2`；运行时解码后归一化。平面直接使用人工确认的朝向，曲面使用简化结构公式；不把图像明度直接当作几何高度。

这是自定义 `CanvasItem` shader 的约定，不保证直接兼容其他引擎或任意切线空间贴图。切换材质前核对方向、Y 通道及中性法线。法线只改变表面受光，不能独自生成正确的几何投影、反射或全局照明。

### 3.2 灰度和通道

九张灰度源图：`scope`、`structure`、`ambient_weight`、`emissive`、`spill`、`repair_weight`、`ground_weight`、`foliage_weight`、`cast_shadow_weight`。数值为作用权重，不是九层高度。

- `maps/controls.png`：R=structure，G=ambient_weight，B=emissive。
- `maps/effects.png`：R=scope，G=spill，B=ground_weight；当前 shader 不直接读取 B，保留用途不能说成已有独立运行时效果。
- `repair_weight`、`foliage_weight`、`cast_shadow_weight` 等参与构建或诊断，并非九个运行时独立滑块。只改某张诊断 PNG 不会自动影响已经打包的通道或工作底图。
- 控制图/法线按数值读写，不作为颜色纹理进行额外颜色变换。当前 shader 明确执行颜色样本 sRGB↔linear 转换，保留现有采样约定，避免重复转换。遮罩边界、透明混合与缩放后的结果仍需实际检查。
- GIMP 中从灰度 PNG 取得数值后，原生蒙版使用 `Y u8` 写入/读取；不能把蒙版数据按 `Y' u8` 再做转换。此问题曾造成数值差异，修正后九张蒙版保存/重开一致。

### 3.3 XCF 与生成文件的所有权

v02.xcf 的 `00_ORIGINAL` 层内容和位置锁定；`60_LAB_BASE_REPAIR` 为可撤销修整；`70_LAB_GRAYSCALE_CONTROLS` 为灰度与原生蒙版；`75_LAB_SURFACE_DATA` 为法线/分区；`80_ACTUAL_GODOT_CAPTURES` 为已渲染参考层，默认显示白天。

**修改底层前先关闭 80 组，否则会被截图层盖住。** 重跑 `build_lab_xcf.py` 会从 S2 原件和当前派生输出重新建立 v02，不会吸收 v02 内未导出的手工编辑。

当前生成权威是母图、annotations、presets 与脚本；地图 PNG 和 XCF 内蒙版是派生结果。手工改蒙版必须先另存，明确回写/导入路径再进入构建；目前没有自动 XCF→annotations 反向同步功能。禁止维护两份相互覆盖的“权威”蒙版。

## 4｜复现与安全调整命令（Sancho 当前环境）

先读取 `A\config.json`，确认本机软件路径和依赖；当前使用 GIMP 3.0.4、Python 3.12.10（Pillow/NumPy/OpenCV）、Godot 4.7.2。`build_previews.py` 读取本机 `C:\Windows\Fonts\msyh.ttc` 画标题，字体不属于交付包。

为保留已批准样板，以下先在同一 runs 父目录下创建新调整目录，仅复制输入与脚本。不要搬走 S2；XCF 构建按相邻 S2 路径读取，整图 UI 合成还引用当前绝对 S2 路径。制作环境尚非可任意搬迁的一键独立包。

```powershell
$root = 'D:\Dev\Tools\ArtControl'
$src = Join-Path $root 'runs\main-menu-stage3-lab-20261112'
$work = Join-Path $root ('runs\main-menu-stage3-lab-adjust-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $work -ErrorAction Stop | Out-Null
$inputs = @('master_original.png','annotations.json','presets.json','build_maps.py',
  'relight.gdshader','capture_lab.gd','build_lab_xcf.py','build_previews.py','test_acceptance.py')
$inputs | ForEach-Object { Copy-Item -LiteralPath (Join-Path $src $_) -Destination $work -ErrorAction Stop }
$python = (Get-Content (Join-Path $root 'config.json') -Raw | ConvertFrom-Json).python
function Run-ArtPython {
  param([string[]]$Arguments)
  & $python @Arguments
  if ($LASTEXITCODE -ne 0) { throw "ArtControl failed: $LASTEXITCODE" }
}
# 在 $work 中改源数据；脚本相对自身目录寻找输入，--run-dir 不能代替复制脚本。
# A：重建工作底图与技术贴图。
Run-ArtPython -Arguments @((Join-Path $work 'build_maps.py'))
# B：在独立工程实际 GPU 渲染。不要换成 dummy/headless 输出冒充可见受光效果。
Run-ArtPython -Arguments @((Join-Path $root 'artctl.py'),'godot',(Join-Path $work 'capture_lab.gd'),'--run-dir',$work)
# C：保存并重开分层文件；内部包含原图与蒙版一致性检查。
Run-ArtPython -Arguments @((Join-Path $root 'artctl.py'),'gimp',(Join-Path $work 'build_lab_xcf.py'),'--run-dir',$work)
# D：整理对照图与 24 帧光向 GIF。
Run-ArtPython -Arguments @((Join-Path $work 'build_previews.py'))
```

修改前另存自己正在编辑的 XCF。只改灯光预设时可跳过 A；改边界、法线或构建系数必须从 A 开始。运行必须检查返回值与日志，不能仅以存在旧输出文件判成功。

获得明确验收授权后，运行已有 `python $work\test_acceptance.py`；不要默认对游戏做额外测试。该验收目前包含研究室像素数、固定尺寸等样板条件，扩展全景时必须更新失效范围，不能删除保护像素/源图一致性断言来“通过”。

## 5｜证据、交付与维护边界

- 原样板已有的证据：`acceptance_final.log`（八项通过）、`preview_verification.json`（处理范围外 1,430,077 像素在五种状态下差值为 0）、`xcf_verification.json`（原图锁定、九张原生蒙版重开一致）、`render_report.json`（真实 GPU 与输入参数）。它们证明当时那一版，修改后须重新核验，不能复用旧日志冒充新结论。
- 新预览至少保留原图/白天/黄昏/夜间、同光源法线关/开、独立窗灯关/开、移动光向、带 UI 全景。对照板只裁切/排版实际渲染，不能另行生图。局部样板周围仍是白天时，必须标明作用范围。
- 手机预览优先 Catbox；上传后实际下载并比对字节/哈希，HTTP 200 或空响应不算成功。失败可用其他文件托管，区分“已下载读回校验”和“仅上传回执大小/MD5 校验”。过期或未验证链接不写进权威流程。禁止把 token、上传私有回执或字体打进交付包。
- GIMP 3.0.4 退出的既有 `g_object_unref` 告警仍保留；成功输出曾通过重开/数值检查，但不能由此断言软件所有操作可靠。
- 本次文档整理只核对路径、字段、源码和历史证据，不重新运行样板测试或 GPU 烘焙，不改动样板素材、游戏代码或玩家存档。

## 6｜后续全景阶段（已形成独立 S4 制作入口）

1. 冻结 S3 为对照基线；先把羽化、颜色筛选、修整强度、光斑位置与灯色整理为可复用区域配置，复用同一计算与渲染链，不复制多套建筑脚本。
2. 标注全景可见区域：天空/远景、地面/道路/水面、家/图书馆/商店/研究室、港口/船/皮卡、主要植被与发光窗灯。不要求全部抠件，保持母图原像素；明确将来移动对象的遮挡与补底需求。
3. 扩展区域灰度控制与必要的大面法线。地面/水域优先低细节权重，避免让每片草和每条木纹都参与强烈法线反应；法线收益不明确的区域保留简化处理。
4. 用同一套全景时间状态同步驱动各区，交付完整白天/黄昏/夜间和连续参数过渡预览；UI 不参与场景压暗，保持入口、名字与工具栏可读。
5. 全景静态层级通过后，再提取船体等必要移动部件、补齐露出背景、加入风水烟等动态；最后绑定本机时间、正式接入主菜单并完成真实交互验收。此次批准不代表这些步骤已实施。

S4 已完成完整静态时段预览，具体源数据、调参和复现按新维护页执行；上述第 5 项动态及实装仍未实施。
