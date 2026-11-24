## 战斗中的单指划过拾取；只调用掉落物原有 collect，入账仍由原对象负责。
## 按连续线段命中按钮，避免低帧率或快速滑动越过小物件。
extends Node

## 只有明确登记的阳光、金币、材料及礼盒参与，不自动触发奖杯和关卡按钮。
const PICKUP_GROUP: StringName = &"touch_collectibles"
## 滑过时额外容许的边距，单位是视口逻辑像素；点按仍使用原按钮范围。
const SWEEP_MARGIN := 8.0
## 由引擎选中的触点必须从可交互战场开始。
var _tracking := false
## 最近一次有效触点在战斗画布上的位置，已应用环境折射。
var _previous := Vector2.ZERO

## [param what] 为暂停、退后台或失焦通知；恢复后必须重新按下，不能续接旧手势。
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_tracking = false

## [param event] 使用引擎从主触点生成的按压和移动，同战斗按钮共用折射映射。
## 原始触控事件可能被折射层消费，且系统触点编号不保证从零开始。
func _input(event: InputEvent) -> void:
	if event.device != InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_tracking = event.pressed and not event.canceled and _can_sweep(event.position)
		_previous = event.position
	elif event is InputEventMouseMotion and _tracking:
		if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT) or not _can_sweep(event.position):
			_tracking = false
			return
		var previous: Vector2 = _previous # 只连接这次按压之后的连续触点。
		_previous = event.position
		if previous != event.position:
			_sweep(previous, event.position)

## [param point] 使用本次触点坐标。持卡、持工具、暂停、切场和模态界面中止滑拾。
func _can_sweep(point: Vector2) -> bool:
	var game: Node = Global.main_game # 工具管理器和掉落物必须属于同一战场。
	if get_tree().paused or not is_instance_valid(game) or not game.is_ancestor_of(self) \
			or game.hand_manager.has_active_board_action():
		return false
	var transition: Node = game.get_node_or_null("SceneTransition") # 使用本场景的切场输入锁。
	var dialog := game.get_node_or_null("%Dialog") as Control # 未暂停的原版提示也会挡住操作。
	if (transition != null and transition.busy) or PVZCheat.is_open() \
			or (is_instance_valid(dialog) and dialog.is_visible_in_tree()):
		return false
	var hovered: Control = get_viewport().gui_get_hovered_control() # 引擎可能尚未更新本次事件的悬停。
	if hovered == null:
		return true
	var local: Vector2 = hovered.get_global_transform_with_canvas().affine_inverse() * point # 旧控件已不在触点下时不能拦住本次滑动。
	if not Rect2(Vector2.ZERO, hovered.size).has_point(local):
		return true
	var ancestor: Node = hovered # 格子及掉落按钮仍属于战场。
	while ancestor != null and ancestor != game:
		if ancestor.is_in_group(PICKUP_GROUP) or ancestor is PlantCell:
			return true
		ancestor = ancestor.get_parent()
	return false

## [param from]、[param to] 为同一手指的连续视口坐标，按各按钮实际画布变换命中。
func _sweep(from: Vector2, to: Vector2) -> void:
	for pickup: Node in get_tree().get_nodes_in_group(PICKUP_GROUP): # 仅本局可交互且尚未收集的实体。
		if not Global.main_game.is_ancestor_of(pickup) or pickup.is_queued_for_deletion() \
				or not pickup.can_process():
			continue
		var button: BaseButton = pickup.get_node_or_null("Button") as BaseButton # 阳光、金币和材料统一按钮名。
		if button == null:
			button = pickup.get_node_or_null("TextureButton") as BaseButton # 原版花园植物礼盒。
		if not is_instance_valid(button) or button.is_queued_for_deletion() \
				or not button.is_visible_in_tree() or button.disabled:
			continue
		var transform: Transform2D = button.get_global_transform_with_canvas() # 兼容缩放、相机与 CanvasLayer。
		if is_zero_approx(transform.determinant()):
			continue
		var inverse: Transform2D = transform.affine_inverse() # 触点换算到掉落按钮的局部坐标。
		var margin := Vector2(SWEEP_MARGIN / transform.x.length(), SWEEP_MARGIN / transform.y.length()) # 大小不同的物件使用相同的屏幕容差。
		var bounds := Rect2(-margin, button.size + 2.0 * margin) # 放宽四边，拾取仍走原收集入口。
		if _crosses_rect(inverse * from, inverse * to, bounds):
			pickup.collect()

## [param from]、[param to] 为按钮局部线段；[param rect] 是按钮的实际可点范围。
## 两端都在范围外时仍检查四条边，快速划过不漏收。
static func _crosses_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	if rect.has_point(from) or rect.has_point(to):
		return true
	var corners := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y)]) # 顺时针四角。
	for index: int in range(4): # 线段与任一边相交即命中。
		if Geometry2D.segment_intersects_segment(from, to, corners[index], corners[(index + 1) % 4]) != null:
			return true
	return false
