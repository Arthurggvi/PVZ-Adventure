## 融合体的独立死亡快照：实体可立即注销，余下落地、压塌与瓦解只保留纯绘制节点。
class_name LargeFusionDeathEffect
extends Node2D

## 没有专属材质的极早死亡实例也使用同一套保色消散。
const SURFACE: Shader = preload("res://shaders/large_fusion_surface.gdshader")
## 落地后鼓胀、压塌和瓦解占用的游戏秒数。
const BODY_SECONDS: float = 1.12
## 只读的当前原画快照，没有角色脚本、动画播放器或碰撞。
var _corpse: Sprite2D
## 独立阴影快照，与身体共同离树，不引用原角色。
var _shade: Sprite2D
## 当前原画与死亡消散参数的独立材质。
var _ink: ShaderMaterial
## 身体落地时的局部变换；脚点是当前效果节点的原点。
var _ground_pose: Transform2D = Transform2D.IDENTITY
## 由空中缩放倒推的接地阴影变换，下降时重新施加当前高度的缩放。
var _shadow_pose: Transform2D = Transform2D.IDENTITY
## 由空中淡化倒推的接地透明度，保留捕获时的其余调色因素。
var _shadow_alpha: float = 1.0
## 捕获时的世界离地高度，不在以后读取原角色。
var _height: float = 0.0
## 空中死亡的加速落地时间；地面死亡为零。
var _fall_seconds: float = 0.0
## 从捕获到当前帧的累计游戏时间，继承场景暂停。
var _age: float = 0.0
## 总生命周期约为 1.3 至 1.5 秒。
var _lifetime: float = 1.3
## 防止低帧率和长帧重复产生压塌尘。
var _dust_sent: bool = false
## 快照所属战场，续战复用行节点时也不能串入下一阶段。
var _battle_game: MainGameManager
## 创建快照时的轮次。
var _battle_round: int = -1
## 创建快照时的阶段身份，普通胜利尾帧仍属于该阶段。
var _battle_phase: StagePhaseDefinition

## 从 [param source] 同步捕获 [param sprite] 和 [param shadow]；调用后原实体可以立即隐藏与释放。
static func capture(source: Zombie000Base, sprite: Sprite2D, shadow: Sprite2D) -> void:
	if not is_instance_valid(source) or not source.is_inside_tree() or source.retiring_from_battle \
			or source.character_init_type != Character000Base.E_CharacterInitType.IsNorm \
			or not is_instance_valid(sprite) or not is_instance_valid(shadow):
		return
	var host: Node2D = source.get_parent() as Node2D # 余尘和尸体保持在原行的绘制与暂停层级。
	if not is_instance_valid(host) or host.is_queued_for_deletion():
		return
	var effect: LargeFusionDeathEffect = LargeFusionDeathEffect.new() # 不复制角色树或战斗组件。
	effect._battle_game = Global.main_game
	if is_instance_valid(effect._battle_game):
		effect._battle_round = effect._battle_game.curr_game_round
		effect._battle_phase = AdventureSession.get_active_phase(effect._battle_game.game_para)
	effect.z_index = source.z_index
	effect.z_as_relative = source.z_as_relative
	host.add_child(effect)
	effect.global_transform = Transform2D(0.0, source.global_position)
	effect._height = maxf(0.0, (source.to_global(source.body.pose_position) - source.body.global_position).y)
	effect._fall_seconds = clampf(0.28 + effect._height * 0.001, 0.28, 0.38) if effect._height > 0.5 else 0.0
	effect._lifetime = maxf(1.3, effect._fall_seconds + BODY_SECONDS)
	effect._shade = _copy_sprite(shadow, host)
	effect.add_child(effect._shade)
	effect._shade.global_transform = shadow.global_transform
	effect._shadow_pose = effect._shade.transform
	var height_ratio: float = clampf(effect._height / 80.0, 0.0, 1.0) # 与在世融合体的阴影高度曲线相同。
	effect._shadow_pose.x /= lerpf(1.0, 0.66, height_ratio)
	effect._shadow_pose.y /= lerpf(1.0, 0.72, height_ratio)
	effect._shadow_alpha = effect._shade.modulate.a / lerpf(1.0, 0.38, height_ratio)
	effect._corpse = _copy_sprite(sprite, host)
	effect.add_child(effect._corpse)
	effect._corpse.global_transform = sprite.global_transform
	effect._ground_pose = effect._corpse.transform
	effect._ground_pose.origin.y += effect._height
	var source_ink: ShaderMaterial = sprite.material as ShaderMaterial # 身体遮罩可能暂时盖住精灵自身的融合材质。
	if source_ink != null and source_ink.shader == SURFACE:
		effect._ink = source_ink.duplicate() as ShaderMaterial
	else:
		effect._ink = effect._corpse.material as ShaderMaterial
	if effect._ink == null or effect._ink.shader != SURFACE:
		effect._ink = ShaderMaterial.new()
		effect._ink.shader = SURFACE
	effect._corpse.material = effect._ink
	effect._ink.set_shader_parameter(&"dissolve", 0.0)

## 只复制 [param art] 的绘制数据；[param host] 以上的调色仍由共同父层继承一次。
static func _copy_sprite(art: Sprite2D, host: Node2D) -> Sprite2D:
	var copy: Sprite2D = Sprite2D.new() # 纯精灵不会保留旧角色脚本或信号连接。
	copy.texture = art.texture
	copy.hframes = art.hframes
	copy.vframes = art.vframes
	copy.frame = art.frame
	copy.flip_h = art.flip_h
	copy.flip_v = art.flip_v
	copy.centered = art.centered
	copy.offset = art.offset
	copy.region_enabled = art.region_enabled
	copy.region_rect = art.region_rect
	copy.region_filter_clip_enabled = art.region_filter_clip_enabled
	copy.texture_filter = art.texture_filter
	copy.texture_repeat = art.texture_repeat
	copy.visible = art.is_visible_in_tree()
	copy.light_mask = art.light_mask
	copy.z_index = art.z_index
	copy.z_as_relative = art.z_as_relative
	copy.self_modulate = art.self_modulate
	copy.modulate = _capture_tint(art, host)
	var material_owner: CanvasItem = art # 解析实际使用的材质，不能误取被父材质遮盖的资源。
	while material_owner.use_parent_material and not material_owner.top_level:
		var parent_item: CanvasItem = material_owner.get_parent() as CanvasItem # 普通 Node 会断开画布材质继承。
		if parent_item == null:
			break
		material_owner = parent_item
	if material_owner.material != null:
		copy.material = material_owner.material.duplicate() as Material
	return copy

## 合成 [param art] 到共同父层 [param host] 之间的 modulate；祖先 self_modulate 不影响子项。
static func _capture_tint(art: CanvasItem, host: Node2D) -> Color:
	var tint: Color = Color.WHITE # 保留当前身体与根节点的调色，不重复乘共同父层。
	var cursor: Node = art # 沿原绘制祖先读取，返回后不再保留源节点引用。
	while cursor != null and cursor != host:
		if cursor is CanvasItem:
			tint *= (cursor as CanvasItem).modulate
		cursor = cursor.get_parent()
	return tint

## [param delta] 为场景游戏时间；所有姿态由累计时间直接采样，不积累位移误差。
func _process(delta: float) -> void:
	if not _same_battle():
		queue_free()
		return
	_age += delta
	if _age >= _lifetime:
		queue_free()
		return
	var fall: float = clampf(_age / _fall_seconds, 0.0, 1.0) if _fall_seconds > 0.0 else 1.0 # 空中阶段的归一化进度。
	var remaining: float = _height * (1.0 - fall * fall) # 从静止开始加速下落，落点固定在原脚点。
	var grounded_age: float = maxf(0.0, _age - _fall_seconds) # 落地前不提前开始身体压塌。
	var swell: float = sin(PI * clampf(grounded_age / 0.18, 0.0, 1.0)) * 0.065 # 接地后短促鼓胀。
	var collapse: float = smoothstep(0.11, 0.45, grounded_age) # 重量逐渐摊开，避免瞬间压成薄纸。
	var size: Vector2 = Vector2(1.0 + swell + collapse * 0.42, 1.0 + swell * 0.60 - collapse * 0.76) # 横宽纵扁。
	var deformation: Transform2D = Transform2D(0.0, size, 0.0, Vector2(0.0, -remaining)) # 仅挤压与升降，不增加旋转。
	_corpse.transform = deformation * _ground_pose
	_ink.set_shader_parameter(&"dissolve", smoothstep(0.24, 1.02, grounded_age))
	_ink.set_shader_parameter(&"hit_strength", maxf(0.0, 1.0 - grounded_age / 0.18) * 0.24)
	var shadow_fade: float = smoothstep(0.15, 1.04, grounded_age) # 身体瓦解时阴影同步失去体积。
	var shadow_size: float = 1.0 - shadow_fade * 0.42 # 仅收缩原阴影，不出现额外光圈。
	var shadow_height: float = clampf(remaining / 80.0, 0.0, 1.0) # 首帧还原原始小淡阴影，接地时恢复常态。
	var shadow_pose: Transform2D = _shadow_pose # 只缩放基向量，脚点偏移不随阴影尺寸漂移。
	shadow_pose.x *= lerpf(1.0, 0.66, shadow_height) * shadow_size
	shadow_pose.y *= lerpf(1.0, 0.72, shadow_height) * shadow_size
	_shade.transform = shadow_pose
	_shade.modulate.a = _shadow_alpha * lerpf(1.0, 0.38, shadow_height) * (1.0 - shadow_fade)
	if not _dust_sent and _age >= _fall_seconds + 0.08:
		_dust_sent = true
		LargeFusionDust.emit_ground(get_parent() as Node2D, global_position, 1.15, LargeFusionDust.Kind.DEATH)

## 只比较战场、轮次和阶段身份，不以运行状态截断普通暂停或胜利后的余帧。
func _same_battle() -> bool:
	return is_instance_valid(_battle_game) and _battle_game.is_inside_tree() \
		and not _battle_game.is_queued_for_deletion() and _battle_game == Global.main_game \
		and _battle_game.curr_game_round == _battle_round \
		and AdventureSession.get_active_phase(_battle_game.game_para) == _battle_phase
