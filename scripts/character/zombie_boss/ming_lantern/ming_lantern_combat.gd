## 结算明灯技能的命中和本体死亡时的清场。
extends RefCounted
class_name MingLanternCombat

## 灯条插入本格的基础伤害。
const ROD_IMPACT := 300
## 水下爆炸对植物的基础伤害；普通僵尸按一半结算。
const UNDERWATER_DAMAGE := 8000
## 浪对普通僵尸的实际基础伤害，已按半伤换算。
const WAVE_ZOMBIE_DAMAGE := 100

## 本场战斗的棋盘和角色索引；图鉴演出不创建此结算器。
var game: MainGameManager
## 明灯本人，也是其直接伤害和碾压的归因。
var caster: ZB000Base

## 本次入场的战场仍在运行，格子允许修改。
func active() -> bool:
	return is_instance_valid(game) and is_instance_valid(game.zombie_manager) \
		and game.zombie_manager.is_game_running() and game.board != null and game.board.allows_mutation()

## 明灯死亡时处决本战场登记的普通僵尸，包括已魅惑和仍在入场的实例。
func defeat_remaining_zombies() -> void:
	if not active():
		return
	for zombie: Zombie000Base in game.zombie_manager.all_zombies_1d.duplicate(): # 死亡回调会同步从原列表移除角色。
		if _alive(zombie):
			zombie.retire_from_battle(true)

## [param address] 的受力最外层植物受伤；路过本格的普通僵尸同样受到半伤。
func rod_impact(address: Vector2i) -> void:
	if not active():
		return
	var cell: PlantCell = game.board.cell_at(address) # 灯条落下时重新定位实际地块。
	if cell == null:
		return
	# 依次选择保护壳、核心植物、伴生或底座，灯条插入一次只打中一株。
	var victim: Plant000Base
	for slot: CharacterRegistry.PlacePlantInCell in [CharacterRegistry.PlacePlantInCell.Shell,
			CharacterRegistry.PlacePlantInCell.Norm, CharacterRegistry.PlacePlantInCell.Imitater]: # 与普通啃食一致的层级。
		var candidate: Plant000Base = cell.plant_in_cell.get(slot) as Plant000Base # 读取当前格最外层。
		if _alive(candidate):
			victim = candidate
			break
	if victim == null:
		victim = cell.first_companion_plant()
		if victim == null:
			var residents: Array[Plant000Base] = cell.living_plants() # 底座或悬浮层由地块返回实际占用。
			if not residents.is_empty():
				victim = residents[0]
	if victim != null:
		_hit(victim, ROD_IMPACT)
	for zombie: Zombie000Base in _zombies([cell]): # 不区分已魅惑和普通僵尸。
		_hit(zombie, ROD_IMPACT / 2)

## [param address] 为 3×3 爆心，多格植物在同一次爆炸只受一次伤害。
func underwater_blast(address: Vector2i) -> void:
	if not active():
		return
	var area: Array[PlantCell] = game.board.neighbors(game.board.cell_at(address), 1) # 地图边缘按实际可用格裁切。
	for plant: Plant000Base in _plants(area): # 爆炸伤害各株实际生命。
		if _alive(plant):
			plant.be_hit_from(UNDERWATER_DAMAGE, caster, BulletRegistry.AttackMode.Penetration, false, false, CombatHitScope.PlantImpact.EXPLOSION)
	for zombie: Zombie000Base in _zombies(area): # 半伤保留原有防御与受击处理。
		_hit(zombie, UNDERWATER_DAMAGE / 2)

## [param address] 为 3×3 锚尖落点，碾死该范围的植物；僵尸承受等效处决量的一半。
func anchor_impact(address: Vector2i) -> void:
	if not active():
		return
	var area: Array[PlantCell] = game.board.neighbors(game.board.cell_at(address), 1) # 使用真实占格而非锚图片大小。
	for plant: Plant000Base in _plants(area): # 逐个复核，多格植物不会重复碾压。
		if _alive(plant):
			plant.be_hit_instantly(CombatHitScope.for_plant_attack(caster, CombatHitScope.PlantImpact.CRUSH))
	for zombie: Zombie000Base in _zombies(area): # 半伤按被砸时的含护甲生命取值。
		if _alive(zombie):
			_hit(zombie, ceili(float(zombie.hp_component.get_all_hp()) * 0.5))

## [param address] 为震颤中心，[param origin] 和 [param radius] 描述当前椭圆的世界几何。
## [param touched] 在主环和余波之间共享，以免同次震颤刷新控制。
func ring_progress(address: Vector2i, origin: Vector2, radius: Vector2, touched: Dictionary[int, bool]) -> void:
	if not active() or radius.x <= 0.0 or radius.y <= 0.0:
		return
	var area: Array[PlantCell] = game.board.neighbors(game.board.cell_at(address), 2) # 控制不会超出五行五列。
	for cell: PlantCell in area: # 按真实居住格判断多格植物的首次接触。
		if ((cell.get_global_rect().get_center() - origin) / radius).length_squared() > 1.0:
			continue
		for plant: Plant000Base in cell.living_plants(): # 施加纯冻结及后续减速，无冰弹附伤。
			var id: int = plant.get_instance_id() # 同一效果的命中身份。
			if not touched.has(id):
				touched[id] = true
				plant.apply_ice_freeze_control(3.0, 4.0)
	for zombie: Zombie000Base in _zombies(area): # 普通僵尸只减速。
		var id: int = zombie.get_instance_id() # 本环的已接触标记。
		if not touched.has(id) and ((zombie.global_position - origin) / radius).length_squared() <= 1.0:
			touched[id] = true
			zombie.be_ice_decelerate(6.0)

## [param lane] 是攻击行，[param left]、[param right] 是本帧浪扫过的横坐标。
## [param push_cells] 为植物顺推步数。返回已受浪的前缘横坐标，未接触返回 NAN。
func wave_contact(lane: int, left: float, right: float, push_cells: int) -> float:
	if not active():
		return NAN
	var cells: Array[PlantCell] = game.board.row_cells(lane) # 通过权威棋盘查询当前行。
	var plant_cell: PlantCell # 水流遇到的首个植物格。
	var zombie: Zombie000Base # 水流遇到的首个普通僵尸。
	var front: float = left - 1.0 # 向左前进时，取所有可接触位置中最靠右者。
	for cell: PlantCell in cells: # 地块枚举不要求矩形棋盘。
		var x: float = cell.get_global_rect().get_center().x # 以地块的横向中心对齐接触。
		if x > front and x >= left and x <= right and not cell.living_plants().is_empty():
			front = x
			plant_cell = cell
	for candidate: Zombie000Base in _zombies(cells): # 僵尸与植物共同决定浪的最早碰撞点。
		var x: float = candidate.global_position.x # 跨帧扫掠以脚点为准。
		if x > front and x >= left and x <= right:
			front = x
			zombie = candidate
			plant_cell = null
	if plant_cell != null:
		_push_plant_chain(plant_cell, push_cells)
	elif zombie != null:
		_hit(zombie, WAVE_ZOMBIE_DAMAGE)
		if _alive(zombie):
			var pitch: float = BoardQueries.local_pitch(game.board, game.board.nearest_cell(zombie.global_position, lane)).x # 僵尸在二阶段仍只移动一格。
			zombie.move_component.apply_forced_displacement(Vector2(-pitch, 0.0), 0.19)
	return front if plant_cell != null or zombie != null else NAN

## [param entry] 为被击中的植物格，[param steps] 重复沿连续占用向左推。
func _push_plant_chain(entry: PlantCell, steps: int) -> void:
	for _step: int in range(steps): # 二阶段先完成一次占格，再按新位置结算第二格。
		if entry == null or entry.living_plants().is_empty():
			return
		var chain: Array[PlantCell] = [entry] # 从接触格向最左侧跟踪连续的占位。
		var gap: PlantCell = _left_of(entry) # 当前接续位置。
		while gap != null and not gap.living_plants().is_empty():
			chain.append(gap)
			gap = _left_of(gap)
		var moved: Dictionary[int, bool] = {} # 多格植物的占格重叠只移动一次。
		for index: int in range(chain.size() - 1, -1, -1): # 从最左端开始为空间腾位。
			var source: PlantCell = chain[index] # 候选植物所属的实际物理列。
			var plants: Array[Plant000Base] = source.living_plants() # 先查看是否需要整格搬动承托。
			var destination: PlantCell = _left_of(source) # 本格的收力位置。
			if destination != null and plants.size() > 1 and is_instance_valid(source.get_support_plant()):
				if not source.relocate_supported_stack(destination):
					return
				for plant: Plant000Base in plants: # 已移动的承托成员不参与后续单株处理。
					moved[plant.get_instance_id()] = true
				continue
			for plant: Plant000Base in plants: # 普通与多格植物沿用经完整预检的占格迁移。
				var id: int = plant.get_instance_id() # 一次推进中只结算一次。
				if moved.has(id) or not _alive(plant):
					continue
				moved[id] = true
				var home: PlantCell = plant.plant_cell # 多格植物以权威主格搬移。
				var next: PlantCell = _left_of(home) # 取实际权威主格的左邻，允许多格重叠。
				if next == null:
					plant.be_hit_instantly(CombatHitScope.for_plant_attack(caster, CombatHitScope.PlantImpact.CRUSH))
				elif not home.relocate_plant(plant, next):
					return
		entry = _left_of(entry)

## 返回 [param source] 的同平台左邻；棋盘边缘返回 null。
func _left_of(source: PlantCell) -> PlantCell:
	if not is_instance_valid(source):
		return null
	var neighbor: PlantCell = game.board.cell_at(source.row_col - Vector2i(0, 1)) # 仅在同一攻击行找前一列。
	return neighbor if neighbor != null and game.board.right_of(neighbor) == source else null

## [param area] 内各植物只登记一次，保留多格占位。
func _plants(area: Array[PlantCell]) -> Array[Plant000Base]:
	var plants: Array[Plant000Base] = [] # 同帧结算用快照。
	for cell: PlantCell in area: # 枚举每格所有存活植物层。
		for plant: Plant000Base in cell.living_plants(): # 实际节点作为去重依据。
			if not plants.has(plant):
				plants.append(plant)
	return plants

## 返回在 [param area] 脚点横向范围内的普通僵尸，包括已魅惑者。
func _zombies(area: Array[PlantCell]) -> Array[Zombie000Base]:
	var result: Array[Zombie000Base] = [] # 不受逐个伤害引起的原始行列表移除影响。
	var lanes: Dictionary[int, Array] = {} # 每行只扫描一次。
	for cell: PlantCell in area: # 按当前行记录地块的实际横向范围。
		var lane: int = cell.row_col.x # 地块的攻击行。
		if not lanes.has(lane):
			lanes[lane] = []
		lanes[lane].append(cell.get_global_rect())
	for zombie: Zombie000Base in game.zombie_manager.all_zombies_1d: # 含不再登记在敌方行索引的魅惑僵尸。
		if not _alive(zombie) or not lanes.has(zombie.lane) or not zombie.hurt_box_component.is_enabling:
			continue
		var x: float = zombie.global_position.x # 同行内以地面接触点而非贴图边缘定位。
		for rect: Rect2 in lanes[zombie.lane]: # 有间隔的地块不合并成实心矩形。
			if x >= rect.position.x and x < rect.end.x:
				result.append(zombie)
				break
	return result

## [param target] 在同步回调之后仍存在且可以继续交互时返回 true。
func _alive(target: Character000Base) -> bool:
	return is_instance_valid(target) and target.is_inside_tree() and not target.is_death and not target.is_queued_for_deletion()

## 通过现有生命入口给 [param target] 施加 [param damage] 点穿透伤害。
func _hit(target: Character000Base, damage: int) -> void:
	if _alive(target):
		var scope: CombatHitScope = CombatHitScope.for_plant_attack(caster) if target is Plant000Base else null # 仅对植物保留反伤来源。
		target.be_attacked_bullet(damage, BulletRegistry.AttackMode.Penetration, false, false, 0, -1, null, scope)
