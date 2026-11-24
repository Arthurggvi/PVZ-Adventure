## 单束柱底的弧长采样和支裂纹。坐标始终是世界像素，时间是战斗秒。
extends RefCounted

## 每束保留的主裂纹节点上限，含冷却窗口左侧用于插值的端点。
const MAX_KNOTS := 144
## 单束可同时保留的分叉上限。
const MAX_BRANCHES := 12
## 每条支裂纹由三段有方向区别的直线连接。
const BRANCH_KNOTS := 4
## 相邻规则样点的格宽比例。
const STEP_IN_CELLS := 0.10
## 插点边界允许的世界弧长舍入误差，单位像素。
const ARC_EPSILON := 0.00001

## xy 为扰动后的中心，z 为战斗出生时刻，w 为累计世界弧长。
var knots := PackedVector4Array()
## 与主纹节点对齐，穿出粗裁区域再回来时另编一段，禁止跨段连接。
var runs := PackedInt32Array()
## 当前仍参与网格的第一个样点，避免对主数组反复前移。
var first := 0
## 每四个世界坐标为一组独立的支裂纹折线。
var branch_points := PackedVector2Array()
## x 为出生时刻，y 为起始弧长，z 为初始宽度，w 为稳定材质种子。
var branches := PackedVector4Array()
## 由施法序号和束号决定，整道轨迹有效期内保持不变。
var seed: int
## 棋盘的世界格距，供取样步距和分叉尺寸共用。
var _cell_span: float
## 固定横截面采样步距，单位世界像素。
var _spacing: float
## 用支裂纹可延伸的距离扩张后的世界粗裁边界。
var _bounds: Rect2
## 上一次收到的真实柱底世界中心。
var _previous: Vector2
## 上一次收到柱底位置的战斗时刻。
var _previous_time: float
## 之前非零位移的方向，用于在急转处补节点。
var _heading := Vector2.ZERO
## 最近一个持久化节点的未扰动世界坐标。
var _sample_at: Vector2
## 截至上一次接触点的累计世界弧长。
var _arc := 0.0
## 当前连接段编号，出界再返回时递增。
var _run := 0
## 上一输入仍在粗裁边界内，可沿既有连接段延伸。
var _inside_run := false
## 真正触地后才开始采样，原地停留不会反复重新出生。
var _started := false

## 创建这道裂隙。[param origin]、[param floor_bounds]、[param cell_span] 使用世界像素。
## [param now] 是开始时的战斗时刻，[param identity] 是本轮唯一稳定的采样种子。
func _init(origin: Vector2, now: float, cell_span: float, floor_bounds: Rect2, identity: int) -> void:
	seed = identity
	_previous = origin
	_previous_time = now
	_sample_at = origin
	_cell_span = cell_span
	_spacing = cell_span * STEP_IN_CELLS
	_bounds = floor_bounds.grow(cell_span * 0.56)

## 从上一位置向 [param point] 累积弧长，按插值后的 [param now] 写入出生时间。
## 返回是否增加了可连接的主纹节点。长距离跳帧在本帧内均匀稀释以保留整条穿越。
func sample(point: Vector2, now: float) -> bool:
	var motion: Vector2 = point - _previous # 本段唯一运动来源是两次真实柱底输入。
	var span: float = motion.length() # 决定相邻采样点的路径长度，而非帧数。
	if not _started:
		_previous_time = now
		_started = true
	if span <= 0.0001:
		_previous_time = now
		return false
	var old_count: int = knots.size() # 比较本帧实际新增的几何节点。
	var interval: Vector2 = _clip_interval(motion) # 仅保留可能在棋盘内绘制主纹或分叉的子段。
	if interval.x < interval.y:
		_sample_interval(interval, span, motion, now)
	else:
		_inside_run = false
	_arc += span # 即使离开棋盘，弧长相位也跟随真实路径。
	_heading = motion / span
	_previous = point
	_previous_time = now
	var changed: bool = knots.size() != old_count # 弧长还没到下一格时无需上传。
	first = maxi(first, knots.size() - MAX_KNOTS)
	_compact()
	return changed

## 求 [param motion] 在世界粗裁区域内的参数区间；两端离场但穿越时仍保留内部子段。
func _clip_interval(motion: Vector2) -> Vector2:
	var interval := Vector2(0.0, 1.0) # 两轴接受范围的交集。
	for axis: int in range(2): # 分别约束水平和竖直参数。
		if is_zero_approx(motion[axis]):
			if _previous[axis] < _bounds.position[axis] or _previous[axis] > _bounds.end[axis]:
				return Vector2.ZERO
			continue
		var near_t: float = (_bounds.position[axis] - _previous[axis]) / motion[axis] # 低坐标边的交点参数。
		var far_t: float = (_bounds.end[axis] - _previous[axis]) / motion[axis] # 高坐标边的交点参数。
		interval.x = maxf(interval.x, minf(near_t, far_t))
		interval.y = minf(interval.y, maxf(near_t, far_t))
	return interval

## 在接受的 [param interval] 采样真实位移 [param motion] 和长度 [param span]，[param now] 是末端时钟。
func _sample_interval(interval: Vector2, span: float, motion: Vector2, now: float) -> void:
	var start_arc: float = _arc + span * interval.x # 剪裁后的入场弧长，保留离场路程。
	var end_arc: float = _arc + span * interval.y # 剪裁后的出场弧长。
	if not _inside_run or knots.is_empty() or interval.x > 0.0:
		_run += 1
		_append_endpoint(motion, interval.x, start_arc, now)
	elif _heading.dot(motion / span) < 0.72 and _arc - knots[-1].w > _spacing * 0.32:
		_append_endpoint(motion, 0.0, start_arc, now) # 急转处留住真实折角。
	var start_index: int = floori((start_arc + ARC_EPSILON) / _spacing) + 1 # 跳过已提交的起点和离场格点。
	var end_index: int = floori((end_arc + ARC_EPSILON) / _spacing) # 最后完全跨过的规则格点。
	var stride: int = maxi(1, ceili(float(end_index - start_index + 1) / (MAX_KNOTS - 2))) # 极端速度时均匀稀释内部格点。
	for index: int in range(start_index, end_index + 1, stride): # 格点序号独立于帧数及是否离场。
		_append_sample(index, span, motion, now)
	_inside_run = interval.y >= 1.0
	if (not _inside_run or stride > 1) and end_arc - knots[-1].w > ARC_EPSILON:
		_append_endpoint(motion, interval.y, end_arc, now) # 截止端和稀释段保留完整的路径尾端。

## 回收出生时间不晚于 [param cutoff] 的轨迹。保留一个旧端点供可见边界连续插值。
## 返回已提交的主纹或支纹是否发生变化。
func expire(cutoff: float) -> bool:
	var old_first: int = first # 用首节点变化判断是否缩短了主纹。
	while first + 1 < knots.size() and knots[first + 1].z <= cutoff:
		first += 1
	var changed: bool = first != old_first # 排除单点仓位的后台回收。
	if not knots.is_empty() and knots[-1].z <= cutoff:
		knots.clear()
		runs.clear()
		first = 0
	_compact()
	var expired_branches := 0 # 分叉与其出生节点用同一时钟，按时间顺序回收。
	while expired_branches < branches.size() and branches[expired_branches].x <= cutoff:
		expired_branches += 1
	if expired_branches > 0:
		_trim_branches(expired_branches)
	return changed or expired_branches > 0

## 返回索引 [param index] 与种子 [param identity] 决定的零到一采样值。
static func unit_hash(identity: int, index: int) -> float:
	return float(hash(Vector2i(identity, index)) & 65535) / 65535.0

## 在 [param motion] 的 [param fraction] 处保存未扰动端点，携带 [param arc] 和到 [param now] 的插值出生时间。
func _append_endpoint(motion: Vector2, fraction: float, arc: float, now: float) -> void:
	_sample_at = _previous + motion * fraction
	knots.append(Vector4(_sample_at.x, _sample_at.y, lerpf(_previous_time, now, fraction), arc))
	runs.append(_run)

## 插入固定格点 [param index]；[param span]、[param motion] 为本段长度和位移，[param now] 是本段末端时钟。
func _append_sample(index: int, span: float, motion: Vector2, now: float) -> void:
	var arc: float = index * _spacing # 格点的连续世界弧长。
	var ratio: float = clampf((arc - _arc) / span, 0.0, 1.0) # 本段内的样点位置与出生时刻使用同一比例。
	var raw: Vector2 = _previous + motion * ratio # 沿真实折线插入，不依赖着色器时间。
	var direction: Vector2 = (raw - _sample_at).normalized() # 同一组规则样点稳定确定横向。
	var coarse: int = index >> 2 # 每四个样点在同一对低频扰动锚点之间过渡。
	var grain: float = lerpf(unit_hash(seed, coarse), unit_hash(seed, coarse + 1), (index & 3) * 0.25) # 石砖内的宽缓偏折。
	var chip: float = unit_hash(seed + 37, index) # 窄边近处的小尺度崩口。
	var lateral: float = ((grain - 0.5) * 0.041 + (chip - 0.5) * 0.021) * _cell_span # 限制扰动在几个世界像素。
	var center: Vector2 = raw + direction.orthogonal() * lateral # 主纹和相接的分叉共用同一中心。
	var birth: float = lerpf(_previous_time, now, ratio) # 跨帧补点仍按先后逐段冷却。
	knots.append(Vector4(center.x, center.y, birth, arc))
	runs.append(_run)
	_sample_at = raw
	if (index + seed) % 5 == 0 and unit_hash(seed + 71, index) < 0.38:
		_append_branch(center, direction, birth, arc, index)

## 从 [param center] 沿 [param direction] 分裂，[param birth]、[param arc] 继承主纹，[param index] 作为种子。
func _append_branch(center: Vector2, direction: Vector2, birth: float, arc: float, index: int) -> void:
	var mix_seed: int = seed * 17 + index # 不同段和不同光束不会复制分叉形状。
	var side: float = -1.0 if unit_hash(mix_seed, 1) < 0.5 else 1.0 # 分向主纹任意一边。
	var length_px: float = lerpf(0.17, 0.53, unit_hash(mix_seed, 2)) * _cell_span # 裂纹向地砖内延伸的总长。
	var opening: float = deg_to_rad(lerpf(27.0, 70.0, unit_hash(mix_seed, 3))) * side # 分叉相对主纹方向的夹角。
	var first_axis: Vector2 = direction.rotated(opening) # 首段从真实主裂纹中心离开。
	var second_axis: Vector2 = first_axis.rotated(lerpf(-0.42, 0.72, unit_hash(mix_seed, 4)) * side) # 第二段碰到石纹时偏折。
	if unit_hash(mix_seed, 5) < 0.28:
		# 局部砖缝视觉近似，部分分叉会短暂沿较接近的横向或纵向延伸。
		second_axis = Vector2(signf(second_axis.x), 0.0) if absf(second_axis.x) > absf(second_axis.y) else Vector2(0.0, signf(second_axis.y))
	var second: Vector2 = center + first_axis * length_px * 0.42 # 分叉第一处折角。
	var third: Vector2 = second + second_axis * length_px * 0.36 # 砖内进一步偏折。
	var tip_axis: Vector2 = second_axis.rotated(lerpf(-0.71, 0.63, unit_hash(mix_seed, 6))) # 夹杂不规则的细尖。
	var width: float = lerpf(0.30, 0.49, unit_hash(mix_seed, 7)) # 分叉明显细过主裂纹。
	if branches.size() == MAX_BRANCHES:
		_trim_branches(1)
	branch_points.append(center)
	branch_points.append(second)
	branch_points.append(third)
	branch_points.append(third + tip_axis * length_px * 0.22)
	branches.append(Vector4(birth, arc, width, unit_hash(mix_seed, 9)))

## 批量丢弃最前面的 [param count] 条分叉及其折线节点。
func _trim_branches(count: int) -> void:
	branches = branches.slice(count)
	branch_points = branch_points.slice(count * BRANCH_KNOTS)

## 批量回收主纹数组里已过期的前缀，避免每次增加样点都移动数组。
func _compact() -> void:
	if first >= 24:
		knots = knots.slice(first)
		runs = runs.slice(first)
		first = 0
