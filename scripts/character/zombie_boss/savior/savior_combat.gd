## 救主的五项技能结算。以原画出手帧启动，共用教堂覆盖、占格和受击系统。
extends RefCounted

## 祈祷种类和所属遭遇的共同时钟。
const ActionTree = preload("res://scripts/character/zombie_boss/savior/savior_action_tree.gd")
## 与亡影清除共用同一暖灯覆盖判定。
const Remains = preload("res://scripts/adventure/zombie_church_plant_remains.gd")
## 路灯花的系统灯信息。
const Light = preload("res://scripts/battle/environment/battle_light_source.gd")
## 福音自己的承伤设施。
const Pillar = preload("res://scripts/character/zombie_boss/savior/savior_gospel_pillar.gd")
## 普通僵尸剪影变体，避免同一只信徒重复转换。
const Follower = preload("res://scripts/character/zombie_boss/savior/savior_follower.gd")
## 连续碰撞与落地范围各自维护。
const Sweep = preload("res://scripts/character/zombie_boss/savior/savior_sweep.gd")
## 救主的原画提供无垠的余像与疯狂的抬掌停留。
const SaviorVisual = preload("res://scripts/character/zombie_boss/savior/savior_visual.gd")
## 已准备的四个黑光落点和共同演出时钟。
const Meteors = preload("res://scripts/character/zombie_boss/savior/savior_meteors.gd")
## 惟一正式的福音柱场景，按救主战斗加载。
const PILLAR_SCENE: PackedScene = preload("res://scenes/character/zombie_boss/savior_gospel_pillar.tscn")

## 当前 Boss 实例，待机行与落点来自它的实战世界位置。
var boss: ZB000Base
## 当前战场，用于取真实棋盘和管理器。
var game: MainGameManager
## 救主共享行动和地图环境的接口。
var arena: SaviorBattle
## 战斗画布上的仪式动效。
var effects: Node2D
## 仅本场行动使用的随机序列。
var _rng := RandomNumberGenerator.new()
## 六柱当前的运动和命中记录。
var _sweep: Sweep
## 绝望的预告落点和伤害时钟。
var _meteors: Meteors
## 福音祈祷期间已经锁定的植株。
var _marked_plant: Plant000Base
## 同时活跃的福音柱，按独立实例管理倒计时与结束。
var _pillars: Dictionary[int, Pillar] = {}

## [param owner]、[param battle] 和 [param host] 分别提供本体、战场及演出宿主。
func _init(owner: ZB000Base, battle: MainGameManager, host: SaviorBattle) -> void:
	boss = owner
	game = battle
	arena = host
	effects = host.savior_effects
	_rng.randomize()
	var tracks = host.savior_channels.acquire(owner.get_instance_id()) # 各自独占会覆盖上一轮数据的演出节点。
	_sweep = Sweep.new(game, tracks.madness, host.savior_actions.claim_cue.bind(ActionTree.Cue.MADNESS_LANDING))
	_meteors = Meteors.new(game.board, tracks.despair, host.savior_actions.claim_cue, owner)

## 本场仍可以接收伤害与出怪。
func active() -> bool:
	return is_instance_valid(game) and game.zombie_manager.is_game_running()

## 判断 [param skill] 是否具备真实目标。疯狂和绝望可在空场施放。
func has_target(skill: ActionTree.Skill) -> bool:
	match skill:
		ActionTree.Skill.VOID:
			return arena.has_revivable_plant_remains()
		ActionTree.Skill.PEACE:
			return game.zombie_manager.all_zombies_1d.any(_can_convert_zombie)
		ActionTree.Skill.GOSPEL:
			return not _gospel_targets().is_empty()
	return skill in [ActionTree.Skill.MADNESS, ActionTree.Skill.DESPAIR]

## 在 [param skill] 起手时锁定实际目标。[param claimed_cells] 是同轮福音已经分配的格子。
func prepare(skill: ActionTree.Skill, claimed_cells: Dictionary[PlantCell, bool]) -> Array[Rect2]:
	var areas: Array[Rect2] = [] # 祈祷的地面目标；福音必须分配到可用格子。
	match skill:
		ActionTree.Skill.VOID, ActionTree.Skill.MADNESS:
			return areas
		ActionTree.Skill.DESPAIR:
			areas = _meteors.prepare(_rng)
		ActionTree.Skill.GOSPEL:
			var candidates: Array[Plant000Base] = _gospel_targets(claimed_cells) # 起手沿用抽签时的保护规则。
			_marked_plant = null if candidates.is_empty() else candidates[_rng.randi_range(0, candidates.size() - 1)]
			if is_instance_valid(_marked_plant):
				var cell: PlantCell = _marked_plant.plant_cell # 同轮各柱留出独立的承伤目标。
				claimed_cells[cell] = true
				areas.append(cell.get_global_rect())
			return areas
	if areas.is_empty():
		var cell: PlantCell = BoardQueries.nearest(game.board, boss.global_position, boss.lane) # 其余法术在本体脚边聚拢黑泪。
		if cell != null:
			areas.append(cell.get_global_rect())
	return areas

## 按共用行动树提供的 [param skill] 结算。[param visual] 在疯狂光柱展开期间保持抬掌。
func release(skill: ActionTree.Skill, visual: SaviorVisual) -> void:
	match skill:
		ActionTree.Skill.VOID:
			_resolve_void()
		ActionTree.Skill.MADNESS:
			_sweep.start(boss.shadow, visual, boss.boss_phase >= 2)
		ActionTree.Skill.PEACE:
			_convert_zombies()
		ActionTree.Skill.DESPAIR:
			_meteors.start()
		ActionTree.Skill.GOSPEL:
			_open_pillar()

## [param battle_delta] 推进已经发射的陨石，[param action_delta] 推进仍操控的光柱。
func advance(battle_delta: float, action_delta: float) -> void:
	_sweep.advance(action_delta)
	_meteors.advance(battle_delta)

## Boss 死亡时回收柱体并取消未完成的技能。
func clear() -> void:
	_sweep.stop()
	_meteors.stop()
	for id: int in _pillars: # 主动撤销这一名施法者的设施，不影响其他福音柱。
		var pillar: Pillar = _pillars[id] # 已获胜或离场的柱体不走成熟。
		if is_instance_valid(arena) and is_instance_valid(arena.savior_gospel):
			arena.savior_gospel.dismiss(id)
		if is_instance_valid(pillar):
			pillar.queue_free()
	_pillars.clear()

## 角色离树时归还自己的长时视觉通道。
func release_tracks() -> void:
	if is_instance_valid(arena):
		arena.savior_channels.release(boss.get_instance_id())

## 提取 [param cells] 中的各层活体植物，一个实体只返回一次。
static func _plants(cells: Array[PlantCell]) -> Array[Plant000Base]:
	var plants: Dictionary[Plant000Base, bool] = {} # 整个结算区域的实体去重。
	for cell: PlantCell in cells: # 活体层仍包括南瓜和支撑物。
		for plant: Plant000Base in cell.living_plants(): # 多格植物或叠种都走实际登记。
			plants[plant] = true
	var result: Array[Plant000Base] = [] # 保留遍历顺序，便于统一技能抽取。
	result.assign(plants.keys())
	return result

## 返回福音可锁定的活体，并排除本轮 [param claimed_cells] 已分配的主格。
func _gospel_targets(claimed_cells: Dictionary[PlantCell, bool] = {}) -> Array[Plant000Base]:
	return _plants(game.board.cells()).filter(func(plant: Plant000Base) -> bool:
		return Pillar.is_target_allowed(plant) and not claimed_cells.has(plant.plant_cell))

## 黑场落稳后依次伤害无保护植株，使旧亡影和本次新亡影一同复生。
func _resolve_void() -> void:
	if not active() or not is_instance_valid(boss) or boss.is_death or boss.is_queued_for_deletion():
		return
	_strike_unlit(_unlit_plants())
	arena.revive_plant_remains(_spawn_follower)

## 入场时先解开已有亡影。同期所有十字共用一次暗场冲击，未被路灯花照到的植物各承伤 1000。
func resolve_entrance() -> void:
	if not active():
		return
	var targets: Array[Plant000Base] = _unlit_plants() # 在复生可能改变占格前冻结路灯花覆盖。
	arena.revive_plant_remains(_spawn_follower)
	_strike_unlit(targets)

## 按结算帧的路灯花覆盖取得所有未受保护的真实活体。
func _unlit_plants() -> Array[Plant000Base]:
	var lights: Array[Light] = arena.plantern_lights() # 施法帧的未遮挡暖光贡献。
	var unprotected: Array[Plant000Base] = [] # 防止先死的灯改变本次伤害顺序。
	for plant: Plant000Base in _plants(game.board.cells()): # 取植物主格中心判断是否位于路灯花实际光圈内。
		if not Remains.lamp_covers(plant.plant_cell.get_global_rect().get_center(), lights):
			unprotected.append(plant)
	return unprotected

## 对预先冻结的 [param targets] 结算真实伤害，保留黑暗死亡的原生通知。
func _strike_unlit(targets: Array[Plant000Base]) -> void:
	for plant: Plant000Base in targets: # 当前受击回调可能同步让同格的其他植株离场。
		if is_instance_valid(plant) and not plant.is_death:
			plant.be_hit_from(1000, boss, BulletRegistry.AttackMode.Real, false)

## 在 [param lane] 和 [param point] 创建信徒；[param replaces] 提供转换单位的名额，失败时返回 null。
func _spawn_follower(lane: int, point: Vector2, replaces: Zombie000Base = null) -> Zombie000Base:
	var follower: Zombie000Base = game.zombie_manager.create_savior_follower(lane, point, replaces) # 占原脚点并接入光场。
	if follower != null:
		effects.follower_burst(point)
	return follower

## [param zombie] 必须是活着的敌方普僵，任意等阶均可，信徒不重复转换。
func _can_convert_zombie(zombie: Zombie000Base) -> bool:
	return is_instance_valid(zombie) and zombie.is_inside_tree() and not zombie.is_queued_for_deletion() \
		and not zombie.is_death and not zombie.is_hypno and not zombie is Follower \
		and zombie.zombie_type == CharacterRegistry.ZombieType.Z001Norm

## 从合格的普通僵尸中随机转换最多八只，保留各自脚点。
func _convert_zombies() -> void:
	var candidates: Array[Zombie000Base] = game.zombie_manager.all_zombies_1d.filter(_can_convert_zombie) # 用与抽签相同的目标条件刷新名单。
	for index: int in range(mini(8, candidates.size())): # 无放回抽取，至多转换八个不同实例。
		var selected: int = _rng.randi_range(index, candidates.size() - 1) # 将已选项目换到前缀。
		var zombie: Zombie000Base = candidates[selected] # 本次转换的活体敌人。
		candidates[selected] = candidates[index]
		candidates[index] = zombie
		if _can_convert_zombie(zombie) and _spawn_follower(zombie.lane, zombie.shadow.global_position, zombie) != null:
			game.zombie_manager.retire_converted_zombie(zombie)

## 在锁定目标仍在场时安装原生可受击设施；死亡与超时分别回调。
func _open_pillar() -> void:
	var target: Plant000Base = _marked_plant # 出手只消费本次锁定。
	_marked_plant = null
	if not is_instance_valid(target):
		return
	var pillar: Pillar = PILLAR_SCENE.instantiate() as Pillar # 使用与同格攻击兼容的独立承伤层。
	if not pillar.setup(game, target):
		pillar.free()
		return
	var id: int = pillar.get_instance_id() # 每根柱子独立计时、绘制及撤销。
	pillar.expired.connect(_on_gospel_expired, CONNECT_ONE_SHOT)
	pillar.signal_character_death.connect(_on_gospel_destroyed.bind(id), CONNECT_ONE_SHOT)
	pillar.tree_exiting.connect(_on_gospel_destroyed.bind(id), CONNECT_ONE_SHOT)
	game.add_child(pillar)
	_pillars[id] = pillar
	arena.savior_gospel.watch(pillar)

## [param structure] 到期或由原株换格触发成熟时，使原植物湮灭并恢复救主 6000 点生命。
func _on_gospel_expired(structure: EnemyStructureBase) -> void:
	var pillar := structure as Pillar # 自身区分被打碎和成熟。
	var id: int = pillar.get_instance_id() # 先撤销演出记录，避免同步死亡回调重入。
	if not _pillars.erase(id) or not active() or boss.is_death:
		return
	var plant: Plant000Base = pillar.living_plant() # 原标记已失效时不误判后来种下的植物。
	arena.savior_gospel.finish(id, true, plant)
	if plant != null:
		plant.be_hit_instantly(CombatHitScope.for_plant_attack(boss), true)
	boss.hp_component.heal(6000)

## [param id] 对应的福音柱被击碎，不再触发湮灭和回血。
func _on_gospel_destroyed(id: int) -> void:
	if _pillars.erase(id) and is_instance_valid(arena) and is_instance_valid(arena.savior_gospel):
		arena.savior_gospel.finish(id, false)
