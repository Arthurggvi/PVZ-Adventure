# PVZ-Adventure｜唯一权威项目交接

更新：2026-11-11。**只记录权威路径、可复用管线、实施方法、有效约束和未关闭的验收边界。** 源码与实际资源优先于本文；“接入”“自动化通过”“实机视觉通过”必须分别表述。

## 0｜权威入口、施工纪律（先读）

- **工程与引擎**：`C:\Dev\PvZ\PVZ-Adventure`（Git `develop`）；Godot 4.7.2：`C:\Users\Arthu\Desktop\Godot_v4.7.2-stable_win64.exe`。Sancho 在线时优先远程只读审计，获授权后直接施工，避免让用户手工搬运文件。
- **本交接文档唯一原件**：`C:\Dev\PvZ\_reference\project_docs\PVZ_Adventure_Project_Handoff.md`。Git 跟踪入口 `docs/adventure/PVZ_Adventure_Project_Handoff.md` 是**同一 NTFS 硬链接**，不应独立编辑/替换。改动需原位写入，并用 `fsutil hardlink list` 验证仍为同一文件。
- **资源权威范围**：`res://assets/adventure/`（新增素材）、`res://assets/reanim/`（原版分件）、`res://animation/`、`res://scenes/`、`res://scripts/`、`res://resources/`。仓外 `C:\Dev\PvZ\_review\<module>` 用于临时审查；`C:\Dev\PvZ\_reference` 为持久参考。游戏运行时不能依赖仓外文件。
- **施工顺序**：检查 Git 和连接 → 读本文及权威代码/资源 → 复现并定位根因 → 设计通用接口与状态所有权 → 直接重构旧实现 → Godot 导入与定向测试 → 真实场景渲染/视觉自审 → 必要时 Catbox 手机验收 → 仅暂存本轮文件并提交。
- **仓库纪律**：先 `git status --short`、`git log -1`，保护并行工作区；禁止未授权的 `git reset`、`git clean`、`git add .` 和 `git push`。提交前 `git diff --cached --check` 并逐项核对暂存清单。被 `.gitignore` 忽略的新美术资源，必要时定向 `git add -f`。
- **架构原则**：一条权威数据与状态链；配置描述差异，组件实现机制。禁止针对某一关/植物/僵尸追加并行实现、补丁式坐标修正、冗余管理器或把重复接线留给后续开发者。

## 1｜核心系统权威总线

| 系统 | 唯一入口与维护边界 |
|---|---|
| 冒险关卡与续战 | `AdventureStageRegistry` / `AdventureStageCatalog` → `AdventureStageOverride` → `AdventureBattleEnvironmentAdapter` → `ResourceLevelData` / `AdventureSession.active_phase` → `AdventureBattleRuntime`、WavePlanner、BossDirector、`AdventureContinuationController`。进入不询问难度；普通结束后有钥匙可选择接续噩梦。 |
| 战场水陆地形 | `AdventureBattleEnvironment.terrain_rows` → `ResourceLevelData.terrain_rows` → `ZombieManager` 行类型、`PlantCellManager` 格子类型、`GIM_LawnMover` 清洁车。视觉材质不能代替地形判定。 |
| 水面视觉与接触 | `AdventureBattleEnvironment.water_surface_profile` → `BackgroundManager` → `WaterSurfaceController` / `WaterSurfaceProfile` → 同源 `WaterBodyArea`；泳池和局部水沟共享水面 Shader 与入水协议，详见 §2。 |
| 植物种植与承托 | 卡片 `HMCharacter.click_cell` → `PlantCell.create_plant` → 实体占用成功 → 卡片 `signal_card_use_end` 费用/冷却结算。`PlantCell` 持有地形条件、占格、承托层锚点；详见 §3。 |
| 研究室/植物卡牌 | `PlantCardInstance` / `PlantSpawnProfile` / `AdventureBattleAdapter` / `PlantSceneFactory`；合成、强化、转职、扣料经 `ResearchService → ResearchTransaction`。战场、卡面、技能书外观基于同一实例/阶段。 |
| 资产、存档、玩家 | `GlobalGameState.adventure_state` → `AdventureInventoryService` → SaveService / SaveFileStore；存档 `user://<profile>/GlobalSaveGame.json`。卡牌实例有独立 UID；玩家战斗效果取冻结快照，装备经事务服务处理。 |
| 天气/雨/镜头 | `StagePhaseDefinition.weather_sequence` → `BackgroundManager.transition_weather` → `BattleWeatherDirector` → 雨幕、雨声、`WeatherLensController` / 光场；详见 §4。 |
| 僵尸、墓碑、Boss | 僵尸等阶 catalog → binding/traits/species installer；墓碑 `gravestone_rules` → `AdventureGravestoneDirector` → TombStoneManager；Boss 由 ZombieManager / ZB000Base 管理阶段与统一 HUD，物种行为树独立。 |
| 调试 | `addons/pvz_cheat/`。修改器可快速布卡/物品/波次，但不能以绕开正常放置及扣费的结果代替完整玩法验收。 |

六关顺序：草坪、没落营地、墓地上游、墓地下游、下水道、埃德加神殿。非商业单机二创。

## 2｜通用水面：原版泳池与下水道 1、5 路

**权威路径**
- 战场底图：`res://assets/adventure/environments/battle_backgrounds/05_sewer_interior_water.png`（1400×600）。
- 下水道覆盖：`res://resources/adventure/stages/overrides/zombie_island_sewer.tres`，其中 `terrain_rows_override = [Pool, Land, Land, Land, Pool]`（对应整数 `[1,0,0,0,1]`）、`water_surface_profile` 指向 `res://resources/water/sewer_water.tres`。
- 通用视觉：`scripts/water/water_surface_controller.gd`、`scripts/water/water_surface_profile.gd`、`shaders/water/water_surface.gdshader`；接触体：`scripts/water/water_body_area.gd`。原版泳池由 `scripts/main_game_item/pool.gd` / `scenes/main_game_bg/pool.tscn` 接入同一 Shader，日夜参数在 `resources/water/pool_day.tres`、`pool_night.tres`。

**正确实现方法**
1. 水底纹理保留静态颜色、池壁和边界；水面独立渲染多频 UV 波纹与焦散。`WaterSurfaceProfile.regions` 使用**背景原图像素坐标**定义水域；改动底图时重新校准区域并实际看图，不能靠关卡 ID 或绘制后的屏幕坐标猜测。
2. `WaterSurfaceController.configure_background` 从同一 `regions` 创建水面 `ColorRect` 与 `WaterBodyArea` 碰撞矩形；`configure_sprite` 支持原版泳池独立贴图。每区域私有材质；游戏时间 `water_time` 受暂停控制，`set_intensity` 调节强度。
3. 僵尸 `SwimBoxComponent`（普通/潜水）通过检测 `area is WaterBodyArea` 进入或离开水，触发身体下沉、游泳动画/水花；不得恢复 `area.owner is Pool` 的旧场景类型耦合。僵尸能否在某行生成、植物能否在该行种植仍取 `terrain_rows`，两种判定不可混用。
4. 改水路时必须同时检查底图、区域视觉、物理入水体、僵尸游泳状态、格子种植条件及泳池清洁车。只画绿水或只添水面 Shader 都不算完成。

**验证入口**：`res://tests/adventure/test_water_surface_integration.tscn`，检查区域、物理进入/离开、游戏帧推进、原版泳池协议。该测试通过只证明管线；完整战斗中的水波可见性、层级和游泳姿态仍须实机/逐帧视觉核验。

## 3｜种植事务与荷叶/花盆承托布局

**权威路径**
- `scripts/main_game_item/plant_cell.gd` 与 `scenes/ui/plant_cell.tscn`；基础承托类 `scripts/character/plant/plant_000_down_base.gd`；荷叶 `scenes/character/plant/plant_017_lily_pad.tscn`；水陆行投影 `scripts/manager/plant_cell_manager/plant_cell_manager.gd`。
- 正式种植与特殊植物条件分别经 `PlantCell.create_plant` / `ResourcePlantCondition`；荷叶 `condition_017_lily_pad.gd`。水路原始条件为 `9`（空/水），荷叶成功占用 Down 槽后为 `17`（空/荷叶）；移除后恢复 `9`。

**不可违反的事务规则**
1. `Plant000DownBase.init_plant` **只初始化实体**，不得提前切换格子地形。正式 `create_plant` 完成两次资格与占用校验，生成成功并写入 `plant_in_cell` 后，才由 `PlantCell._sync_support_terrain_condition()` 根据 Down 槽实际占用推导地形；释放/死亡时再同步。不得回退到旧版位掩码异或翻转。
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

- **PVZ 2009 手绘素材规范**：先读工程素材清单 → 核对原版复用件、动画轨道、尺寸、透明通道与锚点 → 必要时写提示词文档 → 再生图 → 审核不合格即返工 → 拆分、烘焙 PNG/GIF → ZIP/实装 → 真实场景测试。禁止未经需求核对直接生图。手机要求预览时，实际上传 Catbox 并校验可访问性、帧数、尺寸；不虚构链接。
- **原版分件动画**：PvZ2 PAM 转换须保留稳定 ref ID、增量关键帧的继承、原始层级、显隐与事件帧；不能把画层顺序误当实例身份。全明星 `scenes/character/zombie/zombie_026_all_star.tscn` / `scenes/character/zombie/all_star_original_animations.tres` 可复查已建立的转换管线。
- **向日葵转职外观**：原版 `plant_002_sun_flower.tscn` + SunFlower_idle 动画/原 `assets/reanim` 分件；新资源 `assets/adventure/plants/sunflower/manifest.json`；接入 `scripts/adventure/plant_art/adventure_sunflower_promotion_art.gd`。原动画有 texture 轨道，不能直接改 Sprite.texture；需挂载随原动画运动的分件。战斗、卡面与技能书复用同一转职阶段逻辑。
- **僵尸等阶**：`scripts/adventure/adventure_zombie_tier_catalog.gd` → binding/traits/species installer；美术 `assets/adventure/zombies/tier_art_map.json`。固定格挡、二类防具、额外护甲、技能/抗性需独立算，不能只看总 HP；平衡基于整套植物/僵尸阵容与实战消耗（五阶主要对标十星植物），不要做单卡云比较。
- **墓碑/Boss**：`StagePhaseDefinition.gravestone_rules` / `AdventureGravestoneDirector` / TombStoneManager，墓碑的刷新/复生必须使用本格实际生成点；常规旗帜刷怪和特定 Boss 复生的规则分别配置。Boss 统一血条/阶段状态，经 `ZB000Base`、ZombieManager、SoundManager 管线；美术封口不等于行为树和实战验收完成。黑将军实体 `scenes/character/zombie_boss/zombie_boss_002_black_general.tscn`，不要把旧策划数值当作工程当前实际配置。

## 6｜验收与交接收口

- 核对**真实运行链路**：关卡启动、参数投影、有效场景格子、真正的卡槽扣费与冷却、入水触发、屏幕绘制。原版泳池与下水道两处均需回归。尤其关注承托植物种植/铲除/读档和跨行错位。
- 自动化：运行相关的 `test_water_surface_integration.tscn`、`test_ground_support_transaction.tscn`、`test_lily_pad_support_layout.tscn`，同时跑 Godot 4.7.2 headless editor 导入。测试通过不等于完整视觉/用户手操已验收。
- **仍需实机终验**：下水道第 1、5 路水面动态实际可见性、荷叶及上层植物长期浮动/格子对齐、僵尸游泳、真实卡槽阳光结算、原版泳池兼容；暴雨长时性能和正常通关接续噩梦流程亦不能仅以单元测试判定。
- 交接文档永远只保留**当前唯一管线、权威路径、真正可复用的方法与未关闭风险**；旧补丁路径、临时测试结论、过期链接、冗余清单和随时变化的 Git 提交快照不写入正文。
