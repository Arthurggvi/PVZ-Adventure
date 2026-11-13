## 选卡重排的实例级动画所有权；新移动替代旧移动，旧回调不能把卡片挂回错误位置。
extends RefCounted
class_name CardSelectionMotion

## 每张卡当前有效的移动序号，实例 ID 不随候选页或显示位变化。
var _active: Dictionary[int, int] = {}
## 单调递增的本选卡界面移动序号。
var _sequence: int = 0

## [param owner] 拥有动画；[param card] 移动到 [param target]，途中挂到 [param temporary]。
## [param battle] 负责翻动显示位；[param reveal] 仅为新选中的卡移动视野，成功完成返回 true。
func move(owner: Node, card: Card, target: Control, temporary: Control,
		battle: FixedBattleCardSlots, reveal: bool) -> bool:
	if not is_instance_valid(owner) or not owner.is_inside_tree() \
			or not is_instance_valid(card) or not is_instance_valid(target):
		return false
	_sequence += 1
	var revision: int = _sequence # 本次动画独有令牌，覆盖同一卡片尚未完成的移动。
	var card_id: int = card.get_instance_id() # 字典只存身份，不延长节点生命周期。
	_active[card_id] = revision
	card.button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if card.get_parent() != temporary:
		card.reparent(temporary)
	if reveal:
		battle.reveal_slot(target)
	await owner.get_tree().process_frame
	if not _can_finish(owner, card, target, card_id, revision):
		_forget(card_id, revision)
		return false
	var tween: Tween = owner.create_tween() # 使用方法插值，过期动画继续结束但不再写入卡片。
	tween.tween_method(_step.bind(weakref(card), weakref(target), card.global_position, card_id, revision),
		0.0, 1.0, 0.2)
	await tween.finished
	if not _can_finish(owner, card, target, card_id, revision):
		_forget(card_id, revision)
		return false
	card.reparent(target, false)
	card.position = Vector2.ZERO
	card.button.mouse_filter = Control.MOUSE_FILTER_PASS
	_forget(card_id, revision)
	return true

## [param weight] 是进度；[param card_ref]、[param target_ref] 不延长卡片和目标的生命周期。
## [param card_id] 与 [param revision] 共同阻止旧动画操作释放或已重新选择的卡。
## [param origin] 保留本次起点，显示位变化后即时读取新位置，不缓存过期的屏幕坐标。
func _step(weight: float, card_ref: WeakRef, target_ref: WeakRef, origin: Vector2,
		card_id: int, revision: int) -> void:
	if int(_active.get(card_id, -1)) != revision:
		return
	var card: Card = card_ref.get_ref() as Card # 卡片销毁后不再访问其位置。
	var target: Control = target_ref.get_ref() as Control # 显示位随界面销毁时自然失效。
	if is_instance_valid(card) and is_instance_valid(target):
		card.global_position = origin.lerp(target.global_position, weight)

## [param owner]、[param card]、[param target] 必须仍在当前界面，且 [param revision] 仍拥有 [param card_id]。
func _can_finish(owner: Node, card: Card, target: Control, card_id: int, revision: int) -> bool:
	return int(_active.get(card_id, -1)) == revision and is_instance_valid(owner) and owner.is_inside_tree() \
		and is_instance_valid(card) and card.is_inside_tree() and not card.is_queued_for_deletion() \
		and is_instance_valid(target) and target.is_inside_tree() and not target.is_queued_for_deletion()

## 只清理 [param card_id] 的本次 [param revision]，不能抹去已经接管的新动画。
func _forget(card_id: int, revision: int) -> void:
	if int(_active.get(card_id, -1)) == revision:
		_active.erase(card_id)
