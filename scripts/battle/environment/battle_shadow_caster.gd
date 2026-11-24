## 角色的接地标定、剪影缓存以及单主灯滞回状态。
extends RefCounted

## 当前帧的投影光源。
const LightSource = preload("res://scripts/battle/environment/battle_light_source.gd")
## 低于一个遮罩色阶的光不需要投影。
const MIN_COVERAGE := 1.0 / 255.0
## 暖灯光缘最大倍率。显色淡出只能再减少权重，用于推导候选灯的安全距离上界。
const EDGE_SQUARED_OVER_FALLOFF := (1.019 * 1.019) / (3.8 * 0.6931471805599453)

## 实体节点，用于退出场景与可见性判断。
var owner: Node2D
## 当前用于采样动画精灵的表现根。
var body: Node2D
## 持久接地锚点，不随剪影裁切边界改变。
var foot: Node2D
## 标定原画高度，单位世界像素。
var reference_height: float
## 与 [member reference_height] 对应的虚拟高度，登记后固定。
var body_height: float
## 最近一次拓扑更新后收集的精灵部件。
var parts: Array[RefCounted] = []
## 表现树有改动时重新收集部件。
var dirty := true
## 图集中这一帧姿态相对脚点的矩形，包含隔离区。
var pose_bounds: Rect2
## 当前剪影格索引。
var tile := -1
## 已经提交的姿态代数，用于拒绝被重新分配的图集格。
var generation := -1
## 最近一次通过空间筛选的图集帧号。
var atlas_use: int
## 此格下一次允许采样姿态的战斗时间。
var pose_due: float
## 当前投影使用的唯一主灯。
var primary: LightSource
## 当前用于裁剪的可见入射权重。
var light_power: float
## 换灯期间的实际影量因子，普通单灯始终为一。
var handoff := 1.0

## 正在竞争主灯且尚未达到持续时间的灯。
var _challenger: LightSource
## 本轮挑战开始时的战斗时间。
var _challenge_since: float
## 已满足持续时间，等待旧影淡出的目标灯。
var _incoming: LightSource
## 最近一次求解的战斗时间。
var _last_update := -1.0

## 按 [param lights] 在脚点 [param position] 的实际衰减选择主灯，返回是否需要剪影。
## [param now] 以战斗秒计，[param ratio] 为领先比例，[param dwell] 为持续秒数，
## [param fade] 是主灯切换时每段淡出的时间。位置解算不受切灯过程插值。
func update_light(lights: Array[LightSource], position: Vector2, now: float, ratio: float,
		dwell: float, fade: float) -> bool:
	var incumbent: float = primary.coverage_at(position) if primary != null and primary.shadow_slot >= 0 else 0.0 # 先计算既有主灯。
	var incoming_power: float = _incoming.coverage_at(position) if _incoming != null and _incoming.shadow_slot >= 0 else 0.0 # 目标仍需处理退场。
	var strongest: LightSource = primary if incumbent > MIN_COVERAGE else null # 同权重时优先保持主灯。
	var best: float = maxf(incumbent, MIN_COVERAGE) # 迄今最强的确切权重。
	var cutoff: float = -log(best) * EDGE_SQUARED_OVER_FALLOFF # 归一化距离平方上界，确保无需计算的灯不可能更亮。
	for light: LightSource in lights: # 仅遍历已获得遮挡格的光源。
		if light == primary:
			continue
		if light.center.distance_squared_to(position) > cutoff * light.radius * light.radius:
			continue
		var power: float = incoming_power if light == _incoming else light.coverage_at(position) # 用精确的衰减与静态扰动打分。
		if power > best:
			best = power
			strongest = light
			cutoff = -log(best) * EDGE_SQUARED_OVER_FALLOFF
	var step: float = (now - _last_update) / maxf(0.001, fade) if _last_update >= 0.0 else 0.0 # 影量淡化的一步。
	_last_update = now
	if strongest == null:
		primary = null
		_reset_handoff()
		handoff = 1.0
		light_power = 0.0
		return false
	if primary == null or incumbent <= MIN_COVERAGE:
		handoff = 1.0 if primary == null else 0.0
		primary = strongest
		light_power = best
		_reset_handoff()
		return true
	light_power = incumbent
	if _incoming != null and incoming_power > MIN_COVERAGE:
		handoff = move_toward(handoff, 0.0, step)
		if handoff <= 0.0:
			primary = _incoming
			light_power = incoming_power
			_reset_handoff()
		return true
	_incoming = null
	handoff = move_toward(handoff, 1.0, step)
	if strongest == primary or best < incumbent * (1.0 + ratio):
		_challenger = null
	elif _challenger != strongest:
		_challenger = strongest
		_challenge_since = now
	elif now - _challenge_since >= dwell:
		_incoming = strongest
		_challenger = null
	return true

## 清理一次已经完成或因失光取消的换灯。
func _reset_handoff() -> void:
	_challenger = null
	_incoming = null
