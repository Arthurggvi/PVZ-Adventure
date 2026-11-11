## 普通僵尸的水体表现；接触聚合由 SwimBoxComponent 唯一管理。
extends SwimBoxComponent
class_name SwimBoxComponentNorm

## 本次入水前的身体基准高度，不使用每次叠加/减去 30 的漂移算法。
var _dry_body_y: float = 0.0
## 第一段入水前才捕获基准；表现过渡中离开不会重算基准。
var _has_dry_body_y: bool = false
## 当前唯一的出入水过渡，反向切换时先取消。
var _swim_tween: Tween
## 异步完成代号，失效的入水过渡不能在出水后重新发送 true。
var _transition: int = 0

## [param swimming] 为是否仍接触任一水体；重复水域不重复播放下沉。
func _on_water_contact_changed(swimming: bool) -> void:
	_transition += 1
	var generation: int = _transition # 本次过渡身份。
	if _swim_tween != null:
		_swim_tween.kill()
	if not _has_dry_body_y:
		_dry_body_y = body.position.y
		_has_dry_body_y = true
	_apply_swim_art(swimming)
	appear_splash()
	if swimming and owner.is_seaweed:
		body.position.y = _dry_body_y + 30.0
		body.zombie_body_up_from_pool()
		signal_change_is_swimming.emit(true)
		return
	_swim_tween = create_tween()
	_swim_tween.tween_property(body, "position:y", _dry_body_y + (30.0 if swimming else 0.0), 0.5)
	if not swimming:
		signal_change_is_swimming.emit(false)
		return
	await _swim_tween.finished
	if generation == _transition and _water_active and not owner_is_death:
		signal_change_is_swimming.emit(true)

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
