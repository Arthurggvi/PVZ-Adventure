## 超导矩阵的连续主线；每条真实连线使用一个固定宽度的 GPU 实例。
extends MultiMeshInstance2D

## 统一着色器计算宽辉光、双色边缘和白芯。
const BEAM_SHADER: Shader = preload("res://shaders/electric_pea_matrix_beam.gdshader")
## 转职配色权威；五档均与电球及短时电弧一致。
const PromotionArt = preload("res://scripts/adventure/plant_art/adventure_electric_peashooter_promotion_art.gd")
## 四层色带都落在八像素横截面内，轴向长度由实例变换精确给出。
const QUAD_WIDTH: float = 8.0
## 二维实例变换八个浮点数，等阶等自定义数据四个浮点数。
const INSTANCE_STRIDE: int = 12
## 起始容量不限制实际可见的连线数，超出后按二次幂增长。
const INITIAL_CAPACITY: int = 128

## 当前所有线段的变换及等阶，在稳定容量内复用。
var _instance_data := PackedFloat32Array()


## 建立共享网格、五档材质数据与绘制顺序。
func _ready() -> void:
	show_behind_parent = true
	var quad := QuadMesh.new() # 每实例沿局部 X 轴伸展到实际端点。
	quad.size = Vector2(1.0, QUAD_WIDTH)
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	var beam_material := ShaderMaterial.new() # 此战场所有矩阵基线共用一个材质。
	beam_material.shader = BEAM_SHADER
	beam_material.set_shader_parameter(&"rim_tones", _palette_channel(&"rim"))
	beam_material.set_shader_parameter(&"core_tones", _palette_channel(&"core"))
	beam_material.set_shader_parameter(&"glow_tones", _palette_channel(&"glow"))
	material = beam_material


## 从 [param endpoints] 的起止点对和 [param ranks] 同步主线；坐标相对矩阵父节点。
## 原连接顺序与每条线的等阶随传入快照保留，空快照清空可见实例。
func update_lines(endpoints: PackedVector2Array, ranks: PackedInt32Array) -> void:
	if ranks.is_empty():
		if multimesh.visible_instance_count != 0:
			multimesh.visible_instance_count = 0
		return
	if ranks.size() > multimesh.instance_count:
		var capacity: int = maxi(INITIAL_CAPACITY, nearest_po2(ranks.size())) # 只按活跃线段峰值扩容。
		multimesh.instance_count = capacity
		_instance_data.resize(capacity * INSTANCE_STRIDE)
	var used: int = 0 # 退化零长度线段不提交 GPU。
	for index: int in range(ranks.size()): # 一次线性打包取代四层各自构造顶点和索引。
		var start: Vector2 = endpoints[index * 2] # 本条真实线段的第一端。
		var direction: Vector2 = endpoints[index * 2 + 1] - start # 单位面片的局部 X 轴伸缩至线段长度。
		if direction.length_squared() <= 0.000001:
			continue
		var normal: Vector2 = direction.normalized().orthogonal() # 局部 Y 轴保持世界像素宽度。
		var center: Vector2 = start + direction * 0.5 # 使两端覆盖真实球心。
		var base: int = used * INSTANCE_STRIDE # RenderingServer 二维变换写入两行各四个浮点。
		_instance_data[base] = direction.x
		_instance_data[base + 1] = normal.x
		_instance_data[base + 3] = center.x
		_instance_data[base + 4] = direction.y
		_instance_data[base + 5] = normal.y
		_instance_data[base + 7] = center.y
		_instance_data[base + 8] = float(ranks[index]) * 0.25
		used += 1
	if used > 0:
		multimesh.buffer = _instance_data
	if used != multimesh.visible_instance_count:
		multimesh.visible_instance_count = used


## 返回 [param channel] 色阶通道的着色器向量数组。
static func _palette_channel(channel: StringName) -> PackedVector4Array:
	var tones := PackedVector4Array() # 按当前权威配色表的顺序建立 uniform。
	for palette: Dictionary in PromotionArt.EFFECT_PALETTES: # 每档提交一项 RGBA。
		var tone: Color = palette[channel] # 所有实例只用 R 分量索引该等阶。
		tones.append(Vector4(tone.r, tone.g, tone.b, tone.a))
	return tones
