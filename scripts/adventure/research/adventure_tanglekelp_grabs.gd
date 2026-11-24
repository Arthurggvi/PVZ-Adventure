## 海草的一次抓取。战场身份和书目随拖拽保存，击杀奖励不依赖原株仍存活。
extends RefCounted
class_name AdventureTanglekelpGrabs

## 九宫格由活动棋盘的拓扑和当前世界脚点共同判定。
const ADJACENT_RADIUS: int = 1
## 一枚金币的原生抛落距离，单位为像素。
const GOLD_LANDING_OFFSET := Vector2(0.0, 80.0)

## 发动时的战场、棋盘、轮次及阶段。
var battle: RepeaterShotContext
## 本次抓取的中心格；护甲也以该格为中心找受益者。
var _center: PlantCell
## 已冻结的海草转职事件，按事件种类访问参数。
var _rules: Dictionary[String, Dictionary]

## 从当前 [param source] 和 [param rules] 捕获一次抓取；场外或结算期间返回空。
static func capture(source: Plant000Base, rules: Dictionary[String, Dictionary]) -> AdventureTanglekelpGrabs:
	var stamp: RepeaterShotContext = RepeaterShotContext.from_plant(source) # 同步冻结植物实际所属的战局。
	if stamp == null:
		return null
	var grabs := AdventureTanglekelpGrabs.new() # 同次九宫格或宿主亡语共用一个来源。
	grabs.battle = stamp
	grabs._center = source.plant_cell
	grabs._rules = rules
	return grabs

## 返回 [param cell] 的同平台有效九宫格，包含中心，不将稀疏空洞视为地块。
static func neighborhood(cell: PlantCell) -> Array[PlantCell]:
	var result: Array[PlantCell] = [] # 显式邻接也须满足九宫格的逻辑行列和平台边界。
	if not is_instance_valid(cell) or cell.board == null or cell.board_definition == null:
		return result
	for neighbor: PlantCell in cell.board.neighbors(cell, ADJACENT_RADIUS): # 遵守棋盘声明的实际邻接。
		if is_instance_valid(neighbor) and not neighbor.is_queued_for_deletion() \
				and neighbor.board_definition != null and neighbor.board_definition.surface_id == cell.board_definition.surface_id \
				and absi(neighbor.row_col.x - cell.row_col.x) <= ADJACENT_RADIUS \
				and absi(neighbor.row_col.y - cell.row_col.y) <= ADJACENT_RADIUS:
			result.append(neighbor)
	return result

## 返回恶鬼九宫格内位于实际水域的全部可拖拽敌人。
func area_targets() -> Array[Zombie000Base]:
	var result: Array[Zombie000Base] = [] # 先查目标，开始拖拽时不再遍历可变僵尸登记。
	var cells: Array[PlantCell] = neighborhood(_center) # 用实际地块区分水陆与更远的敌人。
	for zombie: Zombie000Base in battle.game.zombie_manager.all_zombies_1d: # 发动时从管理器读取完整的敌方阵容。
		if is_area_target(zombie, cells):
			result.append(zombie)
	return result

## 判断 [param zombie] 是否在 [param cells] 内。等待入水时仅对原生重叠的小集合调用。
func is_area_target(zombie: Zombie000Base, cells: Array[PlantCell]) -> bool:
	if not _can_drown(zombie):
		return false
	var cell: PlantCell = battle.board.cell_at_ground_point(zombie.global_position, zombie.lane) # 范围拖拽必须命中实际水格。
	return cell != null and cells.has(cell) and cell.get_spawn_terrain_type() == CharacterRegistry.ZombieRowType.Pool

## [param zombie] 是正在啃食宿主的候选。真实格子优先，盘外按水体接触决定。
func can_drown_biter(zombie: Zombie000Base) -> bool:
	if not _can_drown(zombie):
		return false
	var cell: PlantCell = battle.board.cell_at_ground_point(zombie.global_position, zombie.lane) # 混合行按地块的实际水陆。
	if cell != null:
		return cell.get_spawn_terrain_type() == CharacterRegistry.ZombieRowType.Pool
	var swim: SwimBoxComponent = zombie.swim_box_component # 盘外直接读取接触，入水动画可能尚未切换泳姿。
	return is_instance_valid(swim) and is_instance_valid(swim.water_contact_area) and swim.water_contact_area.touching_water

## [param zombie] 必须为本局仍能被拖入水下的敌对僵尸；此处只检查角色状态。
func _can_drown(zombie: Zombie000Base) -> bool:
	return is_instance_valid(zombie) and not zombie.is_death and not zombie.is_queued_for_deletion() \
		and not zombie.is_hypno and zombie.is_inside_tree() and battle.game.is_ancestor_of(zombie) \
		and not zombie.is_native_airborne() and zombie.curr_be_attack_status in [
			Zombie000Base.E_BeAttackStatusZombie.IsNorm,
			Zombie000Base.E_BeAttackStatusZombie.IsDownPool,
			Zombie000Base.E_BeAttackStatusZombie.IsJumpInPool]

## 使用 [param template] 的原生缠绕组件逐个抓取 [param targets]；每个目标独享原版生死时钟。
func start(template: GrapComponent, targets: Array[Zombie000Base]) -> void:
	var parent: Node = template.get_parent() # 复制件从同一容器进树，再随各自的目标行动。
	var settlement: AdventureTanglekelpGrabs = self # 闭包强持有结算，母株消失后仍能在实际死亡时兑现。
	var on_kill: Callable = func(victim: Zombie000Base, health: int) -> void: # 每个原生拖拽回调使用同一冻结来源。
		settlement._on_kill(victim, health)
	for index: int in range(targets.size()): # 原件留给最后一个目标，复制时仍是尚未启动的原始姿态。
		var grab: GrapComponent = template if index == targets.size() - 1 else template.duplicate() as GrapComponent # 每个目标使用独立的动画节点。
		if grab != template:
			parent.add_child(grab)
		if not grab.grab_zombie(targets[index], on_kill) and grab != template:
			grab.queue_free()

## 仅原生拖拽实际处决的 [param victim] 兑现奖励；[param health] 为处决前的剩余本体生命。
func _on_kill(victim: Zombie000Base, health: int) -> void:
	if not battle.is_same_battle() or victim.retiring_from_battle or victim.is_hypno:
		return
	var point: Vector2 = victim.global_position # 与下沉的身体分开，掉落和召唤仍落在死亡脚点。
	if _rules.has("tanglekelp_siren"):
		_spawn_charmed(victim, point)
	if _rules.has("tanglekelp_slots"):
		var rule: Dictionary = _rules["tanglekelp_slots"] # 四档等概率，按整数单位抽取。
		var total: int = int(rule.unit) * randi_range(int(rule.min_units), int(rule.max_units)) # 合计阳光只可能为25的整数倍。
		BattleSunDrop.spawn(battle.game, point, total)
	if _rules.has("tanglekelp_envy_vine"):
		_grant_armor(health, int(_rules["tanglekelp_envy_vine"].armor_cap))
	if _rules.has("tanglekelp_greed_vine"):
		var manager: DropItemManager = battle.game.drop_item_manager # 复用拾取、金币倍率和抛落。
		if is_instance_valid(manager) and is_instance_valid(manager.dim_coin):
			manager.dim_coin.spawn_coin(SceneRegistry.COIN_GOLD, point, GOLD_LANDING_OFFSET)

## 在 [param point] 复用 [param victim] 的物种、水路状态和可继承等阶，直接登记为魅惑友军。
## 石像沿用原生封存规则，生成壳内可魅惑的普通僵尸。
func _spawn_charmed(victim: Zombie000Base, point: Vector2) -> void:
	var manager: ZombieManager = battle.game.zombie_manager # 走原生生成设施，不计入敌方名额。
	if victim.lane < 0 or victim.lane >= manager.all_zombie_rows.size() \
			or not CharacterRegistry.ZombieInfo.has(victim.zombie_type):
		return
	var row: ZombieRow = manager.all_zombie_rows[victim.lane] # 沿用死者当时的实际攻击行。
	var species: CharacterRegistry.ZombieType = CharacterRegistry.ZombieType.Z001Norm \
		if victim is ZombieStoneStatue else victim.zombie_type # 石壳中封存的原生物种。
	var cell: PlantCell = battle.board.cell_at_ground_point(point, victim.lane) # 混合行按死亡脚点恢复对应水陆姿态。
	var terrain: CharacterRegistry.ZombieRowType = cell.get_spawn_terrain_type() if cell != null else victim.curr_zombie_row_type # 盘外目标沿用原状态。
	var spawn_point: Vector2 = point # 原生斜坡初始化会再补一次高度，先将它从世界脚点扣除。
	if is_instance_valid(battle.game.main_game_slope):
		spawn_point -= row.get_global_transform().basis_xform(Vector2(0.0,
			battle.game.main_game_slope.get_all_slope_y(point.x)))
	var parameters: Dictionary = {
		Zombie000Base.E_ZInitAttr.Lane: victim.lane,
		Zombie000Base.E_ZInitAttr.CurrZombieRowType: terrain,
		Zombie000Base.E_ZInitAttr.IsMiniZombie: victim.is_mini_zombie,
		Zombie000Base.E_ZInitAttr.ParticipatesNaturalRefresh: false,
		Zombie000Base.E_ZInitAttr.StartsHypnotized: true,
	} # 新实例满血出生，不继承尸体伤势或自然出怪波次。
	manager.create_norm_zombie(species, row, parameters, spawn_point,
		Callable(), victim.inherited_child_modifier())

## 将 [param health] 授予附近随机一株仍可受益的友军；[param cap] 限制受益者叠加后的护甲量。
func _grant_armor(health: int, cap: int) -> void:
	var choices: Array[HpComponentPlant] = [] # 同一株多格植物只作为一个等概率候选。
	for cell: PlantCell in neighborhood(_center): # 局部九宫格可保护相邻陆上的友军。
		for plant: Plant000Base in cell.living_plants(): # 包含承托、保护壳和伴生。
			var hp := plant.hp_component as HpComponentPlant # 使用正常可消耗的临时护甲。
			if hp != null and not hp.is_death and not plant.is_hypno and plant.get_instance_id() != battle.source_id \
					and hp.bonus_armor < cap and not choices.has(hp):
				choices.append(hp)
	if not choices.is_empty():
		var recipient: HpComponentPlant = choices.pick_random() # 每击杀独立抽取一株。
		recipient.grant_bonus_armor(health, cap)
