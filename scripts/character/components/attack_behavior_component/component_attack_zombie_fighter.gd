## 战斗机的三连发机枪和击毁伤害，均通过棋盘的有效格子筛选目标。
extends AttackComponentBase
class_name AttackComponentZombieFighter

## 射出的光弹来自原作飞机开火源图的光核。
const BULLET_IMAGE: Texture2D = preload("res://assets/adventure/zombies/fighter/bullet.png")
## 真实枪击短音源，自由授权素材裁切，不再将小喷菇声音当成机枪。
const SHOT_SOUND: AudioStream = preload("res://assets/adventure/zombies/fighter/audio/gunshot.ogg")
## 每颗子弹固定造成的基础伤害。
const SHOT_DAMAGE: int = 10
## 机枪三连发，发内和组间间隔均以战斗秒计算。
const BURST_SHOTS: int = 3
const SHOT_GAP: float = 0.10
const BURST_COOLDOWN: float = 0.86
## 机身被击毁后一次性爆炸伤害。
const CRASH_DAMAGE: int = 400

## 所属战斗机；只读取标准生命、方向与战斗行动倍率。
var _fighter: Zombie000Base
## 枪口帧由表现层负责，行为层只通知一次事件。
var _visual: FighterPresentation
## 距离下次点射的行动秒数。
var _shot_wait: float = 0.25
## 本组三连发尚未发射的颗数。
var _shots_remaining: int = 0

## 非战斗展示不运行武器的物理时钟。
func _ready() -> void:
	super()
	set_physics_process(false)

## [param fighter] 是正式的僵尸战斗实例，[param visual] 是同一实例的美术控制器。
func activate(fighter: Zombie000Base, visual: FighterPresentation) -> void:
	_fighter = fighter
	_visual = visual
	set_physics_process(true)

## [param delta] 为战斗物理秒；冷却读取行动倍率，低帧率至多点射一颗。
func _physics_process(delta: float) -> void:
	if not is_enabling or not is_instance_valid(_fighter) or _fighter.is_death \
			or _fighter.is_queued_for_deletion() or _fighter.is_action_suspended():
		return
	var seconds: float = delta * _fighter.action_rate() # 减速、眩晕与时间能力统一调制。
	_shot_wait -= seconds
	if _shot_wait > 0.0:
		return
	var target: Plant000Base = _find_target() # 只在允许开火时检查当前行的有效格子。
	if target == null:
		_shots_remaining = 0
		_shot_wait = 0.18
		return
	_fire(target)
	if _shots_remaining == 0:
		_shots_remaining = BURST_SHOTS - 1
	else:
		_shots_remaining -= 1
	_shot_wait = SHOT_GAP if _shots_remaining > 0 else BURST_COOLDOWN

## 沿选中的行搜索飞机前方最近的有效植物，最大六格。
func _find_target() -> Plant000Base:
	if _fighter.is_hypno:
		return null
	var game: MainGameManager = Global.main_game # 只允许本战局做攻击查询。
	if not is_instance_valid(game) or not game.is_ancestor_of(_fighter) or game.board == null:
		return null
	var max_reach: float = maxf(game.board.cell_width_at(_fighter.global_position, _fighter.lane) * 6.0, 400.0)
	var nearest: float = INF # 最近目标的横向距离。
	var chosen: Plant000Base
	for cell: PlantCell in game.board.row_cells(_fighter.lane):
		for plant: Plant000Base in cell.living_plants():
			if not is_instance_valid(plant) or plant.is_death or plant.is_queued_for_deletion() or plant.battle_hidden_from_zombies:
				continue
			var dx: float = _fighter.global_position.x - plant.global_position.x
			if dx >= 18.0 and dx <= max_reach and dx < nearest:
				nearest = dx
				chosen = plant
	return chosen

## [param target] 接收本次锁定目标；弹丸飞行后才命中，死亡或离场时不补发伤害。
func _fire(target: Plant000Base) -> void:
	_visual.fire() # 先播放独立枪焰与机体后坐，不因弹丸轨迹被隐藏。
	SoundManager.play_world_sfx(SHOT_SOUND, self, _visual.muzzle_world_position(),
		-10.0, randf_range(0.97, 1.04), &"fighter_gun", false)
	var bullet: Sprite2D = Sprite2D.new() # 发射时只创建一枚短命可见弹丸。
	bullet.texture = BULLET_IMAGE
	bullet.scale = Vector2(0.56, 0.34)
	bullet.modulate = Color(1.0, 0.96, 0.77, 1.0)
	bullet.z_index = 25
	var trace: Line2D = Line2D.new() # 弹尾同弹丸一起运动，避免逐帧维护第二条轨迹。
	trace.width = 6.0
	trace.default_color = Color(1.0, 0.71, 0.21, 0.72)
	trace.add_point(Vector2(16.0, 0.0))
	trace.add_point(Vector2(66.0, 0.0))
	bullet.add_child(trace)
	var row: Node2D = _fighter.get_parent() as Node2D # 弹丸归属战斗行，敌人死后仍能回收。
	row.add_child(bullet)
	bullet.global_position = _visual.muzzle_world_position() # 与原作枪口光效共用锚点。
	var destination: Vector2 = target.global_position + Vector2(0.0, -34.0)
	var travel_seconds: float = clampf(bullet.global_position.distance_to(destination) / 1030.0, 0.09, 0.42)
	var shooter: Zombie000Base = _fighter # 离树后不得从攻击组件内再取本体。
	var flight: Tween = bullet.create_tween() # 沿本次锁定方向立即发射，不建立常驻查询器。
	flight.tween_property(bullet, ^"global_position", destination, travel_seconds)
	flight.tween_callback(func() -> void:
		if is_instance_valid(target) and not target.is_death and not target.is_queued_for_deletion() \
				and not target.battle_hidden_from_zombies \
				and is_instance_valid(shooter) and not shooter.is_hypno and not shooter.is_death:
			target.be_hit_from(SHOT_DAMAGE, shooter, BulletRegistry.AttackMode.Norm)
			# 落点小爆光采用同一原作弹丸素材，独立于角色死亡演出。
			var hit: Sprite2D = Sprite2D.new() # 只存活 0.14 秒。
			hit.texture = BULLET_IMAGE
			hit.scale = Vector2(0.14, 0.14)
			hit.z_index = 26
			row.add_child(hit)
			hit.global_position = destination
			var fade: Tween = hit.create_tween()
			fade.set_parallel(true)
			fade.tween_property(hit, ^"scale", Vector2(0.67, 0.67), 0.14)
			fade.tween_property(hit, ^"modulate:a", 0.0, 0.14)
			fade.chain().tween_callback(hit.queue_free)
		bullet.queue_free()
	)

## 击毁时立即伤害同行植物。爆炸特效额度和次爆时序不参与结算。
func apply_crash_damage() -> void:
	var game: MainGameManager = Global.main_game # 只结算当前战场的正式出战实例。
	if not is_instance_valid(_fighter) or _fighter.is_hypno or not is_instance_valid(game) \
			or not game.is_ancestor_of(_fighter) or game.board == null:
		return
	# 横向半径为 1.25 格，至少 85 世界像素。
	var radius: float = maxf(game.board.cell_width_at(_fighter.global_position, _fighter.lane) * 1.25, 85.0)
	for cell: PlantCell in game.board.row_cells(_fighter.lane): # 仅遍历同一战斗行的种植格。
		for plant: Plant000Base in cell.living_plants(): # 同格的各株活植物分别承伤。
			if is_instance_valid(plant) and not plant.is_death and not plant.is_queued_for_deletion() \
					and absf(plant.global_position.x - _fighter.global_position.x) <= radius:
				plant.be_zombie_eat(CRASH_DAMAGE, _fighter)

## 角色死亡和强制吹离均停止机枪计时。
func finish_life() -> void:
	set_physics_process(false)

## 机枪由物理时钟启动，跳过原生近战启动信号。
func attack_start() -> void:
	pass

## 机枪独立结束连发，跳过原生近战结束信号。
func attack_end() -> void:
	pass

## [param _speed_product] 位移由原生移动组件处理，攻击时钟自行读取 action_rate。
func owner_update_speed(_speed_product: float) -> void:
	pass
