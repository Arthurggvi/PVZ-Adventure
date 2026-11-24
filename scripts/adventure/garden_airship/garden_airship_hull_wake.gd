## 跟随原绘船框的近身绕流，只在开口、龙骨外侧和两处桨盘下风侧绘制。
extends RefCounted

## 外围巡航轨道及两处独立桨流，按最前几项优先保留兼容档轮廓。
enum Track { RAIL, KEEL, PORT, STARBOARD }

## 船框原 Sprite2D 的局部画布尺寸。锚点以船框 Shader 加宽后的可见形状标定。
const FRAME_SIZE := Vector2(1774.0, 887.0)
## 上梁下侧的实际开口。气流从左舱后向上贴近横梁，在右弓前散开。
const RAIL := [Vector2(240, 361), Vector2(317, 301), Vector2(474, 294), Vector2(762, 305),
	Vector2(1030, 299), Vector2(1193, 298), Vector2(1270, 323), Vector2(1300, 348)]
## 龙骨外侧沿艇首、桨盘和船腹向下绕行，离艇尾后连续收束。
const KEEL := [Vector2(0, 724), Vector2(109, 825), Vector2(239, 902), Vector2(337, 923),
	Vector2(507, 880), Vector2(758, 869), Vector2(1020, 888), Vector2(1187, 915),
	Vector2(1263, 873), Vector2(1355, 795), Vector2(1480, 768)]
## 左右桨盘后下缘的可见出流点，位于换片的旋转包络之外。
const ROTORS := [Vector2(387, 867), Vector2(1240, 860)]

## 本局船框。独立预览未绑定船框时不绘制前景绕流。
var _frame: Sprite2D
## 两层经实际画布合成后的变换，画幅整体变化时仅在相对变换改变后重算。
var _frame_to_flow := Transform2D.IDENTITY
## 已投影到近身气流 Node2D 局部坐标中的上梁路径。
var _rail_points := PackedVector2Array()
## 已转换到同一近身层坐标的船底路径。
var _keel_points := PackedVector2Array()
## 两桨下风侧的可见出流点，按船左、船右排列。
var _rotor_points := PackedVector2Array()

## [param frame] 为正式关卡已有 Sprite2D，重绑时清掉旧投影。
func bind(frame: Sprite2D) -> void:
	_frame = frame
	_rail_points.clear()

## 从 [param canvas] 指定的近身层局部坐标到视口，与船框到视口的变换组合。
## 船体失效时返回 false；跟随两图层共同镜头平移时复用原投影。
func refresh(canvas: Transform2D) -> bool:
	if not is_instance_valid(_frame):
		return false
	var relative: Transform2D = canvas.affine_inverse() * _frame.get_global_transform_with_canvas() # 去掉共同相机，仍保留两个画层的真实相对关系。
	if not _rail_points.is_empty() and relative.is_equal_approx(_frame_to_flow):
		return true
	_frame_to_flow = relative
	var rect: Rect2 = _frame.get_rect() # 兼顾 Sprite2D 的居中开关、偏移和纹理大小。
	_rail_points = _project(RAIL, _rail_points, rect)
	_keel_points = _project(KEEL, _keel_points, rect)
	_rotor_points = _project(ROTORS, _rotor_points, rect)
	return true

## 按 [param rect] 中的原图显示区换算 [param anchors]，返回写入变换结果的 [param points]。
func _project(anchors: Array, points: PackedVector2Array, rect: Rect2) -> PackedVector2Array:
	points.resize(anchors.size())
	for index: int in anchors.size(): # 仅在两画层相对变换变化时投影。
		var anchor: Vector2 = anchors[index] # 船框 Shader 加宽后的实际轮廓坐标。
		points[index] = _frame_to_flow * (rect.position + anchor * (rect.size / FRAME_SIZE))
	return points

## [param track] 是否为一处始于桨盘的有界尾流轨道。
static func is_rotor(track: int) -> bool:
	return track == Track.PORT or track == Track.STARBOARD

## 取 [param track] 的桨盘出流 X 至尾迹极限；[param load] 随相对气流受力。
func rotor_bounds(track: int, load: float) -> Vector2:
	var origin: Vector2 = _rotor_points[track - Track.PORT] # 船框局部锚点转换后的流线起点。
	return Vector2(origin.x, origin.x + _frame_to_flow.x.length() * lerpf(237.0, 348.0, load))

## 取 [param track] 上 [param x] 处的横向显隐，始终给船壳和新生桨流留渐变距离。
## [param length] 为当前整条雾丝长度；[param bounds] 只供两条桨流使用。
func opacity_at(track: int, x: float, length: float, bounds: Vector2) -> float:
	if is_rotor(track):
		return smoothstep(bounds.x + length * 0.36, bounds.x + length * 0.56 + 22.0, x) \
			* (1.0 - smoothstep(bounds.y - 82.0, bounds.y, x))
	if track == Track.RAIL:
		var left: float = _rail_points[0].x # 左舱迎风包络，退至开口中才可显形。
		var right: float = _rail_points[-1].x # 右弓架前缩隐，流线不跨过实体侧梁。
		return smoothstep(left + length * 0.5, left + length * 0.5 + 55.0, x) \
			* (1.0 - smoothstep(right - length * 0.5 - 62.0, right - length * 0.5, x))
	return 1.0

## 取 [param track] 上 [param x] 的轮廓高度。
## [param offset] 是预种的轨道分离量，[param phase] 是同一风场时钟与丝束种子。
## [param bounds] 把桨流扰动限制在下风侧，外侧轮廓不读取桨流长度。
func height_at(track: int, x: float, offset: float, phase: float, bounds: Vector2) -> float:
	if is_rotor(track):
		var origin: Vector2 = _rotor_points[track - Track.PORT] # 由真实桨盘输出位置支撑的短流。
		var spread: float = smoothstep(bounds.x, bounds.y, x) # 与外界空气汇合时，短尾流略向下且缓慢展开。
		return origin.y + (15.0 + offset * 0.65) * spread + sin(phase + x * 0.038) * (2.2 + 4.4 * spread)
	var points: PackedVector2Array = _rail_points if track == Track.RAIL else _keel_points # 取对应画框包络。
	return _contour_y(points, x) + offset + sin(phase + x * 0.020) * 3.3

## 在相邻 [param points] 间按 [param x] 做 C1 连接，超出末端后延续最后一个高度。
func _contour_y(points: PackedVector2Array, x: float) -> float:
	for index: int in range(1, points.size()): # 少量有序实体轮廓采样点。
		var right: Vector2 = points[index] # 可能结束当前采样区间的轮廓点。
		if x <= right.x:
			var left: Vector2 = points[index - 1] # 片段的上风侧已知轮廓点。
			return lerpf(left.y, right.y, smoothstep(left.x, right.x, x))
	return points[-1].y
