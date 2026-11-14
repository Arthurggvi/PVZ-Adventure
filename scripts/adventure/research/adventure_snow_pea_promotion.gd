## 在寒冰射手的原生动画射击上安装技能，暴雪连射冻结触发射击的来源。
extends Node
class_name AdventureSnowPeaPromotion

## 寒冰射手原实例；加射受其攻击和生命状态约束。
var _plant: Plant006SnowPea
## 入树前冻结的技能配置。
var _loadout: SnowPeaLoadout
## 当前战局周期已完成的原生射击次数。
var _shot_count: int = 0
## 最近一次计数的战场身份；同株跨轮或冒险阶段时从零开始。
var _count_battle: RepeaterShotContext
## 等待加射的来源，空值表示无待发弹。
var _volley: SnowPeaShot
## 距下一颗额外弹的有效战斗秒数。
var _remaining: float = 0.0
## 剩余额外弹数。
var _extra_left: int = 0

## 从 [param plant] 和已冻结的 [param events] 安装本株能力。
func configure(plant: Plant006SnowPea, events: Array[Dictionary]) -> void:
	_plant = plant
	_loadout = SnowPeaLoadout.new(events)

## 等原生组件就绪后接线，私有时钟只在加射期间工作。
func _ready() -> void:
	set_physics_process(false)
	_plant.ready.connect(_connect_attack, CONNECT_ONE_SHOT)

## 接入单株攻击信号，保留原动画发射方法。
func _connect_attack() -> void:
	_plant.attack_component.signal_bullet_instantiated.connect(_on_native_bullet)
	_plant.attack_component.signal_change_is_attack.connect(_on_attack_changed)
	_plant.signal_character_death.connect(_cancel_volley)

## [param native_bullet] 为原动画实例化的未初始化子弹；提前安装战斗门禁和书目。
func _on_native_bullet(native_bullet: Bullet000Base) -> void:
	var bullet := native_bullet as Bullet002PeaSnow # 只在原生寒冰弹上安装词条。
	if bullet == null:
		return
	var identity := RepeaterShotContext.from_plant(_plant) # 展示、失效战局或离开实际格子的来源不参与。
	if identity == null:
		# 已失效的动画方法轨不能退回无战局门禁的原版攻击。
		bullet.attack_validity = _reject_shot
		return
	var shot := SnowPeaShot.new(identity, _loadout, bullet) # 根弹与本次加射、棱锥共享来源。
	shot.arm_native(bullet)
	if _loadout.has(&"chione"):
		bullet.native_parameters_frozen.connect(_on_native_shot, CONNECT_ONE_SHOT)

## [param shot] 还原真实原生发射位置，只有一次实际射击可推进计数。
func _on_native_shot(shot: SnowPeaShot) -> void:
	if _plant.attack_component.is_attack_res:
		_count_shot(shot, shot.native_origin())

## 转职株的延迟动画在旧战斗结束后不产生有效攻击。
static func _reject_shot() -> bool:
	return false

## 每满配置次数用 [param shot] 在 [param origin] 吹起暴雪，并安排随后加射。
func _count_shot(shot: SnowPeaShot, origin: Vector2) -> void:
	if _count_battle == null or not _count_battle.is_same_battle():
		_shot_count = 0
		_count_battle = shot.battle
	_shot_count += 1
	if _shot_count < int(_loadout.number(&"chione", &"period")):
		return
	_shot_count = 0
	var game: MainGameManager = shot.battle.game # 当前正式战场。
	var lane: int = _plant.lane # 只作用于实际攻击行。
	var cells: float = _loadout.number(&"chione", &"cells") # 每个目标按当前位置的实际棋盘格距击退。
	for zombie: Zombie000Base in game.zombie_manager.all_zombies_2d[lane].duplicate(): # 原位移入口过滤载具和死亡目标。
		if is_instance_valid(zombie) and not zombie.is_hypno:
			var pitch: Vector2 = shot.battle.pitch_at(zombie.global_position, lane) # 移动平台读取当前而非发射时的尺寸。
			zombie.apply_projectile_knockback(pitch.x * cells)
	SnowPeaBlizzardVisual.spawn(shot.battle, origin, lane)
	_volley = shot
	_extra_left = int(_loadout.number(&"chione", &"shots"))
	_remaining = _loadout.number(&"chione", &"spacing")
	set_physics_process(true)

## [param delta] 为有效战斗秒；每发加射前复核攻击、母株及战场资格。
func _physics_process(delta: float) -> void:
	var attack: AttackComponentBulletBase = _plant.attack_component # 原生当前攻击许可。
	if _volley == null or _volley.battle.source_plant() == null or not attack.is_attack_res \
			or _plant.speed_factor_product() <= 0.0:
		_cancel_volley()
		return
	_remaining -= delta
	while _remaining <= 0.0 and _extra_left > 0:
		var muzzle: Marker2D = attack.markers_2d_bullet[0] # 移动棋盘上也使用当前枪口。
		_volley.emit_projectile(muzzle.global_position, attack.detect_component.ray_area_direction[0], _plant.lane)
		_extra_left -= 1
		_remaining += _loadout.number(&"chione", &"spacing")
	if _extra_left == 0:
		_cancel_volley()

## [param attacking] 为实际攻停状态；停止时同步取消尚未发射的弹。
func _on_attack_changed(attacking: bool) -> void:
	if not attacking:
		_cancel_volley()

## 回收尚未发射的加射队列，已入树的攻击继续结算。
func _cancel_volley() -> void:
	_volley = null
	_extra_left = 0
	set_physics_process(false)

## 离树时取消尚未发射的队列。
func _exit_tree() -> void:
	_cancel_volley()
