## 神殿之光的战斗皮肤。仅在有效装配时载入原画，头像与技能控件共用同一套图集。
extends RefCounted
class_name ValhallaBattleSkin

## 与全部发行编号共用的装备定义 ID。
const BADGE_ID: StringName = &"valhalla_temple_light"
## 技能按钮的设计尺寸，方框与点击范围一致。
const SKILL_SIZE := Vector2(96, 96)
## 原图集中横幅、方框及各自殿景的坐标，单位为素材像素。
const PROFILE_FRAME := Rect2(16, 0, 1342, 816)
const SKILL_FRAME := Rect2(17, 766, 360, 356)
const PROFILE_HALL := Rect2(104, 113, 1191, 643)
const SKILL_HALL := Rect2(97, 789, 276, 267)

## 共用背包的只读贴图和标签构造器。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 两张源图集及材质均按需载入，普通战斗和战外界面不申请它们。
var _frames: Texture2D
## 包含两种尺寸的神殿内部景深图集。
var _halls: Texture2D
## 共用的圣光与金属反光着色器，各层使用独立参数。
var _lighting: Shader

## [param equipment] 必须实际装备本徽章且通过存档绑定校验，返回双控件共用的皮肤。
## 装配无效或核心素材缺失时返回 null，宿主可沿用默认 HUD。
static func for_equipment(equipment: PlayerEquipmentState) -> ValhallaBattleSkin:
	if equipment == null:
		return null
	var service := PlayerEquipmentService.new(equipment) # 走装备服务校验，仓库持有不触发皮肤。
	var badge: EquipmentDefinition = service.equipped_definition(EquipmentDefinition.Slot.BADGE) # 只查询徽章槽。
	if badge == null or badge.id != BADGE_ID:
		return null
	var skin := ValhallaBattleSkin.new() # 随本场战斗释放，两个控件不重复载入。
	skin._frames = Art.texture("res://assets/adventure/ui/player/valhalla_battle_frame.png")
	skin._halls = Art.texture("res://assets/adventure/ui/player/valhalla_battle_hall.png")
	skin._lighting = load("res://shaders/adventure/valhalla_battle_lighting.gdshader") as Shader
	return skin if skin._frames != null and skin._halls != null and skin._lighting != null else null

## 在 [param parent] 的头像或技能底部添加殿景，[param compact] 选择方形技能素材。
func add_hall(parent: Control, compact: bool) -> void:
	var bounds := Rect2(11, 15, 74, 73) if compact else Rect2(26, 34, 355, 192) # 背景外沿藏入柱廊和上层铭牌。
	var hall: TextureRect = _layer(parent, &"TempleHall", _halls,
		SKILL_HALL if compact else PROFILE_HALL, bounds)
	var material := _material(bounds.size, compact) # 仅在神殿内部叠加光束和微尘。
	material.set_shader_parameter("hall_interior", true)
	hall.material = material

## 在 [param parent] 的内容上方添加金边，[param compact] 选择方框；返回可驱动技能状态的材质。
func add_frame(parent: Control, compact: bool) -> ShaderMaterial:
	var bounds := Rect2(Vector2.ZERO, parent.size).grow(5.0) # 原画外围留有透明像素，略放宽美术使可见金边铺满固定热区。
	var frame: TextureRect = _layer(parent, &"TempleFrame", _frames,
		SKILL_FRAME if compact else PROFILE_FRAME, bounds)
	var material := _material(bounds.size, compact) # 每个边框独立响应光效，冷却只影响方框。
	frame.material = material
	return material

## 在 [param parent] 的蓝金铭牌上提供独立的名字控件，沿用神殿题字的暖金与浅蓝彩光。
func add_nameplate(parent: Control) -> Label:
	var title: Label = Art.label(parent, "", Vector2(80, 184), Vector2(240, 32), 25, Color.WHITE) # 只占铭牌内部。
	title.name = &"PlayerName"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_color_override("font_shadow_color", Color("080e28"))
	title.add_theme_color_override("font_outline_color", Color("0b132f"))
	title.add_theme_constant_override("outline_size", 2)
	var serif := load("res://assets/adventure/ui/player/fonts/temple_badge_serif_sc_semibold.otf") as Font # 少量刻字字形独立复用。
	if serif != null:
		var lettering := FontVariation.new() # 玩家可自定义名字，字体子集之外继续使用宿主中文字体。
		lettering.base_font = serif
		lettering.fallbacks = [title.get_theme_font("font")]
		lettering.spacing_glyph = 1
		title.add_theme_font_override("font", lettering)
	var prism := ShaderMaterial.new() # 铭牌地点固定，利用已有的神殿三色反光。
	prism.shader = load("res://shaders/adventure/valhalla_badge_lettering.gdshader") as Shader
	title.material = prism
	return title

## 在 [param parent] 的技能框右下角叠放镜徽，实际悬停与点击交给原生按钮。
func add_inspect_mark(parent: Control) -> void:
	var ring := Panel.new() # 圆形暗蓝内底与金边，托住放大镜小图标。
	ring.name = &"TempleInspect"
	ring.position = Vector2(68, 68)
	ring.size = Vector2(23, 23)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rim := StyleBoxFlat.new() # 两像素金边在战斗内部缩小后仍有轮廓。
	rim.bg_color = Color("172542")
	rim.border_color = Color("f8cf7e")
	rim.set_border_width_all(2)
	rim.set_corner_radius_all(12)
	ring.add_theme_stylebox_override("panel", rim)
	parent.add_child(ring)
	ring.draw.connect(_draw_lens.bind(ring))

## 在 [param mark] 的暗底上画亮金色镜片轮廓，缩至战斗 HUD 尺寸时也能辨认。
func _draw_lens(mark: Control) -> void:
	var gold := Color("ffe2a1") # 高对比的窄金线与静态金边区分。
	mark.draw_arc(Vector2(10, 10), 4.1, 0.0, TAU, 20, gold, 2.0, true)
	mark.draw_line(Vector2(13, 13), Vector2(17, 17), gold, 2.0, true)

## 将 [param target] 用柔和渐显带入战斗，返回可在再度出现时中止的动画。
static func reveal(target: CanvasItem) -> Tween:
	target.modulate.a = 0.0
	var entrance := target.create_tween() # 节点离树时同步销毁，不影响战斗时钟。
	entrance.tween_property(target, "modulate:a", 1.0, 0.48).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return entrance

## 在 [param parent] 定位 [param bounds] 内的只读 [param layer_name] 图层。
## [param sheet] 的 [param region] 保持透明通道，并为小尺寸 HUD 使用图集的 mipmap。
func _layer(parent: Control, layer_name: StringName, sheet: Texture2D, region: Rect2, bounds: Rect2) -> TextureRect:
	var image: TextureRect = Art.image(parent, "", bounds.position, bounds.size) # 不承接任何鼠标和触摸输入。
	image.name = layer_name
	image.stretch_mode = TextureRect.STRETCH_SCALE
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	image.texture = _slice(sheet, region)
	return image

## 返回 [param sheet] 的 [param region] 贴图切片，原始图集保留完整。
func _slice(sheet: Texture2D, region: Rect2) -> AtlasTexture:
	var cut := AtlasTexture.new() # 独立区域共享图集显存。
	cut.atlas = sheet
	cut.region = region
	cut.filter_clip = true
	return cut

## 把 [param extent] 的逻辑像素局部化，[param compact] 决定方框高光锚点。
func _material(extent: Vector2, compact: bool) -> ShaderMaterial:
	var result := ShaderMaterial.new() # 独立充能、悬停及脉冲参数不串到另一控件。
	result.shader = _lighting
	result.set_shader_parameter("extent", extent)
	result.set_shader_parameter("compact", compact)
	return result
