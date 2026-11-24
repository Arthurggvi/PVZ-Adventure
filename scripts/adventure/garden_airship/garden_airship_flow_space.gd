## 花园飞艇各风场订阅者共用的横向速度及深度投影标尺。
extends RefCounted

## 表现速度以宽 1920 的实际可见战场为参考，黑边不进入换算。
const REFERENCE_WIDTH: float = 1920.0

## 返回从参考画幅像素换成战场世界像素的倍率。
## [param view_width] 是实际有效视口宽，[param canvas] 是对应画层世界到画布的变换。
## [param direction] 为单位流向；只使用向量基，不把画布平移计入速度。
static func reference_to_world(view_width: float, canvas: Transform2D,
		direction: Vector2 = Vector2.RIGHT) -> float:
	var basis_scale: float = canvas.basis_xform(direction).length() # 各 CanvasLayer 可采用真实独立缩放。
	return view_width / REFERENCE_WIDTH / maxf(0.01, basis_scale)

## 把 [param distance] 的虚拟航迹按 [param focal] 和虚拟纵深 [param depth] 投到基准画面。
## 返回交给后续虚拟姿态变换的有符号像素位移，深度由此只计算一次。
static func project_travel(distance: float, focal: float, depth: float) -> float:
	return distance * focal / maxf(0.01, depth)
