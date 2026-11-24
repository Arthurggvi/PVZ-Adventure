## 将载具的分段击毁演出放到原战斗行，使余爆在本体离场后仍能播完。
extends RefCounted

## 只通过实际所属战局的已有能力查找花园飞艇爆炸。
const BattleWind := preload("res://scripts/battle/environment/battle_wind_visual.gd")
## 旧战场继续用原场景的火球、冲击波、烟尘、碎片和分段爆声。
const SCENE: PackedScene = preload("res://scenes/character/zombie/arbiter_x/arbiter_x_impact.tscn")


## 返回 [param source] 所属实战明确提供的飞艇爆炸能力，否则返回空。
static func find_airship(source: Node) -> Node:
	var wind: Node = BattleWind.from_node(source) # 预览和其他战场沿用旧车体爆炸。
	return wind.get_airship_blasts() if wind != null and wind.has_method(&"get_airship_blasts") else null


## 给 [param source] 播放一次击毁特效。[param kind] 供所属战局合并附近同类爆炸。
## [param origin] 为主火球世界位置，[param size] 为整体缩放，[param followups] 保留旧场景的局部偏移。
## [param part_world] 记录当帧部件的实际世界位置。返回可用于绑定飞艇快照的正序号。
static func play(source: Zombie000Base, kind: StringName, origin: Vector2, size: float,
		followups: PackedVector2Array, part_world: PackedVector2Array = PackedVector2Array()) -> int:
	var director: Node = find_airship(source) # 只有花园飞艇替换掉以下原版演出。
	if director != null:
		var locals := PackedVector2Array() # 快照保留 Body 的全局变换，Marker 不必留在已死亡的逻辑实体。
		for point: Vector2 in part_world: # 转一次，后续发射直接由移动快照恢复世界位置。
			locals.append(source.body.to_local(point))
		var death: Node = source.airship_death_presentation() # 保留致死阈值跨过前的真实速度。
		var velocity: Vector2 = death.source_velocity(source) if death != null else Vector2.ZERO # 单位为世界 px/战斗秒。
		var profile: StringName = &"fighter" if kind == &"fighter_death_blast" else &"turret" # 目前仅两种共用载具。
		return director.start_burst(profile, origin, size, velocity, source.z_index + 2, locals)
	var row := source.get_parent() as CanvasItem # 兼容 Node2D 与 Panel 战斗行，特效和战斗行同寿命。
	if row == null or row.is_queued_for_deletion():
		return 0
	var game: MainGameManager = Global.main_game # 只申请所属战局的表现额度。
	var budget: BattleBlastFxBudget = game.blast_fx_budget \
		if is_instance_valid(game) and game.is_ancestor_of(source) else null # 图鉴等独立场景没有战局额度。
	if budget != null and not budget.can_start(kind, origin):
		return 0
	var blast := SCENE.instantiate() as ArbiterXImpact # 主爆和次爆共用一个实例。
	blast.z_index = source.z_index + 2
	row.add_child(blast)
	blast.global_position = source.global_position
	if budget != null:
		budget.track(blast, kind, origin)
	blast.play_airburst(origin, size, followups)
	return 0
