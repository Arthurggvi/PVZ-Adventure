## 双发射手的纯视觉配色、光晕和连续曲线；不读取战斗或玩家状态。
extends RefCounted
class_name RepeaterVisualPalette

## 原画明度重映射，保留纹理透明轮廓。
const PALETTE_SHADER: Shader = preload("res://shaders/repeater/repeater_palette.gdshader")
## GL Compatibility 可用的局部加色光材质。
const GLOW_SHADER: Shader = preload("res://shaders/repeater/repeater_glow.gdshader")
## 星弹和星屑都使用原版阳桃纹理。
const STAR_TEXTURE: Texture2D = preload("res://assets/image/projectile/Projectile_star.png")
## 残影使用原版豌豆形状，不创建简化圆形替身。
const PEA_TEXTURE: Texture2D = preload("res://assets/image/projectile/ProjectilePea.png")
## 五种深色星弹的中间色；同轮索引互异。
const DARK_STARS: Array[Color] = [Color("#6741ad"), Color("#973a70"), Color("#3156a5"), Color("#236e73"), Color("#873c40")]
## 五种浅色星屑；第二代任取连续三种仍互异。
const LIGHT_STARS: Array[Color] = [Color("#c6b4ff"), Color("#ffc2dd"), Color("#a5d9ff"), Color("#a4efdc"), Color("#ffe1ab")]
## 程序化径向光晕由所有表现共享；不保存额外图片资产。
static var _halo: GradientTexture2D

## 返回 [param kind] 的暗部、中间色和高光；[param index] 选择星弹配色。
static func colors(kind: StringName, index: int = 0) -> PackedColorArray:
	var palette: PackedColorArray # 每种材质使用明确的明度层次。
	match kind:
		&"frost": palette = PackedColorArray([Color("#07132f"), Color("#1648b9"), Color("#91dfff")])
		&"ember": palette = PackedColorArray([Color("#3c0410"), Color("#df2435"), Color("#ff6977")])
		&"shock": palette = PackedColorArray([Color("#090b11"), Color("#444957"), Color("#b1bbc6")])
		&"detonation": palette = PackedColorArray([Color("#30020b"), Color("#b70e35"), Color("#ff7b8b")])
		&"morning": palette = PackedColorArray([Color("#090510"), Color("#3f173f"), Color("#de96e3")])
		&"hell": palette = PackedColorArray([Color("#050308"), Color("#321040"), Color("#ad57d4")])
		&"kaguya": palette = PackedColorArray([Color("#030307"), Color("#111019"), Color("#ffd87b")])
		&"hades": palette = PackedColorArray([Color("#3b3d48"), Color("#b8bfcb"), Color("#f5f8ff")])
		&"star_dark":
			var shade: Color = DARK_STARS[posmod(index, DARK_STARS.size())] # 同轮深色分裂保留区分度。
			palette = PackedColorArray([shade.darkened(0.78), shade, shade.lightened(0.52)])
		&"star_light":
			var shade: Color = LIGHT_STARS[posmod(index, LIGHT_STARS.size())] # 弱化星更轻、更明亮。
			palette = PackedColorArray([shade.darkened(0.58), shade, Color.WHITE])
		_: palette = PackedColorArray([Color("#161420"), Color("#d0d0d6"), Color.WHITE])
	return palette

## 创建 [param kind] 的私有材质；[param index] 选配色，[param phase] 错开流光。
static func make_material(kind: StringName, index: int = 0, phase: float = 0.0) -> ShaderMaterial:
	var result := ShaderMaterial.new() # 时间与配色不在不同弹体间串写。
	var palette: PackedColorArray = colors(kind, index) # 将原纹理的明度投影到三段颜色。
	result.shader = PALETTE_SHADER
	result.set_shader_parameter(&"shadow_color", palette[0])
	result.set_shader_parameter(&"body_color", palette[1])
	result.set_shader_parameter(&"light_color", palette[2])
	result.set_shader_parameter(&"phase", phase)
	result.set_shader_parameter(&"surface_brightness", 0.43 if kind == &"morning" else 1.0)
	result.set_shader_parameter(&"red_source", kind in [&"ember", &"hell"])
	var mode: int = 0 # 只在对应材质开启细节，避免每种子弹都同样闪烁。
	if kind == &"morning" or kind == &"star_dark" or kind == &"star_light":
		mode = 1
	elif kind == &"kaguya":
		mode = 2
	elif kind == &"ember" or kind == &"hell":
		mode = 3
	result.set_shader_parameter(&"detail_mode", mode)
	return result

## 返回新的加色光材质；只用于低透明度光层。
static func glow_material() -> ShaderMaterial:
	var result := ShaderMaterial.new() # 颜色由每条绘制指令提供。
	result.shader = GLOW_SHADER
	return result

## 返回中心柔亮、边缘完全透明的共享纹理，辅助原画核心产生柔光。
static func halo_texture() -> GradientTexture2D:
	if _halo == null:
		var ramp := Gradient.new() # 两段过渡避免亮斑出现硬圆边。
		ramp.offsets = PackedFloat32Array([0.0, 0.26, 0.65, 1.0])
		ramp.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.40), Color(1, 1, 1, 0.08), Color(1, 1, 1, 0)])
		_halo = GradientTexture2D.new()
		_halo.gradient = ramp
		_halo.width = 64
		_halo.height = 64
		_halo.fill = GradientTexture2D.FILL_RADIAL
		_halo.fill_from = Vector2(0.5, 0.5)
		_halo.fill_to = Vector2(1.0, 0.5)
	return _halo

## [param value] 为归一化时间；首尾速度连续，用于入场、消散和悬停。
static func smooth(value: float) -> float:
	var t: float = clampf(value, 0.0, 1.0) # 五次曲线的两端加速度也归零。
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)

## [param value] 为归一化时间；快速放射后柔和减速，避免匀速硬停。
static func out_cubic(value: float) -> float:
	return 1.0 - pow(1.0 - clampf(value, 0.0, 1.0), 3.0)
