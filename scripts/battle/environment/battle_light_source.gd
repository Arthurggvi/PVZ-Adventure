## 一盏战场局部灯。可见圆心、地面垂足和虚拟高度使用相同世界长度单位。
extends RefCounted

## 灯面四边形相对名义半径的外沿余量。
const EDGE_MARGIN := 1.09
## 红晕在灯片坐标内靠近有效边缘的羽化宽度，与灯片材质约定一致。
const FOOTPRINT_FEATHER := 0.112

## 发光精灵或鼠标位置。
var anchor: Node2D
## 发光点相对 [member anchor] 的坐标。
var offset: Vector2
## 可选的地面垂足。鼠标微光不设置。
var ground_anchor: Node2D
## 名义光圈半径，单位世界像素。
var radius: float
## 用于绘制边界与遮罩图集映射的保守半径。
var reach: float
## 局部红晕的世界裁剪区域。空矩形使用标准点光。
var footprint := Rect2()
## 散晕前沿扩张时中心能量逐步让给外侧，范围零至一。
var spread := 0.0
## 局部收束的红晕会短暂压低同处的暖色表现。
var absorbing := false
## 0 为指针冷光，1 为暖光，2 为红光，3 为演出白光。
var tone: int
## 环境亮度权重，范围零至一。
var intensity := 1.0
## 是否纳入棋盘光照判定，纯演出灯只参与渲染和投影。
var affects_gameplay := true
## 短时的强演出灯优先占用可见灯的投影格。
var shadow_priority := false
## 固定的灯缘扰动种子。
var seed: float
## 负责这一盏灯的实例标识。灯被移除后仍用于诊断换灯状态。
var id: int
## 当前帧可见的发光点。
var center: Vector2
## 当前帧的地面垂足。
var ground: Vector2
## 灯的虚拟高度。非投影光源为零。
var height: float
## 有限光源的半径，用于估计远端半影宽度。
var source_radius: float
## 本帧遮挡图集的灯格索引。负数表示这一盏灯作为未遮挡补光。
var shadow_slot := -1

## 更新实际发光中心。离树、隐藏或熄灭的光源不提供局部照明。
func refresh_center() -> bool:
	if not is_instance_valid(anchor) or not anchor.is_visible_in_tree() or anchor.is_queued_for_deletion() or intensity <= 0.0:
		return false
	center = anchor.to_global(offset)
	return true

## 在 [param point] 采样与战场灯片相同的衰减函数，返回零至一的入射权重。
func coverage_at(point: Vector2) -> float:
	var local: Vector2 = (point - center) / radius # 灯片中以名义半径归一化的坐标。
	local.y = -local.y # 衰减沿用原 QuadMesh 的纹理纵轴。局部阴影另按地面轴采样。
	var distance: float = local.length() # 先排除超出四边形保守外沿的点。
	if distance >= EDGE_MARGIN:
		return 0.0
	var phase: float = seed * TAU # 和灯片使用相同的固定扰动。
	var ripple: float = sin(local.dot(Vector2(4.6, 7.0)) + phase) * sin(local.dot(Vector2(7.1, -3.3)) - phase) # 相交的低频光缘。
	var edge: float = 1.0 + (0.053 * ripple - 0.034) * smoothstep(0.26, 0.77, distance) # 局部光缘。
	var d: float = distance / edge # 包含光缘起伏的衰减距离。
	var falloff_rate: float = 6.2 if tone == 0 else 3.8 # 指针光收得更快，红光与暖光共享衰减。
	var falloff: float = pow(2.0, -falloff_rate * d * d) # 与灯片使用相同的距离曲线。
	var coverage: float = intensity * falloff * (1.0 - smoothstep(0.25, 1.0, d)) * (
		1.0 - (0.14 - 0.10 * ripple) * smoothstep(0.15, 0.73, distance)
	)
	if footprint.has_area():
		var margin: Vector2 = (point - footprint.position).min(footprint.end - point) # 到真实受击区最近边的距离。
		var feather: float = FOOTPRINT_FEATHER * reach * 2.0 # 灯片归一化羽化距离换回世界长度。
		coverage *= smoothstep(0.0, feather, margin.x) * smoothstep(0.0, feather, margin.y)
		coverage *= 1.0 - spread * 0.53 * (1.0 - smoothstep(0.10, 0.54, d))
	return coverage
