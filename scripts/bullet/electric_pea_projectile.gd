## 原版电能豌豆电球：持续向前穿透，独立按半秒节奏向附近随机敌人放电。
extends Node2D
class_name ElectricPeaProjectile

## 原版电球动画，三种普通变体都来自 ElectricPeaDefault 的 AttachedPAMAnimationToPlay。
const EFFECTS: PackedScene = preload("res://scenes/character/plant/electric_peashooter_effects.tscn")
## 原版专属 electroball_effects 电弧与资源组显式依赖的 PlantLightningReedHit 命中独立打包。
const BOLT_EFFECTS: PackedScene = preload("res://scenes/character/plant/electric_peashooter_bolt.tscn")
## 与本株冻结等阶对应的共享电系换色接口。
const PromotionArt = preload("res://scripts/adventure/plant_art/adventure_electric_peashooter_promotion_art.gd")
## 原版一级 ActionXVelocity 覆盖弹体模板速度，单位为世界像素每秒。
const SPEED: float = 180.0
## 原版 BoltFrequency，两次邻近放电之间的游戏秒数。
const BOLT_INTERVAL: float = 0.5
## 原版 BoltRange，以六十四像素格宽为一格；本项目按实际地格宽缩放。
const BOLT_RANGE_CELLS: float = 2.0
## 原版 BoltCount，每次最多击中两个不同目标。
const BOLT_COUNT: int = 2
## 原版程序传给单段电弧的持续秒数。
const BOLT_DURATION: float = 0.15
## 已转换原版电弧的参考长度，单位为世界像素。
const BOLT_LENGTH: float = 91.0
## 三种普通球的原版循环片段名。
const PROJECTILE_CLIPS: Array[StringName] = [&"projectile", &"projectile2", &"projectile3"]
## 原版 Bolt_Fire 声音池三选一；多条电弧在同一轮放电中共用一次提示音。
const BOLT_SOUND: AudioStream = preload("res://assets/adventure/plants/electric_peashooter/audio/bolt_fire.tres")

## 本枚电球的冻结战局、伤害和等阶；必须在入树前配置。
var shot: ElectricPeaShotContext
## 原始飞行坡面，母株移除不改变已经离手的轨迹。
var _slope: MainGameSlope
## 扣除坡面高度后的固定离地高度。
var _level_y: float = 0.0
## 距下次放电的游戏秒数；首轮采用原版随机相位。
var _bolt_remaining: float = 0.0
## 按目标身份记录穿透直击；与每轮重新建立的电击候选完全独立。
var _contact_ids: Dictionary[int, bool] = {}
## 每枚电球独享的连续碰撞查询器。
var _query := ElectricPeaFlightQuery.new()
## 生存秒数用于限制永久追随弹体的镜头造成的泄漏。
var _elapsed: float = 0.0
## 发射时由可见宽度确定的寿命上界。
var _lifetime: float = 0.0


## 入树后只建立本枚电球的表现及计时；没有有效发射快照时直接释放。
func _ready() -> void:
	if shot == null or not shot.is_active():
		queue_free()
		return
	z_index = shot.lane * 50 + 45
	_slope = shot.game.main_game_slope
	_level_y = global_position.y - ElectricPeaFlightQuery.height_at(_slope, global_position.x)
	_bolt_remaining = randf_range(0.0, BOLT_INTERVAL)
	_lifetime = maxf(8.0, _screen_rect().size.x * 2.0 / SPEED)
	var visual: Node2D = EFFECTS.instantiate() as Node2D # 电球美术随逻辑根节点移动。
	add_child(visual)
	PromotionArt.apply_to_effect(visual, shot.appearance_rank)
	var player: AnimationPlayer = visual.get_node(^"AnimationPlayer") as AnimationPlayer # 只播放普通电球，不触发保留的能量豆资源。
	player.play(PROJECTILE_CLIPS.pick_random())


## [param delta] 是已经包含引擎速度的物理秒数；母株冻结不会冻结已经飞出的电球。
func _physics_process(delta: float) -> void:
	if shot == null or not shot.is_active():
		queue_free()
		return
	if get_tree().paused:
		return
	if not is_instance_valid(_slope):
		_slope = null
	_elapsed += maxf(0.0, delta)
	if _elapsed >= _lifetime:
		queue_free()
		return
	var finish_x: float = global_position.x + SPEED * maxf(0.0, delta) # 本帧前进的真实世界位置。
	var finish := Vector2(finish_x, _level_y + ElectricPeaFlightQuery.height_at(_slope, finish_x)) # 保留屋顶离地高度。
	var candidates: Array[Character000Base] = ElectricPeaFlightQuery.all_targets(shot.game) # 原始重叠候选保留跳跃中的敌人。
	var points: Array[Vector2] = ElectricPeaFlightQuery.path_points(global_position, finish, _slope, _level_y) # 低帧率跨坡分段。
	for index: int in range(1, points.size()): # 连续碰撞不依赖 Area2D 的离散进入事件。
		_move_segment(points[index], candidates)
		if not shot.is_active() or is_queued_for_deletion():
			queue_free()
			return
	_bolt_remaining -= maxf(0.0, delta)
	if _bolt_remaining <= 0.0:
		_discharge()
		# 与原版更新循环一样每帧最多放电一轮，不追赶卡顿期间的历史攻击。
		_bolt_remaining = BOLT_INTERVAL
	if not _screen_rect().grow(ElectricPeaFlightQuery.HALF_SIZE).has_point(global_position):
		queue_free()


## 沿当前位置至 [param finish] 的真实线段处理 [param candidates]；普通直击每目标仅一次。
func _move_segment(finish: Vector2, candidates: Array[Character000Base]) -> void:
	var start: Vector2 = global_position # 命中回调不能改变本段查询起点。
	var contacts: Array[Dictionary] = [] # 按首次接触比例排序，避免树顺序决定致死与掉落顺序。
	for reference: Variant in candidates: # 前一坡段命中可能已经释放此段候选。
		if not is_instance_valid(reference):
			continue
		var target: Character000Base = reference # 全局候选没有物理查询数量上限。
		if not ElectricPeaFlightQuery.can_hit(target) or _contact_ids.has(target.get_instance_id()) \
				or (not target is ZB000Base and target.lane != shot.lane):
			continue
		var fraction: float = _query.contact_fraction(target.hurt_box_component.hurt_box_real, start, finish) # 包含出生重叠。
		if is_finite(fraction):
			contacts.append({"target": target, "fraction": fraction})
	contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.fraction) < float(b.fraction))
	for contact: Dictionary in contacts: # 前一次受击可能同步结束战局或释放后续目标。
		if not shot.is_active():
			return
		var reference: Variant = contact.target # 先检查弱化后的变体，避免已释放对象转为强类型报错。
		if not is_instance_valid(reference):
			continue
		var target: Character000Base = reference # 重新确认魅惑、死亡与受击状态。
		if not ElectricPeaFlightQuery.can_hit(target) or _contact_ids.has(target.get_instance_id()):
			continue
		_contact_ids[target.get_instance_id()] = true
		global_position = start.lerp(finish, float(contact.fraction))
		shot.hit(target, shot.contact_damage)
	global_position = finish


## 每次重新随机排列合法僵尸；名额不足才以设施补位，同一目标可在下一轮再次被电击。
func _discharge() -> void:
	if not shot.is_active():
		return
	var zombies: Array[Character000Base] = [] # 原版 query type 2 优先。
	var structures: Array[Character000Base] = [] # 原版 query type 4 仅用于补齐剩余名额。
	var radius_squared: float = pow(BOLT_RANGE_CELLS * shot.cell_pitch.x, 2.0) # 原版128像素半径按64像素格宽移植。
	for target: Character000Base in ElectricPeaFlightQuery.all_targets(shot.game): # 本轮独立候选，不复用直击账本。
		if not ElectricPeaFlightQuery.can_hit(target) \
				or (not target is ZB000Base and absi(target.lane - shot.lane) > 1):
			continue
		var impact: Vector2 = ElectricPeaFlightQuery.target_position(target) # 电弧与距离查询使用真实受击位置。
		if global_position.distance_squared_to(impact) > radius_squared:
			continue
		if target is EnemyStructureBase:
			structures.append(target)
		else:
			zombies.append(target)
	zombies.shuffle()
	structures.shuffle()
	zombies.append_array(structures)
	var strikes: int = 0 # 同一轮最多消费两个不同目标。
	for reference: Variant in zombies: # 致死触发可能改变仍未结算的对象。
		if strikes >= BOLT_COUNT or not shot.is_active():
			break
		if not is_instance_valid(reference):
			continue
		var target: Character000Base = reference # 放电前重查受击资格。
		if not ElectricPeaFlightQuery.can_hit(target):
			continue
		var impact: Vector2 = ElectricPeaFlightQuery.target_position(target) # 目标死亡前保存电弧终点。
		if strikes == 0:
			# 首道电弧播放轻量提示音，相近的放电由音效池合并，避免长采样叠响。
			SoundManager.play_sfx_with_pool(BOLT_SOUND, -18.0)
		strikes += 1
		_show_bolt(impact)
		shot.hit(target, shot.bolt_damage)


## 从本枚电球到 [param impact] 播放原版共享电弧和命中，已产生特效不依赖弹体存活。
func _show_bolt(impact: Vector2) -> void:
	var bolt: Node2D = _spawn_effect(&"bolt", global_position) # 电球发出的弧使用普通分段贴图。
	var direction: Vector2 = impact - global_position # 电弧两端严格对齐实际位置。
	bolt.global_rotation = direction.angle()
	bolt.scale.x = maxf(1.0, direction.length()) / BOLT_LENGTH
	_spawn_effect(&"hit", impact)


## 在原战场播放 [param clip] 于 [param at]；动画结束时释放并返回独立效果根节点。
func _spawn_effect(clip: StringName, at: Vector2) -> Node2D:
	var effect: Node2D = BOLT_EFFECTS.instantiate() as Node2D # 原资源自带Rig，保持全等阶换色契约。
	PromotionArt.apply_to_effect(effect, shot.appearance_rank)
	shot.game.bullets.add_child(effect)
	effect.global_position = at
	effect.z_index = 350
	var player: AnimationPlayer = effect.get_node(^"AnimationPlayer") as AnimationPlayer # 电弧与命中各自管理生命周期。
	player.animation_finished.connect(func(_clip: StringName) -> void: effect.queue_free(), CONNECT_ONE_SHOT)
	var rate: float = player.get_animation(clip).length / BOLT_DURATION if clip == &"bolt" else 1.0 # 原版弧持续0.15秒。
	player.play(clip, -1.0, rate)
	return effect


## 返回当前镜头的世界可见矩形，跟随平移与缩放而不使用固定屏幕宽度。
func _screen_rect() -> Rect2:
	return get_canvas_transform().affine_inverse() * get_viewport_rect()
