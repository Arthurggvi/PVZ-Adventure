## 寒冰直击、冷萃和冰痕共用减速规则，各自保留伤害与附加效果边界。
extends RefCounted
class_name SnowPeaImpact

## [param target] 是直接承受命中且存活的僵尸；格挡归零不等于状态免疫。[param shot] 提供出战词条。
## [param was_slowed] 为扣血前快照；[param prism] 添加棱锥冻结值；[param contact] 标识当前接触。
static func apply_direct_status(target: Zombie000Base, shot: SnowPeaShot, was_slowed: bool,
		prism: bool, contact: int) -> void:
	_apply_traits(target, shot, was_slowed, false, prism, 0 if prism else contact)

## [param target] 是接触冰痕的僵尸；[param shot] 为获选冰痕的来源。
## 共享减速相关词条，并显式跳过冻结值满点时的附伤。
static func apply_trail_status(target: Zombie000Base, shot: SnowPeaShot) -> bool:
	if not _can_chill(target, shot):
		return false
	_apply_traits(target, shot, target.is_cold_slowed(), true, false, 0)
	return true

## [param target]、[param shot] 和 [param was_slowed] 为结算输入。
## [param control_only] 用于无伤冰痕；[param prism] 只为棱锥追加点数；[param contact] 为根弹接触序号，0 不新登记冰雕来源。
static func _apply_traits(target: Zombie000Base, shot: SnowPeaShot, was_slowed: bool,
		control_only: bool, prism: bool, contact: int) -> void:
	if not _can_chill(target, shot):
		return
	var rules: SnowPeaLoadout = shot.loadout # 施效时只读发射快照。
	if was_slowed and rules.has(&"brittleness"):
		AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.BRITTLENESS,
			shot.battle.source_id, rules.number(&"brittleness", &"stacks"))
	var points: float = rules.number(&"winter", &"points") # 凛冬与棱锥在此汇总到同一冻结值入口。
	if prism:
		points += rules.number(&"skadi", &"prism_points")
	if points > 0.0:
		var context: Dictionary = {"control_only": control_only} # 冰痕满点只能控制，根弹附伤为实际承伤者登记来源。
		if contact > 0 and rules.has(&"skadi"):
			context["freeze_hit_scope"] = SnowPeaStatueHit.new(shot, contact)
		AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.FREEZE_CHARGE,
			shot.battle.source_id, points, 0.0, context)
	if _can_chill(target, shot) and _unshielded(target):
		_apply_chill(target, shot, not control_only, true, contact)

## [param target]、[param shot] 为减速输入；[param allow_damage] 允许深寒附伤。
## [param freeze] 为深寒完整直击资格，冷萃只分享减速；[param contact] 为根弹接触序号。
static func _apply_chill(target: Zombie000Base, shot: SnowPeaShot, allow_damage: bool, freeze: bool, contact: int = 0) -> void:
	if not shot.loadout.has(&"deep_cold"):
		AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.ICE_SLOW,
			shot.battle.source_id, shot.slow_seconds)
		return
	var duration: float = shot.loadout.number(&"deep_cold", &"seconds") if freeze else 0.0 # 溅射只施加抗火减速。
	var was_frozen: bool = target.is_cold_frozen() # 深寒只在真正进入冻结时补伤和播放结晶，续时不重复。
	if allow_damage and duration > 0.0 and target.can_cold_freeze() and not was_frozen:
		var hp := target.hp_component as HpComponentZombie # 附伤使用和原生冰冻相同的真实伤害路由。
		var scope: CombatHitScope = SnowPeaStatueHit.new(shot, contact) if contact > 0 and shot.loadout.has(&"skadi") else null # 根弹附伤可以登记，冰锥不新传播冰雕来源。
		hp.apply_hit(int(shot.loadout.number(&"deep_cold", &"damage")), BulletRegistry.AttackMode.Real,
			true, false, true, 1.0, 0, -1, null, scope)
	if _can_chill(target, shot):
		AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.DEEP_COLD,
			shot.battle.source_id, shot.slow_seconds, duration, {"battle": shot.battle, "statuses": shot.zombie_statuses()})
		if not was_frozen and target.is_cold_frozen():
			SnowPeaStatueBurst.crystallize(shot.battle, target)

## [param target] 当前仍处于 [param shot] 允许的寒冷受击状态时返回真。
static func _can_chill(target: Zombie000Base, shot: SnowPeaShot) -> bool:
	return is_instance_valid(target) and shot.battle.is_active() and not target.is_death \
		and not target.is_hypno and not target.is_queued_for_deletion() and target.is_inside_tree() \
		and target.can_receive_cold() and target.can_receive_negative_effects() \
		and target.character_init_type == Character000Base.E_CharacterInitType.IsNorm \
		and target.hurt_box_component.is_enabling \
		and (target.curr_be_attack_status & shot.zombie_statuses()) != 0

## [param target] 的二类防具遵守原生寒冰弹减速门禁；脆弱和冻结值各自按登记资格结算。
static func _unshielded(target: Zombie000Base) -> bool:
	return (target.hp_component as HpComponentZombie).curr_hp_armor2 <= 0

## [param target] 为根接触实体；[param position]、[param lane] 定位爆心。
## [param damage] 含主伤修正；[param shot] 提供几何与倍率；[param contact] 排除同击生成的冰雕。
static func queue_splash(target: Character000Base, position: Vector2, lane: int, damage: int,
		shot: SnowPeaShot, contact: int) -> void:
	if damage > 0 and shot.battle.is_active() and shot.loadout.has(&"cold_extract"):
		_splash.call_deferred(target.get_instance_id(), position, lane, damage, shot, contact)

## [param direct_id] 排除直击者；[param position]、[param lane]、[param damage]、[param shot] 和 [param contact] 为直击快照。
## 在物理冲刷之外按真实受击几何去重，溅射只传播伤害及减速。
static func _splash(direct_id: int, position: Vector2, lane: int, damage: int, shot: SnowPeaShot, contact: int) -> void:
	if not shot.battle.is_active():
		return
	var amount: int = roundi(damage * shot.loadout.number(&"cold_extract", &"damage_factor")) # 按主伤比例只计算一次。
	if amount <= 0:
		return
	var width: float = shot.loadout.number(&"cold_extract", &"width_cells") # 即时棋盘格距的倍数。
	SnowPeaSplashVisual.spawn(shot.battle, position, lane, width)
	var areas := RepeaterFieldQueries.area(shot.battle, position, lane, width) # 复用实际受击层的矩形宽相查询。
	var scope: CombatHitScope = SnowPeaStatueHit.new(shot, contact) if contact > 0 and shot.loadout.has(&"skadi") else CombatHitScope.new() # 根弹冷萃属于本株攻击；同一保护者仍只结算一次，冰锥派生不登记。
	for target: Character000Base in CombatExplosion.plant_blast_targets(areas, lane, 1, shot.zombie_statuses()): # 按角色去重后的候选。
		if not shot.battle.is_active():
			break
		if not is_instance_valid(target) or target.is_death or target.is_queued_for_deletion() \
				or target.get_instance_id() == direct_id \
				or (target is SnowPeaStatue and target.was_created_by(shot, contact)):
			continue
		var receipt: Dictionary = {} # 减速跟随直接溅射命中；伤害被格挡不应成为额外的寒冷免疫。
		target.be_attacked_bullet(amount, BulletRegistry.AttackMode.Norm, true, false, 0, -1, receipt, scope)
		var recipient: Variant = receipt.get("recipient") # 代伤后减速跟随实际承伤者，不额外要求其与弹体同行。
		if is_instance_valid(recipient) and recipient is Zombie000Base \
				and not bool(receipt.get("duplicate_hit", false)) and _can_chill(recipient, shot) and _unshielded(recipient):
			_apply_chill(recipient, shot, false, false)
