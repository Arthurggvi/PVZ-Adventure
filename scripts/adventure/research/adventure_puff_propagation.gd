## 小喷菇感染和群体种植的唯一生成入口；子株共用来源的冻结卡牌配置。
## 创建仍走 PlantCell 放置事务，不扣费、不占用卡槽，也不再次触发玩家种植通知。
extends RefCounted
class_name AdventurePuffPropagation

## 本组件只生成小喷菇，不能把来源快照投射给其他物种。
const PUFF: CharacterRegistry.PlantType = CharacterRegistry.PlantType.P009PuffShroom
## 逻辑十字包含中心及四个单位地址；各格独立种植，不共享跨格占用。
const CROSS_OFFSETS: Array[Vector2i] = [
	Vector2i.ZERO, Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
]

## [param killed] 为本次已确认死亡的敌人；[param source_profile] 为发射时冻结的来源配置。
## 当场确定脚下活格子，延迟到物理提交后再种植；来源植物死亡不影响已发射孢子。
static func infect(killed: Character000Base, source_profile: PlantSpawnProfile) -> void:
	if not is_instance_valid(killed) or not killed.is_death \
			or not _has_effect(source_profile, &"puff_infection"):
		return
	var game: MainGameManager = Global.main_game # 击杀所属的当前战场，拒绝跨场景回调。
	if not _active_battle(game) or game.board == null or not game.is_ancestor_of(killed):
		return
	var board: BoardRuntime = game.board # 延迟提交期间不能转移到重建后的种植空间。
	var round_index: int = game.curr_game_round # 固定击杀轮次，拒绝同场景下一轮的晚到回调。
	var feet: Vector2 = killed.global_position # 普通僵尸的根节点就是实际地面脚点。
	if killed is ZB000Base:
		# 僵王素材可偏离根节点；复用其出生定位的脚底偏移契约。
		feet = killed.to_global(Vector2(0.0, (killed as ZB000Base).get_boss_feet_offset_y()))
	var cell: PlantCell = board.cell_at_ground_point(feet, killed.lane) # 即时脚点，不吸附空洞。
	if cell != null:
		_commit_infection.call_deferred(game, board, round_index, cell, source_profile)

## [param game]、[param board]、[param round_index] 为击杀时冻结的战场、空间及轮次。
## [param cell] 为当时的脚下格；[param profile] 为来源配置；失效或已结束的战斗不再生成。
static func _commit_infection(game: MainGameManager, board: BoardRuntime, round_index: int,
		cell: PlantCell, profile: PlantSpawnProfile) -> void:
	if not _active_battle(game) or game.curr_game_round != round_index or game.board != board \
			or not _active_cell(cell) or cell.board != board:
		return
	_spawn(cell, profile)

## 玩家在 [param cell] 成功使用 [param profile] 后，仅扩张该主操作的单位逻辑十字。
## 中心已由正常卡片创建；占用、缺格、禁种或不支持的水面自然跳过，子株不递归扩张。
static func expand_player_placement(cell: PlantCell, profile: PlantSpawnProfile) -> void:
	if not _active_cell(cell) or not _has_effect(profile, &"puff_collective"):
		return
	var source: Plant000Base = cell.plant_in_cell.get(CharacterRegistry.PlacePlantInCell.Norm) # 已成功提交的主株。
	if not is_instance_valid(source) or source.is_death or source.plant_spawn_profile != profile:
		return
	for offset: Vector2i in CROSS_OFFSETS: # 一次玩家操作最多覆盖五个离散地址。
		var target: PlantCell = cell.board.cell_at(cell.row_col + offset) # 边缘与稀疏缺格返回 null。
		if target == null:
			continue
		if target != cell and cell.board_definition != null and cell.board_definition.explicit_neighbors \
				and not cell.board_definition.neighbor_ids.has(target.cell_id):
			continue
		_spawn(target, profile)

## 将 [param profile] 原样交给 [param cell] 的统一放置事务；失败不修改地形或现有植物。
## 技能子株使用 Spawned 来源，完整复核地形、承托、墓碑、禁种和目标层占用。
static func _spawn(cell: PlantCell, profile: PlantSpawnProfile) -> void:
	if not _active_cell(cell) or profile == null or not profile.matches_plant_type(PUFF):
		return
	cell.create_plant(PUFF, false, true, false, false, profile, PlantCell.PlacementOrigin.Spawned)

## [param cell] 必须属于仍在正式战斗中的稳定地块索引；返回是否可继续放置预检。
static func _active_cell(cell: PlantCell) -> bool:
	var game: MainGameManager = Global.main_game # 延迟回调执行时重新读取战场所有者。
	return is_instance_valid(cell) and not cell.is_queued_for_deletion() \
		and _active_battle(game) and game.board != null and cell.board == game.board \
		and game.board.cell_by_id(cell.cell_id) == cell and game.is_ancestor_of(cell)

## [param game] 必须仍是当前正式战场；胜负结算和冒险续战等待均不接受技能生成。
## 与玩家卡片的 MAIN_GAME 门槛一致，不额外禁止普通轮间仍允许种植的等待阶段。
static func _active_battle(game: MainGameManager) -> bool:
	return is_instance_valid(game) and not game.is_queued_for_deletion() \
		and game == Global.main_game and game.is_inside_tree() and game.get_tree().current_scene == game \
		and game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false)

## 从 [param profile] 的已验证冻结配置读取 [param kind]；不读取库存或同种卡牌。
static func _has_effect(profile: PlantSpawnProfile, kind: StringName) -> bool:
	if profile == null or not profile.matches_plant_type(PUFF):
		return false
	var record: PlantCardInstance = PlantCardInstance.from_dict(profile.snapshot()) # 保留 UID、星级与完整分支链。
	if record == null:
		return false
	for effect: Dictionary in AdventurePromotionCatalog.effects(record).events: # 配置是事件种类的唯一来源。
		if StringName(effect.get("kind", "")) == kind:
			return true
	return false
