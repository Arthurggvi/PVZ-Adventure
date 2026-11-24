## 现有效果查找当前战局显式注入的表现风场，旧关卡不创建这一依赖。
extends RefCounted

## 只为 [param source] 所属的实际战场返回风场。加载预览和切换中的旧场景返回空。
static func from_node(source: Node) -> Node:
	var game: MainGameManager = Global.main_game # 沿用正式战斗所有权，不注册新的全局上下文。
	if not is_instance_valid(game) or not is_instance_valid(source) or not is_instance_valid(game.world_wind):
		return null
	return game.world_wind if source == game or game.is_ancestor_of(source) else null

## 给尚未发射的 [param emitter] 一份独立材质，按 [param wind] 和 [param strength] 施加世界横向拖曳。
## 既有径向爆心和初始发射速度保持，已离开的粒子不随发射器移动。
static func setup_particles(emitter: GPUParticles2D, wind: Vector2, strength: float) -> void:
	if wind.is_zero_approx() or not emitter.process_material is ParticleProcessMaterial:
		return
	var motion := emitter.process_material.duplicate() as ParticleProcessMaterial # 不回写共用的素材和其它关卡。
	motion.gravity += Vector3(wind.x, wind.y, 0.0) * strength
	emitter.process_material = motion
	emitter.local_coords = false

## 按 [param point] 为 [param source] 的 [param emitters] 设置同一真实世界风。
## [param shed] 时顺带把少量余片交给已有落物池，爆心和原判定保持原位置。
static func before_emit(source: Node, point: Vector2, emitters: Array[GPUParticles2D], shed: bool = false) -> void:
	var flow: Node = from_node(source) # 平地默认没有这一表现风。
	if flow == null:
		return
	var wind: Vector2 = flow.wind_for_visual(point) # 每个真实爆心取一次样。
	for emitter: GPUParticles2D in emitters: # 当前这组现有发射器开始前统一接收风量。
		setup_particles(emitter, wind, 0.76)
	if shed:
		flow.shed_fragments(point)
