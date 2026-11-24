## 闪电芦苇的攻击动作和表现，连锁电击读取出战卡冻结的转职技能。
extends Plant000Base

## 管理本植株的索敌、放电和折射进度。
const LightningAttack = preload("res://scripts/character/plant/lightning_reed_attack.gd")
## 出战本体与每段电弧共用的转职配色。
const PromotionArt = preload("res://scripts/adventure/plant_art/adventure_lightning_reed_promotion_art.gd")
## 从起手到下一次起手的随机间隔，单位为游戏秒。
const ATTACK_INTERVAL: Vector2 = Vector2(1.35, 1.5)
## 原版普通攻击在第 4 个 30 FPS 动画帧放电。
const RELEASE_TIME: float = 4.0 / 30.0
## 暂无目标时的重查间隔，避免空闲植株每个物理帧都扫描全场。
const TARGET_RECHECK_DELAY: float = 0.05
## 电弧贴图在特效场景缩放后的参考长度，单位为像素。
const BOLT_LENGTH: float = 104.0
## 本场战斗共享的电弧、跳转和命中表现。
const ReedEffects = preload("res://scripts/character/plant/lightning_reed_effect_pool.gd")
## 每次普通放电都会播放的基础电击层。
const FIRE_SFX = preload("res://assets/adventure/plants/lightning_reed/sfx/fire.tres")
## 原版 Plant_Level_02 的额外音色层，映射到 3～5 星。
const FIRE_TIER_02_SFX = preload("res://assets/adventure/plants/lightning_reed/sfx/fire_tier_02.tres")
## 原版 Plant_Level_03 的额外音色层，映射到 6 星及以上。
const FIRE_TIER_03_SFX = preload("res://assets/adventure/plants/lightning_reed/sfx/fire_tier_03.tres")

## 间隔还剩多少游戏秒；归零后可以立即对进入范围的目标起手。
var _cooldown: float = 0.0
## 本次攻击已经起手但尚未到达放电帧。
var _release_pending: bool = false
## 出战实例专用的电击结算对象，展示与花园实例不创建。
var _attack: LightningAttack
## 冻结出战卡的转职次数，0 为原始外观。
var _appearance_rank: int = 0
## 复用角色动画组件所控制的美术场景播放器。
@onready var _animation: AnimationPlayer = ($AnimComponent as AnimComponentPlayer).animation_player
## 电弧首段在植株上的发射点。
@onready var _bolt_origin: Marker2D = $Body/BodyCorrect/BoltOrigin
## 冻结出战卡的星级，只用来选择放电音色。
@onready var _sound_stars: int = int(plant_spawn_profile.snapshot().get("stars", 0)) if plant_spawn_profile != null else 0


## 展示与花园实例只播放待机动画，战斗实例才推进索敌和攻击计时。
func _ready() -> void:
	super()
	set_physics_process(character_init_type == E_CharacterInitType.IsNorm)
	_animation.animation_finished.connect(_on_animation_finished)
	if character_init_type != E_CharacterInitType.IsNorm:
		return
	_attack = LightningAttack.new(self, _bolt_origin)
	_attack.discharged.connect(_play_fire_sfx)
	_attack.struck.connect(_show_strike)
	if plant_spawn_profile != null:
		# 同种植物的卡片可以选不同分支，只使用本次出战冻结的数据。
		var card: PlantCardInstance = PlantCardInstance.from_dict(plant_spawn_profile.snapshot())
		_attack.configure(AdventurePromotionCatalog.effects(card).events)
		_appearance_rank = plant_spawn_profile.promotion_tier()
		if _appearance_rank > 0 and not PromotionArt.apply_to_body($Body/BodyCorrect, _appearance_rank):
			push_error("无法应用闪电芦苇的出战转职外观")


## 推进攻击间隔和放电帧；[param delta] 为当前物理帧的游戏秒数。
func _physics_process(delta: float) -> void:
	# 当前战斗提供共享索敌区域和特效容器。
	var game: MainGameManager = Global.main_game
	_attack.advance(game, delta, _animation.speed_scale)
	if not _attack.can_fight(game) or _animation.speed_scale <= 0.0:
		return
	_cooldown = maxf(0.0, _cooldown - delta * _animation.speed_scale)
	if _release_pending and _animation.current_animation_position >= RELEASE_TIME:
		_release_attack(game)
	if _cooldown > 0.0 or _animation.current_animation == &"attack":
		return
	if not _attack.has_target(game):
		_cooldown = TARGET_RECHECK_DELAY
		return
	_cooldown = randf_range(ATTACK_INTERVAL.x, ATTACK_INTERVAL.y)
	_release_pending = true
	_animation.play(&"attack")


## 在原版动作帧触发 [param game] 中的放电。同一次起手只消费一次放电标记。
func _release_attack(game: MainGameManager) -> void:
	_release_pending = false
	_attack.release(game)


## 播放本次普通放电的原版音效。以 0 星对应原版 1 级，额外音色与基础电击同时播放。
func _play_fire_sfx() -> void:
	SoundManager.play_world_sfx(FIRE_SFX, _bolt_origin)
	if _sound_stars >= 6:
		SoundManager.play_world_sfx(FIRE_TIER_03_SFX, _bolt_origin, Vector2.INF, 0.0, 1.0, &"reed_accent")
	elif _sound_stars >= 3:
		SoundManager.play_world_sfx(FIRE_TIER_02_SFX, _bolt_origin, Vector2.INF, 0.0, 1.0, &"reed_accent")


## 在 [param game] 中从 [param origin] 到 [param impact] 播放电弧，[param first_hit] 选择首段贴图。
func _show_strike(game: MainGameManager, origin: Vector2, impact: Vector2, first_hit: bool) -> void:
	var effects: ReedEffects = game.bullets.get_node_or_null(NodePath(ReedEffects.POOL_NAME)) as ReedEffects # 同场共享一个池。
	if effects == null:
		# 出战场景拥有已开始的效果，植株离场后仍可播完。
		effects = ReedEffects.new()
		effects.name = ReedEffects.POOL_NAME
		game.bullets.add_child(effects)
	var bolt: Node2D = effects.play(&"bolt_default" if first_hit else &"bolt", origin, _appearance_rank) # 首段和折射沿用各自原片段。
	var direction: Vector2 = impact - origin # 电弧沿横向伸缩，使两端对准实际起点和落点。
	bolt.global_rotation = direction.angle()
	bolt.scale.x = maxf(direction.length(), 1.0) / BOLT_LENGTH
	effects.play(&"hit", impact, _appearance_rank)


## [param anim_name] 为结束的片段，攻击完成后恢复待机。
func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"attack":
		# 加速跨过整个动画时仍只结算一次放电。
		var game: MainGameManager = Global.main_game
		if _release_pending and _attack.can_fight(game):
			_release_attack(game)
		_release_pending = false
		_animation.play(&"idle")
