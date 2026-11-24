## 魅惑菇赋予的随身状态，由原生移动、攻击、受击和击杀事件驱动。
extends Node
class_name AdventureHypnoAlly

## 原生爆炸表现，伤害范围由真实种植格计算。
const BLAST_FX_PATH := "res://resources/combat/jackbox_explosion_profile.tres"
## 卡片在出场时已冻结的转职分支，原菇死亡后仍有效。
var _rules: Dictionary[String, Dictionary]
## 只允许在原战场、轮次及阶段发动后续效果。
var _battle: RepeaterShotContext
## 已转为友军且持有本状态的原生角色。
var _zombie: Zombie000Base
## 当前攻击行最右的真实格子，兼作恶意的爆炸中心。
var _edge_cell: PlantCell
## 缓存边缘格时的攻击行，-1 表示尚未计算。
var _edge_lane: int = -1
## 已经跨过边缘并安排恶意，后续位移不再触发。
var _malice_fired: bool = false
## 肉体改造提供的移动倍率，保留其他速度来源。
var _move_rate: float = 1.0
## 进入原生攻击状态时才应用的攻击节奏倍率。
var _attack_rate: float = 1.0
## 感染只监听确认的敌方普通僵尸击杀。
var _infection_chance: float = 0.0

## 给 [param zombie] 安装来源 [param battle] 的 [param rules]。[param inherited] 由感染还原原有临时增益。
static func install(zombie: Zombie000Base, battle: RepeaterShotContext,
		rules: Dictionary[String, Dictionary], inherited: bool = false) -> void:
	if not inherited and rules.has("hypno_release"):
		AdventureZombieTimedCombatBuff.grant_immunity(zombie, float(rules["hypno_release"]["immune_seconds"]), true)
	if not inherited and rules.has("hypno_remodel"):
		AdventureSunBeanEffect.apply_to(zombie, true)
	if not (rules.has("hypno_remodel") or rules.has("hypno_madness") or rules.has("hypno_malice") or rules.has("hypno_infection")):
		return
	var effect := AdventureHypnoAlly.new() # 每个友军分开持有速度来源及触发状态。
	effect._rules = rules
	effect._battle = battle
	effect._zombie = zombie
	zombie.add_child(effect)

## 安装原生状态和所选事件监听；恶意只在自然越界后的下一物理步做查询。
func _ready() -> void:
	var remodel: Dictionary = _rules.get("hypno_remodel", {}) # 空字典代表未选择肉体改造。
	if not remodel.is_empty():
		_move_rate = float(remodel["move_rate"])
		_attack_rate = float(remodel["attack_rate"])
		_zombie.attack_component.signal_change_is_attack.connect(_on_attack_changed)
		_on_attack_changed(_zombie.attack_component.is_attack_res)
	var madness: Dictionary = _rules.get("hypno_madness", {}) # 生命组件在每次出手和受击时读取数值。
	if not madness.is_empty():
		_zombie.hp_component.missing_health_damage_per_percent = float(madness["damage_per_percent"])
		_zombie.hp_component.missing_health_reduction_per_percent = float(madness["reduction_per_percent"])
		_zombie.hp_component.missing_health_reduction_cap = float(madness["reduction_cap"])
	var infection: Dictionary = _rules.get("hypno_infection", {}) # 未选择感染的角色没有击杀监听。
	if not infection.is_empty():
		_infection_chance = float(infection["chance"])
		_zombie.signal_hypno_enemy_killed.connect(_on_enemy_killed)
	set_physics_process(false)
	if _rules.has("hypno_malice"):
		_zombie.move_component.walked_right.connect(_on_walked_right)

## [param attacking] 由原生索敌驱动。攻速单独作用于出手，移动在叠乘后仍恰好减半。
func _on_attack_changed(attacking: bool) -> void:
	var attack_speed: float = _attack_rate if attacking else 1.0 # 攻态退出即撤销出手倍率。
	_zombie.set_action_speedup(get_instance_id(), attack_speed)
	_zombie.move_component.set_move_rate_source(get_instance_id(), _move_rate / attack_speed)

## [param _victim] 的死者身份已由实际承伤链验证。先拍下状态，延后入树以避开同步击杀回调。
func _on_enemy_killed(_victim: Zombie000Base) -> void:
	if not _battle.is_active() or randf() >= _infection_chance:
		return
	var state: Dictionary = AdventureHypnoClone.capture(_zombie) # 原来源退场也保留已确认击杀时的血量和效果。
	var scheduler: ZombieUpdateScheduler = _battle.game.zombie_manager.periodic_updates # 复用本场的分帧工作队列。
	scheduler.enqueue_battle_spawn(AdventureHypnoClone.spawn.bind(state, _battle, _rules, scheduler.active_seconds()))

## [param previous_x] 是原生步进前的脚点。终点只认走过去，忽略强制移动与原生飞行。
func _on_walked_right(previous_x: float) -> void:
	if _malice_fired or _zombie.is_death or _zombie.is_queued_for_deletion() or _zombie.is_native_airborne():
		return
	if _edge_lane != _zombie.lane or (_edge_cell != null and (
			not is_instance_valid(_edge_cell) or _edge_cell.combat_lane != _edge_lane or _edge_cell.is_queued_for_deletion())):
		_refresh_edge()
	if not is_instance_valid(_edge_cell):
		return
	var right: float = _edge_cell.get_global_rect().end.x # 移动平台采用当前世界变换。
	if previous_x < right and _zombie.global_position.x >= right and _battle.is_active():
		_malice_fired = true
		_zombie.move_component.walked_right.disconnect(_on_walked_right)
		set_physics_process(true)

## [param _delta] 仅供进程回调。跨边缘后在下一物理步查询受击区域，平时没有轮询。
func _physics_process(_delta: float) -> void:
	set_physics_process(false)
	if is_instance_valid(_edge_cell) and not _edge_cell.is_queued_for_deletion() and _battle.is_active():
		_detonate(_edge_cell)

## 根据当前真实攻防行更新右侧格，换行与缺格均不会沿用上一条路线的边界。
func _refresh_edge() -> void:
	_edge_lane = _zombie.lane
	_edge_cell = null
	for cell: PlantCell in _battle.board.row_cells(_edge_lane): # 按当前世界右边界取格，兼容不等宽地块。
		if is_instance_valid(cell) and cell.is_visible_in_tree() and not cell.is_queued_for_deletion() \
				and (_edge_cell == null or cell.get_global_rect().end.x > _edge_cell.get_global_rect().end.x):
			_edge_cell = cell

## 从最后一格 [param center] 的九宫格结算一次爆炸。普通僵尸按脚点，僵王按真实受击盒去重。
func _detonate(center: PlantCell) -> void:
	var game: MainGameManager = _battle.game # 由已验战场提供分行登记和碰撞查询。
	var cells: Array[PlantCell] = AdventureHypnoCast.local_cells(center, _battle.board) # 两种目标共用同一批地块。
	var malice: Dictionary = _rules["hypno_malice"] # 冻结的原值分别用于普通僵尸与僵王。
	var targets: Array[Zombie000Base] = AdventureHypnoCast.enemies_in_cells(cells, _battle) # 先冻结范围内的敌人。
	var bosses: Array[Character000Base] = _bosses_in_cells(game, cells) # 僵王的攻击行可能和实际受击盒不同。
	var scope := CombatHitScope.new() # 代伤者最多从同场爆炸承伤一次。
	for target: Zombie000Base in targets: # 承伤可同步杀死后续目标，逐个复核。
		if is_instance_valid(target) and not target.is_death and not target.is_hypno and not target.is_queued_for_deletion():
			target.be_bomb(int(malice["damage"]), false, 1.0, scope)
	for boss: Character000Base in bosses: # 每个僵王只消费一次爆炸命中。
		if is_instance_valid(boss) and not boss.is_death and not boss.is_queued_for_deletion():
			boss.be_attacked_bullet(int(malice["boss_damage"]), BulletRegistry.AttackMode.Penetration, false, false)
	var visuals := load(BLAST_FX_PATH) as CombatExplosionProfile # 只在实际引爆时使用原生特效资源。
	if is_instance_valid(center):
		CombatExplosion.emit_visuals(game.bombs, visuals, center.get_spawn_global_position())

## 只有 [param game] 有在场僵王才查询 [param cells] 的物理受击区，各格共用形状资源与目标去重。
func _bosses_in_cells(game: MainGameManager, cells: Array[PlantCell]) -> Array[Character000Base]:
	var result: Array[Character000Base] = [] # 保留每个僵王首次命中的顺序。
	if game.zombie_manager.get_living_bosses().is_empty():
		return result
	var profile := CombatExplosionProfile.new() # 仅供本次普通敌方受击盒查询。
	var shape := RectangleShape2D.new() # 按真实种植格的当前尺寸复用。
	profile.shape = shape
	profile.collision_mask = 4 # 植物伤害使用的普通敌方受击层。
	var space: PhysicsDirectSpaceState2D = game.get_world_2d().direct_space_state # 本次越界后的物理帧。
	for cell: PlantCell in cells: # 逐格核对，避免跨越空洞或跨平台命中。
		var rect: Rect2 = cell.get_global_rect() # 地块实际世界坐标。
		shape.size = rect.size
		var areas: Array[Area2D] = CombatExplosion.query_areas(space, profile, rect.get_center()) # 本格接触的受击区。
		for target: Character000Base in CombatExplosion.plant_blast_targets(areas, _edge_lane, 1, Zombie000Base.E_BeAttackStatusZombie.IsNorm): # 再做跨格去重。
			if target is ZB000Base and not result.has(target):
				result.append(target)
	return result
