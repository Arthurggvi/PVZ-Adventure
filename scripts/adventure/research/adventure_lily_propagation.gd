## 睡莲的玩家种植扩张；子株走正常放置事务，但不再派发玩家成功种植通知。
extends RefCounted
class_name AdventureLilyPropagation

## 扩张只生成睡莲，不能把其他物种的冻结配置投给底座。
const LILY: CharacterRegistry.PlantType = CharacterRegistry.PlantType.P017LilyPad

## 玩家在 [param cell] 成功种下 [param profile] 后，仅覆盖一次同平台九宫格。
## 中心由玩家创建，其余格复用水路、墓碑、禁种、底座及上层占用的完整资格检查。
static func expand_player_placement(cell: PlantCell, profile: PlantSpawnProfile) -> void:
	var game: MainGameManager = Global.main_game # 固定本次玩家操作所属的真实战场。
	if not _active_cell(game, cell) or not _has_spread(profile):
		return
	var source: Plant000DownBase = cell.get_support_plant() # 已提交的真实承托者，不按同物种或历史实例猜测。
	if not is_instance_valid(source) or source.is_death or source.is_queued_for_deletion() or not source.can_process() \
			or source.has_node(NodePath(AdventurePlantNullification.NODE_NAME)) \
			or source.spawn_species_id() != LILY or source.plant_spawn_profile != profile:
		return
	for target: PlantCell in cell.board.neighbors(cell, 1): # 拓扑邻接包含中心，适配边缘、缺格与移动平台。
		if target == cell or not _active_cell(game, target) or target.board != cell.board \
				or absi(target.row_col.x - cell.row_col.x) > 1 or absi(target.row_col.y - cell.row_col.y) > 1 \
				or cell.board_definition == null or target.board_definition == null \
				or target.board_definition.surface_id != cell.board_definition.surface_id:
			continue
		target.create_plant(LILY, false, true, false, false, profile, PlantCell.PlacementOrigin.Spawned)

## [param game] 和 [param cell] 必须仍属于正式战斗的当前棋盘，结算和续战等待均不扩张。
static func _active_cell(game: MainGameManager, cell: PlantCell) -> bool:
	return is_instance_valid(game) and not game.is_queued_for_deletion() and game.is_inside_tree() \
		and game == Global.main_game and game.get_tree().current_scene == game \
		and game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false) \
		and game.board != null and is_instance_valid(cell) and not cell.is_queued_for_deletion() \
		and cell.board_definition != null and cell.board == game.board and game.board.cell_by_id(cell.cell_id) == cell and game.is_ancestor_of(cell)

## 只从 [param profile] 的合法冻结分支识别扩张，不读取库存或其他同种卡片。
static func _has_spread(profile: PlantSpawnProfile) -> bool:
	if profile == null or not profile.matches_plant_type(LILY):
		return false
	var record: PlantCardInstance = PlantCardInstance.from_dict(profile.snapshot()) # 保留来源完整卡牌身份。
	if record == null:
		return false
	for event: Dictionary in AdventurePromotionCatalog.effects(record).events: # 目录是书籍效果的唯一来源。
		if StringName(event.get("kind", "")) == &"lily_spread":
			return true
	return false
