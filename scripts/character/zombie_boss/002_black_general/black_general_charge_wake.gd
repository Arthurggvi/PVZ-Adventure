## 连续的冲锋轨迹。前端追随冲锋者，尾端沿走过的路线自行耗散。
extends Node2D
class_name BlackGeneralChargeWake

## 绘制烟层、地面余火和掠过烟中的火线。
const WAKE_SHADER: Shader = preload("res://shaders/black_general_charge_wake.gdshader")
## 烟带的固定画布高度和地面相对偏移，单位像素。
const DRAW_HEIGHT: float = 186.0
## 画布上缘高出地面的像素数，与着色器的地面位置对应。
const TOP_OFFSET: float = 159.0
## 本体的最大可见尾迹长度，单位像素；分路黑影按强度缩短。
const MAX_LENGTH: float = 440.0

## 本段轨迹开始的世界横坐标。
var _origin_x: float
## 轨迹限制的最大世界宽度。
var _max_width: float
## 随前端推进更新范围的绘制节点。
var _canvas: ColorRect
## 可选的地形高度查询，精确坡面直接绘制可弯折的轨迹。
var _ground: MainGameSlope
## 冲锋起点相对平地的高度，单位世界像素。
var _origin_height: float = 0.0
## 当前轨迹前端的世界横坐标。
var _head_x: float
## 当前已经扫过且仍可见的世界宽度。
var _visible_width: float = 0.0
## 每段轨迹拥有自己的时间、强度和退场进度。
var _ink: ShaderMaterial
## 已消耗的战斗时间。
var _elapsed: float = 0.0

## 把轨迹挂在 [param host] 下，以 [param feet] 为右端起点。
## [param depth] 为绝对绘制层级，[param strength] 控制宽度、亮度和退场时长。
## [param ground] 可选地形，烟带在坡脚和坡顶处分段以保持火线贴地。
static func spawn(host: Node2D, feet: Vector2, depth: int, strength: float,
		ground: MainGameSlope = null) -> BlackGeneralChargeWake:
	var wake := BlackGeneralChargeWake.new() # 冲锋的连续烟带，与定格姿势独立。
	wake.top_level = true
	wake.z_as_relative = false
	wake.z_index = depth
	host.add_child(wake)
	wake.global_position = feet
	wake._origin_x = feet.x
	wake._max_width = MAX_LENGTH * lerpf(0.45, 1.0, strength)
	wake._ink = ShaderMaterial.new()
	wake._ink.shader = WAKE_SHADER
	wake._ink.set_shader_parameter(&"strength", strength)
	wake._ground = ground
	if is_instance_valid(ground):
		wake._origin_height = ground.get_all_slope_y(feet.x)
		wake.material = wake._ink
	else:
		wake._canvas = ColorRect.new()
		wake._canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wake._canvas.position.y = -TOP_OFFSET
		wake._canvas.material = wake._ink
		wake.add_child(wake._canvas)
	return wake

## 将火线的左端移动到 [param head_x]，只显示已经扫过的路段。
func follow(head_x: float) -> void:
	var width_px: float = clampf(_origin_x - head_x, 0.0, _max_width) # 停在起点时保持空轨迹。
	if _canvas != null:
		_canvas.position.x = head_x - _origin_x
		_canvas.size = Vector2(width_px, DRAW_HEIGHT)
	else:
		_head_x = head_x
		_visible_width = width_px
		queue_redraw()
	_ink.set_shader_parameter(&"width_px", maxf(width_px, 1.0))

## 按已扫过的坡面折点绘制烟带，每段沿用整条火线的连续纹理坐标。
func _draw() -> void:
	if not is_instance_valid(_ground) or _visible_width <= 0.0:
		return
	var right: float = _head_x + _visible_width # 尾端最多延伸到起点或可见长度上限。
	var left: float = _head_x # 从冲锋前端开始逐段铺开。
	for slope: Slope in _ground.all_slopes: # 父坡面按世界横坐标从左到右登记。
		for edge: float in [slope.slope_global_pos_x_range.x, slope.slope_global_pos_x_range.y]: # 严格切在烟带内部的折点。
			if edge > left and edge < right:
				_draw_ground_strip(left, edge)
				left = edge
	_draw_ground_strip(left, right)

## 将 [param left] 与 [param right] 之间的一段烟带投影到线性坡面。
func _draw_ground_strip(left: float, right: float) -> void:
	var top_left := Vector2(left - _origin_x, _ground.get_all_slope_y(left) - _origin_height - TOP_OFFSET) # 左端画布上角。
	var top_right := Vector2(right - _origin_x, _ground.get_all_slope_y(right) - _origin_height - TOP_OFFSET) # 右端画布上角。
	var height := Vector2(0.0, DRAW_HEIGHT) # 垂直于屏幕 X 的烟带高度。
	var u_left: float = (left - _head_x) / _visible_width # 本段左边在整条火线的纹理进度。
	var u_right: float = (right - _head_x) / _visible_width # 本段右边在整条火线的纹理进度。
	draw_colored_polygon(PackedVector2Array([top_left, top_right, top_right + height, top_left + height]),
		Color.WHITE, PackedVector2Array([Vector2(u_left, 0.0), Vector2(u_right, 0.0),
			Vector2(u_right, 1.0), Vector2(u_left, 1.0)]))

## 停止延伸，让火线和烟层在 [param duration] 个战斗秒内耗散。
func retire(duration: float) -> void:
	var decay := create_tween() # 轨迹仍固定在地面，耗散完毕才释放。
	decay.tween_method(_set_energy, 1.0, 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	decay.tween_callback(queue_free)

## [param energy] 是当前留在场地上的黑焰强度。
func _set_energy(energy: float) -> void:
	_ink.set_shader_parameter(&"energy", energy)

## [param delta] 推进烟带流动，不改变已记录的冲锋路线。
func _process(delta: float) -> void:
	_elapsed += delta
	_ink.set_shader_parameter(&"elapsed", _elapsed)
