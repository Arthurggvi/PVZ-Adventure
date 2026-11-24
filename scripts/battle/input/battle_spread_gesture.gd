## 只记录战斗双指张开的距离和生命周期；输入分流与实际施放由宿主负责。
## 明确张开后才认领输入，随后到全部抬起保持所有权，每次手势最多提交一次意图。
extends RefCounted

## 双指起始间距的下限，单位为视口逻辑像素；过近的触点整次作废。
const MINIMUM_START_SPAN := 24.0
## 按初始间距计算距离门槛的比例；实际门槛另受视口短边上限约束。
const MINIMUM_RELATIVE_GROWTH := 0.12
## 张开距离的绝对下限，单位为视口逻辑像素。
const MINIMUM_ABSOLUTE_GROWTH := 24.0
## 以视口短边计算额外距离门槛的比例，兼容不同逻辑分辨率。
const VIEWPORT_GROWTH_RATIO := 0.04
## 相对初始间距的门槛最多占视口短边的比例，避免宽起点要求过大位移。
const MAXIMUM_RELATIVE_GROWTH_VIEWPORT_RATIO := 0.07
## 每指沿初始连线向外移动的最小投影，单位为视口逻辑像素。
const MINIMUM_FINGER_OUTWARD_GROWTH := 6.0
## 每指向外投影至少达到总距离门槛的比例，允许两指不等距张开。
const FINGER_OUTWARD_GROWTH_RATIO := 0.15

## 当前仍按下的触点及其原始视口位置；触点编号不要求连续或从零开始。
var _contacts: Dictionary[int, Vector2] = {}
## 本次接触序列是否已确认张开并认领输入；只在全部抬起或显式重置时解除。
var _claimed := false
## 本次手势是否失去施放资格；补回手指不会恢复资格。
var _invalidated := false
## 本次手势是否已经提交过施放意图，与实际技能是否成功无关。
var _attempted := false
## 第二指首次落下时的间距，单位为视口逻辑像素。
var _initial_span := 0.0
## 第二指落下时两个触点各自的位置；触点补回或继续移动不能重建基线。
var _initial_positions: Dictionary[int, Vector2] = {}
## 每个触点沿初始连线背离另一指的单位方向，用于排除平移和单指移动。
var _outward_axes: Dictionary[int, Vector2] = {}


## 记录 [param event] 中的原始触点，其他事件不修改状态。
## 第二指只建立候选，不认领输入；最后一指结束时自动清空整个序列。
func update(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event # 移动只更新已知触点，不能凭拖动事件补造按下。
		if _contacts.has(drag.index):
			_contacts[drag.index] = drag.position
		return
	if not event is InputEventScreenTouch:
		return
	var touch: InputEventScreenTouch = event # 按下、抬起与系统取消共用同一个触点编号。
	if touch.canceled:
		_invalidated = true
	if not touch.pressed or touch.canceled:
		if _contacts.has(touch.index) and not _initial_positions.is_empty():
			_invalidated = true
		_contacts.erase(touch.index)
		if _contacts.is_empty():
			reset()
		return
	_contacts[touch.index] = touch.position
	if _contacts.size() > 2:
		_invalidated = true
	if not _invalidated and _initial_positions.is_empty() and _contacts.size() == 2:
		_begin_candidate()


## 返回本次接触序列是否已由双指操作接管，包括失效后等待剩余手指抬起的阶段。
func is_claimed() -> bool:
	return _claimed


## 返回是否仍有按下的触点，供宿主维持残留事件的隔离。
func has_contacts() -> bool:
	return not _contacts.is_empty()


## 返回触点位置的独立字典，宿主可据此取消既有 GUI 按压而不修改识别状态。
func contact_positions() -> Dictionary:
	return _contacts.duplicate()


## 宿主可每帧或在真实抬起事件更新前调用，只有两指都明确向外移动才确认候选。
## [param viewport_size] 为原始触点所在的逻辑视口尺寸，用于计算总距离与每指投影门槛。
## 返回 true 前同时锁存尝试和所有权；实际效果失败也不能在同一次手势中重试。
func take_activation(viewport_size: Vector2) -> bool:
	if _invalidated or _attempted or _contacts.size() != 2 or _outward_axes.size() != 2:
		return false
	var growth: float = _contact_span() - _initial_span # 两指相对首次共同按下时增加的实际间距。
	var viewport_short_side: float = maxf(0.0, minf(viewport_size.x, viewport_size.y)) # 短边统一横竖屏门槛。
	var relative_threshold: float = minf(_initial_span * MINIMUM_RELATIVE_GROWTH,
		viewport_short_side * MAXIMUM_RELATIVE_GROWTH_VIEWPORT_RATIO) # 限制宽起点额外要求的距离。
	var threshold: float = maxf(MINIMUM_ABSOLUTE_GROWTH,
		maxf(viewport_short_side * VIEWPORT_GROWTH_RATIO, relative_threshold)) # 总增量取三个门槛的最大值。
	if growth < threshold:
		return false
	var finger_threshold: float = maxf(MINIMUM_FINGER_OUTWARD_GROWTH,
		threshold * FINGER_OUTWARD_GROWTH_RATIO) # 双指各自须主动向外，但不要求对称移动。
	for contact_id: int in _initial_positions: # 用原始触点编号关联每指的起点与向外方向。
		var displacement: Vector2 = _contacts[contact_id] - _initial_positions[contact_id] # 每指的累计位移。
		if displacement.dot(_outward_axes[contact_id]) < finger_threshold:
			return false
	_attempted = true
	_claimed = true
	return true


## 取消当前手势的施放资格，保留触点与已取得的所有权直到全部抬起；空闲时无副作用。
func invalidate() -> void:
	if not _contacts.is_empty():
		_invalidated = true


## 离场或失焦时彻底释放触点和所有权；之后必须从新的按下事件重新开始。
func reset() -> void:
	_contacts.clear()
	_claimed = false
	_invalidated = false
	_attempted = false
	_initial_span = 0.0
	_initial_positions.clear()
	_outward_axes.clear()


## 用第二指落下时的两指位置建立起点和向外方向；过近的起点整次作废。
func _begin_candidate() -> void:
	var contact_ids: Array = _contacts.keys() # 触点编号不要求连续，也不依赖从零开始。
	var first_id: int = contact_ids[0] # 初始连线的一端。
	var second_id: int = contact_ids[1] # 初始连线的另一端。
	_initial_positions[first_id] = _contacts[first_id]
	_initial_positions[second_id] = _contacts[second_id]
	var initial_delta: Vector2 = _initial_positions[second_id] - _initial_positions[first_id] # 初始连线向量。
	_initial_span = initial_delta.length()
	if _initial_span < MINIMUM_START_SPAN:
		_invalidated = true
		return
	_outward_axes[first_id] = -initial_delta / _initial_span
	_outward_axes[second_id] = initial_delta / _initial_span


## 返回当前两个触点的间距；触点数量不为二时返回零，不能建立可施放的距离基线。
func _contact_span() -> float:
	if _contacts.size() != 2:
		return 0.0
	var positions: Array = _contacts.values() # 距离与字典枚举顺序无关，也不假设触点编号。
	var first_position: Vector2 = positions[0] # 当前两个触点中的任意一端。
	var second_position: Vector2 = positions[1] # 另一端与第一端共同确定双指间距。
	return first_position.distance_to(second_position)
