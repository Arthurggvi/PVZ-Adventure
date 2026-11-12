# PVZ-Adventure｜唯一权威项目交接

更新：2026-11-12。**只记录权威路径、可复用管线、实施方法、有效约束和未关闭的验收边界。** 源码与实际资源优先于本文；“接入”“自动化通过”“实机视觉通过”必须分别表述。

## 0｜权威入口、施工纪律（先读）

- **工程与引擎**：`C:\Dev\PvZ\PVZ-Adventure`（Git `develop`）；Godot 4.7.2：`C:\Users\Arthu\Desktop\Godot_v4.7.2-stable_win64.exe`。Sancho 在线时优先远程只读审计，获授权后直接施工，避免让用户手工搬运文件。
- **本交接文档唯一原件**：`C:\Dev\PvZ\_reference\project_docs\PVZ_Adventure_Project_Handoff.md`。Git 跟踪入口 `docs/adventure/PVZ_Adventure_Project_Handoff.md` 是**同一 NTFS 硬链接**，不应独立编辑/替换。改动需原位写入，并用 `fsutil hardlink list` 验证仍为同一文件。
- **资源权威范围**：`res://assets/adventure/`（新增素材）、`res://assets/reanim/`（原版分件）、`res://animation/`、`res://scenes/`、`res://scripts/`、`res://resources/`。仓外 `C:\Dev\PvZ\_review\<module>` 用于临时审查；`C:\Dev\PvZ\_reference` 为持久参考。游戏运行时不能依赖仓外文件。
- **主菜单新美术制作入口**：`tools/art_bake/main_menu/menu.py` 与同目录README；当前9A建筑悬停/功能入口见 `docs/adventure/main_menu_entries_pipeline.md`。S8已通过，9A候选待审；正式启动菜单尚未替换。
- **施工顺序**：检查 Git 和连接 → 读本文及权威代码/资源 → 复现并定位根因 → 设计通用接口与状态所有权 → 直接重构旧实现 → Godot 导入/解析检查 → 按 AGENTS.md 在明确获授权时运行测试/实机验收 → 必要时 Catbox 手机验收 → 仅暂存本轮文件并提交。
- **仓库纪律**：先 `git status --short`、`git log -1`，保护并行工作区；禁止未授权的 `git reset`、`git clean`、`git add .` 和 `git push`。提交前 `git diff --cached --check` 并逐项核对暂存清单。被 `.gitignore` 忽略的新美术资源，必要时定向 `git add -f`。
- **架构原则**：一条权威数据与状态链；配置描述差异，组件实现机制。禁止针对某一关/植物/僵尸追加并行实现、补丁式坐标修正、冗余管理器或把重复接线留给后续开发者。

## 1｜核心系统权威总线

| 系统 | 唯一入口与维护边界 |
|---|---|
| 冒险关卡与续战 | `AdventureStageRegistry` / `AdventureStageCatalog` → `AdventureStageOverride` → `AdventureBattleEnvironmentAdapter` → `ResourceLevelData` / `AdventureSession.active_phase` → `AdventureBattleRuntime`、WavePlanner、BossDirector、`AdventureContinuationController`。进入不询问难度；普通结束后有钥匙可选择接续噩梦。 |
| 战场种植空间 | `board_definition`（单关覆盖/环境/ResourceLevelData）→ `MainGameManager._enter_tree()` → `BoardSceneAdapter` → `MainGameManager.board: BoardRuntime`。定义与运行时位于 `scripts/battle/board/`；配置/扩展指南 `docs/adventure/board_authoring.md`，见下方 §1.1。 |
| 战场水陆地形 | 显式布局由 `BoardTerrainDefinition` 决定单格能力、`BoardLaneDefinition` 决定出怪与清洁车；旧 `terrain_rows` 只由 BoardSceneAdapter 适配现有场景。两种布局配置不能同时使用，视觉分类不能代替逻辑能力。 |
| 水面视觉与接触 | `AdventureBattleEnvironment.water_surface_profile` → `BackgroundManager` → `WaterSurfaceController` / `WaterSurfaceProfile` → 同源 `WaterBodyArea`；泳池和局部水沟共享水面 Shader 与入水协议，详见 §2。 |
| 植物种植与承托 | 卡片 `HMCharacter.click_cell` → `PlantCell.create_plant` → 实体占用成功 → 卡片 `signal_card_use_end` 费用/冷却结算。`PlantCell` 持有地形条件、占格、承托层锚点；详见 §3。 |
| 研究室/植物卡牌 | `PlantCardInstance` / `PlantSpawnProfile` / `AdventureBattleAdapter` / `PlantSceneFactory`；合成、强化、转职、扣料经 `ResearchService → ResearchTransaction`。战场、卡面、技能书外观基于同一实例/阶段。 |
| 资产、存档、玩家 | `GlobalGameState.adventure_state` → `AdventureInventoryService` → SaveService / SaveFileStore；存档 `user://<profile>/GlobalSaveGame.json`。卡牌实例有独立 UID；玩家战斗效果取冻结快照，装备经事务服务处理。 |
| 天气/雨/镜头 | `StagePhaseDefinition.weather_sequence` → `BackgroundManager.transition_weather` → `BattleWeatherDirector` → 雨幕、雨声、`WeatherLensController` / 光场；详见 §4。 |
| 僵尸、墓碑、Boss | 僵尸等阶 catalog → binding/traits/species installer；墓碑 `gravestone_rules` → `AdventureGravestoneDirector` → TombStoneManager；Boss 由 ZombieManager / ZB000Base 管理阶段与统一 HUD，物种行为树独立。 |
| 调试 | `addons/pvz_cheat/`。修改器可快速布卡/物品/波次，但不能以绕开正常放置及扣费的结果代替完整玩法验收。 |

六关顺序：草坪、没落营地、墓地上游、墓地下游、下水道、埃德加神殿。非商业单机二创。

## 1.1｜种植空间：状态所有权与扩展边界

- **唯一所有权**：`BoardRuntime` 索引稳定 `cell_id`、逻辑 `address` 与平台，不复制占用。`PlantCell` 仍独占种植/升级/释放事务和承托层；`PlantCellManager` 不再自行生成矩阵，墓碑管理器不再维护 `all_is_tombstone` 冗余运行状态或改写格子列号。
- **配置入口**：`BoardDefinition` 声明离散点、平台、地形目录和攻击行；`BoardGridDefinition` 只是规则网格生成器。任意 position/size、稀疏地址、局部 hit_polygon、显式邻接均可配置。当前六关保留原布局，经旧场景适配进入同一管线，没有改成示例行列数。
- **运行时入口**：`game.board.cell_by_id/cell_at/row_cells/neighbors/horizontal_neighbors/right_of/nearest_cell/local_pitch`；移动走 `move_surface_to(surface_id, target, seconds)`，地形变更走 `set_cell_terrain(cell_id, terrain_id, keep_occupants=false)`。行副本只能枚举，禁止以 `[行][逻辑列]` 查询稀疏坐标；禁止缓存初始世界锚点。
- **运动与占用**：地块、植物、荷叶上层/壳层、受击盒和交互区域由同一平台节点平移；多格植物禁止跨独立平台。自动往返/显式过渡使用有效战斗时间并受暂停控制。移动不改 cell_id、攻击行或邻接，不通过逐个植物补偿坐标实现。
- **特殊地形**：能力位、承托能力、tags、具名禁种来源统一进入 ResourcePlantCondition。`BoardTerrainDefinition.create_behavior()` 是行为构造唯一入口；`BoardTerrainLayer.prepare()` 离树准备完整实例后再替换旧层，空场景/错误根类型必须拒绝且保留旧地形。行为继承 `BoardTerrainBehavior`，负责自身更新、移除清理和离树纯校验；`water_contact` 只提供同源接触体，水面美术仍须配套。
- **恢复事务**：`PlantCellManager` → `BoardRestoreTransaction.prepare/commit`；`BoardStateRestore` 准备平台/地形，`BoardRestoreEntities` 准备植物/墓碑/梯子。输入字段、物种/槽位、真实多格占用及结构关系全部预检，离树构造成功后才同步提交。失败返回 false，禁止跳过坏记录、部分恢复或重建失败后谎报成功。`board_state`/cell_id 保持原稳定身份协议，旧 row_col 仅兼容旧布局；恢复只允许空白场地。
- **提交边界**：恢复期间持有 BoardRuntime 唯一令牌，禁止回调重入；先完成全部实体和承托、从实际占用重建计数，再发布创建事件。`PlantPlacement` 是正常种植和读档共用的离树构造计划，`PlantCell.commit_prepared_plant` 是唯一挂载/占用入口；不要重新建立逐格读档旁路。
- **输入与放置资格**：HandManager 的进入/离开/刷新/点击共用 `_refresh_board_hover`；Board 拾取按 GUI 场景树优先级，保留菜单遮挡与点击目标一致性。普通僵尸卡预览/提交共用 `ZombieManager.can_place_zombie_at_cell`，同时检查行兼容、局部地形和活地块身份，不能再写独立的行类型等值比较。
- **边界**：已接入离散种植空间和平移平台；未引入连续无格种植、旋转缩放、运行时增删地块、跨攻击行迁移或自由寻路。背景、镜头、屋顶坡面、原版大型 Boss 演出与按像素/行计算的攻击仍须针对新几何配套核验。源码接入不等于任意布局已完成实机验收。

## 2｜通用水面：原版泳池与下水道 1、5 路

**权威路径**
- 战场底图：`res://assets/adventure/environments/battle_backgrounds/05_sewer_interior_water.png`（1400×600）。
- 下水道覆盖：`res://resources/adventure/stages/overrides/zombie_island_sewer.tres`，其中 `terrain_rows_override = [Pool, Land, Land, Land, Pool]`（对应整数 `[1,0,0,0,1]`）、`water_surface_profile` 指向 `res://resources/water/sewer_water.tres`。
- 通用视觉：`scripts/water/water_surface_controller.gd`、`scripts/water/water_surface_profile.gd`、`shaders/water/water_surface.gdshader`；接触体：`scripts/water/water_body_area.gd`。原版泳池由 `scripts/main_game_item/pool.gd` / `scenes/main_game_bg/pool.tscn` 接入同一 Shader，日夜参数在 `resources/water/pool_day.tres`、`pool_night.tres`。

**正确实现方法**
1. 水底纹理保留静态颜色、池壁和边界；水面独立渲染多频 UV 波纹与焦散。`WaterSurfaceProfile.regions` 使用**背景原图像素坐标**定义水域；改动底图时重新校准区域并实际看图，不能靠关卡 ID 或绘制后的屏幕坐标猜测。
2. `WaterSurfaceController.configure_background` 从同一 `regions` 创建水面 `ColorRect` 与 `WaterBodyArea` 碰撞矩形；`configure_sprite` 支持原版泳池独立贴图。每区域私有材质；游戏时间 `water_time` 受暂停控制，`set_intensity` 调节强度。
3. 僵尸 `SwimBoxComponent` 聚合 `WaterBodyArea` 接触；普通/潜水表现只处理首次入水/最后出水，避免相邻或重叠水格重复下沉。普通下沉使用固定基准和可取消过渡，旧异步回调不能覆盖新状态；不得恢复 `area.owner is Pool` 耦合。出怪行能力、单格种植能力与实际物理入水是分开的协议。
4. 改水路时必须同时检查底图、区域视觉、物理入水体、僵尸游泳状态、格子种植条件及泳池清洁车。只画绿水或只添水面 Shader 都不算完成。

**验证入口**：`res://tests/adventure/test_water_surface_integration.tscn`，检查区域、物理进入/离开、游戏帧推进、原版泳池协议。该测试通过只证明管线；完整战斗中的水波可见性、层级和游泳姿态仍须实机/逐帧视觉核验。

## 3｜种植事务与荷叶/花盆承托布局

**权威路径**
- `scripts/main_game_item/plant_cell.gd` 与 `scenes/ui/plant_cell.tscn`；基础承托类 `scripts/character/plant/plant_000_down_base.gd`；荷叶 `scenes/character/plant/plant_017_lily_pad.tscn`；空间/旧水陆行投影 `scripts/battle/board/board_scene_adapter.gd`，地形能力 `board_terrain_definition.gd`。
- 正式种植与特殊植物条件分别经 `PlantCell.create_plant` / `ResourcePlantCondition`；荷叶 `condition_017_lily_pad.gd`。水路原始条件为 `9`（空/水），荷叶成功占用 Down 槽后为 `17`（空/荷叶）；移除后恢复 `9`。

**不可违反的事务规则**
1. `Plant000DownBase.init_plant` **只初始化实体**，不得提前切换格子地形。正式 `create_plant` 经 `PlantPlacement.prepare` 与提交前复核，使用 `commit_prepared_plant` 写入 `plant_in_cell` 后，才由 `PlantCell._sync_support_terrain_condition()` 根据 Down 槽实际占用投影 `BoardTerrainDefinition.supported_flags`；释放/死亡时恢复原能力。不得回退到旧版位掩码异或翻转。
2. 放置失败应保持格子不变、卡牌不扣阳光；成功后经 `HMCharacter` 的成功信号由卡槽统一扣费/冷却。不能在植物脚本内私自扣阳光。需同时考虑读档、替换植物、铲除和重复种植。
3. `PlantNormContainer` 与 `PlantShellContainer` 是带锚点的 `Control`，**始终留在 PlantCell**。`scenes/ui/plant_cell.tscn` 中各自的 `Content: Node2D` 才是实际植物容器；`_attach_support_layers(support)` 将两块 Content 挂到 `support.down_plant_container` 并使用承托物 `plant_up_position` 定位；`_detach_support_layers()` 回到锚点并归零局部位置。不要重新挂载整个 `Control`，不要用曾缓存的全局坐标回填。
4. 植物的实体、壳体、放置虚影与承托位置必须引用同一组 `plant_container_node` 内容锚点；随荷叶浮动时上层一起移动，荷叶消失后回格子定位。荷叶承托偏移以资源配置为准，当前 `plant_up_position = Vector2(0,10)`；禁止给下水道、西瓜投手或单个植物加特判偏移。
5. 花盆与荷叶共用战场承托布局；花园专用 `PlantCellGarden` 是另一场景和生命周期，未经单独审计不应顺手更改。

**验证入口**
- `res://tests/adventure/test_ground_support_transaction.tscn`：预提交无副作用、成功/重复种植、释放后恢复条件、可重种、屋顶花盆。
- `res://tests/adventure/test_lily_pad_support_layout.tscn`：荷叶 + 西瓜投手正式放置、上层/壳体锚点、尺寸变化、随动、拆除及花盆复用。
- 已做真实工程素材的孤立场景前后烘焙对比；**尚不可代替下水道五行完整战斗画面的人工终验**。特别观察跨行、荷叶遮挡、第一/五路、西瓜投手与南瓜壳的稳定对齐。

## 4｜天气、光场、雨声：当前需要维护的接口

- **仅第四关墓地下游的噩梦阶段触发本次暴雨**；没落营地没有雨。关卡 `resources/adventure/stages/overrides/zombie_island_grave_downstream.tres` 引用 `nightmare_weather_sequence`、`weather_lens_profile`。不要把地区默认配置设成全程降雨。
- 时间轴 `resources/weather/grave_downstream_nightmare_weather.tres`（WeatherSequence / WeatherKeyframe）按 `0→6→15→26→36` 秒递增至暴雨；最后关键帧持续保持，除非显式请求新天气。暂停不能推进天气。暴雨视觉 `resources/weather/grave_downstream_storm_visual.tres`（RainVisualProfile），音频 `resources/weather/storm_rain_audio.tres`（RainAudioProfile）。
- `scripts/weather/battle_weather_director.gd` 为状态/过渡唯一导演；原雨景 `scenes/main_game_bg/rain.tscn` / `MainGameRain`、`RainStormRenderer`（分层雨幕、地面水花、风场）按强度驱动。SoundManager 统一混音，不要创建额外雨声播放器。
- 湿镜头统一 `scenes/weather/weather_lens.tscn` → `WeatherLensController` / `WeatherLensProfile`；光源统一 `WeatherLightField` / `WeatherLightProfile`，关卡预设 `resources/weather/grave_downstream_light_profile.tres`。Bloom、折射、水滴与鼠标擦除都从现有光场/镜头渲染管线实现；镜头擦除只影响水膜，不删除真实雨线或环境光。
- 主要调参先动配置资源，再审 Shader；GL Compatibility 运行、分辨率和 GPU 预算需要测量，不能凭 headless 成功宣称性能达标。全战斗雨景预览入口 `tools/weather_preview/battle_preview.tscn` / `render_battle.gd`；按正式 `--scene` 运行，不能用只有背景的 GIF 冒充完整战斗验收。

## 5｜美术/动画、僵尸、Boss：必要工作方法

- **PVZ 2009 手绘素材规范**：先读清单 → 核对复用件、轨道、尺寸、透明通道与锚点 → 仅有必要时写提示词并生成 → 审核 → 必要分层/拆件与真实 PNG/GIF 烘焙 → ZIP/实装/验收。母图结构与观感已通过时，局部明暗、颜色和遮罩优先确定性处理；不要因可修的局部缺陷重复重生整图。主菜单受光严格走 §5.1，禁止以生成式昼夜变体代替程序渲染。手机预览上传后须实际读回校验，失败使用已说明的备用入口，不虚构链接。
- **原版分件动画**：PvZ2 PAM 转换须保留稳定 ref ID、增量关键帧的继承、原始层级、显隐与事件帧；不能把画层顺序误当实例身份。全明星 `scenes/character/zombie/zombie_026_all_star.tscn` / `scenes/character/zombie/all_star_original_animations.tres` 可复查已建立的转换管线。
- **向日葵转职外观**：原版 `plant_002_sun_flower.tscn` + SunFlower_idle 动画/原 `assets/reanim` 分件；新资源 `assets/adventure/plants/sunflower/manifest.json`；接入 `scripts/adventure/plant_art/adventure_sunflower_promotion_art.gd`。原动画有 texture 轨道，不能直接改 Sprite.texture；需挂载随原动画运动的分件。战斗、卡面与技能书复用同一转职阶段逻辑。
- **僵尸等阶**：`scripts/adventure/adventure_zombie_tier_catalog.gd` → binding/traits/species installer；美术 `assets/adventure/zombies/tier_art_map.json`。固定格挡、二类防具、额外护甲、技能/抗性需独立算，不能只看总 HP；平衡基于整套植物/僵尸阵容与实战消耗（五阶主要对标十星植物），不要做单卡云比较。
- **墓碑/Boss**：`StagePhaseDefinition.gravestone_rules` / `AdventureGravestoneDirector` / TombStoneManager，墓碑的刷新/复生必须使用本格实际生成点；常规旗帜刷怪和特定 Boss 复生的规则分别配置。Boss 统一血条/阶段状态，经 `ZB000Base`、ZombieManager、SoundManager 管线；美术封口不等于行为树和实战验收完成。黑将军实体 `scenes/character/zombie_boss/zombie_boss_002_black_general.tscn`，不要把旧策划数值当作工程当前实际配置。

## 5.1｜主菜单：建筑悬停与功能入口 9A（候选待审）

- **当前入口**：`tools/art_bake/main_menu/menu.py entries`，详见[建筑入口交接](main_menu_entries_pipeline.md)。S8风动已获用户通过，保留为视觉基线；正式启动仍是01StartMenuV8，9B完整日周期/本机时间/最终整合未实施。
- **当前资产目录**：`C:\Dev\Tools\ArtControl\runs\main-menu-stage9a-entries-20261112`。母图1672×941，SHA256 `71ed1970fb89c206a4b97fd6dde9cca1c3792b23e3f6f574d0839b6dfdc2ed02`。原图、S8港口/风/光参数未改，无生图。
- **业务唯一入口**：原AdventureToolbar继承toolbar_entry_host，`feature_status/request_feature/scene_entries_blocked`共用原_hooks、解锁条件和模态生命周期；建筑与工具栏不建第二套窗口/存档。地图、图鉴、研究室真实打开；家/商店保持未开放，皮卡不新增功能。
- **输入与表现分离**：`building_entry_hit/layer.gd`使用稳定原画命中、同目标按下释放、原生GUI遮挡及键盘焦点；hover不打开，拖出取消，鼠标释放时重新核对顶层控件防止捕获穿透。普通模态、导航和教学遮罩都阻断背景入口；只读教学阻塞不妨碍原教学工具栏目标。
- **配置与动态对齐**：`config/entries.json`分开定义hit/exclude与可见shape，提供feature、名称锚点和过渡/颜色参数；entry_assets生成R可见/G内侧边蒙版。entry_highlight处于同一受光后、已有风/港口变换前，高亮随布料/船体同步且不独立重算运动；高亮关闭与S8同相位逐像素一致。
- **真实预览与隔离**：native_entries建立独立manifest和`PVZ-Menu9A-Isolated-20261112`用户目录，复用真实游戏代码/资源；临时演示档案显示解锁/锁定。entry_record发送原生GUI事件并截图，不直接调用建筑业务；三类窗口与关闭返回均为实际界面。原用户存档未复制或修改，演示目录会产生自己的数据。头像/功能台仍为占位，不冒充最终UI。
- **本轮核对**：完整原生输入录像、锁定/未开放拒绝、弹窗/界面阻挡、拖出取消、键盘Enter与两个窗口比例；未高亮的8个昼夜相位与S8像素一致，40个已记录基线文件未变；XCF重开保留原图锁定和16张蒙版。未新增/运行测试套件，不宣称合成事务/关卡实机或全回归通过。证据在reports/entry_record、entry_delivery、final_verification。
- **复现/原生源**：`menu.py entries`重建并录制，`entries-preview`只整理真实帧；原分层文件`MainMenu_Entries_Working_v09.xcf`保留既有部件及新蒙版/命中审阅层。runtime是执行副本，XCF不自动回写JSON。原生交互预览必须依赖完整游戏工程，不把native_project链接递归打包或作为生产运行路径。
- **尚未完成**：9A最终观感待用户验收；完整全天闭环/本机时钟、正式主菜单替换、最终档案与功能台按钮、尚未开放建筑业务和生产性能核对仍属后续范围。新场景未变为生产启动入口。

## 6｜验收与交接收口

- 核对**真实运行链路**：关卡启动、参数投影、有效场景格子、真正的卡槽扣费与冷却、入水触发、屏幕绘制。原版泳池与下水道两处均需回归。尤其关注承托植物种植/铲除/读档和跨行错位。
- 验证遵循 `AGENTS.md`：默认不新增、不运行测试；同步已有测试的失效接口引用，执行 Godot 4.7.2 headless editor 导入/解析。明确获授权后再运行相关水面、承托、关卡和存档测试；解析成功不等于测试或完整视觉验收通过。
- **仍需实机终验**：自定义稀疏坐标、移动平台/静止鼠标交互、荷叶多层随动、地形切换和稳定 ID 读档；下水道第 1、5 路水面动态实际可见性、荷叶及上层植物长期浮动/格子对齐、僵尸游泳、真实卡槽阳光结算、原版泳池兼容；暴雨长时性能和正常通关接续噩梦流程亦不能仅以单元测试判定。
- 交接文档永远只保留**当前唯一管线、权威路径、真正可复用的方法与未关闭风险**；旧补丁路径、临时测试结论、过期链接、冗余清单和随时变化的 Git 提交快照不写入正文。
