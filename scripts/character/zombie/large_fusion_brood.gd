## 累计本体损血并生成同等阶普通僵尸；非致死出生延后到当前伤害调用退出。
extends Node
class_name LargeFusionBrood

## 每生成一只后代所消耗的累计实际本体损血，单位生命点。
const LOSS_PER_ZOMBIE: int = 700
## 只在统一生成器实际登记成功后通知表现层，理论阈值不产生假分裂效果。
signal child_spawned(child: Zombie000Base)

## 一次损血的出生位置快照，不追踪随后移动的母体。
class BirthBatch:
	## 受伤时的行索引。
	var lane: int
	## 受伤时的世界横坐标，纵坐标由该行生成入口计算。
	var world_x: float
	## 本笔损血跨过的完整阈值数。
	var count: int

## 母体仅用于身份与战局校验；后代不会继承母体的计数器。
var _source: Zombie000Base
## 出生战场，禁止延迟回调串入另一局。
var _birth_game: MainGameManager
## 出生轮次，续战清理期间不执行上一轮的出生。
var _birth_round: int = -1
## 出生阶段，阶段切换会丢弃旧请求。
var _birth_phase: StagePhaseDefinition
## 不足一个阈值的损血余数，治疗不会返还已消耗的阈值。
var _loss_remainder: int = 0
## 已预留但尚未创建的后代批次。
var _pending: Array[BirthBatch] = []
## 确保每次伤害串只安排一个延迟消费。
var _flush_queued: bool = false
## 真正死亡的邻行召唤只能消费一次。
var _death_consumed: bool = false
## 死亡结算时首只成功出生的后代接替母体名额，避免满员时所有亡语都被拒绝。
var _death_slot_available: bool = false

## [param source] 已完成战斗初始化；展示实例不调用此入口。
func configure(source: Zombie000Base) -> void:
	_source = source
	_birth_game = Global.main_game
	_birth_round = _birth_game.curr_game_round
	_birth_phase = AdventureSession.get_active_phase(_birth_game.game_para)
	(source.hp_component as HpComponentLargeFusion).body_health_lost.connect(_record_loss)

## [param amount] 为真实本体损血；此同步回调只记账，避免嵌套伤害重入。
func _record_loss(amount: int) -> void:
	if _death_consumed or amount <= 0 or not _can_spawn():
		return
	var accumulated: int = _loss_remainder + amount # 合并上一击不足 700 的剩余部分。
	var count: int = floori(float(accumulated) / LOSS_PER_ZOMBIE) # 一次结算所有完整阈值。
	_loss_remainder = accumulated % LOSS_PER_ZOMBIE
	if count == 0:
		return
	var batch: BirthBatch = BirthBatch.new() # 保存受伤位置，不能在延迟回调中改用落地位置。
	batch.lane = _source.lane
	batch.world_x = _source.global_position.x
	batch.count = count
	_pending.append(batch)
	if not _flush_queued:
		_flush_queued = true
		_flush_births.call_deferred()

## 在母体死亡信号注销在场计数前补齐后代；清场与重复死亡不得召唤。
func resolve_death() -> void:
	if _death_consumed:
		return
	_death_consumed = true
	_death_slot_available = true
	_flush_births()
	if not _can_spawn():
		return
	# 邻行不存在或不支持普通僵尸时由统一生成入口拒绝，不改成其他位置。
	for neighbor: int in [_source.lane - 1, _source.lane + 1]:
		if _can_spawn_neighbor(neighbor, _source.global_position.x):
			_spawn_one(neighbor, _source.global_position.x)

## 校验邻行 [param lane] 的 [param world_x] 是否有可站立地块，不吸附缺格或越界位置。
func _can_spawn_neighbor(lane: int, world_x: float) -> bool:
	var manager: ZombieManager = _birth_game.zombie_manager # 先用统一资格排除无效行。
	if not manager.can_spawn_zombie_in_lane(CharacterRegistry.ZombieType.Z001Norm, lane):
		return false
	var row: ZombieRow = manager.all_zombie_rows[lane] # 纵坐标与正式生成入口使用同一基准。
	var point: Vector2 = Vector2(world_x, row.zombie_create_position.global_position.y) # 母体同一横坐标的邻行脚点。
	if is_instance_valid(_birth_game.main_game_slope):
		point += row.get_global_transform().basis_xform(Vector2(
			0.0, _birth_game.main_game_slope.get_all_slope_y(world_x)))
	var cell: PlantCell = _birth_game.board.cell_at_ground_point(point, lane) # 缺格、隐藏格和棋盘外返回空。
	var terrain: CharacterRegistry.ZombieRowType = Global.character_registry.get_zombie_info(
		CharacterRegistry.ZombieType.Z001Norm, CharacterRegistry.ZombieInfoAttribute.ZombieRowType) # 普僵的地形资格来自注册表。
	return cell != null and ZombieRow.supports_spawn(terrain, cell.get_spawn_terrain_type())

## 先移出待处理队列，再调用生成器，避免回调重入导致同一批次重复出生。
func _flush_births() -> void:
	_flush_queued = false
	var batches: Array[BirthBatch] = _pending # 转移队列所有权，而不是遍历正在新增的数组。
	_pending = []
	if not _can_spawn():
		return
	for batch: BirthBatch in batches: # 每个批次保留原受伤位置和完整阈值数。
		for _index: int in range(batch.count): # 逐只生成，沿用管理器的地形与实体上限保护。
			_spawn_one(batch.lane, batch.world_x)

## [param lane] 和 [param world_x] 为出生位置；普通僵尸只继承母体等阶。
func _spawn_one(lane: int, world_x: float) -> void:
	if _can_spawn():
		var replaces: Zombie000Base = _source if _death_slot_available else null # 每次死亡只转移一个已占名额。
		var child: Zombie000Base = _birth_game.zombie_manager.create_skill_zombie(
			CharacterRegistry.ZombieType.Z001Norm, lane, world_x, _source.adventure_tier_id, replaces) # 沿用管理器的登记与计数。
		if is_instance_valid(child):
			_death_slot_available = false
			child_spawned.emit(child)

## 只允许在母体所属的活动战局生成；不检查死亡标记，以便结算致死一击和亡语。
func _can_spawn() -> bool:
	return is_instance_valid(_source) and _source.is_inside_tree() and not _source.retiring_from_battle \
		and not _source.is_queued_for_deletion() \
		and is_instance_valid(_birth_game) and _birth_game.is_inside_tree() \
		and not _birth_game.is_queued_for_deletion() and _birth_game == Global.main_game \
		and _birth_game.is_ancestor_of(_source) and _birth_game.curr_game_round == _birth_round \
		and AdventureSession.get_active_phase(_birth_game.game_para) == _birth_phase \
		and is_instance_valid(_birth_game.zombie_manager) and _birth_game.zombie_manager.is_game_running()
