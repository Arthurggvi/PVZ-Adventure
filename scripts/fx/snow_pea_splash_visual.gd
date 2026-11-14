## 冷萃真实结算时的低透明范围霜雾；尺寸来自同一格距，只承担瞬时反馈。
extends Node2D
class_name SnowPeaSplashVisual

## 冷萃霜雾的最长战斗秒数，不留下持续地面场。
const LIFETIME: float = 0.34
## 密集棱锥穿透时限制并发画布，纯视觉裁剪不影响真实溅射。
const MAX_ACTIVE: int = 18
## 仅用于计数当前场景的短命霜雾，不保存跨场景全局引用。
const VISUAL_GROUP: StringName = &"snow_pea_cold_extract_visual"
## 结算时的战场快照，切轮或切阶段后立即释放。
var _battle: RepeaterShotContext
## 与溅射宽相查询相同的世界尺寸，单位为像素。
var _extent: Vector2 = Vector2.ZERO
## 当前表现年龄，随战斗暂停。
var _age: float = 0.0

## 在 [param battle] 的 [param position]、[param lane] 播放冷萃；[param cells] 与实际伤害查询共用。
## 仅由成功排定的冷萃事务调用，空地和伤害无效的碰撞不会显示范围反馈。
static func spawn(battle: RepeaterShotContext, position: Vector2, lane: int, cells: float) -> void:
	if not battle.is_active() or cells <= 0.0:
		return
	if battle.game.get_tree().get_nodes_in_group(VISUAL_GROUP).size() >= MAX_ACTIVE:
		return
	var visual := SnowPeaSplashVisual.new() # 每次真实溅射只新增一个短命画布。
	visual._battle = battle
	visual._extent = battle.pitch_at(position, lane) * cells
	visual.position = battle.game.bullets.to_local(position)
	visual.z_index = lane * 50 + 44
	battle.game.bullets.add_child(visual)
	visual.add_to_group(VISUAL_GROUP)

## [param delta] 为有效战斗秒；离开原战局或雾气消散后自动回收。
func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME or not _battle.is_active():
		queue_free()
		return
	queue_redraw()

## 两片宽柔雾和六条向外的薄霜丝显示扩散，保持原僵尸身体可见。
func _draw() -> void:
	var progress: float = clampf(_age / LIFETIME, 0.0, 1.0) # 短促范围反馈的生命周期。
	var spread: float = 1.0 - pow(1.0 - progress, 3.0) # 前段快速到达实际溅射边缘。
	var fade: float = sin(progress * PI) * (1.0 - progress * 0.5) # 出现和消散均柔和，不闪整块白色。
	var size: Vector2 = _extent * lerpf(0.38, 1.0, spread) # 最大尺寸与真实1.6格宽相相同。
	draw_texture_rect(SnowPeaFrostVisual.mist_texture(), Rect2(-size * 0.5, size), false,
		Color(0.49, 0.81, 0.95, fade * 0.16))
	draw_texture_rect(SnowPeaFrostVisual.mist_texture(), Rect2(-size * Vector2(0.49, 0.30), size * Vector2(0.98, 0.60)), false,
		Color(0.78, 0.96, 1.0, fade * 0.11))
	for index: int in range(6): # 固定六条短霜丝，无完整圆环和逐片粒子节点。
		var angle: float = float(index) * TAU / 6.0 + 0.28 # 错开水平轴，给扩散保留层次。
		var point: Vector2 = Vector2.from_angle(angle) * size * 0.42 # 距伤害矩形边界留一点软边。
		var heading: Vector2 = point.normalized() # 霜丝朝向爆心外侧。
		draw_line(point - heading * (4.5 + spread * 4.0), point,
			Color(0.75, 0.95, 1.0, fade * 0.36), 0.85, true)
