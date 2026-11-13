## 双发命中后的独立区域效果；只调用既有爆炸、负面登记与同一持续场时钟。
extends RefCounted
class_name RepeaterAreaEffects

## 引爆值满十点后的基础伤害，卡片倍率在来源快照中仅应用一次。
const DETONATION_DAMAGE: int = 1800
## 爆炸沿用现有美术与声音，仅为本次实例调整一格几何。
const EXPLOSION_PROFILE: String = "res://resources/combat/jackbox_explosion_profile.tres"

## 将 [param kind] 的区域效果延后到碰撞回调之外；[param position]、[param lane] 为实际命中坐标。
## [param shot] 必须仍属于原战局；不重新读取植物或当前卡牌。
static func impact(kind: StringName, position: Vector2, lane: int, shot: RepeaterShotContext) -> void:
	if shot != null and shot.is_active():
		_resolve_impact.call_deferred(kind, position, lane, shot)

## 引爆值回调接收 [param position] 与 [param lane]；[param shot] 由授予时的来源绑定。
static func detonate(position: Vector2, lane: int, shot: RepeaterShotContext) -> void:
	if shot != null and shot.is_active():
		_detonate.call_deferred(position, lane, shot)

## 在安全阶段处理 [param kind]、[param position]、[param lane] 与冻结 [param shot]。
static func _resolve_impact(kind: StringName, position: Vector2, lane: int, shot: RepeaterShotContext) -> void:
	if not shot.is_active():
		return
	match kind:
		&"hell", &"kaguya":
			RepeaterFieldRuntime.spawn_field(kind, position, lane, shot)
		&"hades":
			var areas: Array[Area2D] = RepeaterFieldQueries.area(shot, position, lane, 3.0) # 周围三格边长，共享真实受击区域。
			for target: Character000Base in CombatExplosion.plant_blast_targets(areas, lane, 1, 31): # 每个实体只登记一次状态。
				if not shot.is_active():
					break
				AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.RESENTMENT,
					shot.source_id, 0.0, 0.0, {"on_kill": _effect_kill.bind(shot)})

## [param casualty] 是持续效果的实际死者；绑定的 [param shot] 强持有来源，母弹销毁不丢失回调。
static func _effect_kill(casualty: Character000Base, shot: RepeaterShotContext) -> void:
	shot.on_kill(casualty)

## [param position] 不吸附格心；[param lane] 限制单行；[param shot] 保留真实击杀上下文。
static func _detonate(position: Vector2, lane: int, shot: RepeaterShotContext) -> void:
	if not shot.is_active():
		return
	var template: CombatExplosionProfile = load(EXPLOSION_PROFILE) as CombatExplosionProfile # 延迟加载避免注册表场景循环。
	if template == null:
		return
	var profile: CombatExplosionProfile = template.duplicate(true) as CombatExplosionProfile # 不修改其他植物共用的爆炸配置。
	var shape := RectangleShape2D.new() # 一格尺寸即时取自命中附近棋盘。
	shape.size = shot.pitch_at(position, lane)
	profile.shape = shape
	profile.collision_mask = RepeaterFieldQueries.ENEMY_HURT_MASK
	profile.lane_radius = 0
	profile.visuals_scale = clampf(shape.size.x / 250.0, 0.2, 1.0)
	var areas: Array[Area2D] = CombatExplosion.query_areas(shot.game.get_world_2d().direct_space_state, profile, position) # 沿用统一全量查询及实体去重。
	CombatExplosion.resolve_plant_blast(areas, lane, 0, 31,
		shot.scaled_damage(DETONATION_DAMAGE), true, shot.attack_context)
	if not shot.is_same_battle():
		return
	CombatExplosion.emit_visuals(shot.game.bombs, profile, position)
	RepeaterImpactVisual.spawn(shot.game.bombs, &"detonation", position)
