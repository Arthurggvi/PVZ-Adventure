## 阳光菇成熟扩散的唯一入口；每格同物种最多一株伴生幼菇，不占普通种植位。
## 继续使用统一放置事务验证地形和承托；完整配方继承允许下一代正常成长后再次扩散。
extends RefCounted
class_name AdventureSunShroomPropagation

## 只允许真实注册的阳光菇，拒绝把冻结配方投射到其他物种。
const SUN_SHROOM: CharacterRegistry.PlantType = CharacterRegistry.PlantType.P010SunShroom
## 目录技能每方向最多三格；一次成熟最多检查十二个固定逻辑地址。
const MAX_RADIUS: int = 3
## 行列逻辑坐标中的四个正交方向，不使用显示像素或移动平台位置。
const AXES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

## [param source] 是刚成熟的真实植株；[param radius] 为每个正交方向的逻辑距离。
## 当场冻结来源配方、棋盘和轮次；延迟提交避免物理回调内修改植物碰撞节点。
static func spread(source: Plant010SunShroom, radius: int) -> void:
	if not is_instance_valid(source) or source.is_death or not source.is_grow \
			or source.is_queued_for_deletion():
		return
	var game: MainGameManager = Global.main_game # 本次成熟发生的战场。
	var profile: PlantSpawnProfile = source.plant_spawn_profile # 独立于母株寿命的冻结来源。
	var cell: PlantCell = source.plant_cell # 本次成熟的逻辑中心，不包含中心自身。
	if not _active_battle(game) or game.board == null or not game.is_ancestor_of(source) \
			or profile == null or not profile.matches_plant_type(SUN_SHROOM) \
			or not _active_cell(game, game.board, cell):
		return
	var reach: int = clampi(radius, 0, MAX_RADIUS) # 目录半径有界，禁止损坏事件无限展开。
	var board: BoardRuntime = game.board # 延迟期间不能转移到重建后的棋盘。
	var round_index: int = game.curr_game_round # 同场景下一轮也不能接收旧成熟任务。
	_commit_spread.call_deferred(game, board, round_index, cell, profile, reach)

## [param game]、[param board]、[param round_index] 是成熟时的战场快照。
## [param origin] 是当时中心格；[param profile] 是完整配方；[param reach] 已限制到零至三格。
static func _commit_spread(game: MainGameManager, board: BoardRuntime, round_index: int,
		origin: PlantCell, profile: PlantSpawnProfile, reach: int) -> void:
	if not _active_battle(game) or game.board != board or game.curr_game_round != round_index \
			or not _active_cell(game, board, origin) or origin.board_definition == null:
		return
	for axis: Vector2i in AXES: # 每个方向独立枚举；稀疏缺格只跳过该地址。
		for distance: int in range(1, reach + 1): # 排除中心，不在出生时执行任何成熟逻辑。
			# 前一株的种植通知可能触发结算；每次提交前都复核冻结战场。
			if not _active_battle(game) or game.board != board or game.curr_game_round != round_index:
				return
			var target: PlantCell = board.cell_at(origin.row_col + axis * distance) # 当前权威地址索引。
			if not _active_cell(game, board, target) or target.board_definition == null \
					or target.board_definition.surface_id != origin.board_definition.surface_id \
					or not target.can_host_companion(SUN_SHROOM):
				continue
			target.create_plant(SUN_SHROOM, false, true, false, false, profile,
				PlantCell.PlacementOrigin.Companion)

## [param cell] 必须仍是 [param game] 与 [param board] 索引中的实际地块。
static func _active_cell(game: MainGameManager, board: BoardRuntime, cell: PlantCell) -> bool:
	return is_instance_valid(cell) and not cell.is_queued_for_deletion() and cell.is_inside_tree() \
			and cell.board == board and board.cell_by_id(cell.cell_id) == cell and game.is_ancestor_of(cell)

## [param game] 必须仍是当前正式战场；结算或续战等待均拒绝新的伴生放置。
static func _active_battle(game: MainGameManager) -> bool:
	return is_instance_valid(game) and game.is_inside_tree() and not game.is_queued_for_deletion() \
			and game == Global.main_game and game.get_tree().current_scene == game \
			and game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
			and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
			and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false)
