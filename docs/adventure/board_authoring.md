# 战场种植空间｜配置与扩展入口

## 权威链

`AdventureStageOverride.board_definition` → `AdventureBattleEnvironment.board_definition` → `ResourceLevelData.board_definition` → `MainGameManager._enter_tree()` → `BoardSceneAdapter.install()` → `MainGameManager.board: BoardRuntime`。

源码目录：`res://scripts/battle/board/`。空间索引只管理地块身份、地址、几何与平台；实际植物占用和创建/释放事务仍唯一属于 `PlantCell`，卡牌费用仍由 `signal_card_use_end` 结算。没有第二份占用矩阵。

未设置 `board_definition` 时，由适配器读取原场景，保留原节点路径、坐标和攻击行。现有六关没有改成示例尺寸或新布局。旧 `terrain_rows` 仅在此兼容入口生效；与显式布局同时配置会被拒绝。

## 关卡作者怎样配置

在 Godot Inspector 新建 `BoardDefinition` 资源并挂到单关覆盖的 `board_definition`，不用修改植物脚本。规则矩阵可选择其子类 `BoardGridDefinition`；两种定义展开后走相同运行时。

| 声明 | 必填或关键字段 | 含义 |
|---|---|---|
| `BoardDefinition` | `board_id`、`revision`、`lanes`、`surfaces`、`cells`、`terrains` | 完整静态空间；不兼容拓扑变更递增 revision。 |
| `BoardCellDefinition` | `cell_id`、`address`、`surface_id`、`position`、`size`、`terrain_id` | address.x 是零起点攻击行，address.y 是逻辑列；position 是平台局部像素坐标，size 是交互范围，不缩放植物美术。 |
| `BoardLaneDefinition` | `lane_id`、`spawn_position`、`spawn_type`、`mower_position`、`mower_kind` | 固定攻击行；出生点和清洁车位置使用主战场局部坐标，不由植物格数推测。 |
| `BoardSurfaceDefinition` | `surface_id`、`origin`、`travel_offset`、`travel_seconds`、可选 `visual_scene` | 一个可独立移动的平台，平台内所有格子与植物整体随动；零位移表示静态。 |
| `BoardTerrainDefinition` | `terrain_id`、`planting_flags`、`supported_flags`、`spawn_type`、`tags`、`blocks_planting` | 地形能力；supported_flags 在存在 Down 承托植物时使用。 |

**自定义离散坐标**：可以只声明逻辑地址 `(0,0)`、`(0,4)`、`(1,2)` 的三个种植点，各自设置不同 position/size。中间不存在的地址不会创建占位格，也不会被当作压缩数组的下标。cell_id 在位置变化、资源数组重排时保持不变。

**非矩形点击范围**：`hit_polygon` 的顶点在该格 size 的局部范围内；空值使用矩形。Button 命中和移动后的实时拾取共用此几何，界面菜单/卡槽优先，不穿透 GUI 种植。

**邻接关系**：默认按同平台逻辑地址计算范围；`explicit_neighbors = true` 后改为 `neighbor_ids` 的有向步进关系。需要双向相邻时应在两端都声明。`right_neighbor_id` 可单独声明玉米加农炮等多格植物的向右占格；目标必须同平台、同攻击行。不能让一株多格植物横跨两块独立移动平台。

**规则网格**：`BoardGridDefinition.dimensions` 是行列数，`pitch` 是列/行像素间距，`grid_origin`、`cell_size`、`grid_surface_id`、`default_terrain_id` 控制生成。可在 cells 中按 address 覆盖个别点；重复/越界覆盖会被拒绝。显式 lanes 优先，否则按网格与平台初始高度生成固定攻击行。默认字段不是对任何现有关卡的修改。

## 运行时唯一入口

以下调用针对当前战斗 `game.board`，不创建新的全局单例：

```gdscript
# 稳定身份查询；不存在返回 null。
var cell: PlantCell = game.board.cell_by_id(&"ferry_plant_a")

# 稀疏逻辑地址查询；缺格返回 null，禁止使用压缩枚举行下标。
var target: PlantCell = game.board.cell_at(Vector2i(1, 4))

# 将平台移到主战场局部坐标，用两秒有效战斗时间完成。
var moving: bool = game.board.move_surface_to(&"ferry", Vector2(160, 0), 2.0)

# 换地形默认拒绝有植物/障碍的格子；失败完全不扣费、不铲除植物。
var changed: bool = game.board.set_cell_terrain(&"ferry_plant_a", &"mud")
```

`move_surface_to()` 接受的目标是平台坐标，不是位移增量；秒数为零立即定位。显式移动覆盖自动往返，完成后停在终点，不突然跳回旧轨道。自动运动与过渡只在 MAIN_GAME 推进，遵守场景暂停。不会隐式更改植物攻击行、地块 ID、逻辑邻接或占用。

`set_cell_terrain(..., true)` 明确允许保留现有占用，包括与新地形不兼容的植物；不会自动摧毁、迁移或退款。地形变化通知使用 `board.terrain_changed`。单个来源临时禁种使用 `cell.set_planting_block(source_id, blocked)`，不得通过改其他效果的标志来解除自己的限制。

查询统一使用 `cells()`、`row_cells()`、`cell_at()`、`neighbors()`、`horizontal_neighbors()`、`right_of()`、`nearest_cell()`、`local_pitch()`。`PlantCellManager.all_plant_cells` 仅为旧枚举消费者提供只读行副本，不能用 `[行][逻辑列]` 访问稀疏布局，也不能写回数组。

## 特殊地形扩展

`BoardTerrainDefinition.behavior_scene` 的根必须继承 `BoardTerrainBehavior`；每个地块创建独立实例。扩展脚本通过 `cell` 访问当前占用，覆写 `tick(delta)`、`removed()`，需要持久化时实现 `capture_state()` / `accepts_state()` / `restore_state()`。验证方法必须是离树可调用的纯校验，不能依赖 onready、玩家库存或当前战斗。

新植物对特殊地形的要求使用 `ResourcePlantCondition.required_terrain_tags` / `forbidden_terrain_tags`；不要给 PlantCell 的地形枚举不断追加物种分支。`presentation_kind` 只负责旧美术分类，不能替代生成条件 `spawn_type` 或种植能力。

`water_contact = true` 从本地块矩形/多边形生成随平台移动的 `WaterBodyArea`。它只提供接触，不自动生成水面纹理；表现由行为场景或平台 visual_scene 配置。原场景水面仍由 `WaterSurfaceProfile` 区域承担视觉和物理接触；制作新布局时必须配套校准环境区域，避免重复或错位水体。

`SwimBoxComponent` 聚合多个水体接触，最后一个水体离开才出水；普通/潜水表现只覆写聚合状态回调。普通下沉取消旧过渡并从固定基准求目标位置，不能在每次进入相邻水格时再累加下沉量。

## 存档与生命周期

`ResourceSaveGamePlantCellManager.board_state` 保存布局 ID/revision、地块身份与逻辑地址、地形及行为状态、平台运动阶段、攻击行身份顺序。植物和墓碑新档按 cell_id 恢复；只有原布局兼容旧 row_col 档案。

正式恢复前先对所有空间/植物目标/墓碑目标做完整预检。未知或重复 ID、拓扑不兼容、错误行为状态不允许静默回退到原矩阵。先恢复平台位姿和地形，再恢复植物、承托层与墓碑；不会重做卡牌扣费。

地块身份集合在一场战斗中固定。移动须走平台，不直接重挂/释放格子或改 address。承托层仍使用格子 Control 锚点与 Content Node2D，植物、壳体、受击盒和交互随节点变换移动；禁止缓存初始世界坐标后回填。

## 明确边界

本轮支持规则/稀疏离散种植点、任意点位配置、矩形/多边形点击区域、平移平台与地形行为扩展。未引入连续无格种植、平台旋转缩放、战斗中增删地块、跨攻击行占用迁移或自由寻路。攻击行仍是现有战斗内核的固定逻辑，物理位移不自动改行。

原版 Boss 大型美术、背景、镜头、屋顶坡面和部分按行/像素范围技能仍需与新关卡几何配套；空间资源不自动拉伸美术，也不保证任意战场布局下所有原版攻击范围与演出都已验收。显式图邻接用于拓扑技能；矩形爆炸仍按实际像素几何判断。

验证遵循仓库 `AGENTS.md`：默认不新增、不运行测试；修改时只修复已有测试的失效接口引用。编辑器导入/解析不能替代移动平台、荷叶多层随动、原版泳池、正常卡槽扣费和读档的实机终验。
