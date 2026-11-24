## 阳光菇成长扩散的入口；孢子扩散生成伴生幼菇，月光蔓延使用普通种植位。
## 两者均复用放置事务检查地形和承托，并将完整冻结配方交给新植株。
extends RefCounted
class_name AdventureSunShroomPropagation

## 只允许真实注册的阳光菇，拒绝把冻结配方投射到其他物种。
const SUN_SHROOM: CharacterRegistry.PlantType = CharacterRegistry.PlantType.P010SunShroom
## 孢子扩散每方向最多三格，每次成长最多检查十二个固定逻辑地址。
const MAX_RADIUS: int = 3
## 行列逻辑坐标中的四个正交方向，不使用显示像素或移动平台位置。
const AXES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

## [param source] 是刚完成一次成长的真实植株；[param rule] 是冻结的三转扩散规则。
## 当场冻结来源配方、棋盘和轮次；延迟提交避免物理回调内修改植物碰撞节点。
static func spread(source: Plant010SunShroom, rule: Dictionary) -> void:
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
	var board: BoardRuntime = game.board # 延迟期间不能转移到重建后的棋盘。
	var round_index: int = game.curr_game_round # 同场景下一轮也不能接收旧成熟任务。
	_commit_spread.call_deferred(game, board, round_index, cell, profile, rule)

## [param game]、[param board]、[param round_index] 是成熟时的战场快照。
## [param origin] 是当时中心格；[param profile] 是来源配方；[param rule] 决定扩散方式与半径。
static func _commit_spread(game: MainGameManager, board: BoardRuntime, round_index: int,
		origin: PlantCell, profile: PlantSpawnProfile, rule: Dictionary) -> void:
	if not _active_battle(game) or game.board != board or game.curr_game_round != round_index \
			or not _active_cell(game, board, origin) or origin.board_definition == null:
		return
	if rule.get("kind") == "sunshroom_moonlight":
		_spawn_moonlight_mushroom(game, board, origin, profile)
		return
	var reach: int = clampi(int(rule.get("radius", MAX_RADIUS)), 0, MAX_RADIUS) # 孢子扩散每个正交方向最多三格。
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

## 在 [param game] 的 [param board] 中随机尝试 [param origin] 周围的合法落点。
## 新株与 [param profile] 同星同阶，成功一株后结束；所有组合均不合法时不生成。
static func _spawn_moonlight_mushroom(game: MainGameManager, board: BoardRuntime,
		origin: PlantCell, profile: PlantSpawnProfile) -> void:
	var targets: Array[PlantCell] = [] # 只收集同平台相邻的八个逻辑地址，稀疏缺格直接跳过。
	for row_offset: int in range(-1, 2): # 相邻三行，包含来源所在行。
		for column_offset: int in range(-1, 2): # 相邻三列，包含对角线格子。
			if row_offset == 0 and column_offset == 0:
				continue
			var target: PlantCell = board.cell_at(origin.row_col + Vector2i(row_offset, column_offset)) # 登记的真实格子。
			if _active_cell(game, board, target) and target.board_definition != null \
					and target.board_definition.surface_id == origin.board_definition.surface_id:
				targets.append(target)
	targets.shuffle()
	var species_pool: Array[int] = MushroomPlantQuery.SPECIES.duplicate() # 随机物种仍来自统一的蘑菇分类。
	species_pool.shuffle()
	var stars: int = int(profile.snapshot().get("stars", 0)) # 直接继承星级，不从来源植株的战斗数值倒推。
	var tier: int = profile.promotion_tier() # 匹配已完成的转职次数，独立于当前星级门槛。
	var profiles: Dictionary[int, PlantSpawnProfile] = {} # 每种只抽一次路线，无法达到同阶的物种缓存为 null。
	for target: PlantCell in targets: # 随机顺序保证任何可以种植的目标格有机会先被选中。
		for species: int in species_pool: # 当前格尝试各随机物种，地形和空位由完整放置事务决定。
			if not profiles.has(species):
				profiles[species] = _random_mushroom_profile(species, stars, tier)
			var mushroom: PlantSpawnProfile = profiles[species] # 由该物种自己的书目生成的合法配方。
			if mushroom != null and target.create_plant(species as CharacterRegistry.PlantType,
					false, true, false, false, mushroom, PlantCell.PlacementOrigin.Spawned) != null:
				return

## 给 [param species] 抽取一至 [param tier] 转的连续路线，保留 [param stars] 星。
## 书目不足以达到同阶时返回 null；临时 UID 不占玩家库存，也不关联真实卡槽。
static func _random_mushroom_profile(species: int, stars: int, tier: int) -> PlantSpawnProfile:
	var card := PlantCardInstance.new() # 仅用于构造本次生成的冻结配方。
	card.uid = AdventureBattleAdapter.TEMPORARY_SOURCE_UID
	card.plant_type = species
	card.stars = stars
	for current_tier: int in range(1, tier + 1): # 从每阶合法选项中独立抽一本，保留完整前置路线。
		var options: Array[Dictionary] = AdventurePromotionCatalog.options(card) # 只查询该物种下一转的有效书目。
		if options.is_empty():
			return null
		var book: Dictionary = options.pick_random() # 本阶随机分支，不复制母株的具体选择。
		card.set_promotion(current_tier, book.id)
	return AdventureBattleAdapter.profile_for(card.save_snapshot())

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
