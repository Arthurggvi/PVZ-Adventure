## 借用正式镜头完成三次近景。所有机位仍在同一世界与光场内。
extends RefCounted

## 从原机位放大到能看到救主完整衣袍的近景倍率。
const CLOSE_SCALE := 1.60
## 镜头以人物胸口为构图中心，留出头环和地面。
const PORTRAIT_ANCHOR := Vector2(-25.0, -134.0)
## 在特写期间临时放宽场地边界，允许右侧本体居中。
const FREE_LIMIT := 10000000

## 当前正在借用的正式战斗相机。
var _camera: MainGameCamera
## 原机位的局部放大比率、世界位置及独立震动偏移。
var _base_zoom: Vector2
## 还原战斗镜头时的世界坐标。
var _base_position: Vector2
## 在黑幕下消除震动后保留的偏移。
var _base_offset: Vector2
## 原相机的左、上、右、下裁剪界限。
var _limits: Vector4i
## 一次镜头移动开始时的位姿。
var _from_position: Vector2
## 当前移动结束时的计划机位。
var _to_position: Vector2
## 一次移动开始时的缩放。
var _from_zoom: Vector2
## 本机位结束时的缩放。
var _to_zoom: Vector2

## 在全黑时取得 [param camera] 的控制和可恢复的战斗机位。
func borrow(camera: MainGameCamera) -> void:
	_camera = camera
	_camera.stop_shake()
	_base_zoom = camera.zoom
	_base_position = camera.global_position
	_base_offset = camera.offset
	_limits = Vector4i(camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom)
	camera.limit_left = -FREE_LIMIT
	camera.limit_top = -FREE_LIMIT
	camera.limit_right = FREE_LIMIT
	camera.limit_bottom = FREE_LIMIT

## 接续当前画面，靠近 [param actor] 的胸口。[param view_size] 取实际逻辑视口。
func aim_at(actor: Node2D, view_size: Vector2) -> void:
	_from_position = _camera.global_position
	_from_zoom = _camera.zoom
	_to_zoom = _base_zoom * CLOSE_SCALE
	_to_position = actor.to_global(PORTRAIT_ANCHOR) - _base_offset
	if _camera.anchor_mode == Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT:
		_to_position -= view_size * 0.5 / _to_zoom

## 用同样的缓入缓出接回原关卡机位。
func aim_home() -> void:
	_from_position = _camera.global_position
	_from_zoom = _camera.zoom
	_to_position = _base_position
	_to_zoom = _base_zoom

## 将本镜头的 [param progress] 归一化进度提交给相机，以便冻结中仍可更新光场。
func move(progress: float) -> void:
	var t: float = clampf(progress, 0.0, 1.0) # 五次曲线两端速度和加速度均归零。
	var ease: float = t * t * t * (t * (6.0 * t - 15.0) + 10.0) # 在近景之间无抖动地起落。
	_camera.zoom = _from_zoom.lerp(_to_zoom, ease)
	_camera.global_position = _from_position.lerp(_to_position, ease)
	_camera.force_update_scroll()

## 正常完成或提前离场时，都准确归还原画布变换与裁剪范围。
func restore() -> void:
	if not is_instance_valid(_camera):
		return
	_camera.zoom = _base_zoom
	_camera.global_position = _base_position
	_camera.offset = _base_offset
	_camera.limit_left = _limits.x
	_camera.limit_top = _limits.y
	_camera.limit_right = _limits.z
	_camera.limit_bottom = _limits.w
	_camera.force_update_scroll()
	_camera = null
