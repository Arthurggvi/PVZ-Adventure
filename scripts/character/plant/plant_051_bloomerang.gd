## 回旋镖射手。以原版动画的 use_action 帧发射，接回花瓣后才开始下一次攻击。
extends Plant000Base

## 种下后首次攻击的最短等待时间，单位为游戏秒。
const INITIAL_DELAY := 1.5
## 原版普攻冷却的随机区间，单位为游戏秒。
const ATTACK_INTERVAL := Vector2(2.85, 3.0)
## 未索敌成功时的重查间隔，避免每帧扫描检测区域。
const TARGET_RECHECK_DELAY := 0.1

## 从种植或上一轮攻击动作起算的剩余冷却。
var _cooldown := INITIAL_DELAY
## 等待收回的花瓣；回到植株或退出场景时释放。
var _in_flight: Bullet017Boomerang

## 负责同行索敌，并与投射物共用可攻击状态配置。
@onready var _detect: DetectComponent = $DetectComponent
## 原版动作播放器，随通用角色速度倍率推进。
@onready var _animation: AnimationPlayer = $AnimationPlayer
## 投射物的发射点与接回位置。
@onready var _launch: Marker2D = $Body/BodyCorrect/Launch


## 展示和花园实例只播放待机，正常出战实例才推进攻击。
func _ready() -> void:
	super()
	set_physics_process(character_init_type == E_CharacterInitType.IsNorm)
	_animation.animation_finished.connect(_on_animation_finished)


## [param delta] 为当前物理帧的游戏秒数；冷却到期且找到同行前方目标时播放投掷动作。
func _physics_process(delta: float) -> void:
	# 当前关卡负责判定战斗阶段与视野边界。
	var game: MainGameManager = Global.main_game
	if not _can_attack(game) or _animation.speed_scale <= 0.0:
		return
	_cooldown = maxf(0.0, _cooldown - delta * _animation.speed_scale)
	if _cooldown > 0.0 or is_instance_valid(_in_flight) or _animation.current_animation != &"idle":
		return
	# 取战斗视口的右缘，场外等待入场的僵尸不触发攻击。
	var right_edge: float = _battle_edges().y
	for target: Character000Base in _detect.get_all_enemy_can_be_attacked(): # 同行受击目标，含墓碑。
		if not target.is_hypno and target.global_position.x >= global_position.x \
				and target.global_position.x <= right_edge:
			_cooldown = randf_range(ATTACK_INTERVAL.x, ATTACK_INTERVAL.y)
			_animation.play(&"attack")
			return
	_cooldown = TARGET_RECHECK_DELAY


## 判断 [param game] 是否仍为本株所在的出战关卡，避免展示和结算期间发射。
func _can_attack(game: MainGameManager) -> bool:
	return not is_death and not is_queued_for_deletion() and is_instance_valid(game) \
		and game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and game.is_ancestor_of(self)


## 返回战斗视口的左、右边缘，使用世界坐标以适应不同场地的镜头偏移。
func _battle_edges() -> Vector2:
	# 把视口两端从屏幕像素换算到战场坐标。
	var world_from_screen: Transform2D = get_canvas_transform().affine_inverse()
	var viewport_rect: Rect2 = get_viewport_rect() # 当前战斗视口在屏幕坐标中的范围。
	return Vector2((world_from_screen * viewport_rect.position).x,
		(world_from_screen * viewport_rect.end).x)


## 原版投掷动作的 use_action 方法轨，生成一枚继承本次出战伤害倍率的回旋镖。
func _release_boomerang() -> void:
	# 子弹留在关卡容器中，植株消失后仍可结束本次飞行。
	var game: MainGameManager = Global.main_game
	if not _can_attack(game) or is_instance_valid(_in_flight):
		return
	# 由注册表加载独立子弹，并沿用同一套阵营、行号和伤害参数。
	var bullet: Bullet017Boomerang = Global.bullet_registry.get_bullet_scenes(
		BulletRegistry.BulletType.Bullet017Boomerang).instantiate()
	bullet.init_bullet({
		Bullet000NormBase.E_InitParasAttr.BulletLane: lane,
		Bullet000NormBase.E_InitParasAttr.Position: game.bullets.to_local(_launch.global_position),
		Bullet000NormBase.E_InitParasAttr.CanAttackZombieState: _detect.can_attack_zombie_status,
		Bullet000NormBase.E_InitParasAttr.DamageMultiplier: battle_damage_multiplier,
	})
	bullet.configure_flight(self, _battle_edges(), game.main_game_slope)
	bullet.returned.connect(_on_boomerang_returned)
	_in_flight = bullet
	game.bullets.add_child(bullet)
	SoundManager.play_character_SFX(&"Throw")


## 接住花瓣时播放原版 attack_02 动作。
func _on_boomerang_returned() -> void:
	if _can_attack(Global.main_game):
		_animation.play(&"catch")


## [param animation_name] 为结束的动作；投掷和接回动作结束后恢复待机。
func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"attack" or animation_name == &"catch":
		_animation.play(&"idle")
