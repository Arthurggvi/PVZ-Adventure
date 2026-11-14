## 电能豌豆专属的冷电配色；保留原版分层、表情和能量白芯，不复用芦苇的金色五阶。
extends Node2D
class_name AdventureElectricPeashooterPromotionArt

## 电能豌豆在卡片、图鉴和存档中的稳定编号。
const PLANT_TYPE: int = 52
## 按原画彩色区域换色、保留白芯与线条的专属材质。
const PALETTE_SHADER: Shader = preload("res://shaders/electric_peashooter_palette.gdshader")
## 本体根部到头顶的局部参考高度，单位为原版动作坐标像素。
const BODY_HEIGHT: float = 84.0
## 一至五阶的亮芯、主电光和细辅色；所有电球、电弧与矩阵共用该只读色表。
const EFFECT_PALETTES: Array[Dictionary] = [
	{"core": Color("f0fff9"), "rim": Color("4cebbd"), "glow": Color("74cfff")},
	{"core": Color("f0fbff"), "rim": Color("64c8ff"), "glow": Color("728eff")},
	{"core": Color("f0f4ff"), "rim": Color("7d9cff"), "glow": Color("b18dff")},
	{"core": Color("faf3ff"), "rim": Color("c08aff"), "glow": Color("71deff")},
	{"core": Color("f5fdff"), "rim": Color("48e8ff"), "glow": Color("a481ff")},
]
## 二至五阶的根、茎和头顶轮廓色；五阶以电青为主，紫色只留在根部和辅光。
const BODY_PALETTES: Array[Dictionary] = [
	{"root": Color("507edb"), "stem": Color("58b1ec"), "tip": Color("75d7ff")},
	{"root": Color("8767d2"), "stem": Color("648bea"), "tip": Color("91b9ff")},
	{"root": Color("8660ba"), "stem": Color("ad7be1"), "tip": Color("d3a8ff")},
	{"root": Color("8e7ccc"), "stem": Color("42bfd9"), "tip": Color("79edff")},
]
## 特效不使用空间渐变，每阶只创建一份只读共享材质。
static var _effect_materials: Dictionary[int, ShaderMaterial] = {}
## 每阶共用小尺寸根光纹理，避免逐株创建图像。
static var _root_textures: Dictionary[int, GradientTexture2D] = {}

## 当前植株或卡面独享的材质，局部坐标随锚点更新。
var _body_material: ShaderMaterial
## 叶丛下方的低亮度椭圆根光，不覆盖本体轮廓。
var _root_glow: Sprite2D


## 返回 [param rank] 对应的电光颜色副本，键为 core、rim、glow；越界值夹到一至五阶。
## core 为细亮芯，rim 为主电色，glow 为低透明度辅光，调用方可独立设置透明度。
static func effect_colors(rank: int) -> Dictionary:
	return EFFECT_PALETTES[clampi(rank, 0, EFFECT_PALETTES.size() - 1)].duplicate()


## 为身体容器 [param body] 应用 [param rank] 转配色；0 恢复原画，1～4 对应二至五阶。
## 返回是否找到完整的原版美术层；保留隐藏部件以支持后续动作切换。
static func apply_to_body(body: Node2D, rank: int) -> bool:
	if body == null:
		return false
	var visual := body.get_node_or_null(^"ElectricPeashooterVisual") as Node2D # 根部对齐的原版动画容器。
	if visual == null:
		return false
	var rig := visual.get_node_or_null(^"Rig") as Node2D # PAM 转换后的分层精灵。
	if rig == null:
		return false
	var sprites: Array[Sprite2D] = [] # 同一植株所有动作部件共享渐变坐标。
	for child: Node in rig.get_children(): # 包括暂时隐藏的眨眼、发射和电光部件。
		if child is Sprite2D:
			sprites.append(child)
	return _apply_palette(visual, sprites, rank, BODY_HEIGHT)


## 为静态预览 [param preview] 应用 [param rank] 转配色；返回是否成功找到卡面。
static func apply_to_preview(preview: Node2D, rank: int) -> bool:
	if preview == null:
		return false
	var visual := preview.get_node_or_null(^"ElectricPeashooter") as Node2D # 与场上植株一致的根部锚点。
	if visual == null:
		return false
	var artwork := visual.get_node_or_null(^"Artwork") as Sprite2D # 原版透明种子包插图。
	if artwork == null or artwork.texture == null:
		return false
	var portrait_height: float = maxf(1.0, -artwork.position.y + artwork.texture.get_height() * absf(artwork.scale.y) * 0.5) # 顶边距根部的实际局部高度。
	return _apply_palette(visual, [artwork], rank, portrait_height)


## 为电球、电弧或命中特效 [param effect] 应用 [param rank] 转配色；缺少原版 Rig 时不作更改。
## 一阶也使用专属白芯/薄色边材质，确保所有电光入口遵循同一色表。
static func apply_to_effect(effect: Node2D, rank: int) -> void:
	if effect == null:
		return
	var rig := effect.get_node_or_null(^"Rig") as Node2D # 原动画继续驱动所有分层的位姿与透明度。
	if rig == null:
		return
	var safe_rank: int = clampi(rank, 0, EFFECT_PALETTES.size() - 1) # 缓存只使用合法阶级。
	if not _effect_materials.has(safe_rank):
		var material := _new_material(safe_rank) # 缓存拥有该只读特效材质。
		material.set_shader_parameter(&"projectile", true)
		_effect_materials[safe_rank] = material
	for child: Node in rig.get_children(): # 隐藏层在后续动画中亮起时沿用同一颜色。
		if child is Sprite2D:
			child.material = _effect_materials[safe_rank]


## 返回原版电球片段 [param clip] 的球面半径，单位为外观场景局部像素，不含向下垂尾。
static func projectile_radius(clip: StringName) -> float:
	match clip:
		&"projectile2":
			return 24.0
		&"projectile3":
			return 32.0
	return 16.0


## 为飞行电球 [param effect] 应用 [param rank] 配色；[param clip] 决定保留原球面的尺寸。
## 原动画会跨帧复用球面和垂尾图层，所以只在球面范围外柔和隐去垂尾，不抢写任何动画属性。
static func apply_to_projectile(effect: Node2D, rank: int, clip: StringName) -> void:
	if effect == null:
		return
	var rig := effect.get_node_or_null(^"Rig") as Node2D # 保留原动画控制的全部图层和循环片段。
	if rig == null:
		return
	var art := effect.get_node_or_null(^"ElectricProjectilePalette") as AdventureElectricPeashooterPromotionArt # 独立坐标材质随电球移动与缩放更新。
	if art == null:
		art = AdventureElectricPeashooterPromotionArt.new()
		art.name = &"ElectricProjectilePalette"
		effect.add_child(art)
	art._body_material = _new_material(clampi(rank, 0, EFFECT_PALETTES.size() - 1))
	art._body_material.set_shader_parameter(&"projectile", true)
	art._body_material.set_shader_parameter(&"trim_projectile_tail", true)
	art._body_material.set_shader_parameter(&"projectile_radius", projectile_radius(clip))
	art._update_basis()
	for child: Node in rig.get_children(): # 攻击和命中仍使用另一共享材质，不受飞行电球裁尾影响。
		if child is Sprite2D:
			child.material = art._body_material


## 为 [param anchor] 下的 [param sprites] 绑定 [param rank] 专属颜色及参考高度 [param height]。
## 返回是否完成绑定；0 撤下本套材质，保持其他状态系统的材质所有权。
static func _apply_palette(anchor: Node2D, sprites: Array[Sprite2D], rank: int, height: float) -> bool:
	if rank < 0 or rank > BODY_PALETTES.size() or sprites.is_empty():
		return false
	var art := anchor.get_node_or_null(^"ElectricPromotionPalette") as AdventureElectricPeashooterPromotionArt # 每个本体只创建一套动态坐标材质。
	if rank == 0:
		if art != null:
			for sprite: Sprite2D in sprites: # 只撤销本套换色，不覆盖冻结等外部状态材质。
				if sprite.material == art._body_material:
					sprite.material = null
			anchor.remove_child(art)
			art.queue_free()
		return true
	if art == null:
		art = AdventureElectricPeashooterPromotionArt.new()
		art.name = &"ElectricPromotionPalette"
		anchor.add_child(art)
		anchor.move_child(art, 0)
	art._configure(rank, height)
	for sprite: Sprite2D in sprites: # 不改原版纹理、节点顺序、动作或颜色乘数。
		sprite.material = art._body_material
	return true


## 返回第 [param rank] 阶的新材质；调用方负责本体坐标或将其标记为特效材质。
static func _new_material(rank: int) -> ShaderMaterial:
	var colors: Dictionary = effect_colors(rank) # 所有入口共用的电光色。
	var body: Dictionary = BODY_PALETTES[clampi(rank - 1, 0, BODY_PALETTES.size() - 1)] # 一阶特效不使用本体参数。
	var material := ShaderMaterial.new() # 当前植株或特效缓存拥有此实例。
	material.shader = PALETTE_SHADER
	material.set_shader_parameter(&"root_tone", body.root)
	material.set_shader_parameter(&"stem_tone", body.stem)
	material.set_shader_parameter(&"tip_tone", body.tip)
	material.set_shader_parameter(&"rim_tone", colors.rim)
	material.set_shader_parameter(&"core_tone", colors.core)
	return material


## 返回 [param rank] 对应的低透明根光，38×12 像素内渐隐，不叠加全身辉光。
static func _root_texture(rank: int) -> GradientTexture2D:
	if _root_textures.has(rank):
		return _root_textures[rank]
	var hue: Color = BODY_PALETTES[rank - 1].root # 五阶紫根光与电青头部形成小面积冷色层次。
	var gradient := Gradient.new() # 边缘完全透明，中心也不遮盖叶片。
	gradient.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	gradient.colors = PackedColorArray([Color(hue, 0.24), Color(hue, 0.10), Color(hue, 0.0)])
	var texture := GradientTexture2D.new() # 同阶卡面和战斗外观复用这一资源。
	texture.gradient = gradient
	texture.width = 38
	texture.height = 12
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	_root_textures[rank] = texture
	return texture


## 切换到 [param rank] 转及参考高度 [param height]；不改变动画图层的变换。
func _configure(rank: int, height: float) -> void:
	_body_material = _new_material(rank)
	_body_material.set_shader_parameter(&"body_height", height)
	if _root_glow == null:
		_root_glow = Sprite2D.new()
		_root_glow.position = Vector2(0.0, -3.0)
		add_child(_root_glow)
	_root_glow.texture = _root_texture(rank)
	_update_basis()


## 让卡面拖动、战场缩放与屋顶变换同步更新整株渐变的根部锚点。
func _ready() -> void:
	set_notify_transform(true)
	_update_basis()


## [param what] 为引擎通知，仅在祖先或自身的变换改变时更新材质坐标。
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_update_basis()


## 将各动画部件像素映射回整株局部高度；暂时缩放至零时等待下一次有效变换。
func _update_basis() -> void:
	if _body_material == null or not is_inside_tree():
		return
	var world_from_root: Transform2D = global_transform # 根光与原画共用同一个外观锚点。
	if is_zero_approx(world_from_root.determinant()):
		return
	var root_from_world: Transform2D = world_from_root.affine_inverse() # 逆变换的负 Y 行表示离根部的高度。
	_body_material.set_shader_parameter(&"root_origin", world_from_root.origin)
	_body_material.set_shader_parameter(&"width_axis", Vector2(root_from_world.x.x, root_from_world.y.x))
	_body_material.set_shader_parameter(&"height_axis", -Vector2(root_from_world.x.y, root_from_world.y.y))
