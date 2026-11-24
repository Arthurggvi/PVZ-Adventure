## 一株樱桃炸弹的爆炸结算。首爆、追爆、地火与恶果共享来源快照和击杀归因。
extends Node
class_name AdventureCherryBlast

## 追爆和恶果使用与首爆同源的视觉场景。
const BLAST_FX = preload("res://scenes/fx/cherry_blast.tscn")
## 一格恶果爆炸的视觉倍率。
const SMALL_BLAST_SCALE: float = 0.48

## 持有爆炸及延迟效果的战场。
var _game: MainGameManager
## 首爆发生的轮次，用于取消换轮后的延迟效果。
var _round: int
## 冻结的独立来源卡 UID，用于返回冷却及种植费用减免。
var _card_uid: String
## 来源种植点，用于查询邻格。
var _cell: PlantCell
## 冻结的爆心攻击行。
var _lane: int
## 排除坡面高度的受击中心。
var _hit_origin: Vector2
## 追爆所用的世界表现中心。
var _visual_origin: Vector2
## 爆心附近的实际网格间距，单位为世界像素。
var _pitch: Vector2
## 原爆炸检测使用的碰撞层掩码。
var _mask: int
## 可受爆炸伤害的僵尸状态位。
var _statuses: int
## 追爆复用的原版爆炸音效。
var _sound: StringName
## 首爆和追爆共用的伤害范围。
var _blast: CombatExplosionProfile
## 本次引爆中按地块实际宽度复用的恶果范围，地形和碰撞掩码仍取自本次爆炸。
var _death_burst_profiles: Dictionary[float, CombatExplosionProfile] = {}
## 震爆独立的外扩控制范围。
var _shock: CombatExplosionProfile
## 已计入星级、场上修正和词条倍率的主爆伤害。
var _damage: int
## 首爆时冻结的单次僵王伤害上限，供主爆、追爆和恶果共用。
var _boss_damage_cap: int = -1
## 单次恶果伤害，零表示未启用。
var _death_burst_damage: int
## 地火每跳伤害，已计入星级。
var _burn_damage: int
## 来源卡经验证的樱桃转职参数。
var _rules: Dictionary[String, Dictionary] = {}
## 同一株炸弹只记一次的击杀身份，包括经护甲保护者转移的命中。
var _credited: Dictionary[int, bool] = {}
## 距子母雷的第二爆还有多少战斗秒，零表示无追爆。
var _repeat_left: float = 0.0
## 地火独立存活。追爆有重叠时只刷新同一片地火。
var _burn_zone: AdventureCherryBurnZone


## 在 [param plant] 仍存活时冻结 [param bomb] 的位置与伤害。
## [param uid] 是来源卡，[param effects] 是该卡已验证的樱桃词条。
## 准备失败时返回 false，调用方可保留原版爆炸。
func configure(plant: Plant000Base, bomb: BombComponentNorm, uid: String,
		effects: Array[Dictionary]) -> bool:
	_game = Global.main_game
	if not is_instance_valid(_game) or _game.board == null or not is_instance_valid(_game.bombs) \
			or not is_instance_valid(plant.plant_cell) or not _game.is_ancestor_of(plant) \
			or _game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME:
		return false
	# 原版圆形范围和高度从场景读取，避免复制伤害区域的常量。
	var collider := bomb.area_2d_bomb.get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if collider == null or not collider.shape is CircleShape2D:
		return false
	_round = _game.curr_game_round
	_card_uid = uid
	_cell = plant.plant_cell
	_lane = plant.lane
	_hit_origin = collider.global_position
	_visual_origin = bomb.bomb_effect.global_position
	_mask = bomb.area_2d_bomb.collision_mask
	_death_burst_profiles.clear()
	_statuses = bomb.can_attack_zombie_status
	_sound = bomb.bomb_sfx
	_pitch = _measure_pitch()
	# 每条词条来自卡片当前已选择的单个转职分支。
	for effect: Dictionary in effects:
		_rules[str(effect.kind)] = effect
	# 伤害在首爆时结算星级、光环和劣化，追爆与恶果继承这个值。
	var multiplier: float = float(_rules.get("cherry_fruit_of_fear", {}).get("multiplier", 1.0))
	_damage = roundi(float(bomb.resolved_damage()) * multiplier)
	_boss_damage_cap = bomb.boss_blast_damage_cap()
	_death_burst_damage = roundi(float(_damage) * float(_rules.get("cherry_bad_fruit", {}).get("damage_fraction", 0.0)))
	_burn_damage = plant.battle_damage(int(_rules.get("cherry_combustion", {}).get("damage", 0)))
	_repeat_left = float(_rules.get("cherry_double_blast", {}).get("delay", 0.0))
	# 聚变使用矩形网格，常规范围仍由原版圆形决定。
	var fusion_radius: int = int(_rules.get("cherry_fusion", {}).get("radius", 0))
	var native_shape: CircleShape2D = collider.shape as CircleShape2D
	_blast = _square_profile(fusion_radius) if fusion_radius > 0 else _profile(native_shape, bomb.bomb_lane)
	# 外扩只影响抛飞的索敌范围，爆炸伤害仍走 _blast。
	var extra_range: int = int(_rules.get("cherry_shock_blast", {}).get("extra_range", 0))
	if extra_range > 0:
		_shock = _square_profile(fusion_radius + extra_range) if fusion_radius > 0 \
			else _circle_profile(native_shape.radius + maxf(_pitch.x, _pitch.y) * extra_range,
				bomb.bomb_lane + extra_range)
	# 首爆由原组件播放，必须在激活前注入与追爆一致的转职表现参数。
	var visual := bomb.bomb_effect as BombEffectCherryBomb # 只调整樱桃自己的特效实例。
	if visual != null:
		_configure_visual(visual)
	return true


## 首爆由原版引信触发。母株随后销毁，战场节点继续持有追爆。
func detonate() -> void:
	if not _battle_active():
		queue_free()
		return
	_detonate_primary()
	if _repeat_left > 0.0 and _battle_active():
		set_physics_process(true)
	else:
		queue_free()


## 挂入战场后等待原版引信把首爆交给 [method detonate]。
func _ready() -> void:
	set_physics_process(false)


## [param delta] 为战斗秒数。子母雷到期只引爆一次，不重复启动引信。
func _physics_process(delta: float) -> void:
	if not _battle_active():
		queue_free()
		return
	_repeat_left -= delta
	if _repeat_left > 0.0:
		return
	SoundManager.play_character_SFX(_sound)
	_show_blast(_visual_origin, false)
	_detonate_primary()
	queue_free()


## 返回本轮战斗是否仍接受延迟爆炸和地火。
func _battle_active() -> bool:
	return is_instance_valid(_game) and not _game.is_queued_for_deletion() \
		and _game.curr_game_round == _round \
		and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME


## 主爆先结算伤害和恶果，再对仍存活的范围内僵尸施加震爆，最后生成或刷新地火。
func _detonate_primary() -> void:
	# 同一组地块同时给梯子清理与地火表现使用，聚变按 5×5 查询。
	var cells: Array[PlantCell] = [] # 本次主爆的邻格快照。
	if is_instance_valid(_cell) and not _cell.is_queued_for_deletion():
		cells = _game.board.neighbors(_cell, _blast.lane_radius)
	for cell: PlantCell in cells: # 各邻格已有的梯子也属于主爆清理范围。
		if is_instance_valid(cell.ladder):
			cell.ladder.ladder_death()
	var casualties: Array[Character000Base] = _blast_at(_hit_origin, _lane, _blast, _damage, true) # 主爆实际击杀。
	_award_kills(_resolve_casualties(casualties))
	if _battle_active():
		if _shock != null:
			_shock_survivors()
		if _rules.has("cherry_combustion"):
			_ignite_ground(cells)


## 在 [param origin] 按 [param profile]、[param lane] 结算 [param damage]，返回实际击杀。
## [param ash] 仅由主爆启用灰烬演出。
func _blast_at(origin: Vector2, lane: int, profile: CombatExplosionProfile,
		damage: int, ash: bool) -> Array[Character000Base]:
	# 几何命中和生命结算共用植物爆炸入口。
	var areas: Array[Area2D] = CombatExplosion.query_areas(_game.get_world_2d().direct_space_state, profile, origin)
	return CombatExplosion.resolve_plant_blast(areas, lane, profile.lane_radius, _statuses, damage, ash, null, _boss_damage_cap)


## 迭代处理 [param casualties] 及恶果新增的击杀。每个身份至多进入一次奖励和死亡爆炸。
func _resolve_casualties(casualties: Array[Character000Base]) -> int:
	var index: int = 0 # 当前爆炸队列的读取游标。
	var count: int = 0 # 这一爆和其恶果新产生的总击杀数。
	while index < casualties.size():
		var reference: Variant = casualties[index] # 死亡回调可能已移除角色。
		index += 1
		if not is_instance_valid(reference):
			continue
		var zombie: Character000Base = reference # 仅普通僵尸和僵王进入击杀队列。
		var id: int = zombie.get_instance_id()
		if _credited.has(id):
			continue
		_credited[id] = true
		count += 1
		if _death_burst_damage > 0 and _battle_active():
			casualties.append_array(_death_burst(zombie))
	return count


## 在实际被击杀的 [param zombie] 落点结算一次一格恶果。连锁继承同一主爆的半伤害。
func _death_burst(zombie: Character000Base) -> Array[Character000Base]:
	# 索敌中心优先用检测形状，避免屋顶高度和无固定行的僵王根节点影响范围。
	var visual_point: Vector2 = zombie.global_position + Vector2(0.0, -28.0) # 受击组件已卸载时的尸体位置。
	var point: Vector2 = visual_point # 物理检测用的中心，屋顶上与表现坐标不同。
	var hit_box: HurtBoxComponent = zombie.hurt_box_component # 角色死亡后可能先移除受击组件。
	if is_instance_valid(hit_box):
		if is_instance_valid(hit_box.hurt_box_real):
			visual_point = hit_box.hurt_box_real.global_position
		var shape := hit_box.get_node_or_null(^"HurtBoxDetection/CollisionShape2D") as Node2D
		point = shape.global_position if shape != null else visual_point
	var tile: PlantCell = _game.board.nearest_cell(zombie.global_position, zombie.lane) # 取尸体附近的一格。
	var lane: int = zombie.lane if zombie.lane >= 0 else (tile.combat_lane if tile != null else _lane) # 跨行僵王使用附近地块的行。
	var width: float = tile.get_global_rect().size.x if tile != null else _pitch.x # 小爆炸的一格世界半径。
	var profile: CombatExplosionProfile = _death_burst_profiles.get(width) # 同一宽度共享只读圆形范围。
	if profile == null:
		profile = _circle_profile(width, 1)
		_death_burst_profiles[width] = profile
	_show_blast(visual_point, true)
	return _blast_at(point, lane, profile, _death_burst_damage, false)


## 将 [param count] 个实际击杀的冷却或费用收益记回本次引爆的独立卡。
func _award_kills(count: int) -> void:
	if count <= 0 or not is_instance_valid(_game.card_manager):
		return
	# 只有拥有击杀收益词条时才查询战斗卡槽。
	var cooldown: float = float(_rules.get("cherry_spark", {}).get("cooldown_per_kill", 0.0))
	var discount: int = int(_rules.get("cherry_red_core", {}).get("discount_per_kill", 0))
	if cooldown <= 0.0 and discount <= 0:
		return
	var slots: CardSlotBattle = _game.card_manager.card_slot_battle # 普通冒险出战卡槽持有本局费用。
	var card: Card = slots.find_plant_card_by_uid(_card_uid) if is_instance_valid(slots) else null
	if card == null:
		return
	if cooldown > 0.0:
		card.adventure_adjust_remaining_cooldown(-cooldown * count)
	if discount > 0:
		card.add_next_planting_discount(discount * count)
		card.judge_sun_enough(slots.sun_value)


## 震爆区域只对普通僵尸请求强制位移。落地回调使用独立状态入口，母株和爆炸节点可先释放。
func _shock_survivors() -> void:
	# 伤害范围外仍可震飞，已经死亡、魅惑和受击禁用的目标会被通用筛选排除。
	var areas: Array[Area2D] = CombatExplosion.query_areas(_game.get_world_2d().direct_space_state, _shock, _hit_origin)
	var targets: Array[Character000Base] = CombatExplosion.plant_blast_targets(areas, _lane, _shock.lane_radius, _statuses)
	var rule: Dictionary = _rules["cherry_shock_blast"] # 震飞距离、弧高、持续时间和落地眩晕。
	for target: Character000Base in targets: # 震爆范围内当前存活的候选。
		if not target is Zombie000Base or not is_instance_valid(target.move_component):
			continue
		# 两格距离使用目标脚下行的实际格宽，超出棋盘仍由位移入口处理。
		var width: float = _game.board.cell_width_at(target.global_position, target.lane)
		if width <= 0.0:
			continue
		var landed: Callable = AdventurePlantNegativeEffects.apply.bind(target,
			AdventurePlantNegativeEffects.Kind.STUN, 0, float(rule.stun))
		target.move_component.apply_forced_displacement(Vector2(width * int(rule.cells), 0.0),
			float(rule.flight), float(rule.height), landed)


## [param cells] 是完整波及地块。地火覆盖全部格子，灼伤沿用本次爆炸的地面范围。
func _ignite_ground(cells: Array[PlantCell]) -> void:
	if is_instance_valid(_burn_zone) and not _burn_zone.is_queued_for_deletion():
		_burn_zone.refresh()
		return
	var rule: Dictionary = _rules["cherry_combustion"] # 星级修正后的每跳伤害已在首爆冻结。
	_burn_zone = AdventureCherryBurnZone.new()
	_burn_zone.ignite(_game, _hit_origin, _lane, _blast, _burn_damage,
		float(rule.interval), float(rule.duration), cells)


## 在 [param at] 播放原版爆炸表现，[param small] 表示恶果的小型烟团。
func _show_blast(at: Vector2, small: bool) -> void:
	if not _game.blast_fx_budget.can_start(StringName(BLAST_FX.resource_path), at):
		return
	# 独立特效自行回收，不随爆炸结算节点一起释放。
	var effect := BLAST_FX.instantiate() as BombEffectCherryBomb # 原爆炸场景实例。
	effect.small_burst = small
	if small:
		effect.scale *= SMALL_BLAST_SCALE
	_game.bombs.add_child(effect)
	effect.global_position = at
	_configure_visual(effect, not small)
	effect.activate_bomb_effect()


## 向 [param effect] 注入纯表现快照；[param echo] 区分子母雷的追爆，恶果仍保留小型预算。
func _configure_visual(effect: BombEffectCherryBomb, echo: bool = false) -> void:
	effect.configure_presentation(_rules, _profile_size(_blast),
		_profile_size(_shock) if _shock != null else Vector2.ZERO, echo)


## 返回 [param profile] 的世界包围尺寸，让聚变、震爆视觉随真实范围扩张。
func _profile_size(profile: CombatExplosionProfile) -> Vector2:
	if profile.shape is RectangleShape2D:
		return (profile.shape as RectangleShape2D).size
	return Vector2.ONE * (profile.shape as CircleShape2D).radius * 2.0


## 返回 [param radius] 格的矩形范围，包含中心格。
func _square_profile(radius: int) -> CombatExplosionProfile:
	var shape := RectangleShape2D.new() # 用当前棋盘的行列间距换算世界尺寸。
	shape.size = _pitch * float(2 * radius + 1)
	return _profile(shape, radius)


## 用同列格子的检测基线推导行距，避免把屋顶不同列的高度差误当作攻击行间距。
func _measure_pitch() -> Vector2:
	var pitch: Vector2 = _cell.get_global_rect().size # 没有相邻行时用中心格实际尺寸。
	var local_pitch: Vector2 = _game.board.local_pitch(_cell) # 横向间距可直接使用棋盘查询。
	if local_pitch.x > 0.0:
		pitch.x = local_pitch.x
	# 爆炸检测使用扣除坡面高度后的基线，和植物、僵尸的检测框一致。
	var base_y: float = _cell.get_slot_anchor_global_position(CharacterRegistry.PlacePlantInCell.Norm).y - _cell.get_ground_height()
	for side: int in [-1, 1]: # 上下相邻行的偏移。
		var neighbor: PlantCell = _game.board.cell_at(_cell.row_col + Vector2i(side, 0)) # 同列相邻行。
		if neighbor != null:
			var row_y: float = neighbor.get_slot_anchor_global_position(CharacterRegistry.PlacePlantInCell.Norm).y - neighbor.get_ground_height()
			pitch.y = maxf(pitch.y, absf(row_y - base_y))
	return pitch


## 返回 [param radius] 世界像素的圆形范围，同时按 [param lanes] 过滤普通僵尸。
func _circle_profile(radius: float, lanes: int) -> CombatExplosionProfile:
	var shape := CircleShape2D.new() # 独立形状，避免改写共享场景资源。
	shape.radius = radius
	return _profile(shape, lanes)


## 创建使用 [param shape] 与 [param lanes] 的敌方爆炸查询参数。
func _profile(shape: Shape2D, lanes: int) -> CombatExplosionProfile:
	var profile := CombatExplosionProfile.new() # 保留原生炸弹的敌方检测层。
	profile.shape = shape
	profile.lane_radius = lanes
	profile.collision_mask = _mask
	return profile
