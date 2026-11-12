## 闪电芦苇的转职配色，实战、图鉴与卡面共用。本体与放电保留原贴图和动画。
extends Node2D
class_name AdventureLightningReedPromotionArt

## 闪电芦苇的存档物种编号。外观脚本只依赖美术资源。
const PLANT_TYPE: int = 50
## 按原贴图亮度着色的材质，植株与电弧使用不同参数。
const PALETTE_SHADER = preload("res://shaders/lightning_reed_palette.gdshader")
## 本体的局部高度参考值，单位为像素。
const BODY_HEIGHT: float = 96.0
## 卡面根部锚点到种子包图案顶端的局部高度，单位为像素。
const PORTRAIT_HEIGHT: float = 82.25
## 一至四转的根部、茎身、顶端、电弧外缘和亮芯色，分别对应二至五阶。
const PALETTES: Array[Dictionary] = [
	{"root": Color("4274f3"), "stem": Color("4274f3"), "tip": Color("4274f3"),
		"arc": Color("4a7af5"), "core": Color("d5edff")},
	{"root": Color("9d57f2"), "stem": Color("2856cf"), "tip": Color("4e82f1"),
		"arc": Color("655cf6"), "core": Color("d9dfff")},
	{"root": Color("7741ca"), "stem": Color("8647db"), "tip": Color("ce79f5"),
		"arc": Color("b45cf2"), "core": Color("f3d9ff")},
	{"root": Color("c28a31"), "stem": Color("dda536"), "tip": Color("ffe36c"),
		"arc": Color("f4c341"), "core": Color("fff3b0")},
]

## 同一转职的电弧不需要实例坐标，可以共享只读材质。
static var _bolt_materials: Dictionary[int, ShaderMaterial] = {}
## 每阶共用一张小尺寸根光纹理，植株和卡面只各自持有精灵。
static var _root_textures: Dictionary[int, GradientTexture2D] = {}

## 此植株或卡面的专用材质，局部渐变坐标随锚点更新。
var _body_material: ShaderMaterial
## 绘制于植株图层下的紧凑根光。
var _root_glow: Sprite2D


## 在身体容器 [param body] 上应用 [param rank] 转外观。0 为原始形象。
static func apply_to_body(body: Node2D, rank: int) -> bool:
	if body == null:
		return false
	# 原版动作和比例统一从这一美术场景读取。
	var visual := body.get_node_or_null(^"LightningReedVisual") as Node2D
	if visual == null:
		return false
	# Rig 的直接子节点是受原动作控制的分层精灵。
	var rig := visual.get_node_or_null(^"Rig") as Node2D
	if rig == null:
		return false
	# 保留隐藏的攻击部件，播放动作时它们也要使用同一配色。
	var sprites: Array[Sprite2D] = []
	for child: Node in rig.get_children():
		if child is Sprite2D:
			sprites.append(child)
	return _apply(visual, sprites, rank, BODY_HEIGHT)


## 给独立卡面 [param preview] 应用 [param rank] 转外观，涵盖持卡预览和技能书头像。
static func apply_to_preview(preview: Node2D, rank: int) -> bool:
	if preview == null:
		return false
	# 种子包模板已经把此节点的原点对齐到叶丛根部。
	var visual := preview.get_node_or_null(^"LightningReed") as Node2D
	if visual == null:
		return false
	# 卡面是一张独立纹理，着色使用和战斗相同的根部与电弧配色。
	var artwork := visual.get_node_or_null(^"Artwork") as Sprite2D
	if artwork == null:
		return false
	return _apply(visual, [artwork], rank, PORTRAIT_HEIGHT)


## 为一次放电的 [param effect] 应用 [param rank] 转配色。各帧的透明度和动画时长由原场景决定。
static func apply_to_effect(effect: Node2D, rank: int) -> void:
	if rank <= 0 or rank > PALETTES.size():
		return
	# 首段、折射、命中都使用此 Rig，动画会独立更新子部件。
	var rig := effect.get_node(^"Rig") as Node2D
	if not _bolt_materials.has(rank):
		# 电弧材质没有空间渐变，每阶创建一次后只读复用。
		var material := _new_material(rank)
		material.set_shader_parameter(&"projectile", true)
		_bolt_materials[rank] = material
	for child: Node in rig.get_children():
		if child is Sprite2D:
			child.material = _bolt_materials[rank]


## 复用 [param anchor] 上的外观节点，为 [param sprites] 设置 [param rank] 与局部 [param height]。
## 传入 0 时撤下根光和本次着色，供卡面更换出战快照时恢复原始图案。
static func _apply(anchor: Node2D, sprites: Array[Sprite2D], rank: int, height: float) -> bool:
	if rank < 0 or rank > PALETTES.size() or sprites.is_empty():
		return false
	# 同一外观锚点只放一套根光，反复切换转职时复用该节点。
	var art := anchor.get_node_or_null(^"PromotionPalette") as AdventureLightningReedPromotionArt
	if rank == 0:
		if art != null:
			# 只清理本套材质，避免覆盖调用方另外应用的状态材质。
			for sprite: Sprite2D in sprites:
				if sprite.material == art._body_material:
					sprite.material = null
			anchor.remove_child(art)
			art.queue_free()
		return true
	if art == null:
		art = AdventureLightningReedPromotionArt.new()
		art.name = &"PromotionPalette"
		anchor.add_child(art)
		anchor.move_child(art, 0)
	art._configure(rank, height)
	for sprite: Sprite2D in sprites: # 原动画持续驱动同一精灵的位姿和颜色乘数。
		sprite.material = art._body_material
	return true


## 返回使用第 [param rank] 转颜色的新材质，调用者可以写入自己的尺寸和坐标。
static func _new_material(rank: int) -> ShaderMaterial:
	# 同一份色表同时给植株和闪电提供色值。
	var palette: Dictionary = PALETTES[rank - 1]
	var material := ShaderMaterial.new() # 该材质由当前植株或电弧缓存拥有。
	material.shader = PALETTE_SHADER
	material.set_shader_parameter(&"root_tone", palette.root)
	material.set_shader_parameter(&"stem_tone", palette.stem)
	material.set_shader_parameter(&"tip_tone", palette.tip)
	material.set_shader_parameter(&"arc_tone", palette.arc)
	material.set_shader_parameter(&"core_tone", palette.core)
	return material


## 返回 [param rank] 对应的椭圆根光。低透明度的径向渐隐覆盖根部附近 38×14 像素。
static func _root_texture(rank: int) -> GradientTexture2D:
	if _root_textures.has(rank):
		return _root_textures[rank]
	# 同色渐隐能保持边缘的钴蓝、紫或浅金色，不引入脏黑边。
	var hue: Color = PALETTES[rank - 1].root
	var gradient := Gradient.new() # 中心较亮，外缘自然降到完全透明。
	gradient.offsets = PackedFloat32Array([0.0, 0.38, 1.0])
	gradient.colors = PackedColorArray([Color(hue, 0.38), Color(hue, 0.17), Color(hue, 0.0)])
	var texture := GradientTexture2D.new() # 独立于原角色贴图的窄椭圆光。
	texture.gradient = gradient
	texture.width = 38
	texture.height = 14
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	_root_textures[rank] = texture
	return texture


## 切换到 [param rank] 转和局部参考高度 [param height]，将根光压在叶丛下方。
func _configure(rank: int, height: float) -> void:
	_body_material = _new_material(rank)
	_body_material.set_shader_parameter(&"root_only", rank == 1)
	_body_material.set_shader_parameter(&"body_height", height)
	if _root_glow == null:
		_root_glow = Sprite2D.new()
		_root_glow.position = Vector2(0, -4)
		add_child(_root_glow)
	_root_glow.texture = _root_texture(rank)
	_update_basis()


## 入树后接收祖先变换通知，覆盖卡面拖动、图鉴适配和战场斜面。
func _ready() -> void:
	set_notify_transform(true)
	_update_basis()


## [param what] 为引擎通知类型，只有锚点变换需要重新绑定渐变坐标。
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_update_basis()


## 从锚点的逆变换取 Y 轴系数，着色器可把各个动画部件的像素转回根部的局部高度。
func _update_basis() -> void:
	if _body_material == null or not is_inside_tree():
		return
	# 某些界面收放会暂时把缩放设为 0，等待下次可逆变换再更新坐标。
	var world_from_root: Transform2D = global_transform
	if is_zero_approx(world_from_root.determinant()):
		return
	var root_from_world: Transform2D = world_from_root.affine_inverse() # 逆变换 Y 行的负值表示离地高度。
	_body_material.set_shader_parameter(&"root_origin", world_from_root.origin)
	_body_material.set_shader_parameter(&"height_axis", -Vector2(root_from_world.x.y, root_from_world.y.y))
