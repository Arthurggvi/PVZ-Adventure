## 一名角色的环境色和短时抖雪。所属注册表离场时必须调用 release。
extends RefCounted

## 本场采样后的颜色、风及共享雪粒预算。
const Presentation = preload("res://scripts/weather/snow/snow_actor_presentation.gd")

## 原登记器持有的战斗角色，退场时解绑。
var actor: Character000Base
## 从现有角色美术读取的扬雪源，仅在真正准备喷发时取样。
var _sources: Array[Node2D] = []
## 决定抖雪节奏的粉雪蓄量，范围为 0..1。
var _shed_reserve: float = 0.0
## 下一次可抖落前的游戏秒数。
var _cooldown: float = 0.0
## 待消费的实际命中，一次采样前可合并多次。
var _hit: bool = false
## 仅在实战天气推进后接收命中触发。
var _active: bool = false

## 保留 [param character] 的已入树身体，无扬雪源的角色同样接收环境色。
func _init(character: Character000Base) -> void:
	actor = character

## 将现有 [param sprite] 登记为扬雪位置，首个源同时启用受击触发。
func add_shed_source(sprite: Node2D) -> void:
	if _sources.is_empty():
		actor.hp_component.combat_attack_received.connect(_on_hit)
	_sources.append(sprite)

## 应用 [param presentation] 的低频天气样本。[param retention] 调整粉雪的积攒速率。
func advance(presentation: Presentation, retention: float = 1.0) -> void:
	_active = true
	if presentation.sample_seconds <= 0.0:
		return
	actor.body.set_environment_color(presentation.tint)
	if not _sources.is_empty():
		_update_shedding(presentation, retention)

## 暂停环境色和抖雪触发，保留本局积攒的粉雪。
func suspend() -> void:
	if not _active:
		return
	_active = false
	_hit = false
	if is_instance_valid(actor) and is_instance_valid(actor.body):
		actor.body.set_environment_color(Color.WHITE)

## 还原环境色并释放本角色的扬雪源和命中连接，允许重复调用。
func release() -> void:
	suspend()
	if is_instance_valid(actor) and is_instance_valid(actor.hp_component):
		if actor.hp_component.combat_attack_received.is_connected(_on_hit):
			actor.hp_component.combat_attack_received.disconnect(_on_hit)
	_sources.clear()
	actor = null

## 从 [param presentation] 的天气和受击事件推进抖雪；[param retention] 为蓄积倍率。
func _update_shedding(presentation: Presentation, retention: float) -> void:
	var seconds: float = presentation.sample_seconds # 与本次颜色采样同步，单位为游戏秒。
	_shed_reserve = clampf(_shed_reserve + presentation.deposition_rate * retention * seconds, 0.0, 1.0)
	_cooldown = maxf(0.0, _cooldown - seconds)
	# 以实例编号错开强风脱落时机，共用原阵风的强度与风向。
	var gust_threshold: float = 0.43 + float(actor.get_instance_id() % 11) * 0.033 # 归一化阵风阈值。
	if _shed_reserve > 0.14 and _cooldown <= 0.0 and (_hit or presentation.gust > gust_threshold) \
			and actor.body.material == null and actor.body.show_status_tints:
		var origin: Vector2 = _shed_origin() # 实际可见的最高扬雪源。
		if presentation.shed(origin):
			_shed_reserve *= 0.71
			_cooldown = 1.25 + float(actor.get_instance_id() % 13) * 0.073
	_hit = false

## 挑选当前可见帧中最高的扬雪源；没有有效帧时返回 [constant Vector2.INF]。
func _shed_origin() -> Vector2:
	var origin: Vector2 = Vector2.INF # 当前最靠上的有效世界出雪点。
	for reference: Variant in _sources: # 已卸下的装备可能随动画释放，先验证后转换类型。
		if not is_instance_valid(reference):
			continue
		var point: Vector2 = _visible_shed_point(reference) # 只在触发抖雪时读取真实动画帧。
		if point.y < origin.y:
			origin = point
	return origin

## 读取已验证的 [param source] 当前可见帧上部，隐藏、淡出或专用演出时返回 [constant Vector2.INF]。
func _visible_shed_point(source: Node2D) -> Vector2:
	if not source.is_visible_in_tree() or source.material is ShaderMaterial:
		return Vector2.INF
	var bounds: Rect2 # 当前帧在源精灵本地的矩形。
	if source is Sprite2D:
		var sprite: Sprite2D = source as Sprite2D # 当前部件可能是分帧或图集精灵。
		if sprite.texture == null:
			return Vector2.INF
		bounds = sprite.get_rect()
	elif source is AnimatedSprite2D:
		var sprite: AnimatedSprite2D = source as AnimatedSprite2D # 图集动画每帧可有不同大小。
		var frames: SpriteFrames = sprite.sprite_frames # 当前动画的帧集合。
		if frames == null or not frames.has_animation(sprite.animation) or sprite.frame >= frames.get_frame_count(sprite.animation):
			return Vector2.INF
		var texture: Texture2D = frames.get_frame_texture(sprite.animation, sprite.frame) # 当前帧实际绘制的图格。
		if texture == null:
			return Vector2.INF
		var size: Vector2 = texture.get_size() # 当前帧的本地绘制尺寸。
		bounds = Rect2(sprite.offset - size * 0.5 if sprite.centered else sprite.offset, size)
	if not bounds.has_area():
		return Vector2.INF
	var opacity: float = source.self_modulate.a # 粉雪脱离角色画布前检查实际可见度。
	var ancestor: CanvasItem = source # 只沿仍继承乘色的画布父级累计透明度。
	while ancestor != null and opacity > 0.05:
		opacity *= ancestor.modulate.a
		if ancestor.top_level:
			break
		ancestor = ancestor.get_parent() as CanvasItem
	if opacity <= 0.05:
		return Vector2.INF
	if source.get_viewport().snap_2d_transforms_to_pixel:
		bounds.position = (bounds.position + Vector2(0.5, 0.5)).floor()
	return source.to_global(bounds.position + bounds.size * Vector2(0.48, 0.16))

## [param amount] 为实际记录的战斗命中伤害，只合并本样本期间的脱落请求。
func _on_hit(amount: int) -> void:
	if _active and amount > 0 and _cooldown <= 0.0:
		_hit = true
