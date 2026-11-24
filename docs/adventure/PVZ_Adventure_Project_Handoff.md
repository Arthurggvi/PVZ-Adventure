# PVZ-Adventure｜唯一权威项目交接

更新：2026-11-18。**只记录权威路径、可复用管线、实施方法、有效约束和未关闭的验收边界。** 源码与实际资源优先于本文；“接入”“自动化通过”“实机视觉通过”必须分别表述。

## 0｜权威入口、施工纪律（先读）

- **工程与引擎**：`D:\Dev\PvZ\PVZ-Adventure`（Git `develop`）；Godot 4.7.2：`C:\Users\Arthu\Desktop\Godot_v4.7.2-stable_win64.exe`。Sancho 在线时优先远程只读审计，获授权后直接施工，避免让用户手工搬运文件。
- **本交接文档唯一原件**：`D:\Dev\PvZ\_reference\project_docs\PVZ_Adventure_Project_Handoff.md`。Git 跟踪入口 `docs/adventure/PVZ_Adventure_Project_Handoff.md` 是**同一 NTFS 硬链接**，不应独立编辑/替换。改动需原位写入，并用 `fsutil hardlink list` 验证仍为同一文件。
- **资源权威范围**：`res://assets/adventure/`（新增素材）、`res://assets/reanim/`（原版分件）、`res://animation/`、`res://scenes/`、`res://scripts/`、`res://resources/`。仓外 `D:\Dev\PvZ\_review\<module>` 用于临时审查；`D:\Dev\PvZ\_reference` 为持久参考。游戏运行时不能依赖仓外文件。源码备份只放仓外，不能让带全局类名的旧脚本进入 Godot 扫描范围；解析时须确认类索引指向正式源码。
- **素材参考库**：`_reference/FVM-Reborn/sounds/` 保留完整音乐和音效，`_reference/FVM-Official-UI-References/resource/image/` 保留已采用的等级角标和道具原图。两套参考库采用 Git 稀疏检出，上游提交和素材来源可追溯。
- **主菜单运行/制作入口**：启动入口 `scenes/main/00Bootstrap.tscn`；正式菜单 `scenes/main/01StartMenuCoastal.tscn`；维护 `docs/adventure/main_menu_runtime_pipeline.md`；离线构建/发布/录制统一 `tools/art_bake/main_menu/menu.py`。9B已接当地时间与真实UI，不再使用占位主菜单。
- **施工顺序**：检查 Git 和连接 → 读本文及权威代码/资源 → 复现并定位根因 → 设计通用接口与状态所有权 → 直接重构旧实现 → Godot 导入/解析检查 → 按 AGENTS.md 在明确获授权时运行测试/实机验收 → 必要时 Catbox 手机验收 → 仅暂存本轮文件并提交。
- **仓库纪律**：先 `git status --short`、`git log -1`，保护并行工作区；禁止未授权的 `git reset`、`git clean`、`git add .` 和 `git push`。提交前 `git diff --cached --check` 并逐项核对暂存清单。被 `.gitignore` 忽略的新美术资源，必要时定向 `git add -f`。
- **架构原则**：一条权威数据与状态链；配置描述差异，组件实现机制。禁止针对某一关/植物/僵尸追加并行实现、补丁式坐标修正、冗余管理器或把重复接线留给后续开发者。

## 0.1．启动/加载权威协议（先读）

- **唯一启动入口**：`project.godot → scenes/main/00Bootstrap.tscn`，正式海滨菜单仍为 `scenes/main/01StartMenuCoastal.tscn`；Bootstrap 不静态引用重型菜单、战斗或卡牌总览。
- **唯一切场实现**：`SceneTransition.change_scene(path, after_switch=Callable(), resource_paths=PackedStringArray())` 的第三参数是可选动态依赖；接受请求不等于完成。遮幕开始即通过 `resource_load_batch.gd` 请求目标与依赖，每批最多2个根资源在途、不启用子线程，只有 `THREAD_LOAD_LOADED` 才取结果。目标根脚本可静态声明 `get_initial_resource_paths()` 补充动态首屏资源。
- **单次构造与交接**：资源与遮幕都准备好后，在主线程只构造一次目标，以 `prepared_resources` metadata 持有准备资源；使用 Godot 4.7 `SceneTree.change_scene_to_node`，成功后执行预先保留的回调，早于目标入树及 `_ready`。`transition_failed` 恢复旧场景/输入；普通取消异步回收请求，退出才允许完成剩余请求。不得另建 Loader、预实例化校验场景或同步黑幕切场。
- **卡牌唯一门面**：`AllCards` 的 `lazy_card_catalog.gd` 只按需构造单卡；`card_catalog_manifest.gd` 支持纯身份/路径查询。当前有84个逐卡场景、83个运行时基础引用，`scenes/autoload/all_cards.tscn` 是编辑总览及顺序源，运行时不实例化整棵总览。单卡/总览改动后用 `python tools/card_catalog.py` 生成，再用 `python tools/card_catalog.py --check` 检查；禁止手工维护第二份目录。
- **既有资源拥有者**：`Global.character_registry` / `SceneRegistry` / `SoundManager` 保留按需加载门面；`AdventureToolbar._ensure_presenter` 仅在真实宿主建 UI。禁止在 Autoload 预加载全部角色、音效或窗口。`battle_resource_plan.gd` 仅收集本局动态依赖路径，后台读取不意味着节点构造和渲染已无主线程成本。
- **关卡解析与地形**：`enter_stage` 一次解析，同一个配置交给 `entry_error_for_stage` 与构建；Registry 缓存私有合并模板，对外深拷贝，editor feature 运行在重新进入地图时显式失效。地形校验使用 `BoardDefinition` 或 `MainSceneRegistry.LEGACY_SPAWN_ROWS`，不加载/实例化战场读行数；真实旧战场装配时在地形覆盖前核对静态表与节点。首次配置读取仍是同步步骤。
- **模态生命周期**：`request_feature` 先过正式解锁条件，立即提供可取消反馈，异步准备脚本及首屏依赖；主线程构造、可选 `is_content_ready()` 完成后才发布到 `modal_for()`。取消、换档、重载和离场撤销旧请求资格；当前可见项通过 `prepared_visual_queue.gd` 按需准备、每帧最多构造一个预览，不能预建整本图鉴或隐藏页签。
- **业务状态与揭幕**：`MapNavigation` 校验玩家后切场；`AdventureSession._commit_battle_entry/_commit_map_return` 仅在目标被接纳后发布/回收战斗状态。战斗基场景共享过渡；海滨菜单提供 `is_visual_ready()`，再等待真实绘制帧揭幕。加载百分比仅反映资源批次，不代表可选卡或窗口内容就绪。
- **验收与计时边界**：详细契约及串行隔离命令见 `docs/adventure/startup_loading.md`；Windows GUI Godot 输出接 `| Out-String` 等待进程结束后再跑下一项。仓外本轮日志/JSON/PNG位于 `D:\Dev\PvZ\_review\interaction_loading_20261114`，记录入口同步耗时、内容就绪和帧间隔；未解锁窗口明确列为未覆盖。上一轮 Autoload/Bootstrap 基线只作历史记录，不能作为本轮首次关卡或窗口提速证据，源码接入不能写成验收通过。

## 1｜核心系统权威总线

| 系统 | 唯一入口与维护边界 |
|---|---|
| 冒险关卡与续战 | `AdventureStageRegistry` / `AdventureStageCatalog` → `AdventureStageOverride` → `AdventureBattleEnvironmentAdapter` → `ResourceLevelData` / `AdventureSession.active_phase` → `AdventureBattleRuntime`、WavePlanner、BossDirector、`AdventureContinuationController`。进入不询问难度；普通结束后有钥匙可选择接续噩梦。 |
| 战场种植空间 | `board_definition`（单关覆盖/环境/ResourceLevelData）→ `MainGameManager._enter_tree()` → `BoardSceneAdapter` → `MainGameManager.board: BoardRuntime`。定义与运行时位于 `scripts/battle/board/`；配置/扩展指南 `docs/adventure/board_authoring.md`，见下方 §1.1。 |
| 战场水陆地形 | 显式布局由 `BoardTerrainDefinition` 决定单格能力、`BoardLaneDefinition` 决定出怪与清洁车；旧 `terrain_rows` 只由 BoardSceneAdapter 适配现有场景。两种布局配置不能同时使用，视觉分类不能代替逻辑能力。 |
| 水面视觉与接触 | `AdventureBattleEnvironment.water_surface_profile` → `BackgroundManager` → `WaterSurfaceController` / `WaterSurfaceProfile` → 同源 `WaterBodyArea`；泳池和局部水沟共享水面 Shader 与入水协议，详见 §2。 |
| 植物种植与承托 | 卡片 `HMCharacter.click_cell` → `PlantPlacement` 预备/复核 → `PlantCell.commit_prepared_plant` 实体占用及同步放置动作 → `Card.complete_placement` → 原 `signal_card_use_end` 费用/冷却结算。`PlantCell` 持有地形条件、占格、承托层锚点；详见 §3。 |
| 研究室/植物卡牌 | `PlantCardInstance` / `PlantSpawnProfile` / `AdventureBattleAdapter` / `PlantSceneFactory`；合成、强化、转职、扣料经 `ResearchService → ResearchTransaction`。战场、卡面、技能书外观基于同一实例/阶段。 |
| 角色主动技能 | `CharacterSkillLoadout` → `AdventureSession.character_skill_id_for` → `CharacterSkillCatalog` → 战场常驻 `CharacterSkillRuntime`。成功施放通过 `cast_committed` 播放统一 Cut-in。园丁刷新卡槽，大肥鱼施加全场深寒，向日葵娘触发额外生产与阳光雨，新春小璐引爆双圈贯穿尖刺，邮差派发三张继承背包配方的升星零费临时卡。接入指南见 `docs/adventure/character_skill_framework.md`。 |
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

## 3.1｜植物转职书、技能生成与负面状态

- **书目唯一来源**：`scripts/adventure/research/research_promotion_catalog.gd` 汇总既有、小喷菇、阳光菇、胆小菇、大喷菇、睡莲、咖啡豆、回旋镖射手和双发射手的 `research_*_promotion_books.gd` 定义模块；`ItemRegistry` 自动把目录中的书注册为道具，不再双处手填。每物种每阶二选一，书封、植物头像与研究室选项仍复用 `promotion_book_visual.gd` 和冻结卡牌快照。
- **小喷菇出生/射击**：`AdventureResearchBattleEffects.apply` 经 `AdventureResearchPlantEventDispatch` 入树前应用白昼耐心，挂载 `AdventurePuffPromotionEffects`；控制器等植物就绪后取得攻击组件与来源配方，再按路径加载派生弹体场景；禁止在全局类静态预加载该场景，避免与注册表形成资源加载环。`bullet_003_puff_adventure.tscn` 继承原孢子场景，由 `AdventurePuffProjectileEffects` 补充距离伤害、实际击杀与命中异常。全行同时扩索敌与弹体射程，按当前棋盘几何更新；孢涌按发射时格距区分半格内二倍、一格内原伤、之外半伤。
- **大喷菇攻击接入**：`AdventureFumePromotionEffects` 等原株就绪后接原生发射；`AdventureFumeHitEffects` 每次攻击冻结一次规则和犹格十一选一结果，同股穿透喷雾对每个角色只命中一次。已发弹独立于母株，场景、轮次或冒险阶段失效则先于主伤害拒绝；局部爆炸走 `CombatExplosion` 的同一目标/护甲结算链，当前格距决定一格尺寸，不递归触发词条。
- **涌潮与海神** `AdventureFumeRange` 按当前同行前方边界投影私有检测形状、弹体射程和原生喷雾粒子行程，随移动棋盘更新。涌潮每次有效喷射或伤害脉冲增加10%攻速，最多十层，与腐能利用的固定攻速加算。索敌结果为空时清空涌潮层数。海神复用 `AttackComponentBulletBase.configure_continuous_attack` 的原攻击时钟，基础周期0.5秒，按当前攻速缩放。攻击时钟与喷雾随原生索敌和禁用状态启停，再次索敌成功时从完整周期计时。持续伤害沿用原生穿透分流，范围改变后等待物理重叠缓存同步。
- **回旋镖自然发射**：`Plant051Bloomerang` 由 `BloomerangAttackCycle` 的唯一时钟驱动起手、声音与有限三连投，动画只负责表现，接镖不阻塞普通冷却。岚刀只加速攻击事务与投掷动画；暂停保留进度，死亡、无效化、零速及跨轮取消未离手动作。所有新投掷共用 `BloomerangEmitter` 门禁与构造入口，正常索敌仍走原 `DetectComponent`；扫荡在任一侧有目标时双向发射，不能依靠动画名或在飞弹数量解锁。
- **回旋镖飞行与派生**：`BloomerangShotContext` 冻结战局、棋盘、轮次、冒险阶段、原株身份及每枚规则；`Bullet017Boomerang` 分别管理去程、返程、弱镖和结束，`BloomerangFlightQuery` 按实际形状扫掠与接触顺序去重。每程默认三目标，斩切五目标，折返只清本程命中表；同一枚的苍镰成长保留。真实回收使用原实例当前离手点，先结束弹体再发布一次回收；原株失效后自然终止，不永久等待。螺旋补投单枚并撤销再次补投资格；暴雨新镖反向直行、基础半伤且成长独立，不能再次分裂或补投，触及原株或出屏终止。屏幕边界随视口变换读取，平台移动不沿用初始坐标，弹体设有限寿命兜底。
- **双发连射与弹种**：`AdventureRepeaterPromotionEffects` 经原事件派发入树前冻结四转选择，`RepeaterVolleyAnimation` 只复制本株射击动画库，在原有两次发射之间追加方法键；总发数为原两发加已选书数，不另建连射计时器。每颗弹只抽一个四等分区间，每本固定25%，未选区间保持普通豌豆。停止攻击时中止旧OneShot；同帧承托重挂保留私有库。`RepeaterProjectileFactory` 按路径加载原豌豆、火豆、阳桃的薄继承场景，特殊弹禁止火炬覆盖；普通弹的 `AttackValidity` 随原初始化参数跨火炬变换，静态绑定来源快照避免失效方法放行。
- **双发派生与持续场**：`RepeaterShotContext` 冻结游戏、棋盘、轮次、阶段及原实例，开始伤害使用 `is_active`，末击治疗和纯视觉只放宽到 `is_same_battle`。晨星圆周随机间隔至少15度，只分五颗同基础伤深星及每颗三颗半伤浅星，子星忽略直接产生它的目标，有限两代，真实移动使用平滑速度的解析积分。`RepeaterFieldRuntime` 每战场一个60Hz时钟，地狱场五秒整秒吸取，辉夜三秒逐步结算；`RepeaterFieldQueries` 一次宽相后将原生受击形状与实际可见星核核对，跨场/受击盒先去重，再用 `CombatHitScope` 在转伤后的真正承伤者扣血前去重。
- **双发处决与视觉**：HpComponent.living_health_fraction 按原生死亡阈值余下的有效生命计算冥弹30%处决资格，Boss不受处决。RepeaterExecutionVisual 仅采集原身体分件进行白化碎散，完整剪影并发上限6；冥弹命中交给 RepeaterHadesImpact 的黑白撕裂与魂波，普通弹不再共用冥弹命中视觉。
- **双发高并发视觉权威管线**：RepeaterFieldRuntime._tick 是唯一60Hz伤害时钟，_process 是唯一视觉提交点；RepeaterFieldQueries 复用宽相与五像素接触形状并先做无损AABB剔除。辉夜始终24枚真实接触核、三秒寿命，LOD不改伤害。RepeaterFieldVisual 委托 RepeaterGalaxyVisual（定向爆发、旋臂形成、坍缩）/ RepeaterAbyssVisual（纵裂、黑紫吸收、坍缩）；RepeaterVisualBudget 统一计数并有界降级装饰和绘制频率。RepeaterHadesTrail 最多24采样、最长170像素、单画布。RepeaterVisualPool 随战斗宿主销毁，有界回收 RepeaterImpactVisual / RepeaterHadesImpact。渲染权威路径 scripts/fx/repeater/ 与 shaders/repeater/；禁止再引入逐星Sprite、双漩涡帧混合或无界视觉节点。
- **视觉验收边界**：同机隔离GPU压力场与回收契约存于工程外 _review/repeater_fx_performance_20261113；不代表完整游戏战斗、低配置GPU或密集敌人物理性能验收。
- **实际损失与共享命中资格**：角色/HP伤害入口的可选 `receipt` 返回真正承伤者、实际全部血池损失、本体损失与本次死者；保护者沿原伤害链透传，Boss仍经过原受击窗口。后续可选 `hit_scope: CombatHitScope` 在实际承伤组件受击事件和扣血前消费一次资格，未传入的旧攻击保持原算法。漩涡按回执治疗原植物弱引用及真实占格，免疫、过量和旧位置新植物不产生错误收益，已完成末击可在同局结算时兑现。
- **同击附伤与严格上限**：`BloomerangDamage` 只以命中前本体已损生命计算追猎，防具和临时护甲不参与基数；卡片、苍镰和弱镖基础倍率均不再放大该附伤。`Bullet000NormBase._modify_impact_damage / _impact_bonus` 是纯计算扩展，仍通过原伤害类型分发。生命入口用默认零的 `bonus_damage` 与默认无限的 `bonus_cap` 尾参传递同一次命中，`HpComponent.resolve_damage` 在劣化放大后限制附伤，再统一格挡、减伤与护甲结算，Boss 的0.08%附伤上限不能被劣化绕过。保护者继承原目标冻结附伤并用自己的防御结算，不重新采样、不额外扣一次生命或脆弱防具；未携带附伤的旧攻击保持原算法。
- **玩家扩种钩子**：成功的 `HMCharacter.click_cell` → `PlantSpawnProfile.player_placement_committed` → `PlantSpawnModifier` 所属模式 → `AdventurePuffPropagation` / `AdventureLilyPropagation`。主格只结算一次费用/冷却；十字或九宫格子株、感染与恢复都不再次触发该钩子。子株继承不可变来源的 UID、星级与已选分支，不能再乘母株已经计算的战斗倍率。
- **最终属性与选卡名额**：目录统一合成 `flat` / `percent`，再应用 `final_multiplier`，`fixed` 为最终覆盖值；旧书未声明新字段时保持原算法。睡莲生命倍率在星级加成后乘算。`PlantSpawnModifier → PlantSpawnProfile → Card.selection_slot_cost` 同时供 UI 与 `AdventureSession` 权威预算使用，不能只扩大显示槽；免名额卡仍是实际可操作卡片，出战至少需要一张，超出原可视范围时通过前后按钮翻动固定显示窗口，保留原卡片尺寸与星徽。
- **睡莲周期与扩散**：`AdventureLilyPromotionEffects` 每5个有效战斗秒查询 `Plant000DownBase.supported_plants()`，只给当前真实承托容器中的存活植物治疗或护甲，基数是该睡莲最终最大生命的10%。`AdventureLilyPropagation` 只响应玩家主操作，九宫格按同棋盘/同平台/逻辑距离及正常水面条件检查，子株占用普通 Down 槽，不递归扩张。
- **咖啡目标与生产增益**：`PlantSpawnProfile.placement_condition` 复制投影专属条件，不改注册表资源；预览和实际放置使用相同规则。咖啡默认作用蘑菇，光能亲和额外开放持有真实 `CreateSunComponent` 的生产者。`CoffeeBeanUsePlan` 冻结施效前的清醒状态，`PlantPlacementUseContext` 在同次点击含柱子模式去重目标并冻结死亡记录；生命支付走原不受护甲阻挡的生命入口，致死后不授予效果。动画仅完成已冻结目标的唤醒，不再次找格子中的替代对象。原生预置和读档在完整事务结束后，只冻结中心原生唤醒目标，不重放转职支付；已付费唤醒可跨同场普通轮次，咖啡动画和目标伸缩末端均复核战场/空间/冒险阶段，取消时释放重入标记。永久产值在正常生产层结算并保存，同族不叠加，成熟不覆盖，奖励/储蓄提现不再放大；临时攻速与伤害各自续时10秒，独立撤销来源，不加速生产或成长。
- **植物死亡与普通复生**：`PlantRevivalArchive` 持有每格最新的 `PlantDeathRecord`，保留原物种、冻结配方、原生持久状态；铲除、升级替换、模仿中间体、咖啡消耗和场景退出不记录。多格共享一个记录，成功后仅消费仍指向该记录的格子；失败不丢失，跨场景/冒险阶段不复用。`PlacementOrigin.Revival` 走正常实体占格和承托管线，只省略紫卡升级前置消耗，所有目标槽、地形、障碍、禁种及多格平台必须合法。复生唯一常驻差异是正常配方最终最大生命减半，并以新上限满血出生；再次死亡复生不连乘，读档保留该上限，恢复成熟不发新的成长事件。只有实际授盾或复生成功，咖啡本次冷却才加5秒。
- **技能生成事务**：`PlantCell.PlacementOrigin.Spawned` 与玩家放置共用完整资格预检与提交前复核；占格、地形、承托、墓碑和具名禁种均生效。感染经 `BoardRuntime.cell_at_ground_point` 按实际脚点/攻击行找格，不能把盘外或稀疏空洞吸附到最近格；延迟提交复核同战场/棋盘/轮次和活动战斗，结算或续战询问期间不生成。
- **阳光菇成长与生产**：自然成年和基因突破各发一次 `Plant010SunShroom.signal_matured`，分别结算扩散与蜂群；恢复成长状态不补发。基因突破复用成长计时和潮汐能时长修饰，当前与最大生命一起翻倍。突破后每轮额外产出75阳光，计入 `CreateSunComponent.production_created(total_value)` 和储蓄，固定额外产值独立于咖啡倍率。代谢强化将幼体/成年基础产值提高50%。储蓄各株独立、上限500，统一死亡通知只提现一次。固定高额产出与高额提现都拆成每份不超过50的阳光，提现仍排除在生产事件之外。
- **不占位技能子株**：`PlacementOrigin.Companion` 沿用 `PlantPlacement → PlantCell.commit_prepared_plant`，只为单格普通 Norm 植物跳过普通槽冲突，地形、承托、障碍及禁种仍须通过。伴生由格子独立持有，每格同物种至多一株，不进入升级前置或 `plant_in_cell`；阳光菇扩散取四方向各三格，子株为完整配方的幼体，正常成熟后仍可扩散。普通种植不被伴生挡住；铲除、啃食、弹体、碾压、墓碑、坑洞、咖啡豆及受益光环共用真实实体查询。
- **实体查询与搬迁**：`PlantCell.plant_entities()` 用于数量及恢复空场预检，`living_plants()` 用于伤害/光环，不能把“在场植物”继续等同于普通种植槽。伴生死亡同步释放；离树延后以物种及实例身份核对，承托容器短暂 reparent 不算死亡。承托搬迁只显式恢复原本活动的 `SpeedTimer` 剩余进度，不改基础周期、倍率或死亡/禁用状态；真实离树仍按计时器原契约终止任务。
- **日眠与月光**：`SleepComponent` 独立合成原生日眠、咖啡豆永久唤醒与按来源 ID 的临时豁免；状态切换幂等，撤销一个光环不覆盖其他来源。`MushroomPlantQuery` 按真实生成物种识别蘑菇（含忧郁、金磁和模仿目标），出生前冻结的日眠标记仅作扩展兼容。月光与共生统一继承 `AdventureMushroomAura`，使用拓扑邻接和 `living_plants()`，种植同步刷新、低频复核、死亡/无效化撤销；静态弱引用回收区分同步承托重挂与真正释放，不依赖源节点继续存活。月光每次成长在同平台3×3范围的相邻格尝试生成一株同星同转的随机蘑菇。生成株使用普通放置槽与临时卡牌配方，在该物种的连续书目中随机选取路线。存档永久唤醒字段只记录永久来源。
- **胆小菇原生词条** `AdventureScaredyTraits` 保存冻结书目与各共享来源，`AdventureScaredyTraitRules` 在白名单中合并同类词条的最大值。腐能利用、菌核裂变和菌系群落的攻速按基础速度加算，作用于攻击时钟和独立攻击动画。群落按受益者自身九宫格内的不同蘑菇物种计数，包含自身与伴生。腐食渴望监听真实射击，每次由原弹口以正前方为中心散射1～4发原生胆小菇孢子，角度在±30°内随机，额外弹通过实际碰撞命中任意行。
- **腐殖共生与卡牌数值** `AdventureScaredySymbiosis` 传播来源自己的前三转词条，作用于周围其他物种的蘑菇。同类效果取较强来源。`AdventureMushroomCardDiscount` 通过受益株的冻结UID登记真实卡的减费或后续冷却缩短。数值在当次用卡结算后生效，来源离场、无效化或换卡时撤销。大喷菇已有同名的白昼耐性或腐能利用攻速时保留自身的对应数值。
- **统一攻击上下文** `Plant000Base.capture_attack_context` 合成冻结配方与动态词条，随原生弹体参数和变换传递，忧郁范围攻击及毁灭爆炸共用该上下文。阻击与菌核裂变按直接命中者当时的一、二类装备防具判定倍率。腐蚀之触在 `HpComponentZombie.apply_hit` 对装备防具使用三倍消耗，破甲后按原伤害容量向内层溢出。近伤在半格内双倍，向原恐惧外缘线性回落。光能转化按命中时的阳光余额计算，最高额外1000%，真实击杀掉8阳光。
- **攻击结算边界**：死亡开始、发信号清理来源之前冻结亡语上下文，已发攻击与同步亡语都不依赖母株继续存活。每次命中开始确认活动资格，实际击杀返回后即使同步触发结算仍完成该次掉光，不能补领其他死亡；游戏、轮次及冒险phase身份共同隔离旧攻击，普通进入噩梦不能令旧弹重新有效。失效上下文在命中计数和HP入口前拒绝，不用零伤害冒充取消命中。
- **成功用卡与冷却**：`Card.complete_placement(extra_cooldown)` 仅在原同步通知期间携带实际施效结果，柱子模式按同次最大值汇总，不按目标数累加；无冷却模式也清空该结果。卡槽先扣本次显示费用、启动冷却、消费旧一次性收益，再发 `signal_card_committed(card, consumed_followup)`。固定冷却在新计时开始时跳过倍率，成功施效额外秒数随后加入并更新完整遮罩范围。代谢强化的续种效果由 `AdventureSunShroomCardEffects` 读取冻结书目，只给该 UID 卡下一次成功用卡减25并立即清冷却；消费续种的那次不再授予，失败放置不消耗，技能生成不触发。旧买一赠一的卡片转职、库存和货架归并为代谢强化。蜂群调用 `halve_remaining_cooldowns`，逐张减半当前剩余时间，不修改基础/最大冷却；续战保留原卡及其待消费收益。
- **击杀与弹体生命周期**：直接命中与毒伤都读取 `HpComponentZombie.apply_hit` 的实际死亡返回，包含保护者代伤；不要订阅目标将来的任意死亡来猜归属。礼物固定8～12颗径向孢子，孢涌不会把亡语弹数再次倍增；来源规则和配方由弹体独立持有，母株死亡不取消已发射能力。
- **统一负面入口与跳伤**：`scripts/adventure/adventure_plant_negative_effects.gd` 的 `apply(..., context)` 登记中毒、灼烧、冻结值、恐惧、沉默、光能、魅惑、引爆值和缠怨，复用原减速、眩晕、免疫与伤害路由。中毒/灼烧的 amount 表示持续秒数：5层即5秒，每0.5战斗秒造成本体最大生命2%的基础伤害；`AdventurePeriodicDamageEffect` 统一节拍，各状态实例独立，重施只续时并保留跳伤相位。灼烧与火豆共享 `scenes/fx/fire_pea_impact.tscn` 的原命中动画，仅循环视觉，不借用子弹碰撞、伤害或解冻。
- **引爆、缠怨与设施免疫**：`AdventureDetonationChargeEffect` 同目标累计十点先清零再回调冻结来源，爆炸经 `RepeaterAreaEffects` 延后到碰撞回调之外，按当前格距一格1800基础伤害，不递归附加弹体词条。`AdventureResentmentEffect` 复用周期父类的显式永久标记和一秒节拍，3×3内同种不叠跳伤，重复施加保留相位；黑白正弦明度是独立颜色通道。`EnemyStructureBase.can_receive_negative_effects/can_receive_cold` 与原生寒冷/魅惑覆盖共同保护令旗和墓碑，冰瓜等直接调用也不能泄漏状态；设施不进入普通僵尸强制位移链。
- **冻结值与位移**：`AdventureFreezeChargeEffect` 每点只降低10%实际移速并加深独立蓝色滤镜，不改啃咬；满10点归零，调用原生3秒冰冻和后续5秒减速。真实解冻（含提前解冻）后一秒由角色公共计时器拒绝新冻结值；原生寒冷免疫继续生效。`MoveComponent.set_move_rate_source` 合成移动专用倍率，`set_flee_source` 反向行走并独立封锁攻击；恐惧不改阵营，结束恢复当时原生意图方向。`can_receive_forced_displacement` 在公共入口拒绝载具的击退、抛起和换行，换行事务必须先通过资格再改行索引。
- **沉默与等阶资格**：`Zombie000Base.set_tier_suppressed / are_tier_skills_active` 是唯一启停入口；`AdventureZombieTierAbility` 保存能力期望输出和显式原生配置覆盖，沉默撤销持续速度、攻击、防御和光环并暂停其时钟，恢复保留消耗与进度，不重新 setup。事件、动画末端与延迟爆炸/召唤均须复核；死亡前冻结资格，清理状态不能重新放行亡语。基础等阶生命/攻击成长、原生物种动作及已结算治疗/护甲/召唤保留；自身等阶定时输出与外部已经授予的增益明确区分。
- **光能与状态寿命**：`AdventureSunBeanEffect` 监听 `HpComponent.combat_health_lost` 的实际本体/装备/临时护甲损失，每层转换20%，以5阳光为单位兑现并保留余数；重复授予增加转换层数，光能自身持有独立黄色滤镜。`BattleSunDrop` 复用原生阳光拾取与寿命，不触发生产事件或直接改余额；脚本卸甲、过量伤害、尸体后续扣血不产光，转移伤害只由实际承受者结算，同步末击保留当次奖励。新状态按场景、轮次、冒险阶段、死亡、魅惑和真实离树清理；大蒜可逆换行保留状态和节拍，不能当作退场。
- **劣化必须分通道**：`HpComponent.degradation_fraction` 只保存原不可叠加最强值；`stacked_degradation_fraction` 单独累计新劣化，每次尸变追加0.05。引爆弹另用 `apply_capped_degradation` 按具名效果族累计至50%，同族多来源共用上限，不截断小喷菇旧叠加池。`total_degradation_fraction()` 只汇总结算，不反写或覆盖任一通道。尸变先判60%，再按毒/劣化/减速/眩晕/魅惑的2/2/2/2/1权重只取一种；默认减速5秒，眩晕0.5秒。
- **寒冰射手书目与原生发射**：`scripts/adventure/research/research_snow_pea_promotion_books.gd` 定义四阶八本技能书，由 `AdventurePromotionCatalog` 和 `ItemRegistry` 共用。出战冻结配置由 `AdventureResearchPlantEventDispatch` 安装 `AdventureSnowPeaPromotion`，原生动画射击经 `Bullet002PeaSnow.init_bullet` 冻结真实参数。根弹、喀俄涅加射与斯卡蒂棱锥复用 `SnowPeaShot` 的战场、棋盘、轮次、阶段、伤害及受击状态资格。转职寒冰弹保留寒冰属性通过火炬树桩，普通寒冰弹仍按原版转换。
- **寒冰直击与地面控制**：`SnowPeaImpact` 统一施效。直接命中的减速、冻结值、深寒与脆性不以实际扣血大于零为前提；伤害回执的 duplicate_hit 仍阻止已消费的穿透或溅射命中重复叠状态。五阶铁桶只有减伤和代伤，不具有寒冷免疫；代伤后控制跟随回执的实际承伤者，允许跨行保护者受控，脆性同样读取其扣血前寒冷。仍保留寒冷免疫和二类防具门禁，酷刑登记及冷萃派生继续要求根弹造成实伤。冷萃按主伤的50%在1.6格宽区域溅射并分享所选减速；回廊按接触前的寒冷减速判定。脆弱只在最终承伤方的 `HpComponent.resolve_damage` 放大入伤，上限100层，每层1%。深寒减速与0.2秒冻结独立计时，同强度普通冰与抗火冰重叠仍保持半速；火焰只清除普通冰。深寒对未冻结且允许冻结的目标造成20点可配置真实伤害。酷刑用 `SnowPeaIceTrail` 的单个8 Hz战场时钟采样，每格最多四段，每段5秒，重叠位置续时。每个敌人每秒最多接受一次接触，复用统一冻结值，满点仍冻结3秒并减速5秒，冰痕施加的满点冻结不附伤。
- **冰雕事务**：斯卡蒂根弹、加射、冷萃与附伤在真实承伤者处由 `SnowPeaStatueHit.try_claim` 登记 `SnowPeaStatueMark`，护甲吸收或伤害格挡不吞掉登记。该敌人之后首次死亡即在 `HpComponent.before_death` 采集姿势与受击形状，不要求本株补刀；只排除最终烧死和冥弹直击/处决，先前火伤或冥弹非致死命中不污染后续死因，独立缠怨仍是普通死亡。活体寒冷免疫不阻止死亡冰雕，魅惑、离场及战局失效撤销标记。原僵尸照常完成死亡、掉落与波次清算，`SnowPeaStatue` 延迟作为一生命设施入场，不延长波次。冰雕受真实战斗伤害释放16枚等角跨行穿透棱锥，每枚按实际承伤者去重、继承书目并追加5点冻结值；棱锥不新增冰雕标记，但杀死原先已有标记的敌人仍可形成冰雕。
- **暴雪位移**：喀俄涅每第5次原生射击横扫同行，经 `MoveComponent.apply_forced_displacement` 按实际棋盘格距在0.60秒内缓入缓出后移1格；旧配置同样限制为1格，重叠暴雪共享当前终点，不叠加为多格击退；战局失效时撤销未完成轨迹。随后按0.1秒间隔加射5发。停攻、死亡、离场及轮次/阶段失效取消待发弹，已发弹继续遵守原战局门禁。
- **寒冰表现**：普通弹保留原画并叠加方向细霜尾，深寒弹提亮蓝核；命中霜雾在0.22–0.31秒内消散，冷萃按真实格距显示低透明范围反馈。冰雕原画使用轮廓内的透明切面与霜边，0.42秒自下向上结晶；破碎使用有限数量的上抛冰片与薄雾，视觉并发有上限。暴雪0.60秒横扫与击退同步，0.12秒尾风消散；冰痕跟随地块变换，以薄冰片及分叉霜纹显示并在末0.85秒淡出。表现不参与伤害与控制判定。
- **寒冰实机验收边界**：研究室与背包交互、冰痕脚点在各类棋盘上的接触、密集棱锥跨行碰撞与性能、火焰与深寒叠加表现、末波和跨阶段取消均待完整战斗验收。
- **电能豌豆出战与直击**：`research_electric_pea_promotion_books.gd` 的八本书由 `AdventurePromotionCatalog`、`ItemRegistry` 共用。出生事件冻结参数；第38帧离手仍由原株唯一动作时钟触发。`ElectricPeaVolley` 同口发球，中路与两侧最大±14°形成持续展开的三射线，不在邻行截平；飞行使用等速二维向量，并按真实地面投影定位攻击行，屋顶正向、反向及竖向路径均保留连续扫掠，每枚电球分别持有实际承伤去重，同一电球保护者代伤只结算一次，不同电球可独立命中。电荷牵引减半速度并按等效飞行距离延长寿命。脉冲在母球首次合法直击时即停止贯穿并向360°三等扇区分出三枚小球；整体随机相位加每支最多±12°偏转，覆盖前后上下，小球排除母命中目标且不再递归分裂；同时尝试施加0.2秒眩晕；伤害免疫仍由公共状态和生命入口判定，小球按离手伤害的60%结算。
- **电击、矩阵与共生**：`ElectricPeaBolt` 每球独立半秒放电，静电附着最多四个主目标；电弧跳跃只从原始实伤电弧折射一次。`ElectricPeaShotContext.hit` 统一走 Real 伤害与回执，过载实伤眩晕0.1秒。矩阵按植株实例连接排序相邻的活跃球，每源每个60 Hz游戏帧经真实受击几何最多扣一次10点基础伤害，不触发眩晕。电磁共生按同平台3×3邻格的存活雷电植株（50、52）每株贡献40%，由单株独立光环来源维护。
- **电能豌豆表现**：`AdventureElectricPeashooterPromotionArt` 和专属 shader 共用原画明暗，保留白脸、眼睛及线条；五阶使用白芯、电青主色、少量紫辅光，不再套用芦苇金色表。弹体细尾按实际世界速度对齐，分裂和出膛短促起光。`ElectricPeaArcVisual` 用端点固定的分段主弧、短分叉和两次脉冲替代拉伸贴图，折射只延迟45毫秒的表现，伤害仍同步；单场最多64道短放电。矩阵的2像素真实判定线持续可见，仅前96条叠加细流装饰；共生用低亮度细流区分，不改变增伤或连接拓扑。
- **电能豌豆实机验收边界**：研究室选书与背包、屋顶和移动平台上的三路覆盖及边行、护甲转伤与僵王窗口、密集矩阵的扣血节拍与性能、暂停恢复和换阶段清理、同格伴生与铲换后的共生仍需完整战斗验收。
- **火爆辣椒转职**：`research_jalapeno_promotion_books.gd` 经 `AdventurePromotionCatalog` 与 `ItemRegistry` 发布四阶八本书。`AdventureResearchPlantEventDispatch` 入树前冻结卡 UID 与规则，`BombComponentJalapeno` 从原生单次引信委派 `AdventureJalapenoBlast`。完整行保留盘外命中，额外纵列以当前格子世界几何判定，仅清该列梯子；普通僵尸、设施及僵王使用原生受击入口。
- **爆炸对僵王的伤害上限** 樱桃炸弹和火爆辣椒用组件的原始爆炸伤害乘1.5作为单次僵王伤害上限，当前为2700。普通爆炸、转职主爆、樱桃追爆及恶果均在出战增伤后应用对应上限，再进入僵王原生受击与减伤结算。
- **火爆辣椒表现**：普通与转职辣椒共用 `JalapenoFireVisual`，保留原株一秒鼓胀引爆动作和音效，专用画布恢复原始 `fire.reanim` 的三帧燃烧与九帧退火，不修改通用 Fire。整行主火以最多0.12秒的纯美术延迟向两侧展开，地火在主爆后以低矮三簇显现，辅以有限火星及贴地热光。火焰挂在实际地块下跟随平台；地火仍由原五秒控制器回收，伤害时间与范围不变。
- **火爆辣椒持续效果与验收边界**：爆燃与击杀奖励跟随战场来源，连锁使用公共 `BURN`；涅槃统一经 `AdventurePlantNegativeEffects.purge` 净化，并从 HP 按本次独立来源撤销无敌。本轮已做 Godot 4.7.2 编辑器解析与原资源 GPU 美术取样，未执行测试或完整战斗验收；仍需实战核对费用/冷却、屋顶和移动平台命中、保护者与僵王、灼烧归属和连锁、涅槃净化及暂停换轮边界。
- **寒冰菇转职** `research_ice_shroom_promotion_books.gd` 经 `AdventurePromotionCatalog` 和 `ItemRegistry` 发布四阶八本书。出生时冻结来源卡 UID 和动态词条，原生单次引信交给 `AdventureIceShroomCast`。速冻给普通冻结阶段增加2秒，只有减速的目标继续使用原生合并时长。世界、皇朝和珊瑚抑制读取本次冻结周期。低温再生和速冻按成功冻结的普通僵尸实例计数。冻原的非首领附伤独立于寒冷免疫。设施、珊瑚与僵王由 `ZombieManager` 统一处理，博士火球通过独立消除事件处理。费用与基础冷却沿用卡牌 stat，战斗中的冷却返还与回声只调整实卡剩余时间。
- **寒冰菇持续效果与验收边界**：世界在 `ZombieWaveManager` 按施放来源挂起自然刷新，和 Boss 的挂起来源共同生效。皇朝由每株复用的状态保存各来源时限，经 `Dynasty` 速度因子影响动画和攻击时钟，生产和成长保留原速度。实战还需验收多次引爆的冷却与阳光归属、深寒遇火、冻原的护甲和僵王窗口、世界与 Boss 重叠和换阶段、密集植株与僵尸阵容、屋顶和移动平台。
- **海草转职**沿用四阶八本书、研究室、图书馆和通用书封。种植事务冻结寄生宿主的实例，宿主死亡时以原生啃食目标和实际水域判定，棋盘外按水体接触。疯狂海草从主格铺满合法九宫格。恶鬼等待敌人入水时只复核原生索敌区内的重叠对象，实际发动才查询九宫格目标。塞壬、老虎机和两种藤蔓由拖拽的实际击杀兑现，嫉妒之藤按处决前剩余本体生命授予附近友军，技能护甲上限3000。运行 `tests/adventure/test_tanglekelp_promotions.tscn` 时使用名称包含 `kelp-audit` 的隔离用户目录。
- **魅惑菇转职**共四阶八本。种植提交和原生唤醒负责幻觉，清醒时的合格死亡由孢子选最近四名。限制解放沿用五阶上限，肉体改造的光能挂在被魅惑的友军上。没入疯狂以当前本体已损生命的完整百分点结算增伤与最高80%的独立免伤。恶意由原生右行越过末列触发，僵王伤害单独结算。感染只由伤害回执确认的敌方死亡抽取，分帧生成并扣除排队耗去的限时效果。运行 `tests/adventure/test_hypno_promotions.tscn` 使用名称包含 `hypno-audit` 的隔离用户目录，通过 `-- --profile-infection` 加跑批量复制。
- **毁灭菇转职**共四阶八本，三转为焚与涤，荡仅在四转。昼保留原生引信并跳过弹坑事务，尽读取战斗画布的可见范围。灭、涤的基础增幅相加，荡在其他出战加成后结算。普通敌人与僵王独立计算倍率，焚和空按对应主爆数值的50%或5%结算。真实死者在每株连锁内各触发已选效果一次，代伤以实际死者的致死前位置为准。密集命中分帧，辣椒火浪与小爆炸复用已有表现。运行 `tests/adventure/test_doom_promotions.tscn` 使用名称包含 `doom-audit` 的隔离用户目录，通过 `-- --profile-doom` 核对连锁分帧和暂停。
- **窝瓜转职**共四阶八本。普通落地与窝瓜王共用真实承伤和击杀归属。愤恨只在整轮无击杀且未有效命中僵王时通过原格种植事务生成，同卡训练最高300%。窝瓜王逐枚重选格子并复用原立绘，落下、压扁和消散不生成战斗植物或计入训练。地震在整轮结束后叠加本轮仍存续的震撼，领袖同样每轮只引爆一次。窝瓜王单次对僵王上限为基础压砸的30%，领袖为300。运行 `tests/adventure/test_squash_promotions.tscn` 使用名称包含 `squash-audit` 的隔离用户目录，通过 `-- --profile-squash` 加跑压砸、阳光掉落分帧和暂停。
- **验证边界**：转职实现只做独立静态审查和Godot导入/解析，不运行测试套件；散射、连锁感染、伴生密度、重叠月光/共生、群落攻速、真实卡费与击杀掉光、海神持续伤害/粒子、移动范围、复合状态滤镜、等阶沉默恢复、睡莲周期护甲与免名额选卡、咖啡九宫格/柱子重叠与扣血结算、复生多格/承托/读档、回旋镖双向连射/高速折返/密集分裂与移动回收、双发密集多发/两代散射/火炬变换/多漩涡/辉夜实际承伤去重与处决、承托搬迁和长时间战斗仍需实机验收。正式冒险退出即放弃战斗、续战保留实体，本次不改造原版逐株中途存档；伴生不进入旧版按槽序列化格式，恢复空场预检仍必须识别它。

## 4｜天气、光场、雨声：当前需要维护的接口

- **仅第四关墓地下游的噩梦阶段触发本次暴雨**；没落营地没有雨。关卡 `resources/adventure/stages/overrides/zombie_island_grave_downstream.tres` 引用 `nightmare_weather_sequence`、`weather_lens_profile`。不要把地区默认配置设成全程降雨。
- 时间轴 `resources/weather/grave_downstream_nightmare_weather.tres`（WeatherSequence / WeatherKeyframe）按 `0→6→15→26→36` 秒递增至暴雨；最后关键帧持续保持，除非显式请求新天气。暂停不能推进天气。暴雨视觉 `resources/weather/grave_downstream_storm_visual.tres`（RainVisualProfile），音频 `resources/weather/storm_rain_audio.tres`（RainAudioProfile）。
- `scripts/weather/battle_weather_director.gd` 为状态/过渡唯一导演；原雨景 `scenes/main_game_bg/rain.tscn` / `MainGameRain`、`RainStormRenderer`（分层雨幕、地面水花、风场）按强度驱动。SoundManager 统一混音，不要创建额外雨声播放器。
- **没落营地风沙（2026-11-15）**：该关覆盖引用 `fallen_camp_normal_weather.tres` / `fallen_camp_nightmare_weather.tres`，普通阶段维持 0.28 浮尘，噩梦按 `0→7→16→27→36` 秒升至沙暴并保持。`WeatherKeyframe.sand` 与雨/湿镜头独立；`WeatherSequence.sample_channels()` 统一采样，旧 `sample()` 仍返回雨/镜头 Vector2。不要以雨强度代替沙强度。
- **风沙表现与指针**：`SandStormRenderer` / `SandVisualProfile` / `shaders/weather/sand_storm.gdshader` 共用底图坐标，远处沙墙在背景层，流沙和飞砂在现有前景层；显式游戏时钟随暂停停止。噩梦 `sand_cursor_speed=18`（视口像素/秒上限），由同一阵风驱动 `WeatherCursorDrift`，实际满强度约 11～17 px/s 向左漂移。普通浮尘、非战斗阶段、UI 遮挡、按住鼠标、暂停和失焦均不施力；不捕获鼠标。
- **本轮证据与边界**：隔离 user 目录下完成 Godot 4.7.2 导入和 GL Compatibility 完整战场预览，使用真实卡牌、植物和僵尸，最后渲染无脚本/材质/退出报错。最小证据在 `D:\Dev\PvZ\_review\fallen_camp_sand_20261115`。未新增或运行测试；未做完整续战、真实鼠标漂移手感或跨平台性能验收。
- 湿镜头统一 `scenes/weather/weather_lens.tscn` → `WeatherLensController` / `WeatherLensProfile`；光源统一 `WeatherLightField` / `WeatherLightProfile`，关卡预设 `resources/weather/grave_downstream_light_profile.tres`。Bloom、折射、水滴与鼠标擦除都从现有光场/镜头渲染管线实现；镜头擦除只影响水膜，不删除真实雨线或环境光。
- 主要调参先动配置资源，再审 Shader；GL Compatibility 运行、分辨率和 GPU 预算需要测量，不能凭 headless 成功宣称性能达标。全战斗雨景预览入口 `tools/weather_preview/battle_preview.tscn` / `render_battle.gd`；按正式 `--scene` 运行，不能用只有背景的 GIF 冒充完整战斗验收。

### 4.1｜教堂暗场与逐高度地面投影（P4）

- 奇境第 102 关圣堂使用 `scenes/adventure/zombie_church_battle.tscn`。`zombie_church_lighting.gd` 管理普通的亮 10 秒、暗 10 秒，以及噩梦的亮 5 秒、暗 10 秒。两种节奏均以未暂停的真实时间计时，包含短过渡。Boss 登场后环境维持熄灯。战斗 HUD 在独立画布调色，战斗音乐由冒险阶段管理。
- 普通 70 波刷 3–4 阶普僵，噩梦 100 波刷 4 阶普僵，两种难度均只有末波旗帜。复光事件分别补刷 3 阶和 4 阶石像，按自然波进度分五段，每次 1–5 只。自然波前 3 波较轻，第 4 波起增量，刷新间隔乘 0.8。所有敌人共享 30 个在场名额，破壳及转换复用原敌人名额。
- `zombie_church_light_sources.gd` 通过棋盘平均格宽标定角色原画高度、虚拟身体高度、灯高和光源半径。路灯花的玻璃中心控制画面光圈，脚点是虚拟灯的地面垂足。植物、普通僵尸、僵王使用既有生命周期登记。实体换行沿用原脚点和图集格，死亡动作的剪影随实体离树回收，路灯花死亡立即撤销光源。
- `battle_shadow_projection.gd` 选择与灯区相交的剪影，超出 128 格时保留脚点入射光较强的角色。`battle_shadow_atlas.gd` 缓存每格 48×56 的 Alpha 和两纹素透明边。按原纹理分批覆写脏格，每帧最多采样 38 个姿态。采样上限为 24 Hz，36 个活跃角色起为 18 Hz。脚点和主灯仍逐帧更新。
- `battle_shadow_ground.gd` 用 `INSTANCE_ID` 索引四列 RGBAF 参数，给一个共享 MultiMesh 提交每实体一个网格。十个竖段、两个横段共用 `battle_shadow_ground.gdshaderinc`。剪影横向位置沿固定斜轴落在地面上，高度由像素离脚线的距离与固定身体标定换算。顶点独立计算 `S = P + h/(H-h) * (P-L)`，脚线处 `h=0`，灯脚重合时中心线延伸归零。最大影长预算约束临界高度与屏外裁剪，半影由有限灯源尺寸按高度估计。原有接地影负责保留贴脚暗部。
- `battle_light_source.gd` 使用与灯片一致的衰减和光缘扰动给暖灯评分。主灯竞争需领先 25% 持续 0.14 秒，满足时旧影和新影各用 0.07 秒过渡。灯格在一个 384×384 视口内复用，最多 16 盏投影灯，其余暖灯自然补光。统一四分之一分辨率光场用 R 存原始暖光、G 存指针、B 存逐灯扣影后的暖光。每盏灯按自身灯格只衰减自己的份额，原位角色遮罩从 R 恢复 B。世界合成以 B/G 决定亮度和颜色，零覆盖输出纯黑。
- 已删除整张剪影绕脚转向、经验影长下限、近灯旋转死区，以及以同一影量乘所有色温的合成。旧的短影、全屏模糊、假凹凸仍已退役。暗场暖光曝光按同机位测量校准为 0.255，保持原有暗场的可见度范围。
- 使用 GL Compatibility 运行 `--script res://tests/adventure/test_church_shadow_geometry.gd` 验证同线过零、错纵深顶点、真实 GPU 参数表和分灯遮挡。正式第 102 关可复查鼠标绕行、双灯交接、死亡与复光。性能分开记录整帧间隔、脚本提交、渲染 CPU/GPU 与图集刷新，128 个投影加 12 灯的本机压力档低于 60 FPS。
- `BoardRuntime.plant_dying` 在植物释放占格前通知环境，覆盖铲除、伤害死亡和灰烬自毁。教堂只在环境光归零时接收非路灯花的死亡。`zombie_church_plant_remains.gd` 给原占格设置独立禁种来源，同格其他活株仍使用原占位与碰撞。`zombie_church_plant_imprint.gd` 复用精灵 Alpha 帧，冻结死前姿态后放在活株下层。
- 残影的占格中心连续受路灯花照射 8 个未暂停的真实秒后解锁，破散随后收尾。多格植物的各格需同时受光，同格多道残影全部清除才解除禁种。阶段续战沿用原棋盘和残影。路灯花覆盖使用统一光场的衰减，环境光和指针光不参与计时。

### 4.2｜救主遭遇

- 第 102 关的噩梦阶段清空第 100 波后登记救主。环境熄灯，复光出怪结束。救主存活期间每 22 战斗秒最多补刷 18 只 4 阶普僵，比末段每波计划的 30 只少 40%。最后一位救主完成死亡演出并清场后结算。本体固定在第三行，生命为 120000。二阶段在本局余下时间允许打开菜单，战斗时钟继续运行，演出时停和其他暂停因素照常生效。
- 若在自然波次期间手动召唤救主，存活救主把冒险自然出怪换成四阶普通僵尸。一阶段每波两倍名额，二阶段减回一倍，最后一位倒下后恢复模板。波中变化从下一只尚未生成的僵尸生效。援军、信徒及手动生成拥有独立来源。
- 祈祷的原画抬掌帧启动技能。无垠留出 0.18 个战斗秒看清抬手，再用 0.40 秒压暗战场与 HUD。黑场落稳后结算，灰色余像使用当时的原画帧和屏幕位置，随复光自然溶散。安乐用同一黑幕快速闪屏。黑幕让暂停界面和通用切场接管画面，音乐继续播放。
- 疯狂先在高处聚光，再砸向救主的真实脚点。触地的亮芯、贴地冲击、震屏与地鸣同拍触发。一阶段抬掌停到相邻柱底拉开约半个接触半径，二阶段按同一扩散进度收手。`savior_sweep.gd` 提供六束真实接触点、5.2 战斗秒的扫掠及连续命中判定。柱身错峰缓闪，后方由救主原画遮挡，扫出棋盘后先绷紧再抽回。真实红光和投影继续通过 RedMask 合成。
- **P5 地表熔裂** `savior_madness_ground.gd` 接收每个命中物理步的世界接触点，并用同一战斗物理时钟记录出生时间。`savior_fissure_stroke.gd` 用实际平均格宽的 0.10 倍重采样弧长，插值各段出生时间并生成确定性支裂纹。部分支纹采用顺石缝方向的近似偏折。`savior_fissure_geometry.gd` 用一张索引 ArrayMesh 合并全部主裂与分支，最多保留三轮共 18 束、2,592 个活跃主裂样点、216 个分支和 6,444 个三角形。每帧至多一次几何提交，仅在新增或回收样点时执行。
- **冷却与遮挡** `savior_madness_fissure.gdshader` 按真实棋盘行的外沿裁切，分别计算炭化、熔融壁、细裂芯和贴地散射。顶点带独立的出生战斗秒和热量，最长 1.8 秒。停柱后继续冷却，暂停时冻结时钟，换关或退出活动战斗清空。石面在角色下方将 Alpha 透过率乘进现有世界捕获，原位实体覆盖余热。`zombie_church_composite.gdshader` 按统一上限叠加裂隙自发光。世界合成仍输出不透明画面，教堂退出时恢复视口设置。没有增加屏幕复制、纹理或视口。
- **删除项** 旧 `MadnessContact/Trail` MultiMesh、160 槽短贴片和 0.61 秒盖章时钟已删除。移除 `savior_madness_trail.gdshader` 及其 UID。地面冲击仍用原柱底材质和原触地时刻。
- **P5 实机验收** Godot 4.7.2 GL Compatibility、RTX 5060 Laptop、1066×600。第 102 关同机位 A/B 以 `c837bdee` 的旧地表为基线。六束全程扫掠及受控收招后的 0.15、0.55、1.20 秒用于画面对比。64 僵尸和 25 植物（含 5 路灯花）时，旧版到新版的渲染 CPU / GPU P95 分别为 2.50→2.75 / 2.71→3.52 ms，整帧 P95 为 11.87→13.54 ms。15 Hz、2 倍速压力档的整帧 P95 为 12.59→13.95 ms，单个画面帧收到四步真实接触。实测密集档最多 910 个裂隙三角形、约 37 KB 网格和 203 次上传（417 帧），两版场景纹理内存相同。按裁切前的投影三角形面积估算，地表批次的峰值覆盖下降 78.1%。
- **复测与证据** `tests/adventure/test_savior_fissure_geometry.gd` 复查六束弧长、暂停时间、叠轮冷却、场外采样和容量。`tests/adventure/test_church_shadow_geometry.gd` 在 GL 下复查真实光场。`D:/Dev/PvZ/_review/savior-fissure-p5` 保留 `P5-static-AB.png`、`P5-motion-AB.mp4`、`P5-profile.json` 和采集脚本。实景断言覆盖停柱余热、实体遮挡、自然熄灭与主动清空后纯黑、两轮施法、震屏及退出恢复视口设置。旧版和新版的录像采集进程均在退出时报告相同的 ObjectDB 与资源引用告警，详见采集记录。
- **绝望结算** `savior_meteors.gd` 在祷告抬掌后开始 0.85 战斗秒的坠落。四格无放回，重叠按出手顺序逐束结算，每束植物 200 点或最近的路灯花 100 点。触地时获取同一份 `BoardQueries.neighbors()` 供伤害和散晕使用，同时保留有效光束的原编号及吸收灯的垂足、玻璃中心。绝望继续使用掌间祷告变体。
- **垂落红光** `savior_despair_meteor_mesh.gd` 用一个 168 顶点、160 三角形的合批网格绘制从拱顶至前沿的四束透光红幕。`savior_despair_lights.gd` 直接读取同一曲线的前沿，按实际高度与地面垂足更新现有 RedMask 和剪影投影。触地后光芯在 0.50 战斗秒内沿弧长收窄并退回落点，外缘的暗红余辉较晚消散。
- **触地散晕** 同一盏演出灯从格心向外扩大，在 0.74 战斗秒内熄灭。共用灯片遮罩以双轴羽化控制实际 3×3。石面主反光先衰减，低亮度的外沿继续缓慢扩散。吸收变体沿快照收进灯罩，红光遮罩的 G 通道暂时压低暖色表现。B 通道保留正常投影和红光合成。
- **绝望音效** 抬掌释放与实际触地分别播放 `savior_despair_descent.wav` 和 `savior_despair_impact.wav`。`SaviorDespair/Cue` 复用场景 SFX 路由和战斗倍速，四束共用一次落地低响与尾音。实机有声预览为 `D:/Dev/PvZ/_review/savior-despair-tail/Despair-tail-audio.mp4`，录制时单独静音 BGM 以便试听。
- **退场顺序** 结算中的植物亡语可同步杀死救主，已落地各束继续完成伤害，已撤销的演出不会再开启。离开战斗时由 `main_game_progress_update` 同步清除光束、临时灯和技能音效。若先前绘制了红光，暂停后补交一帧现有光场，恢复剩余红灯。
- **实景验收** 第 102 关噩梦，Godot 4.7.2 GL Compatibility。单束阶段隐藏光束网格后，照明对照在地面取样中有 4,451 个像素变亮，红光遮罩可见真实投影。四束实战覆盖 3×3 重叠、路灯花吸收、暂停恢复和退光。预览为 `D:/Dev/PvZ/_review/savior-despair-red/P6-red-preview.mp4`。`test_savior_despair_ribbon.gd` 复查光束几何和前沿，`test_savior_despair_light.gd` 在 GL 下复查边缘裁剪、扩散与吸收。
- **密集场景** `82491a7e` 在 RTX 5060 Laptop 上以 80 只僵尸与 66 株植物（含 6 株路灯花）采样。1066×600 窗口的坠落、散晕整帧 P95 为 16.16、16.34 ms，1440×900 窗口为 15.75、16.57 ms。`P6-red-profile.json` 保留两档的待机、渲染 CPU 和 GPU 原始样本。实测取消中间光束后其余投影身份仍接续，触地时失败只留下救主原有红光。
- 救主周身红光沿用路灯花的半径与衰减，独立遮罩共用投影，合成曝光为两倍。无垠的庇护与亡影清除只采样真实种植的路灯花。
- 救主在场时亡影停止累积清除进度。无垠有可复生亡影才进入抽签，先按同一帧的灯光覆盖结算伤害，再把旧亡影和新死亡产生的亡影复生为信徒。安乐有存活的敌方普僵才进入抽签，任意等阶的普僵均可转换。原体从自然波次扣除且不入死亡档案。
- **没入福音** `savior_gospel_pillar.gd` 初次锁定时跳过从左数第一、第二列及占到这两列的跨格植物。白柱作为 4000 生命的敌方设施接受同格攻击。白柱存活至 12 个战斗秒或原株成功换格时立即成熟，湮灭原株并为施法救主治疗 6000。换格触发的演出位于新格，包括前两列。原株提前离场时白柱留在最后落点。
- **福音演出** `savior_gospel_effects.gd` 共用疯狂的柱身 Shader 与 MultiMesh 实例格式。白色照明进入教堂光场，成熟时同一落点切入红灯与现有投影，击破则在白色余光中回收。`savior_gospel_fragments.gd` 在真实死亡前读取原株当前可见精灵帧，每个部件一次提交带原画纹理的微片网格，碎片先向外崩散并沿红柱上卷，使用同一个战斗时钟收尾。
- **遭遇与结算** 正式遭遇在实例入树前接入死亡、演出完成和离树信号。战斗分组由 `boss_encounter_group_id()` 提供，技能、奖励与 HUD 读取同一身份。`[BossLifecycle]` 记录用战场、分组和实例 ID 关联登记、死亡来源、遭遇结果和胜利阻塞条件。`spawn_instant_kill` 标记新生处决；教堂噩梦仍需打完末波并清空敌人。
- **救主入场与分裂** `savior_cinematic.gd` 驱动传送、原画祈祷和覆盖 HUD 的黑闪。在落黑帧复生已有亡影，对路灯花照不到的植株结算 1000 点伤害，再由 `savior_entry_cross_attack.gd` 在战斗物理步中沿四个方向连续扫掠，`savior_entry_cross.gd` 用同一组接触点绘制柱身与光照，每名救主对同一株结算一次 100 点基础伤害及 30% 劣化。第一阶段严格低于半血时，`savior_split_formation.gd` 准备两名分身，整组登记后才提交本体血池。教堂使用第六列第二、四路。其他棋盘优先选不同有效行的替代地块；不足两格时本体按当前血量继续单体二阶段，并记录降级原因。
- **分裂镜头与承伤** 三位救主各有 20000 生命和可受击的原生实体。时停临时持有 `SaviorCinematic` 暂停因素，特写按本体、第二路、第四路播放半速祈祷，镜头回位后归还战斗与输入，三位同时完成入场攻击后收手。战斗 UI 仅显示以 120000 为满值的底部总血条。分身各自承伤和死亡，福音白柱用光色提示进度。正式遭遇在最后一位完成死亡演出后结算。
- **救主行动树** `savior_action_tree.gd` 按遭遇成员编号分组，在入场或合演结束后等待 8／6 战斗秒。每轮只抽一次，存活成员同帧起手，等实际抬掌帧到齐后同帧释放。无垠的全场伤害和安乐最多八只转化均每轮结算一次，各位分身分别发出疯狂光柱、绝望流光或福音白柱。福音优先锁不同格，疯狂的同步触地共用一次震屏和地鸣，绝望的同时下坠与触地分别共用一声。无垠在实际抬掌帧保存余像和屏幕位置；任一成员存活即可接手已释放的全场结算，整组离场时撤销其待播请求。
- **手动召唤** `scenes/fx/savior_battle.tscn` 统一管理入场、技能与分裂。教堂为它提供光场和亡影；普通战场首次召唤时才挂载场景，路灯花庇护按同一灯罩位置和衰减结算。导演队列只保存演员实例编号，已经退场的请求会跳过，后续演员照常入场。
- **施法者轨道** `scenes/fx/savior_spell_track.tscn` 是本体与分身共用的初始定义。停招保留本通道可复用的灯池；销毁分身通道时同步注销灯并释放挂在世界层的锚点。
- **救主传送** `savior_teleport.gd` 用移动的世界光源照出真实石面与剪影。角色后方的空气在世界层合批，随同一光场调色，角色保留原有尺幅和姿势。离场收光后发出死亡完成通知。入场落光、离场聚光与三次特写的实际最高抬掌帧各敲一次。临时照明仅用于演出。钟声取自 HMTSCCSound 录制的 Bethesda 教堂最低钟，截取单击、略降调并保留 13 秒衰减。[原录音](https://freesound.org/people/HMTSCCSound/sounds/554655/) · [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)

## 5｜美术/动画、僵尸、Boss：必要工作方法

- **Savior 美术演出**：`scenes/character/zombie_boss/savior_visual.tscn` 默认循环原画待机，原祈祷仍可单独预览。`cast_prayer` 接收世界坐标格子矩形数组。原画双掌完全展开时发出 `prayer_released`，主滴在 0.28 个战斗秒后接触首个有效格，其余格按距离展开，`prayer_finished` 在角色回到待机时发出。`cancel_prayer` 同步结束本次表现。墨滴和刻痕在世界画布接受教堂遮罩，保留光圈外纯黑。
- **PVZ 2009 手绘素材规范**：先读清单 → 核对复用件、轨道、尺寸、透明通道与锚点 → 仅有必要时写提示词并生成 → 审核 → 必要分层/拆件与真实 PNG/GIF 烘焙 → ZIP/实装/验收。母图结构与观感已通过时，局部明暗、颜色和遮罩优先确定性处理；不要因可修的局部缺陷重复重生整图。主菜单受光严格走 §5.1，禁止以生成式昼夜变体代替程序渲染。手机预览上传后须实际读回校验，失败使用已说明的备用入口，不虚构链接。
- **原版分件动画**：PvZ2 PAM 转换须保留稳定 ref ID、增量关键帧的继承、原始层级、显隐与事件帧；不能把画层顺序误当实例身份。全明星 `scenes/character/zombie/zombie_026_all_star.tscn` / `scenes/character/zombie/all_star_original_animations.tres` 可复查已建立的转换管线。
- **向日葵转职外观**：原版 `plant_002_sun_flower.tscn` + SunFlower_idle 动画/原 `assets/reanim` 分件；新资源 `assets/adventure/plants/sunflower/manifest.json`；接入 `scripts/adventure/plant_art/adventure_sunflower_promotion_art.gd`。原动画有 texture 轨道，不能直接改 Sprite.texture；需挂载随原动画运动的分件。战斗、卡面与技能书复用同一转职阶段逻辑。
- **僵尸等阶**：`scripts/adventure/adventure_zombie_tier_catalog.gd` → binding/traits/species installer；美术 `assets/adventure/zombies/tier_art_map.json`。固定格挡、二类防具、额外护甲、技能/抗性需独立算，不能只看总 HP；平衡基于整套植物/僵尸阵容与实战消耗（五阶主要对标十星植物），不要做单卡云比较。
- **墓碑/Boss**：`StagePhaseDefinition.gravestone_rules` / `AdventureGravestoneDirector` / TombStoneManager，墓碑的刷新/复生必须使用本格实际生成点；常规旗帜刷怪和特定 Boss 复生的规则分别配置。Boss 统一血条/阶段状态，经 `ZB000Base`、ZombieManager、SoundManager 管线；美术封口不等于行为树和实战验收完成。黑将军实体 `scenes/character/zombie_boss/zombie_boss_002_black_general.tscn`，不要把旧策划数值当作工程当前实际配置。

## 5.1｜正式海滨主菜单 9B：全天时间、档案与建筑入口

- **正式入口/返回**：`res://scenes/main/01StartMenuCoastal.tscn`；project、MainSceneRegistry.StartMenu及地图返回均统一。旧01/V6/V8场景仅重定向，旧V6/V8运行脚本已删除，不再实例化旧环境。详细维护见[正式运行管线](main_menu_runtime_pipeline.md)。
- **运行所有权**：`scripts/ui/start_menu/coastal/`＋`shaders/ui/main_menu/`＋`assets/adventure/main_menu/coastal/`。制作工具 `tools/art_bake/main_menu/menu.py` 复用同一运行实现；不在玩家运行时调用Python/GIMP或依赖ArtControl绝对目录。
- **视觉与数据**：既有母图/灰度/法线/地面/港口/风/高亮沿用已批准来源，母图 SHA256 `71ed1970fb89c206a4b97fd6dde9cca1c3792b23e3f6f574d0839b6dfdc2ed02`。运行纹理无损发布为原生 `.res`，`texture_catalog.json` 为唯一映射，`asset_store.gd` 按宿主缓存。旧溢光与旧灯组自发光复用现有纹理的 Alpha 通道，RGBA32F 光场保留原精度。
- **时间调参**：运行config/daily_cycle.json为24小时环形关键帧：深夜→黎明→清晨→白天→黄昏→夜晚，午夜连续。menu_clock读当地时间并平滑校准，daily_cycle只产显示参数；动画用单调计时，任务/战斗日期不由菜单控制。set_preview_hour/use_local_time是同一路径的制作覆盖，不修改系统时间。
- **真实UI/业务**：原User选择器提取为scenes/ui/profile_selector.tscn，复用SaveService事务；HUD显示真实头像/等级/名字并在切档后同步。功能台设置共用工具栏入口；帮助更新当前操作；退出确认后保存，失败留在菜单。布局在ui_layout.json，窗口阻塞与建筑/工具栏互斥统一。
- **建筑入口**：沿用9A稳定命中与动态同步高亮；图书馆→真实图鉴、研究室→原研究功能、港口/船→地图。家/商店仍未开放、皮卡无独立入口。解锁由同一toolbar_entry_host查询/请求，不存于美术配置。
- **2026-11-13视觉整理**：日间方向光、暮色冷暖、远景空气透视和夜间暖窗已重调；母图与31份纹理不变。船/风/水分为8.4/9.6/11.2秒，低幅错相灯光由显式动作时钟驱动。入口用 `building_entry_badge.gd` 显示图鉴/研究室/启程，原命中几何不变；锁定原因仅聚焦显示。档案经 `configure_coastal_presentation()` 使用296×118小卡片，其他场景保持原布局。正式调色、运动与entries现由runtime_inputs保护，旧制作发布不得覆盖；重建蒙版时需明确同步正式几何。核对目录 `D:\Dev\PvZ\_review\menu_polish_20261113`：五时段、牌面原生点击打开研究/地图导航/图鉴/档案、键盘焦点、锁定与模态遮挡、1066×800命中及144帧动作片段；原生日志无脚本/材质错误，未运行测试套件或进入战斗。
- **实际核对**：本轮隔离录制含240帧全天、556帧真实档案切换/设置帮助/功能窗口/地图往返/退出保存；午夜前后最大像素差0，旧菜单宿主入地图后释放。原生资源逐份重开像素一致，空工程PCK绘制与正式背景最大差昼0/夜1。最终原生日志无脚本/材质ERROR或退出泄漏报告。
- **发布与复现**：menu.py publish-runtime / runtime-preview / runtime-preview-images为单入口。交付在 `D:\Dev\Tools\ArtControl\runs\main-menu-stage9b-runtime-20261112`。运行daily_cycle/ui_layout为正式权威，不被旧制作目录覆盖；原生资源包已验证可搬迁，但未安装exe模板、未导出完整游戏exe。
- **边界**：只操作PVZ-Menu9B-Isolated-20261112演示档案，未读写正式玩家存档；没有进入战斗/验收合成事务，没有物理睡眠唤醒或全平台性能验证。未新增/运行游戏测试套件；旧版本专用美术探针已标明退役，不作为新菜单通过证据。实机短采样数据与详细限制见维护页，不夸大为完整回归或发布保证。

## 5.2｜主菜单效果：参数可达、算法替换与重载

- **权威索引**：[效果调参与扩展接口](main_menu_effects_api.md)，按各阶段列出“配置→方法→材质→重建/发布”。正式效果文件为 `assets/adventure/main_menu/coastal/config/effect_profile.json`，正式默认已启用低幅错相灯光和独立水周期；空hover使用当前内侧暖边高亮。强变化示例只放在 tools/art_bake/main_menu/effect_examples。
- **明确方法**：菜单 `reload_visual_effects()`；宿主 `reload_effects()`；`host.effects.set_hover_effect / set_light_behavior / set_water_effect / apply_profile / snapshot / describe`。错误输入不半更新，返回error且保留上次有效状态，不碰档案/入口权限。
- **hover替换**：entry_highlight维持命中反馈和过渡，Shader按entry_mask/strength/accent/effect_seconds契约替换，参数按真实uniform名称/类型验证；内置entry_sweep示例不默认启用。不再为换高亮算法修改输入控制器。
- **灯光行为**：light_behavior按home/library/shop/research四组支持steady/breathe/flicker/off，窗口、接收光、光晕共用倍率；日周期不能覆写倍率，显式动作秒数决定波形。独立到单扇窗或新增灯组仍需重建通道资产，不虚构任意命名光源。
- **水面扩展**：water_surface.gdshaderinc只拥有表面位移/亮纹；water_effect负责drift/ripples/still与独立周期，保留岸线/遮挡和船体合成。水速改变不改船phase；普通幅度在motion.water，接触波纹仍独立。
- **所有权与生效**：effect_profile与daily_cycle/ui_layout是运行所有，发布旧制作资产时不得覆盖。参数索引明确区分即时重载、重进菜单、重建蒙版/浮点场、显式发布；风/几何/业务不因本次例子扩张重构。
- **接口历史核对（2026-11-12）**：正式宿主空工程完成三个案例、错误配置保留状态、文件重载恢复默认及全天参数提交不覆盖灯光调制。当时中性默认夜景/hover与基线像素完全一致，白天只有1像素相差1/255；该结论不适用于11月13日重新调色的默认表现。未新增/运行游戏测试套件、未加载玩家服务。
- **复现**：`menu.py effects-preview --workspace <独立目录> --tools-config <原生工具配置>`；本轮证据目录 `D:\Dev\Tools\ArtControl\runs\main-menu-effects-access-20261112`。制作预览复用正式组件，不维护第二套效果算法。

## 6｜验收与交接收口

- 核对**真实运行链路**：关卡启动、参数投影、有效场景格子、真正的卡槽扣费与冷却、入水触发、屏幕绘制。原版泳池与下水道两处均需回归。尤其关注承托植物种植/铲除/读档和跨行错位。
- 验证遵循 `AGENTS.md`：默认不新增、不运行测试；同步已有测试的失效接口引用，执行 Godot 4.7.2 headless editor 导入/解析。明确获授权后再运行相关水面、承托、关卡和存档测试；解析成功不等于测试或完整视觉验收通过。
- **仍需实机终验**：自定义稀疏坐标、移动平台/静止鼠标交互、荷叶多层随动、地形切换和稳定 ID 读档；下水道第 1、5 路水面动态实际可见性、荷叶及上层植物长期浮动/格子对齐、僵尸游泳、真实卡槽阳光结算、原版泳池兼容；暴雨长时性能和正常通关接续噩梦流程亦不能仅以单元测试判定。
- 交接文档永远只保留**当前唯一管线、权威路径、真正可复用的方法与未关闭风险**；旧补丁路径、临时测试结论、过期链接、冗余清单和随时变化的 Git 提交快照不写入正文。
