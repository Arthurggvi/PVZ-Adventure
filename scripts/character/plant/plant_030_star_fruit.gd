## 杨桃保留原生五个弹口和攻击动画，转职齐射只挂在原生攻击回调。
extends Plant000Base
class_name Plant030StarFruit

## 发射、持续接触和派生星弹共用战场运行时。
const StarRuntime = preload("res://scripts/adventure/research/starfruit_battle_runtime.gd")
## 未转职的星弹也提交到同一个共享画布。
const StarVisual = preload("res://scripts/adventure/research/starfruit_visual.gd")
## 原生五路弹口及攻击节奏。
@onready var attack_component: AttackComponentBulletBase = $AttackComponent
## 卡牌冻结的普通星弹词条，随实际出手传播。
var _traits: int = 0
## 恒星开启五个间隙方向。
var _stellar: bool = false
## 彗星在原本五个方向释放蓝星。
var _comet: bool = false
## 明星只由第三次原生齐射触发。
var _celebrity: bool = false
## 只记录原生攻击次数，子弹与亡语都不会更新。
var _volley_count: int = 0

## [param events] 是出战卡冻结的杨桃转职事件，尚未入树即可应用。
func configure_promotions(events: Array[Dictionary]) -> void:
	for effect: Dictionary in events: # 每阶为卡牌已校验的单选技能。
		match String(effect.get("kind", "")):
			"starfruit_lurk": battle_hidden_from_zombies = true
			"starfruit_aim": _traits |= Bullet008Star.Trait.AIM
			"starfruit_stellar": _stellar = true
			"starfruit_pierce": _traits |= Bullet008Star.Trait.PIERCE
			"starfruit_comet": _comet = true
			"starfruit_refract": _traits |= Bullet008Star.Trait.REFRACT
			"starfruit_celebrity": _celebrity = true
			"starfruit_stream": _traits |= Bullet008Star.Trait.STREAM

## 正常入场时接管同一个动画发射信号，并为蛰伏提供辨识。
func ready_norm_signal_connect() -> void:
	super()
	signal_update_speed.connect(attack_component.owner_update_speed)
	if battle_hidden_from_zombies:
		body.set_other_color(BodyCharacter.E_ChangeColors.StarFruitLurk, Color(0.62, 0.92, 0.84, 0.57))
	if _traits != 0 or _stellar or _comet or _celebrity:
		attack_component.shoot_override = _release_volley
	else:
		attack_component.signal_bullet_instantiated.connect(_prepare_native_star)

## 仅为本株原生发射的 [param bullet] 启用星弹退场，其他物种复用弹体时保持自己的演出。
func _prepare_native_star(bullet: Bullet000Base) -> void:
	if bullet is Bullet008Star and is_instance_valid(attack_component.bullets):
		bullet.enable_native_exit(StarVisual.for_bullets(attack_component.bullets))

## 冻结本轮攻击。紫星夹在相邻弹道中间，蓝星与普通星共用原方向。
func _release_volley() -> void:
	var shot: RepeaterShotContext = RepeaterShotContext.from_plant(self) # 所有派生子弹保留本轮战斗归属。
	if shot == null:
		return
	var runtime := StarRuntime.for_battle(shot.game) # 只有实际出手才实例化。
	attack_component.signal_shoot_bullet.emit()
	attack_component.play_throw_sfx()
	var mouths: Array[Marker2D] = attack_component.markers_2d_bullet # 五个标记按原生圆周顺序配置。
	var rays: Array[Vector2] = attack_component.detect_component.ray_area_direction # 冻结这一轮方向。
	for index: int in range(mouths.size()): # 同一物理步内发完普通星和额外星。
		var origin: Vector2 = mouths[index].global_position # 实际动画弹口。
		var ray: Vector2 = rays[index] # 普通星方向。
		runtime.launch(shot, origin, ray, _traits, Bullet008Star.Kind.GOLD, attack_component)
		if _stellar:
			var next: int = (index + 1) % mouths.size() # 最后一个间隙和第一个方向闭合。
			var between: Vector2 = (ray + rays[next]).normalized() # 相邻短弧的角平分向量。
			var midpoint: Vector2 = origin.lerp(mouths[next].global_position, 0.5) # 紫星从相邻弹口间出射。
			runtime.launch(shot, midpoint + between * 5.0, between, _traits, Bullet008Star.Kind.VIOLET, attack_component)
		if _comet:
			runtime.launch(shot, origin + ray * 10.0, ray, _traits, Bullet008Star.Kind.BLUE, attack_component)
	if _celebrity:
		_volley_count += 1
		if _volley_count == 3:
			_volley_count = 0
			runtime.cast_meteor(shot, _traits)
