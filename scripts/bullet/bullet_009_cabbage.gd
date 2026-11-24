## 卷心菜特殊弹保留原生抛物线、碰撞和普弹，独立冻结一次落点。
extends Bullet000ParabolaBase

## 特殊颜色和命中归同一战场处理。
const Landing = preload("res://scripts/adventure/research/cabbage_landing.gd")
## 原生卷心菜精灵，不修改已有贴图。
@onready var _sprite: Sprite2D = $Body/BulletBody
## 无转职时保持原生逻辑，发射时不建立新的战场状态。
var _runtime: Node2D
## 原来的轮次和攻击上下文。
var _shot: RepeaterShotContext
## 实际投出的组合弹种。
var payload: int = 0
## 只有强化的特殊弹携带溅射。
var has_splash: bool = false
## 当前弧线目标的上一有效地面锚点。
var _foot: Vector2
## 受到卡牌和三倍基础修饰后的伤害，尚未应用单个目标的修正。
var _base_damage: int
## 落点进入共享队列后立即结束物理弹。
var _submitted: bool = false

## 入树前冻结 [param runtime]、[param shot]、[param flags]、[param boosted] 及 [param foot]。
## 200%先乘基础伤害再由原生初始化应用卡牌倍率。
func configure(runtime: Node2D, shot: RepeaterShotContext, flags: int, boosted: bool, foot: Vector2) -> void:
	_runtime = runtime
	_shot = shot
	payload = flags
	_foot = foot
	has_splash = boosted and payload != 0
	if has_splash:
		attack_value *= 3
	is_rotate = false

## 特殊弹使用原生叶片精灵着色和同色轮廓，保留真实受击半径。
func _ready() -> void:
	super()
	if _runtime == null:
		return
	_base_damage = attack_value
	if payload == 0:
		return
	bullet_effect.is_bullet_effect = false
	trigger_be_attack_sfx = false
	if payload & Landing.Payload.BLACK:
		type_bullet_SFX = SoundManagerClass.TypeBulletSFX.Null
		_sprite.modulate = Color(0.19, 0.16, 0.24)
	elif payload & Landing.Payload.HELL:
		_sprite.modulate = Color(1.78, 0.35, 0.26)
	elif payload & Landing.Payload.GOLD:
		_sprite.modulate = Color(1.78, 1.17, 0.23)
	if payload & Landing.Payload.HOMERUN:
		_sprite.scale *= 1.73
	body.draw.connect(_draw_charge)
	body.queue_redraw()

## [param delta] 推进原抛物线并保留最近一次实际脚点，旧阶段的弹直接回收。
func _physics_process(delta: float) -> void:
	if _runtime != null:
		if not is_attack_active():
			queue_free()
			return
		if is_instance_valid(target_enemy):
			if not Landing.can_hit(target_enemy, can_attack_zombie_status):
				target_enemy = null
			elif movement_component.curr_diff_x < movement_component.max_diff_x:
				if target_enemy.lane >= 0 and target_enemy.lane != lane:
					lane = target_enemy.lane
					global_pos_y_shadow = _shot.game.zombie_manager.all_zombie_rows[lane].zombie_create_position.global_position.y
				if target_enemy is Zombie000Base:
					_foot = target_enemy.global_position
		body.rotation += delta * (4.4 if payload & Landing.Payload.HOMERUN else 6.28)
	super(delta)

## 地表随 [param displacement] 移动时，死目标的最后脚点也与原弧线同步平移。
func translate_with_board(displacement: Vector2) -> void:
	super(displacement)
	_foot += displacement

## [param enemy] 仍须通过原生护框和 [param check_lane]；已魅惑的敌人不能提前消耗特殊弹。
func _can_attack_character(enemy: Character000Base, check_lane: bool = true) -> bool:
	return super(enemy, check_lane) and (_runtime == null or Landing.can_hit(enemy, can_attack_zombie_status))

## 原生结算把 [param enemy] 作为实际碰撞对象，落空时由原生弧线终点确定地面位置。
func _attack_enemy(enemy: Character000Base) -> void:
	if _runtime == null or payload == 0:
		super(enemy)
		return
	if _submitted:
		return
	_submitted = true
	var impact := Landing.Impact.new() # 队列只接收独立落点数据，不延长弹体生命周期。
	impact.shot = _shot
	impact.direct = enemy
	impact.row = enemy.lane if is_instance_valid(enemy) and enemy.lane >= 0 else lane
	if is_instance_valid(enemy):
		impact.foot = Landing.foot_at(_shot, enemy, global_position.x, impact.row)
	else:
		impact.foot = Vector2(movement_component.end_global_pos.x, _foot.y)
	impact.flags = payload
	impact.base_damage = _base_damage
	impact.splash = has_splash
	impact.statuses = can_attack_zombie_status
	_runtime.submit(impact)

## 原生叶片外的同色辉光，金红同时命中时各保留内外层颜色。
func _draw_charge() -> void:
	var tint: Color = Landing.tint_for(payload) # 避免黑菜从夜间背景中消失。
	var radius: float = 29.0 if payload & Landing.Payload.HOMERUN else 16.0 # 巨菜有更厚外轮廓。
	body.draw_circle(Vector2.ZERO, radius * 1.34, Color(tint, 0.16), true, -1, true)
	body.draw_circle(Vector2.ZERO, radius, Color(tint, 0.74), false, 2.5, true)
	if payload & Landing.Payload.GOLD:
		body.draw_arc(Vector2.ZERO, radius + 3.5, -2.56, -0.62, 13, Color(1.0, 0.82, 0.36, 0.85), 2.8, true)
	if payload & Landing.Payload.HELL:
		body.draw_arc(Vector2.ZERO, radius + 4.0, 0.48, 2.26, 13, Color(1.0, 0.28, 0.1, 0.88), 2.8, true)
	if has_splash:
		body.draw_arc(Vector2.ZERO, radius + 8.0, 1.75, 4.88, 17, Color(1.0, 0.96, 0.66, 0.82), 2.6, true)
