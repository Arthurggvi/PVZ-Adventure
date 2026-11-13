## 一次大喷攻击的冻结命中词条；穿透目标共享同一次异变抽签，不依赖母株继续存活。
extends RefCounted
class_name AdventureFumeHitEffects

## 犹格的十一种异变等概率，顺序固定供同一次攻击保存结果。
enum Mutation { POISON, DEGRADATION, FEAR, CHARM, BURN, SLOW, FREEZE_CHARGE, STUN, EXPLOSION, SILENCE, SUN_INFUSION }
## 一格爆炸的基础伤害，出生卡与共享攻击规则仅在各自入口应用一次。
const EXPLOSION_DAMAGE: int = 1800
## 复用现有爆炸表现配置，仅在运行时复制几何和掩码。
const EXPLOSION_PROFILE_PATH: String = "res://resources/combat/jackbox_explosion_profile.tres"
## 本次发射所属战场，结束或换场后拒绝新命中。
var _game: MainGameManager
## 同场景的普通轮次身份。
var _round_index: int = -1
## 冒险阶段身份；普通与噩梦不会因复用场景而串效果。
var _phase: StagePhaseDefinition
## 原植株实例身份仅用作负面来源标识，不持有植物节点。
var _source_id: int = 0
## 本次攻击的冻结词条字典。
var _rules: Dictionary = {}
## 未学犹格时为-1；其余情况在发射时仅抽签一次。
var _mutation: int = -1
## 同一次喷射按角色身份去重，多个受击框不重复叠状态或触发爆炸。
var _hit_ids: Dictionary[int, bool] = {}
## 出生点真实格距作为盘外命中的尺寸回退，不移动爆心。
var _cell_pitch: Vector2 = Vector2.ONE
## 一次冻结的出战卡与原光环爆炸伤害。
var _explosion_damage: int = EXPLOSION_DAMAGE
## 独立爆炸共享攻击上下文，不复用主弹体当前命中的奖励资格。
var _explosion_context: PlantAttackContext

## 从 [param plant] 捕获本次攻击和 [param rules]，只在活动战场接受实际发射。
static func capture(plant: Plant000Base, rules: Dictionary) -> AdventureFumeHitEffects:
	if not is_instance_valid(plant) or not is_instance_valid(plant.plant_cell):
		return null
	var effect: AdventureFumeHitEffects = AdventureFumeHitEffects.new() # 一轮攻击独享抽签及命中集合。
	effect._game = Global.main_game
	if not is_instance_valid(effect._game):
		return null
	effect._round_index = effect._game.curr_game_round
	effect._phase = AdventureSession.get_active_phase(effect._game.game_para)
	effect._source_id = plant.get_instance_id()
	effect._rules = rules.duplicate(true)
	if not effect.is_active():
		return null
	effect._cell_pitch = effect._game.board.local_pitch(plant.plant_cell) \
		if effect._game.board != null else plant.plant_cell.get_global_rect().size
	if rules.has("fume_yog"):
		effect._mutation = randi_range(0, Mutation.size() - 1)
		if effect._mutation == Mutation.EXPLOSION:
			effect._explosion_damage = plant.battle_damage(EXPLOSION_DAMAGE)
			effect._explosion_context = plant.capture_attack_context()
	return effect

## 原生弹体也使用此门禁，阻止没有共享伤害上下文的旧大喷弹跨阶段继续扣血。
func is_active() -> bool:
	return is_instance_valid(_game) and _game.is_inside_tree() and not _game.is_queued_for_deletion() \
		and _game == Global.main_game and _game.get_tree().current_scene == _game \
		and _game.curr_game_round == _round_index \
		and AdventureSession.get_active_phase(_game.game_para) == _phase \
		and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false)

## [param target] 已由原攻击链实际命中；[param impact_position] 为命中世界坐标。
## 只附加词条，不再次扣主攻击伤害；爆炸不会重新调用此入口。
func apply(target: Character000Base, impact_position: Vector2) -> void:
	if not is_active() or not is_instance_valid(target):
		return
	var identity: int = target.get_instance_id() # 同一股穿透喷雾的每个角色只登记一次。
	if _hit_ids.has(identity):
		return
	_hit_ids[identity] = true
	if _mutation == Mutation.EXPLOSION:
		_detonate.call_deferred(target.global_position if target.is_inside_tree() else impact_position, target.lane)
	if target.is_death or target.is_queued_for_deletion() or target.is_hypno \
			or not (target is Zombie000Base or target is ZB000Base):
		return
	if _rules.has("fume_knockback") and target is Zombie000Base:
		target.apply_projectile_knockback(float(_rules["fume_knockback"].get("distance", 12.0)))
	if _rules.has("fume_hell_touch"):
		var hell: Dictionary = _rules["fume_hell_touch"] # 劣化仍为原最强值通道，烧伤层数表示秒。
		_apply(target, AdventurePlantNegativeEffects.Kind.DEGRADATION, float(hell.get("degradation", 0.5)))
		_apply(target, AdventurePlantNegativeEffects.Kind.BURN, float(hell.get("burn_seconds", 2.0)))
	if _rules.has("fume_ice_touch"):
		var ice: Dictionary = _rules["fume_ice_touch"] # 减速与冻结值分别进入公共状态系统。
		_apply(target, AdventurePlantNegativeEffects.Kind.ICE_SLOW, float(ice.get("slow_seconds", 5.0)))
		_apply(target, AdventurePlantNegativeEffects.Kind.FREEZE_CHARGE, float(ice.get("freeze_points", 2.0)))
	_apply_mutation(target)

## 对 [param target] 执行本轮已经抽定的一种异变，免疫失败不会重新抽签。
func _apply_mutation(target: Character000Base) -> void:
	match _mutation:
		Mutation.POISON: _apply(target, AdventurePlantNegativeEffects.Kind.POISON, 2.0)
		Mutation.DEGRADATION: _apply(target, AdventurePlantNegativeEffects.Kind.DEGRADATION, 0.5)
		Mutation.FEAR: _apply(target, AdventurePlantNegativeEffects.Kind.FEAR, 1.0)
		Mutation.CHARM: _apply(target, AdventurePlantNegativeEffects.Kind.CHARM)
		Mutation.BURN: _apply(target, AdventurePlantNegativeEffects.Kind.BURN, 2.0)
		Mutation.SLOW: _apply(target, AdventurePlantNegativeEffects.Kind.ICE_SLOW, 5.0)
		Mutation.FREEZE_CHARGE: _apply(target, AdventurePlantNegativeEffects.Kind.FREEZE_CHARGE, 2.0)
		Mutation.STUN: _apply(target, AdventurePlantNegativeEffects.Kind.STUN, 1.0)
		Mutation.SILENCE: _apply(target, AdventurePlantNegativeEffects.Kind.SILENCE, 2.0)
		Mutation.SUN_INFUSION: _apply(target, AdventurePlantNegativeEffects.Kind.SUN_INFUSION)

## 将 [param target]、[param kind] 和 [param amount] 交给唯一负面入口；不绕过角色免疫。
func _apply(target: Character000Base, kind: AdventurePlantNegativeEffects.Kind, amount: float = 0.0) -> void:
	AdventurePlantNegativeEffects.apply(target, kind, _source_id, amount)

## 在 [param position] 的一格范围结算独立爆炸；[param lane] 保留原命中行，不吸附爆心。
func _detonate(position: Vector2, lane: int) -> void:
	if not is_active() or _game.board == null:
		return
	var cell: PlantCell = _game.board.nearest_cell(position, lane) # 最近格仅提供当地尺寸，盘外位置不挪入棋盘。
	var pitch: Vector2 = _game.board.local_pitch(cell) if cell != null else _cell_pitch # 当前移动地形的真实格距。
	var template: CombatExplosionProfile = load(EXPLOSION_PROFILE_PATH) as CombatExplosionProfile # 复用原爆炸表现，避免静态场景加载环。
	if template == null:
		return
	var profile: CombatExplosionProfile = template.duplicate(true) as CombatExplosionProfile # 只修改本次爆炸实例。
	var shape: RectangleShape2D = RectangleShape2D.new() # 宽高各一格，沿用战场实际单位。
	shape.size = Vector2(maxf(1.0, pitch.x), maxf(1.0, pitch.y))
	profile.shape = shape
	profile.collision_mask = 4
	profile.lane_radius = 0
	profile.visuals_scale = minf(1.0, maxf(0.2, pitch.x / 250.0))
	var areas: Array[Area2D] = CombatExplosion.query_areas(_game.get_world_2d().direct_space_state, profile, position) # 借用唯一爆炸目标与去重管线。
	CombatExplosion.resolve_plant_blast(areas, lane, 0, 31, _explosion_damage, true, _explosion_context)
	CombatExplosion.emit_visuals(_game.bombs if is_instance_valid(_game.bombs) else _game, profile, position)
