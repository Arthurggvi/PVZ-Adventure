## 樱桃爆燃的单格余火：焦炭、分层火舌和升腾火星共用地火控制器的时钟，不参与伤害。
extends Node2D

## 原版三帧火舌；只复用纹理，避免每格创建整套动画场景。
const FLAMES: Array[Texture2D] = [preload("res://assets/reanim/fire1.png"),
	preload("res://assets/reanim/fire2.png"), preload("res://assets/reanim/fire3.png")]
## 原版炭火图集，第一片保留完整焦黑边缘和橙色余烬。
const COALS: Texture2D = preload("res://assets/image/particles/Zombie_boss_fireball_groundparticles.png")
## 原版柔光，只在地面叠加低透明度热晕。
const GLOW: Texture2D = preload("res://assets/reanim/Zombie_boss_fireball_superglow.png")

## 该格的世界尺寸；火苗分散到格内的前后两层，不只挤在一个点上。
var cell_size: Vector2 = Vector2(80.0, 100.0)
## 稳定的格子相位，让相邻格的轮廓和燃烧节拍错开。
var variation: float = 0.0
## 普通爆燃的圆形半径；零表示聚变矩形，所有覆盖格均显示火苗。
var clip_radius: float = 0.0
## 圆形伤害中心相对于本格脚点的检测平面坐标，已排除屋顶高度。
var clip_center: Vector2 = Vector2.ZERO
## 从点燃开始的表现秒数；子母雷续燃时不重置动画相位。
var _age: float = 0.0
## 伤害控制器传入的剩余秒数，用于结束前收拢火舌。
var _remaining: float = 0.0
## 两次主爆之间的短促复燃亮度，不延长伤害时限。
var _flare: float = 0.0

## 按 [param age]、[param remaining] 战斗秒同步表现；[param flare] 为 0–1 的复燃强度。
func update_visual(age: float, remaining: float, flare: float = 0.0) -> void:
	_age = age
	_remaining = remaining
	_flare = flare
	queue_redraw()

## 每格前后各三簇火苗铺开；地面焦痕与热晕连接各簇，保持角色上半身清楚。
func _draw() -> void:
	var strength: float = smoothstep(0.0, 0.14, _age) * smoothstep(0.0, 0.32, _remaining) # 点火和退火包络。
	if strength <= 0.0:
		return
	var coal_region := Rect2(0.0, 0.0, 52.0, 17.0) # 原图集第一片，不把其他退火帧并排画出。
	for depth: int in range(2): # 后层先画，前层盖住火根形成地面纵深。
		var base_y: float = -cell_size.y * (0.62 if depth == 0 else 0.15) # 覆盖格子中部及靠近脚点的位置。
		var glow_rect := Rect2(Vector2(-cell_size.x * 0.62, base_y - 17.0), Vector2(cell_size.x * 1.24, 34.0)) # 热晕横向衔接邻格。
		if _contains_root(Vector2(0.0, base_y)):
			draw_texture_rect(GLOW, glow_rect, false, Color(1.0, 0.35, 0.07, strength * (0.20 + _flare * 0.12)))
		for cluster: int in range(3): # 每格六簇固定预算，不随等阶无限增加。
			var phase: float = variation * 1.37 + float(depth * 3 + cluster) * 2.41 # 每簇固定差异。
			var point := Vector2((float(cluster) - 1.0) * cell_size.x * 0.31 + (_noise(phase) - 0.5) * cell_size.x * 0.16,
				base_y + (_noise(phase + 7.0) - 0.5) * cell_size.y * 0.36) # 根部纵向充分错开，避免连成十条整齐的横线。
			if not _contains_root(point):
				continue
			var breadth: float = cell_size.x * (0.29 + 0.22 * _noise(phase + 13.0)) # 宽窄簇交替，焦痕不连接成黑色腰带。
			var height: float = (24.0 + 30.0 * _noise(phase + 29.0)) * minf(1.25, cell_size.y / 100.0) # 低余焰中穿插较高火舌。
			var flicker: float = 0.94 + sin(_age * 10.0 + phase) * 0.06 + _flare * 0.16 # 火根稳定，顶端起伏。
			var frame: int = int(floor(_age * 12.0 + phase)) % FLAMES.size() # 保留原版逐帧燃烧节奏。
			var coal_rect := Rect2(point + Vector2(-breadth * 0.48, -3.0), Vector2(breadth * 0.96, 9.0)) # 小片薄焦痕衬托火根，不抢占火焰轮廓。
			draw_texture_rect_region(COALS, coal_rect, coal_region, Color(0.65, 0.45, 0.28, strength * 0.35))
			var flame_rect := Rect2(point - Vector2(breadth * 0.5, height * flicker), Vector2(breadth, height * flicker)) # 固定根部，缩放不离地。
			draw_texture_rect(FLAMES[frame], flame_rect, false, Color(1.0, 0.83 + 0.1 * float(depth), 0.68, strength * 0.94))
	_draw_embers(strength)

## 从 [param seed] 得到稳定的 0–1 美术采样；不读写战斗随机源。
func _noise(seed: float) -> float:
	return fposmod(sin(seed * 12.9898) * 43758.5453, 1.0)

## [param point] 为相对本格脚点的火根；普通爆燃不会在圆形范围之外铺出整块假地火。
func _contains_root(point: Vector2) -> bool:
	return clip_radius <= 0.0 or point.distance_squared_to(clip_center) <= clip_radius * clip_radius

## 绘制低密度上升火星；[param strength] 控制整片地火的出入场。
func _draw_embers(strength: float) -> void:
	for index: int in range(5): # 5×5 区域最多 125 颗轻量火星，不创建粒子节点。
		var phase: float = variation * 0.39 + float(index) * 1.73 # 火星固定种子。
		var cycle: float = fposmod(_age * 0.83 + phase, 1.0) # 每颗火星的归一化寿命。
		var point := Vector2(sin(phase * 5.3) * cell_size.x * 0.45 + sin(cycle * 4.0 + phase) * 6.0,
			-cell_size.y * (0.12 + fposmod(phase, 0.5))) # 先确认火星来自有效地火，再向上升腾。
		if not _contains_root(point):
			continue
		point.y -= cycle * 48.0
		var opacity: float = sin(cycle * PI) * strength * 0.8 # 自然出现与消失。
		draw_line(point, point + Vector2(-1.0, 2.8), Color(1.0, 0.61, 0.12, opacity), 1.6, true)
