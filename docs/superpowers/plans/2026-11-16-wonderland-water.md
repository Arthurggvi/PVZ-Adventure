# 奇境大陆海洋与河流水面 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 先校准水域数据，再依次实现海洋、河流的连续水面运动，保持岸线、建筑及地图交互稳定。

**Architecture:** 沿用 `fx_regions.json` schema 1、1774×887 世界坐标和现有 8192×4096 分块底图。新增场景局部水面适配器，复用主菜单水面算法与参数校验，经 `world_map_effect_bus` 注册 `ocean`、`river`；所有图块使用同一世界 UV 与宿主显式动画时间。

**Tech Stack:** Godot 4.7.2、GDScript、CanvasItem shader、现有 Python 美术烘焙工具；不新增运行依赖或 Autoload。

**Spec:** 本轮用户要求的下一阶段准备；承接 `docs/superpowers/plans/2026-11-16-wonderland-8k.md`。本计划现已实装。用户补充海洋名为“致幻洋流”，要求漂移、扭转及极光感；实现与检查记录见 `docs/adventure/wonderland_water.md`。

## Global Constraints

- 复用当前工作区，不另建 worktree；原 AVIF、原始素材、用户存档及其他脏改保持完整。
- 保持 `art_layout.json` schema 3、世界尺寸 1774×887；相机默认可见世界高度 289.52。不以屏幕坐标或图块局部 UV 定义水纹。
- 岸线、码头、桥、船体及陆地位移严格为零；不重绘整张地图，不新增操作指导或开发状态文字。
- 依 `AGENTS.md` 默认不新增、不运行测试；仅在既有测试引用因接口变化而失效时同步修正。图形检查、导入解析不能写成测试通过。
- 图形验证使用数据盘独立临时目录及隔离 `user://`；启动前设置超时，终端、错误及引擎文件日志合计上限 8 MiB，刷错或挂起即停止本次进程树。保留最少必要证据，清理仅限本任务可重建产物。
- 完成后只提交本轮文件，本地 commit，不 push；蒙版、采样边与运行时存在资源依赖，本轮统一提交。

## Review Focus

1. 高清岸线与旧蒙版偏移：近景下不得拖动岸石、桥墩或陆地颜色；第一阶段核对。
2. 纹理跨块采样：统一相位还不够，位移采样必须有足够重叠像素；第二阶段核对。
3. 海河交界及窄河：不得重复叠加高光、反向流动或把河岸拉进水中；第二阶段B核对。
4. 暂停与开关恢复：暂停冻结相位，开关不重置时钟；第二阶段A、B核对。
5. 窗口尺寸和拖动：水纹不能跟随屏幕游动，地标点击、UI阻断与边缘导航不回归；第二阶段B核对。

## 第一阶段：校准 ocean / river 岸线与 flow

**文件：** 修改 `assets/adventure/wonderland/config/fx_regions.json`；在 `masks/water/runtime/` 新增三张技术图，保留旧蒙版作为输入。`tools/art/build_wonderland_water.py` 保存可复现的校准步骤，高清烘焙器扩充采样边。新增说明 `docs/adventure/wonderland_water.md`，记录实际通道编码和单位。

**交付接口：** `regions.ocean`、`regions.river` 保留 `kind`、`mask`、`flow` 路径，schema 仍为 1；共享全世界坐标。校准后统一 flow 为 RG 方向（0—1解码到−1—1）、B 速度权重、A 岸边衰减权重；先核对现有编码，必要时重烘焙，禁止只改解码造成含义倒置。

- [x] 将现有水域蒙版叠到新8K原图，分别核对海岸、岛屿、桥墩、码头、河流转弯及海河交界；删除陆地覆盖；入海口使用总和不超过一的软权重交叉渐变。
- [x] 在1774×887世界空间校准水域和连续流向，记录实际纹理分辨率；技术蒙版不为“8K”机械放大。岸边设置严格零位移带，向水内平滑衰减，窄河保留岸线安全范围。
- [x] 按同一世界 UV检查 mask / flow；保存最少的岸线与海河交界叠图，核对通道值域、尺寸、透明边缘及资源路径；此阶段不接入动态效果。
- [x] 更新校准说明和阶段状态，执行 `git diff --check`，纳入本轮统一提交。

## 第二阶段A：复用主菜单算法，先接海洋

**文件：** 新增 `scripts/adventure/world_map/world_map_water_effect.gd`、`shaders/adventure/wonderland/water_surface.gdshader`；修改 `world_map_assets.gd`、`wonderland_map.gd` 接入资源与实例。现有 `world_map_effect_bus.gd` 只在确需补契约时修改。复用 `scripts/ui/start_menu/coastal/water_effect.gd`、`effect_uniforms.gd` 和 `shaders/ui/main_menu/water_surface.gdshaderinc`，不改变主菜单已接受效果。

**接口：** 水面适配器提供 `configure(effect_id: String, assets: RefCounted, terrain_root: Node2D) -> bool`、`validate_profile(profile: Dictionary) -> String`、`apply_profile(profile: Dictionary) -> void`、`set_animation_seconds(seconds: float) -> void`、`set_effect_enabled(enabled: bool) -> void`。复用总线现有 `register_effect()`、`apply_profiles()`、`set_enabled()`；分别注册 `ocean`、`river`。

- [x] 适配器只持有本区域覆盖节点、私有材质和参数快照，复用底图纹理；失败保留静态地图。`profile.water` 交给现有 `water_effect.validate()`，地图层的幅度、波长及亮纹参数另做白名单、有限数和范围校验；总线全部校验成功后才提交。
- [x] 每块由 `pixel_origin`、`pixel_size`、`pixels_per_world` 还原世界位置，统一 `world_uv = world_position / vec2(1774.0, 887.0)`。波纹、flow、mask 都在此空间采样；include 的空间尺度参数统一解释为世界单位。
- [x] 复用 `water_surface_offset()`、`water_surface_shimmer()` 与 `water_effect.set_elapsed(seconds)`；所有块接收相同宿主秒数，不使用 shader `TIME` 或各块独立时钟。岸边零权重处恢复原像素；限制源采样也留在安全水域，禁止把陆地颜色采入水中。
- [x] 核算重叠边：所需像素至少为 `ceil(最大位移世界单位 × pixels_per_world) + 2`，超过现有两像素重叠时，先扩充采样边及声明。重叠部分采用一致裁切或无重复叠加合成，不因水面半透明形成亮缝。
- [x] 以海洋单一区域完成近景全周期观察、相邻块接缝与固定岸线核对；检查关闭恢复静态原图、暂停相位不变、恢复不跳回起点。记录实际窗口、周期、幅度和硬件，不把主菜单复用视为地图验收通过。
- [x] 将水面所需资源纳入既有首屏准备清单，仍走统一场景转换；更新状态说明，执行 `git diff --check` 后纳入本轮统一提交。

## 第二阶段B：同一适配器接河流并完成验收

**文件与接口：** 复用第二阶段适配器；在 `wonderland_map.gd` 注册 `river`，只调整 `fx_regions.json`、对应蒙版及必要参数。不要复制第二套时钟或另造河流总线。

- [x] 以海洋近景为先，再完成河流检查；沿已校准流向逐段检查窄河、弯道、桥下及入海口，分别调速和幅度，不改变海洋或主体相位。
- [x] 在当前固定近景下观察至少一个完整周期，检查首尾相位连续、相邻图块无可见接缝、岸线固定、海河交界没有双重高光；保留少量代表帧或一段有明确用途的短预览。
- [x] 在1066×600、较宽及较高窗口下拖动穿越图块和水域边缘；核对水纹锁定世界坐标、镜头不露图外、拖动不误点及UI阻断。逐项检查总开关、区域开关、暂停和恢复。
- [x] 对相同窗口与视角分别记录静态、仅海洋、海洋加河流的帧耗时、draw call及可获得的显存/内存数据，说明采样时长和条件；无法取得的数据明确留空，不声称“零开销”或未经测量的性能提升。
- [x] 更新 `docs/adventure/wonderland_water.md`：列出已通过项、未覆盖项、参数与最小证据位置；核对临时目录大小，按约定清理后本地提交，不 push。

## 完成边界

仅在海洋与河流同时满足无缝、固定岸线、近景全周期、开关/暂停恢复和窗口/拖动检查后，才把这两个区域标为已实现。瀑布、特殊区域、天气与关卡接入按此顺序留待后续独立阶段；本计划不提前实现或宣称它们可用。
