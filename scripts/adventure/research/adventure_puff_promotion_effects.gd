## 小喷菇转职的单株射击与亡语控制器；所有弹体独立保存冻结规则和来源。
extends Node
class_name AdventurePuffPromotionEffects

## 继承原版孢子场景；只保存路径，避免注册表加载基础孢子时循环预加载其派生场景。
const PUFF_SCENE_PATH: String = "res://scenes/bullet/bullet_003_puff_adventure.tscn"
## 战斗初始化后取得的派生场景，资源缓存由 Godot 统一持有。
var _puff_scene: PackedScene
## 全行检测按战斗时间每零点二秒刷新，闲置时也跟随移动平台。
const RANGE_REFRESH_SECONDS: float = 0.2
## 当前植物；仅在发射或同步死亡回调期间读取。
var _plant: Plant000Base
## 当前战场，防止退场后仍生成弹体。
var _game: MainGameManager
## 原生攻击组件，继续负责检测、动画、攻速和音效。
var _attack: AttackComponentBulletBase
## 不可变的来源种植配方；弹体持有该引用，不依赖母株存活。
var _profile: PlantSpawnProfile
## 本株已经选择的转职事件，不查询可变背包。
var _rules: Dictionary = {}
## 独占的全行检测形状，避免修改其他小喷菇共享的资源。
var _range_shape: RectangleShape2D
## 原场景检测宽度的冻结下限；平台回移时允许扩展部分收缩。
var _native_range_width: float = 0.0
## 全行检测的碰撞节点，用于移动独占矩形中心。
var _range_collision: CollisionShape2D
## 当前棋盘和出生点决定的世界坐标右界。
var _right_limit: float = 0.0
## 亡语已执行标志，阻止死亡回调重入。
var _burst_fired: bool = false

## [param plant] 是本株小喷菇；[param events] 是已验证的转职事件。
## 在入树前调用；复制规则，实际组件绑定等植物完成就绪。
func configure(plant: Plant000Base, events: Array[Dictionary]) -> void:
	_plant = plant
	for event: Dictionary in events: # 只保留本物种事件，阻止借用其他植物的能力。
		var kind: String = str(event.get("kind", "")) # 权威目录中的事件身份。
		if kind.begins_with("puff_"):
			_rules[kind] = event.duplicate(true)

## 子节点先于植物就绪，等根节点完成初始化再接管攻击。
func _ready() -> void:
	if not is_instance_valid(_plant):
		queue_free()
	elif _plant.is_node_ready():
		_bind()
	else:
		_plant.ready.connect(_bind, CONNECT_ONE_SHOT)

## 仅绑定本株一次；保留原生攻击组件的睡眠、目标和攻速门禁。
func _bind() -> void:
	_game = Global.main_game
	_attack = _plant.get_node_or_null("AttackComponent") as AttackComponentBulletBase
	_profile = _plant.plant_spawn_profile
	if not is_instance_valid(_game) or not is_instance_valid(_attack):
		return
	_puff_scene = load(PUFF_SCENE_PATH) as PackedScene
	if _puff_scene == null:
		push_error("小喷菇转职弹体场景无法加载")
		return
	if _attack.shoot_override.is_valid():
		push_error("小喷菇转职需要空闲的原生射击入口")
		return
	_attack.shoot_override = _shoot
	if _rules.has("puff_death_burst"):
		_plant.signal_character_death.connect(_on_death, CONNECT_ONE_SHOT)
	if _rules.has("puff_full_row"):
		_range_collision = _attack.detect_component.get_node_or_null("Area2D/CollisionShape2D") as CollisionShape2D
		if _range_collision != null and _range_collision.shape is RectangleShape2D:
			_range_shape = _range_collision.shape.duplicate() as RectangleShape2D
			_native_range_width = _range_shape.size.x
			_range_collision.shape = _range_shape
		_refresh_full_row()
		var refresh: Timer = Timer.new() # 只有全行转职创建计时器，继承战场暂停和时间倍率。
		refresh.wait_time = RANGE_REFRESH_SECONDS
		refresh.timeout.connect(_refresh_range_if_active)
		add_child(refresh)
		refresh.start()

## 即使没有目标也更新全行几何；结算、退场和死亡期间不改检测范围。
func _refresh_range_if_active() -> void:
	if _battle_active() and is_instance_valid(_plant) and not _plant.is_death \
			and not _plant.is_queued_for_deletion():
		_refresh_full_row()

## 返回当前真实列间距；孤立地块回退自身世界宽度，不写死地图格宽。
func _cell_pitch() -> float:
	if not is_instance_valid(_plant.plant_cell):
		return 1.0
	if _game.board != null:
		return maxf(1.0, _game.board.local_pitch(_plant.plant_cell).x)
	return maxf(1.0, _plant.plant_cell.get_global_rect().size.x)

## 按实际同行地块和僵尸出生点扩展前方射程；每轮射击重读平台位置。
func _refresh_full_row() -> void:
	if not _rules.has("puff_full_row") or _game.board == null:
		return
	var bounds: Rect2 = BoardQueries.bounds(_game.board.row_cells(_plant.lane)) # 同行地块的世界边界。
	_right_limit = bounds.end.x
	if _plant.lane >= 0 and _plant.lane < _game.board.lanes.size():
		_right_limit = maxf(_right_limit, _game.to_global(_game.board.lanes[_plant.lane].spawn_position).x)
	_right_limit += _cell_pitch()
	if _range_shape == null:
		return
	var area: Node2D = _range_collision.get_parent() as Node2D # 检测区域的局部坐标基准。
	var reach: float = maxf(_native_range_width, area.to_local(Vector2(_right_limit, area.global_position.y)).x) # 前方长度。
	_range_shape.set_deferred("size", Vector2(reach, _range_shape.size.y))
	_range_collision.set_deferred("position", Vector2(reach * 0.5, _range_collision.position.y))
	_attack.detect_component.need_judge = true

## 只在正式战斗和有效弹体容器内允许发射，结束场景不生成残留对象。
func _battle_active() -> bool:
	return is_instance_valid(_game) and _game.is_inside_tree() and not _game.is_queued_for_deletion() \
		and _game == Global.main_game and _game.get_tree().current_scene == _game \
		and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false) \
		and is_instance_valid(_game.bullets) and not _game.bullets.is_queued_for_deletion()

## 原版动画每请求一次就发射一轮；孢涌总扇角为十八度，保留普通射击同行限制。
func _shoot() -> void:
	if not _battle_active() or not is_instance_valid(_plant) or _plant.is_death \
			or _plant.is_queued_for_deletion() or not _attack.is_attack_res:
		return
	_refresh_full_row()
	var rule: Dictionary = _rules.get("puff_shotgun", {}) # 无孢涌时保留单发。
	var count: int = randi_range(int(rule.get("count_min", 1)), int(rule.get("count_max", 1))) # 本轮弹数。
	var spread: float = deg_to_rad(float(rule.get("spread_degrees", 18.0))) # 总扇角，左右各一半。
	_attack.signal_shoot_bullet.emit()
	for index: int in range(_attack.markers_2d_bullet.size()): # 小喷菇原场景只有一个枪口。
		var marker: Marker2D = _attack.markers_2d_bullet[index] # 发射时的真实枪口。
		if not is_instance_valid(marker):
			continue
		var forward: Vector2 = _attack.detect_component.ray_area_direction[index].normalized() # 原生方向。
		for pellet: int in range(count): # 每颗孢子独立命中和抽取负面效果。
			var angle: float = lerpf(-spread * 0.5, spread * 0.5, float(pellet) / float(count - 1)) if count > 1 else 0.0 # 均匀散射。
			_fire_bullet(marker.global_position, forward.rotated(angle), false)
	_attack.play_throw_sfx()

## 同步冻结亡语参数；即便铲除或母株随后释放，独立弹体仍保留转职。
func _on_death() -> void:
	if _burst_fired:
		return
	_burst_fired = true
	if not _battle_active() or not is_instance_valid(_plant):
		return
	_refresh_full_row()
	var rule: Dictionary = _rules["puff_death_burst"] # 亡语固定生成八至十二颗，不被孢涌再次倍增。
	var count: int = randi_range(int(rule.get("count_min", 8)), int(rule.get("count_max", 12))) # 本次亡语弹数。
	var origin: Vector2 = _plant.global_position # 无枪口时回退死亡位置。
	if not _attack.markers_2d_bullet.is_empty() and is_instance_valid(_attack.markers_2d_bullet[0]):
		origin = _attack.markers_2d_bullet[0].global_position
	var phase: float = randf() * TAU # 随机整体旋转，保持完整圆周的均匀分布。
	for index: int in range(count): # 径向弹跨行，以实际碰撞决定目标。
		_fire_bullet(origin, Vector2.RIGHT.rotated(phase + TAU * float(index) / float(count)), true)
	_attack.play_throw_sfx()

## 从 [param origin] 向单位 [param direction] 发射；[param radial] 允许跨行并延迟入树。
## 亡语可能来自物理回调，弹体先保存参数再交由战场入树，避免跟随母株释放。
func _fire_bullet(origin: Vector2, direction: Vector2, radial: bool) -> void:
	var bullet: Node = _puff_scene.instantiate() # 派生脚本随其场景加载，避免反向静态依赖基础弹体。
	if not is_instance_valid(bullet) or not bullet.has_method(&"attach_to_battle"):
		if is_instance_valid(bullet):
			bullet.free()
		push_error("小喷菇转职弹体场景类型不兼容")
		return
	var parameters: Dictionary = _attack.get_bullet_paras(origin, direction.normalized()) # 含发射时伤害倍率。
	if radial:
		parameters[Bullet000NormBase.E_InitParasAttr.IsActivateLane] = false
	if _rules.has("puff_full_row"):
		bullet.max_distance = maxf(bullet.max_distance, _right_limit - origin.x)
	bullet.configure(_game, _profile, _rules, origin, _cell_pitch(), _plant.get_instance_id())
	_attack.signal_bullet_instantiated.emit(bullet)
	bullet.init_bullet(parameters)
	if radial:
		bullet.attach_to_battle.call_deferred()
	else:
		bullet.attach_to_battle()
