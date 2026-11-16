## 普通僵尸的水体表现；接触聚合由 WaterContactArea 管理。
extends SwimBoxComponent
class_name SwimBoxComponentNorm

## 普通游泳分件相对陆地姿态的下移像素数。
const SWIM_DEPTH: float = 30.0

## 本次入水前的身体基准高度，不使用每次叠加/减去 30 的漂移算法。
var _dry_body_y: float = 0.0
## 第一段入水前才捕获基准；表现过渡中离开不会重算基准。
var _has_dry_body_y: bool = false
## 当前唯一的出入水过渡，反向切换时先取消。
var _swim_tween: Tween
## 海草僵尸从池底上浮时由当前过渡持有临时遮罩。
var _rising_from_pool: bool = false
## 异步完成代号，失效的入水过渡不能在出水后重新发送 true。
var _transition: int = 0

## [param swimming] 为是否仍接触任一水体；重复水域不重复播放下沉。
func _on_water_contact_changed(swimming: bool) -> void:
	_transition += 1
	var generation: int = _transition # 本次过渡身份。
	_stop_swim_transition()
	if not _has_dry_body_y:
		_dry_body_y = body.pose_position.y
		_has_dry_body_y = true
	_apply_swim_art(swimming)
	appear_splash()
	_swim_tween = create_tween()
	if swimming and owner.is_seaweed:
		_rising_from_pool = true
		body.body_mask_start()
		body.pose_position.y = _dry_body_y + SWIM_DEPTH + 100.0
		_swim_tween.tween_property(body, ^"pose_position:y", _dry_body_y + SWIM_DEPTH, 1.0)
		_swim_tween.tween_callback(_finish_pool_rise)
		signal_change_is_swimming.emit(true)
		return
	_swim_tween.tween_property(body, ^"pose_position:y", _dry_body_y + (SWIM_DEPTH if swimming else 0.0), 0.5)
	if not swimming:
		signal_change_is_swimming.emit(false)
		return
	await _swim_tween.finished
	if generation == _transition and water_contact_area.touching_water and not swim_pose_locked:
		signal_change_is_swimming.emit(true)

## 捕获与死亡接管身体前停止出入水过渡，并释放原上浮遮罩。
func lock_swim_pose() -> void:
	super()
	_stop_swim_transition()
	if owner.is_death and _has_dry_body_y and not water_contact_area.touching_water:
		body.pose_position.y = _dry_body_y # 已离开水域的尸体使用完整陆地姿态。
		shadow.show()

## 水中死亡从标准游泳高度播放 [param state]，以 [param frame_rate] 帧每秒推进。
## 入水途中死亡也把白浪放在水线上。
func play_water_death(state: StringName, frame_rate: float) -> void:
	if _has_dry_body_y:
		body.pose_position.y = _dry_body_y + SWIM_DEPTH
	super(state, frame_rate)

## 取消当前过渡，避免晚到的上浮或出水补间覆盖死亡姿态。
func _stop_swim_transition() -> void:
	if _swim_tween != null:
		_swim_tween.kill()
		_swim_tween = null
	_finish_pool_rise()

## 只释放珊瑚僵尸上浮时设置的遮罩。
func _finish_pool_rise() -> void:
	if _rising_from_pool:
		_rising_from_pool = false
		body.body_mask_end()

## 切换 [param swimming] 的已有美术部件，不修改原共享 ResourceBodyChange。
func _apply_swim_art(swimming: bool) -> void:
	if body_change_swim == null:
		return
	for path: NodePath in body_change_swim.sprite_disappear: # 入水隐藏的部件。
		var sprite: CanvasItem = get_node(path) as CanvasItem # 原资源声明的节点。
		sprite.visible = not swimming
	for path: NodePath in body_change_swim.sprite_appear: # 入水显示的部件。
		var sprite: CanvasItem = get_node(path) as CanvasItem # 原资源声明的节点。
		sprite.visible = swimming
