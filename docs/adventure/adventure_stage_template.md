# 冒险新关卡配置

## 默认战斗流程

已登记的新关卡缺少专属配置时，自动使用 `resources/adventure/stages/templates/fallen_camp.tres`。模板提供没落营地的五行陆地战场、背景、初始阳光、普通和噩梦波次、阶段音乐、掉落及黑将军遭遇。

1. 从地图进场，使用统一战场界面预览敌人并从玩家库存选卡。模板初始为 6 个选卡槽，实际容量也会计入玩家的商店扩槽。
2. 普通阶段共 30 波。每次清场结算时，套用模板的新关卡发放一把本关噩梦钥匙，玩家可以领取奖励后结束挑战，也可以消耗钥匙续战。
3. 续战在同一战场保留已选卡组和已种植物。噩梦第 50 波清场后自动进入黑将军遭遇，击败后结算 Boss 掉落。

选卡、阶段续战与 Boss 调度分别接入已有的 `AdventureSession`、`AdventureContinuationController` 和 `AdventureBossDirector`。关卡通关、首通奖励和 Boss 任务使用各自的 ID。没落营地的浮尘、沙暴、指针漂移及埃德加钥匙（上）由它的单关覆盖提供。

## 开新关卡需要登记的内容

1. 在 `scripts/adventure/adventure_stage_registry.gd` 的 `STAGES` 登记正式编号、稳定 ID 和名称。例如 `102: {"id": &"wonderland.resting_plain", "name": "安息平原"}`。同地区使用连续编号时，前一关普通通关后解锁下一关。
2. 让地图节点引用该编号。奇境节点在 `resources/adventure/wonderland_map_nodes.json` 填 `stage_number`，僵尸岛节点在 `assets/adventure/zombie_island/layout.json` 填 `id`。新增地区时，在 `REGION_RETURN_SCENES` 登记返图场景，并在 `AdventureStageCatalog.is_unlocked()` 接入该地区首关的解锁条件。
3. 在 `scripts/autoload/global/item_registry.gd` 的 `BASE_ITEMS` 登记 `<稳定 ID>.nightmare_key`，填写关卡名称作为 `subject`，`category` 填 `key`。模板负责发放本关钥匙及检查续战库存。

## 自定义关卡内容

- **调整模板的部分内容**。在 `resources/adventure/stages/overrides/` 添加 `AdventureStageOverride`，文件名把稳定 ID 中的点换成下划线，例如 `wonderland_resting_plain.tres`。按需填写 `battle_background_texture`、`board_definition`、普通或噩梦的 `*_wave_profile`、`*_drop_table`、`*_battle_music` 和 `*_weather_sequence`。圣堂通过 `battle_scene` 和 `environment` 接入专属战场，并覆盖普通和噩梦波次、复光出怪与噩梦 Boss 遭遇。
- **调整噩梦的波数、Boss 或事件**。Boss 的触发波数要落在新的波次范围内。更换 Boss 时用 `replace_nightmare_bosses` 和 `nightmare_bosses`，同时用 `replace_nightmare_events` 更新关联的触发和掉落，事件中的 `encounter_id` 要对应新遭遇。替换 `normal_drop_table` 时，在新掉落表或其他奖励里配置本关噩梦钥匙的来源。
- **提供整套专属配置**。在 `resources/adventure/stages/` 根目录放置同名 `StageDefinition`。它优先于模板和局部覆盖。填本关 `stage_id`、`environment`、`phases` 和续战钥匙。需要自有战场、返图、选卡槽位或独立终末阶段时，用 `battle_scene`、`return_scene`、`max_selected_cards`、`terminal_key_id` 和对应的终末阶段资源。草坪和致幻洋流可参考这一结构。

墓地上游、墓地下游、下水道和埃德加神殿的既有局部配置沿用原僵尸岛基底。新的局部配置以没落营地模板为基底。
