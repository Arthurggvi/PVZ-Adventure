# 工程架构

## 启动、场景与界面

`project.godot` 启动 `scenes/main/01StartMenuCoastal.tscn`。`Global` 提供角色注册、档案与存档服务。`SceneRegistry` 管辅助场景，`MainSceneRegistry.MainScenesMap` 管主场景。地图经同一注册表返回海滨。

建筑、地图按钮和工具栏共用 `AdventureToolbar.feature_status()` 与 `request_feature()`。工具栏控制器持有模态窗口，`map_navigation.gd` 持有临时地区选择器。新功能在 `scripts/adventure/ui/toolbar_features.gd` 登记，并在工具栏控制器注册权限查询和动作。渲染与建筑命中见 [海滨菜单](docs/adventure/main_menu_runtime_pipeline.md)。

## 关卡、天气与 Boss

- `AdventureStageRegistry.resolve()` 组合 `resources/adventure/stages/zombie_island_default.tres` 和 `overrides/`。进场由 `AdventureStageCatalog` 校验前置、钥匙、阶段和地形。扩展关卡时沿用 `scripts/adventure/stages/` 的 Resource 接口，检查波次、固定行号、物种能力、事件和战利品。
- `AdventureSession.enter_stage()` 经 `AdventureBattleEnvironmentAdapter.build()` 生成 `ResourceLevelData`，再加载前院、后院或屋顶战场。`AdventureBattleRuntime` 连接波次、遭遇和墓碑导演。`AdventureContinuationController` 在当前战场里推进下一阶段。
- `BackgroundManager` 将阶段的 `WeatherSequence` 交给 `BattleWeatherDirector`。后者以受暂停控制的战斗时间驱动雨幕、光场和湿镜头。第四关噩梦的预设位于 `resources/weather/`。
- `AdventureBossDirector` 管队列，`AdventureBossEncounter` 管波次暂停、援军和退出结果。角色沿 `ZB000Base`、`ZombieManager` 和生命组件进入战斗结算。技能参数在 `resources/zombie_boss/`，冷却和目标属于战场实例。

## 棋盘、植物与存档

- `MainGameManager` 在入树时以 `BoardSceneAdapter` 建立 `BoardRuntime`。扩展格子、地形、行或平台使用 `scripts/battle/board/` 的定义和查询。稳定的 `cell_id` 标识格子，`PlantCell` 持有占用与承托。见 [棋盘配置](docs/adventure/board_authoring.md)。
- `HandManager` 拾取手牌与格子，`HM_Character.click_cell()` 经 `PlantPlacement` 准备和复核，由 `PlantCell.commit_prepared_plant()` 占格。卡槽随后扣阳光、启动冷却。读档由 `BoardRestoreTransaction` 预检并复用提交入口。
- `WaterSurfaceProfile` 用背景像素区域描述水面。`WaterSurfaceController` 从同一区域生成视觉和 `WaterBodyArea`。`SwimBoxComponent` 汇总入水体。泳池和下水道一、五路共用该流程。
- `CharacterRegistry`、`BulletRegistry` 和 `AllCards` 提供物种、子弹和卡片身份。僵尸的等阶由 `AdventureZombieTierBinding` 在出生时绑定，由 `AdventureZombieTierAbility` 处理沉默启停和有效战场门禁。
- 背包、配方和书目由 `ItemRegistry` 与 `AdventureInventoryService` 提供。`AdventureResearchService` 经 `ResearchTransaction` 提交合成、强化或转职。进战后 `PlantSpawnProfile` 冻结卡牌 UID、星级与分支，由 `PlantSceneFactory` 和 `AdventureResearchBattleEffects` 安装在实际植株上。加书目和事件先改 `scripts/adventure/research/` 的目录与派发。双发持续场的伤害时钟在 `repeater_field_runtime.gd`，视觉代码在 `scripts/fx/repeater/`。
- `GlobalGameState.adventure_state` 保存冒险数据，经 `UserManager`、`SaveService` 和 `SaveFileStore` 写入 `user://<玩家>/GlobalSaveGame.json`。维护存档时核对旧档字段、稳定枚举与关卡 ID、失败回滚以及档案 A/B 隔离。
