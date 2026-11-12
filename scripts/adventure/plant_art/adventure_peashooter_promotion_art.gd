## 豌豆射手的转职外观，战场、卡面和冒险图鉴使用同一组分件。
extends RefCounted
class_name AdventurePeashooterPromotionArt

## 普通豌豆射手的物种编号，其他豌豆家族继续使用各自的外观。
const PLANT_TYPE: int = 1
## 瞄具与军帽使用原头部贴图的像素坐标。
const SIGHT = preload("res://assets/adventure/plants/peashooter/red_dot_sight.svg")
## 军帽与瞄具共用头部锚点，帽檐位于瞄具上沿。
const CAP = preload("res://assets/adventure/plants/peashooter/field_cap.svg")
## 色表读取每帧原贴图，覆盖待机与射击时不同的眨眼贴图。
const PALETTE_SHADER = preload("res://shaders/adventure/peashooter_promotion_palette.gdshader")
## 枪灰覆盖脸、嘴和两套眨眼分件。
const HEAD_PARTS: Array[NodePath] = [^"Anim_face", ^"Idle_mouth", ^"Anim_blink", ^"Idle_shoot_blink"]
## 茎与小叶用迷彩底色，保持与大叶片的分件衔接。
const CAMO_BASE_PARTS: Array[NodePath] = [
	^"Backleaf_left_tip", ^"Backleaf_right_tip", ^"Stalk_bottom", ^"Stalk_top",
	^"Frontleaf_right_tip", ^"Frontleaf_tip_left", ^"Anim_stem/stem_correct/Anim_sprout",
]
## 只在有足够面积的叶片上绘制迷彩色块。
const CAMO_LEAVES: Array[NodePath] = [^"Backleaf", ^"Frontleaf"]
## 着色器的三种色表模式。
enum Palette {GUNMETAL, CAMO_BASE, CAMO_LEAF}
## 同一色表只创建一份材质，各植株和预览只读共享。
static var _palettes: Dictionary[int, ShaderMaterial] = {}


## 在静态卡面 [param preview] 应用 [param rank] 次转职外观，0 恢复原图。
## 返回是否找到并应用到预期的部件。
static func apply_to_preview(preview: Node2D, rank: int) -> bool:
	if preview == null:
		return false
	# 卡面保留了原战斗场景的分件与枢轴。
	var body := preview.get_node_or_null(^"Plant001PeaShooterSingle/Body/BodyCorrect") as Node2D
	return apply_to_body(body, rank)


## 给 [param body] 中的原分件套用 [param rank] 次转职外观。第 0 次转职显示一阶原图。
## 返回是否找到原头部锚点并完成应用。
static func apply_to_body(body: Node2D, rank: int) -> bool:
	if body == null or rank < 0 or rank > 4:
		return false
	# 头部动画在此容器中分别驱动脸、嘴与眨眼。
	var stem := body.get_node_or_null(^"Anim_stem/stem_correct") as Node2D
	if stem == null:
		return false
	# 跟随原脸部的每一帧变换，包括开火前的挤压和回弹。
	var face := stem.get_node_or_null(^"Anim_face") as Sprite2D
	if face == null:
		return false
	# 配件位于眨眼层之后，重用节点以支持在同一卡面切换转职。
	var gear := stem.get_node_or_null(^"PeaPromotionGear") as Node2D
	if gear == null:
		if rank == 0:
			return true
		gear = _add_gear(stem, face)
	gear.visible = rank >= 1
	(gear.get_node(^"Cap") as Sprite2D).visible = rank >= 2
	_color_parts(stem, HEAD_PARTS, Palette.GUNMETAL, rank >= 3)
	_color_parts(body, CAMO_BASE_PARTS, Palette.CAMO_BASE, rank >= 4)
	_color_parts(body, CAMO_LEAVES, Palette.CAMO_LEAF, rank >= 4)
	return true


## 在 [param stem] 的眨眼层上方添加配件，返回随 [param face] 原动画移动的容器。
static func _add_gear(stem: Node2D, face: Sprite2D) -> Node2D:
	# 初始变换供尚未入树的静态卡面使用。
	var gear := Node2D.new()
	gear.name = &"PeaPromotionGear"
	gear.transform = face.transform
	gear.use_parent_material = face.use_parent_material
	gear.add_child(_accessory(&"Cap", CAP, Vector2(4, -9), face.use_parent_material))
	gear.add_child(_accessory(&"Sight", SIGHT, Vector2(27, 11), face.use_parent_material))
	stem.add_child(gear)
	# 同层排序盖住眨眼贴图，变换仍来自脸部，无需为配件添加动画轨道。
	var follower := RemoteTransform2D.new()
	follower.remote_path = ^"../../PeaPromotionGear"
	face.add_child(follower)
	return gear


## 创建使用 [param texture] 的配件，按 [param part_name] 注册。
## [param origin] 是头部贴图坐标，[param inherit_material] 为真时沿用角色材质。
static func _accessory(part_name: StringName, texture: Texture2D, origin: Vector2,
		inherit_material: bool) -> Sprite2D:
	# 原头部贴图从左上角绘制，配件沿用同一坐标系。
	var sprite := Sprite2D.new()
	sprite.name = part_name
	sprite.texture = texture
	sprite.centered = false
	sprite.position = origin
	sprite.use_parent_material = inherit_material
	return sprite


## 对 [param root] 下的 [param parts] 按 [param palette] 着色。
## [param enabled] 为假时仅清理由本方法设置的材质。
static func _color_parts(root: Node2D, parts: Array[NodePath], palette: Palette,
		enabled: bool) -> void:
	# 低阶没有使用过该色表时，无需创建材质或遍历分件。
	var material: ShaderMaterial = _palettes.get(palette)
	if material == null:
		if not enabled:
			return
		material = ShaderMaterial.new()
		material.shader = PALETTE_SHADER
		material.set_shader_parameter(&"palette", int(palette))
		_palettes[palette] = material
	for path: NodePath in parts: # 各分件保持原贴图和动画路径。
		var sprite := root.get_node_or_null(path) as Sprite2D # 只修改绘制材质。
		if sprite != null:
			if enabled:
				sprite.material = material
			elif sprite.material == material:
				sprite.material = null
