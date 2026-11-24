## 仙人掌弹体保留原生碰撞和防具路由，转职只改变弹道、继续飞行资格与命中词条。
extends BulletLinear000Base
class_name BulletLinear007Cactus

## 冻结的技能位，可跨形态复用，不因母株离场失效。
enum Power { GUIDED = 1, PIERCE = 2, WOUND = 4, SHOCK = 8, FLOOD = 16, THUNDER = 32, BURST = 64, SCATTER = 128 }
## 制导每秒最大转角，使弹体逐渐转向正在移动的空中受击点。
const TURN_SPEED: float = TAU * 1.6
## 尖刺黑边轮廓，顶点以实际碰撞中心为基准。
const OUTLINE := [Vector2(-12, 0), Vector2(-6, -3.9), Vector2(3, -3.9), Vector2(12, 0), Vector2(3, 3.9), Vector2(-6, 3.9)]
## 短菱形主色边缘，保证在背景与多发之间仍能读出独立弹头。
const RIM := [Vector2(-9, 0), Vector2(0, -2.65), Vector2(10, 0), Vector2(0, 2.65)]
## 位于碰撞中心前方的亮色尖端。
const CORE := [Vector2(-3, 0), Vector2(5, -1.2), Vector2(9, 0), Vector2(3, 1.28)]
## 只有锁定空中目标的针才记录几个拖尾锚点，在已经移动的真实曲线上渐隐。
const TRACE_COLORS := [Color(0.29, 0.76, 1.0, 0.0), Color(0.29, 0.76, 1.0, 0.12),
	Color(0.29, 0.76, 1.0, 0.22), Color(0.54, 0.89, 1.0, 0.48), Color(0.77, 0.96, 1.0, 0.68)]
## 命中前的绘制颜色可由所有跟踪弹共享。
static var _trace_palette := PackedColorArray(TRACE_COLORS)

## 转职弹所使用的战场共享状态与绘制入口。
var _runtime: Node
## 发射时冻结原战局和来源。
var _shot: RepeaterShotContext
## 仅携带本轮有资格生效的词条。
var _powers: int = 0
## 亡语尖刺只能传播原栈，普通直接发射用负一作为哨兵。
var _inherited_wounds: int = -1
## 真实锁定单位与其实际碰撞点；离场或落地后沿当前方向飞行。
var _guided_target: Zombie000Base
## 缓存该锁定目标的碰撞形状，制导中不遍历受击树。
var _guided_point: Node2D
## 扇形弹先拉开弹幕轮廓再制导，单位为游戏秒。
var _steer_delay: float = 0.0
## 负面效果门面使用同一份来源参数。
var _status_context: Dictionary
## 同一个弹只在有效状态命中时才填充并复用这个回执。
var _receipt: Dictionary
## 五个弹体容器局部坐标，普通尖刺不会分配缓冲。
var _trace: PackedVector2Array = []
## 当前帧绘制用的局部副本，始终复用固定大小的缓冲。
var _trace_draw: PackedVector2Array = []
## 制导拖尾隔帧采点，只有较长的移动距离才显露。
var _trace_step: bool = false

## [param runtime] 持有战斗状态，[param shot] 保存出战，[param powers] 是词条位。
## [param target] 为空时保持直线，[param turn_delay] 延迟制导，[param inherited] 为亡语传播层数。
func configure_promotion(runtime: Node, shot: RepeaterShotContext, powers: int,
		target: Zombie000Base = null, turn_delay: float = 0.0, inherited: int = -1) -> void:
	_runtime = runtime
	_shot = shot
	_powers = powers
	_inherited_wounds = inherited
	_guided_target = target
	_steer_delay = turn_delay
	if target != null:
		var area: Area2D = target.hurt_box_component.hurt_box_real # 以空中真实受击框为追踪点。
		_guided_point = area.get_node_or_null(^"CollisionShape2D") as Node2D
		if _guided_point == null:
			_guided_point = area
	if (_powers & Power.PIERCE) != 0:
		max_attack_num = -1
		unique_target_hits = true
	if inherited >= 0:
		max_distance = 265.0
		speed *= 1.28

## 只有实战转职弹使用程序绘制，其阴影和碰撞仍是原生命中区。
func _ready() -> void:
	super()
	if can_attack_zombie_status & Zombie000Base.E_BeAttackStatusZombie.IsSky:
		bullet_shadow.position.y = 100
	if _powers != 0 or _inherited_wounds >= 0:
		$Body/BulletBody.hide()
		body.draw.connect(_draw_spike)
		body.queue_redraw()
	if _guided_point != null:
		_trace.resize(TRACE_COLORS.size())
		_trace.fill(position)
		_trace_draw.resize(TRACE_COLORS.size())

## 用 [param delta] 推进朝向，缓转制导不创建每弹 Tween 或查询全场。
func _physics_process(delta: float) -> void:
	if is_instance_valid(_guided_target) and is_instance_valid(_guided_point):
		if not _can_attack_character(_guided_target, false) or _promotion_hit_ids.has(_guided_target.get_instance_id()):
			_guided_target = null
			_guided_point = null
		else:
			_steer_delay -= delta
			if _steer_delay <= 0.0:
				var aim: Vector2 = (get_parent() as Node2D).to_local(_guided_point.global_position) - position # 对齐弹体容器空间。
				var angle: float = clampf(direction.angle_to(aim), -TURN_SPEED * delta, TURN_SPEED * delta) # 每帧限制转角。
				direction = direction.rotated(angle).normalized()
				body.rotation = direction.angle()
	super(delta)
	if not _trace.is_empty():
		if _trace_step:
			for i: int in range(_trace.size() - 1): # 移动有界轨迹样本，不创建独立发射器。
				_trace[i] = _trace[i + 1]
			_trace[-1] = position
		_trace_step = not _trace_step
		queue_redraw()

## 带二类防具的 [param enemy] 以命中前状态阻挡，击碎该防具的子弹仍停下。
func _continues_after_hit(enemy: Character000Base) -> bool:
	if (_powers & Power.PIERCE) == 0:
		return super(enemy)
	if enemy is Zombie000Base:
		return (enemy.hp_component as HpComponentZombie).curr_hp_armor2 <= 0
	return enemy != null

## [param zombie] 的二类防具不可因扇形或背向飞行绕过这一发的防具结算。
func _attack_zombie(zombie: Zombie000Base) -> void:
	if ((_powers & Power.PIERCE) != 0 or _inherited_wounds >= 0) and (zombie.hp_component as HpComponentZombie).curr_hp_armor2 > 0:
		_hit_zombie(zombie, BulletRegistry.AttackMode.Norm)
	else:
		super(zombie)

## 按 [param zombie] 的原生装备路由计算 [param mode]、[param armor] 与 [param bonus]。
## 命中后使用回执中的真实承伤者叠层，反射或转伤不让原碰撞体重复收到状态。
func _apply_zombie_impact(zombie: Zombie000Base, mode: BulletRegistry.AttackMode,
		armor: float, bonus: Vector2i) -> Zombie000Base:
	if not is_instance_valid(_runtime) or _powers == 0 and _inherited_wounds < 0:
		return super(zombie, mode, armor, bonus)
	if (_powers & (Power.WOUND | Power.SHOCK | Power.FLOOD | Power.THUNDER)) == 0 and _inherited_wounds <= 0:
		return super(zombie, mode, armor, bonus)
	var at: Vector2 = global_position # 致死同步回调可能立即移除受击对象。
	# 伤害保留原防具与代伤，随后以回执核对真正接触的角色。
	var casualty: Zombie000Base = (zombie.hp_component as HpComponentZombie).apply_hit(
		attack_value, mode, true, trigger_be_attack_sfx, true, armor, bonus.x, bonus.y, _receipt)
	var struck: Zombie000Base = _receipt.get("recipient") as Zombie000Base # 实际承伤者可能是替别人挨打的保护者。
	if not is_instance_valid(struck):
		return casualty
	if _inherited_wounds < 0 and (_powers & Power.FLOOD) != 0:
		_runtime.mark_flood(struck, _shot)
	if struck.is_death or struck.is_queued_for_deletion():
		if casualty == struck and (_powers & Power.THUNDER) != 0:
			_runtime.finish_thunder_on_lethal_hit(struck, _shot)
		_runtime.spike_hit(at, _powers, _inherited_wounds >= 0)
		return casualty
	if _status_context.is_empty():
		_status_context = {"cactus_runtime": _runtime, "shot": _shot}
	var wound: int = _inherited_wounds if _inherited_wounds >= 0 else (20 if _powers & Power.WOUND else 0) # 圈弹使用死者的精确层数。
	if wound > 0:
		AdventurePlantNegativeEffects.apply(struck, AdventurePlantNegativeEffects.Kind.CACTUS_WOUND, 0, wound, 0.0, _status_context)
	if _powers & Power.SHOCK:
		AdventurePlantNegativeEffects.apply(struck, AdventurePlantNegativeEffects.Kind.CACTUS_SHOCK, 0, 1, 0.0, _status_context)
	if _powers & Power.THUNDER:
		AdventurePlantNegativeEffects.apply(struck, AdventurePlantNegativeEffects.Kind.CACTUS_THUNDER, 0, 1, 0.0, _status_context)
	_runtime.spike_hit(at, _powers, _inherited_wounds >= 0)
	return casualty

## 颜色同时供弹体、发射和命中亮片使用。
static func primary_color(powers: int, ring: bool = false) -> Color:
	if (powers & Power.WOUND) != 0 or ring:
		return Color(0.76, 0.34, 1.0)
	if (powers & Power.SHOCK) != 0:
		return Color(0.21, 0.79, 1.0)
	return Color(0.66, 1.0, 0.36)

## 用共享形状绘制原生弹口射出的尖刺，局部轮廓随弹体平滑转向。
func _draw_spike() -> void:
	var tint: Color = primary_color(_powers, _inherited_wounds >= 0) # 三种轨迹有各自的主体颜色。
	body.draw_line(Vector2(-27, 0), Vector2(-4, 0), Color(tint, 0.28), 2.4, true)
	body.draw_colored_polygon(PackedVector2Array(OUTLINE), Color(0.13, 0.07, 0.21, 0.97))
	body.draw_colored_polygon(PackedVector2Array(RIM), tint)
	body.draw_colored_polygon(PackedVector2Array(CORE), tint.lerp(Color.WHITE, 0.77))
	if _powers & (Power.SHOCK | Power.GUIDED):
		body.draw_line(Vector2(-13, 0), Vector2(-21, -3), Color(tint, 0.63), 1.25, true)
		body.draw_line(Vector2(-15, 3), Vector2(-23, 3), Color(tint, 0.37), 1.0, true)

## 绘制受速度影响的真实制导轨迹。少于一个弹身长时先让弹口与尖刺保持清晰。
func _draw() -> void:
	if _trace.is_empty() or _trace[0].distance_squared_to(position) < 430.0:
		return
	for i: int in range(_trace_draw.size() - 1): # 头部始终对齐实际当前位置。
		_trace_draw[i] = _trace[i] - position
	_trace_draw[-1] = Vector2.ZERO
	draw_polyline_colors(_trace_draw, _trace_palette, 2.2, true)

