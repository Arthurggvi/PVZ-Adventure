## 幻影克拉托斯的蓄力和飞行画笔。由调用者的画布按需重绘。
extends RefCounted

## 原版 55×48 西瓜贴图，保留幻影中可辨认的瓜皮纹路。
const MELON_TEXTURE := preload("res://assets/reanim/Melonpult_melon.png")
## 原版西瓜贴图的居中像素范围。
const MELON_RECT := Rect2(-27.5, -24.0, 55.0, 48.0)
## 幻影轮廓的半透明紫光。
const VIOLET := Color(0.68, 0.41, 0.96)
## 蓄力汇聚和飞行前缘的薄荷高光。
const MINT := Color(0.72, 1.0, 0.87)


## 幻影本体共享一个惰性材质，使用原瓜皮亮度着色，不为每枚弹重新编译。
static var _core_material: ShaderMaterial

## 在第一枚幻影离手时准备紫色瓜皮，保留原生纹路和透明边界。
static func core_material() -> ShaderMaterial:
	if _core_material == null:
		var shader := Shader.new() # 只有幻影需要这一次画布编译。
		shader.code = """
shader_type canvas_item;
render_mode unshaded;
void fragment() {
	vec4 sample_color = texture(TEXTURE, UV);
	float luminance = dot(sample_color.rgb, vec3(0.28, 0.65, 0.07));
	vec3 shadow = vec3(0.14, 0.08, 0.31);
	vec3 rind = vec3(0.66, 0.47, 1.0);
	vec3 light = vec3(0.84, 0.96, 1.0);
	vec3 palette = mix(shadow, rind, smoothstep(0.06, 0.68, luminance));
	COLOR = vec4(mix(palette, light, 0.7 * smoothstep(0.67, 0.91, luminance)), COLOR.a * 0.97);
}
"""
		_core_material = ShaderMaterial.new()
		_core_material.shader = shader
	return _core_material


## 在 [param item] 的绘制回调中以局部坐标 [param center] 为瓜心绘制蓄力光弧。
## [param progress] 限制在 0 到 1。完成前光弧逐渐收拢，结束时恢复默认绘制变换。
static func draw_charge(item: CanvasItem, center: Vector2, progress: float) -> void:
	var charge := clampf(progress, 0.0, 1.0) # 蓄力计时的规范化进度。
	if charge <= 0.0:
		return
	var strength := smoothstep(0.0, 0.88, charge) # 前段柔和淡入，末段维持亮度。
	var radius := lerpf(42.0, 29.0, charge) # 从瓜外收拢到接近瓜皮，单位为局部像素。
	var sweep := TAU * (0.14 + 0.66 * charge) # 明弧覆盖范围随蓄力增加。
	var tip := TAU * charge - PI * 0.5 # 亮点在一轮蓄力中沿瓜皮转一圈。
	item.draw_set_transform(center, 0.0, Vector2(1.0, 0.83))
	item.draw_arc(Vector2.ZERO, radius, tip - sweep, tip, 24, Color(VIOLET, 0.66 * strength), 4.0, true)
	item.draw_arc(Vector2.ZERO, radius, tip - sweep * 0.57, tip, 16, Color(MINT, 0.95 * strength), 1.8, true)
	item.draw_arc(Vector2.ZERO, radius + 6.0, tip + 0.62, tip + 1.94, 10,
		Color(VIOLET, 0.48 * strength), 1.5, true)
	for index: int in range(4): # 四颗瓜籽形亮点错相汇聚，位置不消耗战斗随机数。
		var orbit := tip - float(index) * TAU / 4.0 # 当前亮点的环绕角度，单位为弧度。
		# 晚收拢的亮点保持稍大的半径，让四颗亮点留出间距。
		var point := Vector2.from_angle(orbit) * (radius + 4.0 + float(index) * (1.0 - charge) * 2.0)
		# 随圈收缩的尾迹沿公转切线拉长。
		var tangent := Vector2.from_angle(orbit + PI * 0.5)
		item.draw_line(point - tangent * (3.0 + 5.0 * charge), point, Color(MINT, strength * 0.8), 2.0, true)
	item.draw_set_transform(Vector2.ZERO)


## 在 [param item] 的绘制回调中，从局部轨迹点 [param far]、[param middle]、[param close] 依次绘制残影。
## 实弹中心在局部原点。[param angle] 是轨迹向前切线的局部弧度角，亮弧贴在前缘外侧。
## 近似重合实弹的残影省略，结束时恢复默认绘制变换。
static func draw_flight(item: CanvasItem, close: Vector2, middle: Vector2, far: Vector2, angle: float) -> void:
	_draw_echo(item, far, angle - 0.40, 0.47, VIOLET, 0.32)
	_draw_echo(item, middle, angle - 0.18, 0.65, VIOLET, 0.48)
	_draw_echo(item, close, angle + 0.05, 0.82, MINT, 0.64)
	item.draw_set_transform(Vector2.ZERO)
	item.draw_arc(Vector2.ZERO, 30.0, angle - 1.03, angle + 1.03, 15, Color(VIOLET, 0.84), 4.0, true)
	item.draw_arc(Vector2.ZERO, 30.0, angle - 0.78, angle + 0.35, 10, Color(MINT, 0.97), 1.8, true)


## 在 [param item] 的 [param point] 绘制一层原生瓜皮残影及半圈轮廓。
## [param rotation] 以弧度表示局部朝向，[param size_scale] 是贴图比例，
## [param tint] 和 [param opacity] 描述层的色调和透明度。保留变换供调用者继续绘制。
static func _draw_echo(item: CanvasItem, point: Vector2, rotation: float, size_scale: float,
		tint: Color, opacity: float) -> void:
	if point.length_squared() < 1.0:
		return
	item.draw_set_transform(point, rotation, Vector2.ONE * size_scale)
	item.draw_texture_rect(MELON_TEXTURE, MELON_RECT, false, Color(tint, opacity))
	item.draw_arc(Vector2.ZERO, 26.0, 1.56, 4.76, 13, Color(tint, opacity * 0.86), 2.0, true)
