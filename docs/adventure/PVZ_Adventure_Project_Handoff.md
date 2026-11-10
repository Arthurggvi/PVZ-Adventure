# PVZ-Adventure｜唯一权威项目交接

更新：2026-11-10。此文件只记录有效的权威入口、施工方法、当前系统边界及下一次接手必须知道的风险。**功能已接入、自动化验证通过、人工视觉验收通过是三个不同状态**；不得相互代替。

## 0｜唯一权威路径与仓库纪律（每次先读）

- **工程**：`C:\Dev\PvZ\PVZ-Adventure`（Git：`develop`）；Godot 4.7.2：`C:\Users\Arthu\Desktop\Godot_v4.7.2-stable_win64.exe`。Sancho 在线时，优先 Remote Desktop Commander 远程只读核验、再按授权直接施工。
- **本文件唯一权威原件**：`C:\Dev\PvZ\_reference\project_docs\PVZ_Adventure_Project_Handoff.md`。在工程 Git 中的 `docs/adventure/PVZ_Adventure_Project_Handoff.md` 为**同一 NTFS 文件的硬链接跟踪入口**，只用于版本控制，禁止当成第二份可独立修改的权威稿。若编辑器以“保存为新文件再替换”方式写盘，须核对并重建硬链接，防止两处脱钩。
- **权威项目资源**：`res://assets/adventure/`（新增冒险美术），`res://assets/reanim/`（原版分件），`res://animation/`、`res://scenes/`、`res://scripts/`、`res://resources/`；仓外审查 `C:\Dev\PvZ\_review\<module>\`、长效资料 `C:\Dev\PvZ\_reference\`。运行时不得引用仓外临时资源。
- **工作顺序**：确认连接/仓库状态 → 读本文与对应权威源码/资源 → 审计可复用管线 → 用现有模型和配置最小改动 → Godot 导入/真实场景烘焙 → 自审 → 定向测试/性能 → Catbox 交付 → 定向 Git commit。
- **Git**：先 `git status --short` 和 `git log -1`；保护用户并行改动。禁止无授权 `git reset`、`git clean`、`git add .`、`push`；只暂存本轮文件，执行 `git diff --cached --check`，提交后报告 hash 与工作区剩余修改。`assets/adventure/*` 的忽略文件须必要时定向 `git add -f` 并核对清单。
- **工程要求**：一条权威数据总线；组件可配置、可替换、相互解耦。拒绝补丁堆叠、为未来植物/僵尸开发者增加重复接线、在场景 ID 上硬编码天气或战斗状态。

### 0.1｜素材 / 动画 / 手机验收

- 先确认原版分件、动画轨道、尺寸、RGBA、锚点、图层和 PVZ 2009 手绘风；优先复用。必要缺件先列资源清单和提示词，再绘制；不合格的透明度、裁切、比例、风格直接返工。禁止把有背景的展示图当作可用分件。
- 动画验收要用真实工程数据烘焙完整 GIF，逐帧核对动作、遮挡、锚点、循环、切图与音效事件；不得只看静态拼装图。PvZ2 PAM 转换必须保留增量关键帧、稳定 ref ID 和继承显隐/变换，绘制顺序不作为实例身份；原版 FScmd/事件帧须保留。
- 用户要求手机预览必须**实际上传 Catbox 并给直链**：静态 PNG/JPG、动画 GIF、必要时 ZIP。检查上传 HTTP 200、文件大小/MIME、GIF 帧数与画面裁切。上传不是渲染验收；优先在 Godot 真实场景烘焙而非伪造预览。Catbox GIF 大文件可能失败，必要时降帧率/保留全尺寸。
- 优先定向 headless editor 导入与真实场景测试。**Godot headless 0 错误不等于完整动画/战斗视觉验收**；测试范围以本轮功能和明确验收指标为准。

## 1｜项目权威总线与有效系统

| 模块 | 唯一入口 / 关键维护约束 |
|---|---|
| 关卡与续战 | `AdventureStageRegistry` / `AdventureStageCatalog` → `AdventureSession.active_phase` → `AdventureBattleRuntime` / WavePlanner / BossDirector → `AdventureContinuationController`。普通完成后有钥匙可选择噩梦；续战切换实际阶段并重置波次。 |
| 天气（详见 §2） | `StagePhaseDefinition.weather_sequence` → `BackgroundManager.transition_weather` → `BattleWeatherDirector` → 原版雨景/雨声、RainStormRenderer、WeatherLensController 与光场。**天气配置与阶段切换彼此解耦。** |
| 资产与存档 | `GlobalGameState.adventure_state` → `AdventureInventoryService` → SaveService / SaveFileStore，存档 `user://<profile>/GlobalSaveGame.json`；卡牌资产使用独立 UID，不允许第二资产源。 |
| 植物 / 研究室 | `PlantCardInstance` / `PlantSpawnProfile` / `AdventureBattleAdapter` / `PlantSceneFactory`；合成、升星、转职、扣料经过 `ResearchService → ResearchTransaction`，失败事务回滚；卡牌、战场、书面视觉复用同一表现入口。 |
| 玩家 / 背包 | `PlayerProgression` / `PlayerEffects` 用战斗冻结快照；背包 11×6 / 四类别，ItemRegistry 及 `res://assets/adventure/ui/items/item_icon_map.json` 为图标映射；装备六槽由 PlayerEquipmentService / PlayerTransaction 管理。 |
| 僵尸等阶 | `adventure_zombie_tier_catalog.gd` → binding / traits / species_installer；权威美术 `res://assets/adventure/zombies/tier_art_map.json` → `AdventureZombieTierArt`。美术继承不代替行为继承。 |
| 可攻击墓碑 | `StagePhaseDefinition.gravestone_rules` → `AdventureGravestoneDirector` → TombStoneManager；PvZ2AttackableTombstone / PvZ2TombstoneTarget 统一占格、受击和损伤。 |
| 全 Boss | ZombieManager / ZB000Base → 阶段信号 → SoundManager、LevelInfo / boss_hp_progress_bar，统一头像+血条；个别 Boss 行为由独立行为树实现。 |
| 调试 | `addons/pvz_cheat/`，用于卡牌、材料、快速通关等定向测试；不可绕开正常玩法业务链作为正式验收。 |

六关：草坪 → 没落营地 → 墓地上游 → 墓地下游 → 下水道 → 埃德加神殿。非商业单机同人。功能完成度以现有源代码及实际测试为证，不凭文档描述推断。

## 2｜墓地下游噩梦暴雨：当前权威天气实现（2026-11-10）

### 2.1 关卡触发与时间轴

- **只有第四关「墓地下游」进入噩梦阶段才启动当前暴雨**；普通阶段无雨，第二关「没落营地」无雨。权威配置 `res://resources/adventure/stages/overrides/zombie_island_grave_downstream.tres`：`weather_lens_profile` 和 `nightmare_weather_sequence`。不得将 `AdventureBattleEnvironment.rain` 或共享地区默认值改成全程下雨。
- **唯一触发链**：`AdventureContinuationController` 在接续噩梦后调用 `game.background_manager.apply_phase_weather(AdventureSession.active_phase)` → `BackgroundManager.transition_weather(timeline)` → `BattleWeatherDirector.play_sequence`；`StagePhaseDefinition.weather_sequence` 为可选，空值代表保持原天气。该 API 也允许其他关卡/剧情从任意天气过渡到目标天气。
- **时间轴资源**：`res://resources/weather/grave_downstream_nightmare_weather.tres`，`WeatherSequence` + `WeatherKeyframe`。关键帧 (秒, 雨强度, 湿镜头强度)：`(0, .04, 0) → (6, .18, .07) → (15, .47, .34) → (26, .81, .75) → (36, 1, 1)`；使用 smoothstep 插值，36 秒后**永久保持最后状态**直到显式新天气，不允许自动回晴。满雨原版粒子发射比 `rain_particle_ratio_at_full = .68`。
- 雨与镜头可以分开配置；设置静态持续下雨的关卡不必提供过渡关键帧。注意过渡和持续状态都应按战斗时间推进，暂停不前进，离开场景释放状态。

### 2.2 雨、风、地面与音频

- **主入口** `scripts/weather/battle_weather_director.gd`；原雨景 `scenes/main_game_bg/rain.tscn` / `scripts/main_game_item/back_ground/main_game_rain.gd`：保留 `GPUParticles2D` 和 Fog/Fog3，`MainGameRain.set_intensity` 同时调节原粒子 `amount_ratio`、雾与 `SoundManager.set_rain_intensity`，退出雨景停止雨声。天气导演**按需生成**雨景，初始无雨的普通阶段不要提前占用资源。
- **分层暴雨** `scenes/weather/rain_storm_renderer.tscn` → `RainStormRenderer`，使用 `rain_curtain.gdshader`（远/中/近三层速度与尺度）、`rain_splashes.gdshader`（地面溅水）、`rain_storm_clouds.gdshader`（天空暗云），阵风 `RainWindField`。已有雨景粒子保留；不要复活已废弃的旧雨线 Shader。
- **唯一美术参数** `res://resources/weather/grave_downstream_storm_visual.tres`（RainVisualProfile）：三层雨密度/不透明度、速度、阵风、溅水、雨色、地面范围、压暗。按关卡配置引用 `WeatherSequence.rain_visual_profile`；其他关卡可不设置而保留默认雨场景表现。改强度先调资源，不在 Shader 和关卡 ID 间散落常量。
- 视觉上暴雨应来自密集但透明的近景雨线、空间尺度差、阵风改变斜率、地面溅水；过高的纯白雨线和强烈均匀灰雾均属返工对象。

### 2.3 湿镜头、局部光场与 Bloom

- **表现入口** `res://scenes/weather/weather_lens.tscn`（独立 CanvasLayer 8，游戏卡槽 CanvasLayer 10+ 保持独立）→ `WeatherLensController`。预设 `res://resources/weather/rainstorm_wet_lens.tres`（WeatherLensProfile）：柔焦、Bloom、雾色/强度、水珠、折射、擦拭半径/恢复时间、闪电与可选 `light_profile`。镜头使用屏幕 UV，不随摄像机平移；背景光锚点使用背景 Sprite 的变换转换成屏幕 UV。
- **共享光场** `WeatherLightField` / `WeatherLightProfile` / `WeatherLightSource`，地图配置 `res://resources/weather/grave_downstream_light_profile.tres`：月亮、窗户、提灯、两组烛火。半分辨率 `SubViewport` 光场 + 两张四分之一分辨率 tight/wide Bloom；着色器 `weather_light_field.gdshader`、`weather_bloom_blur.gdshader`。通过 `WeatherLensController.get_light_field_texture()` 向 RainStormRenderer 分发光场；其他实体可通过 `register_light_emitter` / `unregister_light_emitter` 注册动态光源。静态 5 光源，统一容量上限 8。
- **全分辨率最终合成** `shaders/weather/wet_lens.gdshader`：独立亮度光场的多尺度 Bloom + 空气散射 + 非均匀柔焦 + 水膜折射/反光/高光压缩；雨线和地面水花读取同一光场以响应冷月光、暖烛光。未提供 LightProfile 的雨关走兼容旧泛光。避免多全屏 Shader 无序屏幕采样；必要时正确处理 BackBufferCopy/离屏纹理更新。
- **水珠、交互隔离** `WeatherLensDroplets` 负责附着、增长、合并、滑落；`WeatherLensWipe` 负责鼠标轨迹/指数恢复，Shader 仅采样二者 uniform。鼠标只擦掉镜头水膜相关模糊/水珠，不擦掉环境中的真实雨和大气光。光场、雨幕、镜头均不直接写战斗资产或阶段状态。
- **注意性能**：当前镜头 Shader 仍有 24 个擦拭点 / 20 颗水珠片元循环；不要无预算叠加更多全分辨率 Pass。光场半分辨率、Bloom 四分之一分辨率，目标 1066×600 / 60FPS；2ms 额外 GPU 目标仅为设计预算，尚未实测证实。适配当前 GL Compatibility，不能假设 Forward+ HDR 可用。

### 2.4 验证方法与边界

- **完整战斗预览**：`res://tools/weather_preview/battle_preview.tscn` / `render_battle.gd`；通过 Godot 正常 `--scene` 启动（渲染驱动 `opengl3`），**不要**用 `--script` 替代完整自动加载场景。预览在隔离用户数据环境中运行，真实场景 `MainGame01Front.tscn`，含 7 卡槽、12 植物、5 僵尸；人为触发噩梦天气时间轴，输出 54 帧到 `%TEMP%\pvz_weather_battle_preview`，ffmpeg GIF 后上传 Catbox。演示用背景为墓地下游，不能拿仅有背景的 GIF 冒充完整战斗。
- **现有证据**：Godot 4.7.2 editor headless 退出码 0；OpenGL Compatibility 完整战斗烘焙 54 帧，stderr 0，普通雨势 0、噩梦渐强至 1；光源过曝已实机调校收敛，最后提交天气光学主线 `905986e6`。正式图像（非设计图）由 Catbox 上的最终 GIF 验收；临时预览链接不写入长期权威文档。
- **未验收**：正常游玩完整走“普通通关 → 钥匙弹窗 → 确认噩梦”与后续阶段续存；高密度单位实战的 GPU 帧耗时、低配置设备适配；人工视觉验收所有镜头与鼠标擦痕。无头运行成功不得冒充上述项已通过。

## 3｜植物外观 / 僵尸等阶 / Boss 的必要维护知识

### 3.1 向日葵四转：复用原版 Idle

- 原版权威：`scenes/character/plant/plant_002_sun_flower.tscn` + `animation/character/plant/002_sun_flower/SunFlower_idle.tres` + `assets/reanim/SunFlower_*.png`；原花盘、茎叶、眨眼和关键帧继续复用。正式分件 `assets/adventure/plants/sunflower/manifest.json` 定义 `tier_1..tier_4`，每阶 19 张原尺寸/alpha 花瓣、星芒；三转需要原 Wink 配件，旧三块式 `head/petal_halo/leaves_and_collar` 废弃。
- 唯一入口 `scripts/adventure/plant_art/adventure_sunflower_promotion_art.gd`。`PlantSpawnProfile.snapshot().promotion_1..4` 决定同一 UID 的转职阶段；0 阶维持原版。原 Idle 动画有 texture 轨道，直接改写 Sprite.texture 会被覆盖；必须在原 Sprite 子节点上叠加 PromotionPetal / PromotionStar 等部件，继承原运动。
- 战场和卡面以 `AdventureBattleAdapter.profile_for` / `AllCards.create_static_preview(reference, promotion_tier)` 复用；转职书由 `AdventurePromotionCatalog.definition(book_id)` 的目标阶决定书面形象，而非卡牌持有人的当前阶。保留 UID 粒度，避免同物种共用一张全局升级图片。
- 已完成 Godot 导入及定向卡面/战场挂点验证；完整人工画面/所有动画视觉验收仍须单独确认。

### 3.2 僵尸等阶与墓碑

- 1–25 号原版僵尸等阶 1–5 已接入数值、主要能力及美术；1 阶 base，2–5 分别 veteran/elite/tier4/tier5。通用 HP 及原护甲倍率 1/1.5/3/5/10，普通啃咬及出怪预算从各自权威 catalog 取值；**固定格挡、二类防具、额外护甲、技能和伤害类型不可归并为一个总血量**。
- 权威链 `scripts/adventure/adventure_zombie_tier_catalog.gd` → tier_binding / tier_traits / tier_species_installer / 特有行为组件；美术 `res://assets/adventure/zombies/tier_art_map.json` → `AdventureZombieTierArtCatalog` / `AdventureZombieTierArt`。`inherits` 仅复用美术；不推断行为。27+ 扩展物种不可假冒为已接入等阶；全明星 26 与 Boss 单独动画/数值管线。
- 平衡必须以**整套阵容**为单位；五阶主要对标十星植物，不能用零星单卡单挑评价。垫材、铲除、磁力/魅惑/灰烬、穿透、冷却与阳光都要算成本；扶梯搭载与无效化、巨人召唤小鬼及投篮多路压制需按真实物种能力审查。多项定向测试和导入通过不代表全混编波次、真实手操和战术平衡已验收。
- 可攻击墓碑 HP 700 / 五段损伤；`StagePhaseDefinition.gravestone_rules` → `AdventureGravestoneDirector` → TombStoneManager，禁止已占格生成。墓地上游黄昏支持天阳光且蘑菇不睡；墓地下游夜晚；按关卡 overrides 区分规则，雨天不能替代墓碑配置。

### 3.3 Boss / 全明星共用规范

- 黑将军实体 `scenes/character/zombie_boss/zombie_boss_002_black_general.tscn`，HP 120000，主美术 `assets/adventure/zombies/black_general/`，动作 `animation/character/zombie_boss/002_black_general/`；已封口资源及两阶段视觉不重复施工。
- `ZB000Base` 的阶段信号（首次 HP≤50%）→ `ZombieManager` / `SoundManager`，全 Boss HUD `LevelInfo → scenes/ui/boss_hp_progress_bar.tscn`（统一头像框、血条、淡入淡出、鼠标避让）。黑将军行为树/召唤/遭遇规则不应因为美术与 HUD 已完工就宣称实装。
- 全明星采用 PvZ2 原始 PAM 的稳定 ref ID、稀疏关键帧继承、原始层级/动画事件；正式 `scenes/character/zombie/zombie_026_all_star.tscn` 与 `scenes/character/zombie/all_star_original_animations.tres`。可复用转换方法位于 `C:\Dev\PvZ\_review\all_star\pvz2_original_5_8_1\`；不要复制其物种逻辑到其它僵尸，替代哨声不可冒充原版音效。

## 4｜维护要求

- 新需求先更新/定位权威数据源，再写实现；需要调整状态和视觉时分别修改配置/控制器，不建立并行“全局天气”“独立镜头”“额外卡牌外观”捷径。
- 新一轮交接只保留**权威路径、总线、经过验证的稳定事实、方法与尚未关闭的验收边界**；删除过时 commit 快照、失败实验、短期预览 URL 和重复旧待办。文档不记录临时工作树状态。
