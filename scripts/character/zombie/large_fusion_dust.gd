## 融合体的短命脚点尘：固定在发生位置，只绘制接触、落地、出生及死亡的余尘。
class_name LargeFusionDust
extends Node2D

## 复用石像的低顶点椭圆画法，不载入石像贴图或碎块。
const GroundShapes: Script = preload("res://scripts/character/zombie/stone_statue/stone_statue_effects.gd")
## 尘土颜色压在草坪与融合体之间，不增加白光或血色。
const DUST: Color = Color(0.59, 0.57, 0.48)
## 脚点压痕接近原版阴影的深灰绿色。
const EARTH: Color = Color(0.20, 0.22, 0.16)
## 出生与死亡时混入少量融合体衣物的灰紫色。
const ASH: Color = Color(0.38, 0.32, 0.37)
## 表现种类只调整尘量和时长，不产生伤害或生成角色。
enum Kind { TRAIL, IMPACT, LANDING, BIRTH, DEATH }

## 此次尘土的固定世界脚点，与随后移动的融合体分离。
var _anchor: Vector2 = Vector2.ZERO
## 此次表现类型。
var _kind: Kind = Kind.LANDING
## 尘土的大小与浓度倍率，限制极端输入。
var _strength: float = 1.0
## 已播放的战斗秒数，继承场景暂停。
var _age: float = 0.0
## 当前类型的总持续秒数。
var _lifetime: float = 0.62
## 仅由位置计算的散布相位，不消耗战斗随机流。
var _phase: float = 0.0
## 尘土所属战场，续战复用父层时也不能残留到下一阶段。
var _battle_game: MainGameManager
## 创建尘土时的轮次。
var _battle_round: int = -1
## 创建尘土时的阶段身份，普通胜利尾帧仍允许自然散去。
var _battle_phase: StagePhaseDefinition

## 在 [param host] 的绘制层创建余尘；传入稳定的行或战场节点，避免随母体提前删除。
## [param world_position] 是发生时的世界脚点；[param strength] 和 [param kind] 仅控制表现。
static func emit_ground(host: Node2D, world_position: Vector2,
		strength: float = 1.0, kind: Kind = Kind.LANDING) -> LargeFusionDust:
	if not is_instance_valid(host) or not host.is_inside_tree() or host.is_queued_for_deletion():
		return null
	var dust: LargeFusionDust = LargeFusionDust.new() # 每次事件独立计时，旧尘不会跟随新脚点。
	host.add_child(dust)
	dust.burst(world_position, strength, kind)
	return dust

## 滚动时由调用方按位移或间隔触发的小尘团，不自行创建永久发射器。
static func trail(host: Node2D, world_position: Vector2, strength: float = 0.25) -> LargeFusionDust:
	return emit_ground(host, world_position, strength, Kind.TRAIL)

## 重启当前节点的短表现；[param world_position]、[param strength]、[param kind] 与创建入口一致。
func burst(world_position: Vector2, strength: float, kind: Kind) -> void:
	_battle_game = Global.main_game
	if is_instance_valid(_battle_game):
		_battle_round = _battle_game.curr_game_round
		_battle_phase = AdventureSession.get_active_phase(_battle_game.game_para)
	_anchor = world_position
	_strength = clampf(strength, 0.1, 1.8)
	_kind = kind
	_age = 0.0
	_lifetime = 0.92 if kind == Kind.DEATH else (0.68 if kind == Kind.BIRTH else 0.55)
	if kind == Kind.TRAIL:
		_lifetime = 0.42
	_phase = fposmod(world_position.dot(Vector2(0.071, 0.113)), TAU)
	global_transform = Transform2D(0.0, _anchor)
	set_process(true)
	queue_redraw()

## [param delta] 使用引擎战斗时间；不使用真实时钟或忽略暂停的计时器。
func _process(delta: float) -> void:
	if not _same_battle():
		queue_free()
		return
	_age += delta
	if _age >= _lifetime:
		queue_free()
		return
	global_transform = Transform2D(0.0, _anchor)
	queue_redraw()

## 只比较战场、轮次和阶段身份，不以运行状态截断普通暂停或胜利后的余帧。
func _same_battle() -> bool:
	return is_instance_valid(_battle_game) and _battle_game.is_inside_tree() \
		and not _battle_game.is_queued_for_deletion() and _battle_game == Global.main_game \
		and _battle_game.curr_game_round == _battle_round \
		and AdventureSession.get_active_phase(_battle_game.game_para) == _battle_phase

## 尘团从脚点向两侧摊开，保留轮廓阅读；地面压痕不形成规则光环。
func _draw() -> void:
	var progress: float = clampf(_age / _lifetime, 0.0, 1.0) # 归一化生命周期。
	var fade: float = (1.0 - exp(-progress * 22.0)) * pow(1.0 - progress, 1.7) # 快起慢散。
	var radius: float = sqrt(_strength) # 温和缩放，避免强度翻倍时覆盖整个角色。
	var count: int = 10 if _kind == Kind.DEATH else (4 if _kind == Kind.TRAIL else 7) # 小量固定尘团。
	var reach: float = 76.0 if _kind == Kind.DEATH else (23.0 if _kind == Kind.TRAIL else 51.0) # 最大横向铺开范围。
	var opacity: float = 0.21 * _strength * fade # 最浓处仍能看清地面。
	var tint: Color = DUST.lerp(ASH, 0.27) if _kind in [Kind.BIRTH, Kind.DEATH] else DUST # 只在分裂时染灰紫。
	if _kind != Kind.TRAIL:
		GroundShapes.ellipse(self, Vector2(0.0, 1.5), Vector2(29.0 + progress * 11.0, 5.0) * radius,
			Color(EARTH, 0.15 * _strength * pow(1.0 - progress, 2.0)))
	for index: int in range(count): # 同一事件的固定布局保证暂停和逐帧观察稳定。
		var angle: float = float(index) * 2.399 + _phase # 错开的方向避免等间距圆圈。
		var scatter: float = 0.72 + 0.14 * float(index % 3) # 尘团速度略有差异。
		var center: Vector2 = Vector2(cos(angle) * (8.0 + progress * reach * scatter),
			sin(angle) * 3.0 - sin(progress * PI * 0.7) * (7.0 + float(index % 3) * 4.0)) * radius # 扬起后散开。
		var size: Vector2 = Vector2(6.0 + progress * 11.0, 3.5 + progress * 7.0) * radius * scatter # 扁平柔尘。
		GroundShapes.ellipse(self, center, size * 1.23, Color(tint, opacity * 0.28))
		GroundShapes.ellipse(self, center + Vector2(1.0, -0.8), size, Color(tint, opacity * 0.62))
		if _kind != Kind.TRAIL and index % 2 == 0:
			_draw_chip(index, angle, progress, radius, fade)
	if _kind == Kind.IMPACT or _kind == Kind.LANDING:
		_draw_contact(progress, radius)

## 少量米灰碎屑以短抛物线回落；[param index]、[param angle] 决定稳定方向。
## [param progress]、[param radius] 与 [param fade] 继承当前尘团的生命周期。
func _draw_chip(index: int, angle: float, progress: float, radius: float, fade: float) -> void:
	var flight: float = minf(progress / 0.72, 1.0) # 碎屑先落地，余尘稍后消散。
	var point: Vector2 = Vector2(cos(angle) * (9.0 + flight * (29.0 + float(index) * 2.0)),
		-4.0 * (10.0 + float(index % 3) * 5.0) * flight * (1.0 - flight)) * radius # 无横跨草坪的大碎块。
	var chip: Color = DUST.lerp(EARTH, 0.35) # 暗边不会像发光星点。
	chip.a = fade * 0.48 * _strength
	draw_line(point - Vector2(1.5, 0.7) * radius, point + Vector2(1.0, -0.4) * radius, chip, 1.8, true)

## 撞击瞬间出现几条贴地短压痕；[param progress] 与 [param radius] 决定退隐和大小。
func _draw_contact(progress: float, radius: float) -> void:
	var strength: float = maxf(0.0, 1.0 - progress / 0.36) * 0.31 * _strength # 不留下持久裂地。
	for index: int in range(5): # 压痕是断续不规则短线，不画封闭圆环。
		var angle: float = float(index) * 1.27 + 0.31 # 固定偏角让压痕错开水平轴。
		var direction: Vector2 = Vector2(cos(angle), sin(angle) * 0.24) # 压到地面透视。
		draw_line(direction * 15.0 * radius, direction * (24.0 + float(index % 3) * 7.0) * radius,
			Color(EARTH, strength), 1.3, true)
