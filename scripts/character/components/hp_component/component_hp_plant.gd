## 植物专用生命组件：独立冰壳、可消耗临时护甲与单次有效伤害上限。
## 减伤后依次消耗冰壳和技能护甲；脚本强制死亡仍绕过二者。
extends HpComponent
class_name HpComponentPlant

## 临时护甲池；所有植物均可被守护技能授予护甲。
var bonus_armor: int = 0
## 单次实际战斗伤害上限占最大生命的比例；0 表示不限制。
var max_single_hit_fraction: float = 0.0
## 该株可以承接身后一格的战斗伤害。
var guards_rear_cell: bool = false
## 免疫直接爆炸并承接附近其他植物的爆炸伤害。
var intercepts_explosions: bool = false
## 原生即死碾压转为该比例的本体最大生命伤害；0 沿用原来规则。
var crush_health_fraction: float = 0.0
## 将实际消耗的血池反击给来源。
var reflects_damage: bool = false
## 护甲变化信号；与生命损失分开，不触发坚果破损外观。
signal bonus_armor_changed(amount: int)
## 护甲数值指示，仅存在护甲时显示，跟随生命值显示设置。
var _armor_label: Label
## 普通冻结的独立冰壳；只有本株生命组件持有，持久性由冰壳自身维护。
var _ice_shell: PlantIceShell = PlantIceShell.new()
## 当前可消耗的冰壳耐久；未冻结、死亡及退场时为零，不混入本体生命。
var ice_shell_hp: int:
	get:
		return _ice_shell.current_hp()

## 复用生命面板显示独立护甲，并显式绑定本株冰壳的生命周期。
func _ready() -> void:
	super()
	_armor_label = Label.new()
	_armor_label.name = "BonusArmorLabel"
	_armor_label.position = Vector2(-30.0, 14.0)
	_armor_label.add_theme_color_override("font_color", Color(0.48, 0.94, 1.0))
	_armor_label.add_theme_font_size_override("font_size", 12)
	_armor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(%HpControl as Control).add_child(_armor_label)
	_update_armor_label()
	_ice_shell.setup(owner_character as Plant000Base, %HpControl as Control)

## 返回本株是否仍有普通冻结冰壳；不按剩余本体生命推算耐久。
func has_ice_shell() -> bool:
	return _ice_shell.is_active()

## 返回是否由猎人维持当前冻结，避免定时冻结覆盖持久性。
func has_persistent_ice_shell() -> bool:
	return _ice_shell.is_persistent()

## 在植物完成资格检查后准备持久冰壳，返回是否首次授予；不会补满已有壳。
func begin_persistent_ice_shell() -> bool:
	return _ice_shell.begin_persistent()

## 植物原实例换格时同步冰壳代理的行与几何，不重新生成或恢复冰壳。
func sync_ice_shell_target() -> void:
	_ice_shell.sync_target_placement()

## [param amount] 正数表示新授护甲；[param maximum] 可选总护甲上限，-1 无限。
## 返回实际增加的护甲，护甲上限不影响今后其他来源的授予规则。
func grant_bonus_armor(amount: int, maximum: int = -1) -> int:
	if amount <= 0 or is_death or owner_character.is_death:
		return 0
	var granted: int = amount if maximum < 0 else mini(amount, maxi(0, maximum - bonus_armor)) # 仅记录未超过本次上限的新增护甲。
	if granted <= 0:
		return 0
	bonus_armor += granted
	bonus_armor_changed.emit(bonus_armor)
	_update_armor_label()
	return granted

## [param damage] 已完成原版减伤；先消耗冰壳，再消耗技能护甲，余量进入本体生命。
func absorb_temporary_armor(damage: int) -> int:
	damage = _ice_shell.absorb(damage)
	if damage <= 0 or bonus_armor <= 0:
		return maxi(0, damage)
	var absorbed: int = mini(damage, bonus_armor) # 冰壳之后仅消耗实际存在的技能护甲。
	bonus_armor -= absorbed
	bonus_armor_changed.emit(bonus_armor)
	_update_armor_label()
	return damage - absorbed

## 冰壳和技能护甲均不参与生命百分比与自动回复，仅加入总可消耗血量查询。
func get_all_hp() -> int:
	return curr_hp + bonus_armor + ice_shell_hp

## [param attack_value] 和 [param bonus_damage] 是同次命中；[param bonus_cap] 保留原附伤限制。
## [param mode]、[param drop]、[param sfx] 和 [param extra_drop] 沿用伤害表现设置。
## [param receipt] 记录真实承伤者，[param hit_scope] 保存伤害来源和实际受击资格。返回原目标是否死亡。
func Hp_loss(attack_value: int, mode: BulletRegistry.AttackMode = BulletRegistry.AttackMode.Norm,
		drop = true, sfx: bool = true, extra_drop: bool = true, bonus_damage: int = 0,
		bonus_cap: int = -1, receipt: Variant = null, hit_scope: CombatHitScope = null):
	if _bypass_damage_block or is_death or attack_value + maxi(0, bonus_damage) <= 0:
		return super.Hp_loss(attack_value, mode, drop, sfx, extra_drop, bonus_damage, bonus_cap, receipt, hit_scope)
	var impact: CombatHitScope.PlantImpact = hit_scope.plant_impact if hit_scope != null else CombatHitScope.PlantImpact.DIRECT # 历史调用默认为普通伤害。
	var recipient: HpComponentPlant = _impact_recipient(impact) if not is_damage_immune() else self # 无敌目标不转嫁已免疫的伤害。
	if recipient == null:
		reset_hit_receipt(receipt, owner_character)
		return false
	recipient._receive_plant_hit(attack_value, mode, drop, sfx, extra_drop, bonus_damage, bonus_cap, receipt, hit_scope)
	if impact == CombatHitScope.PlantImpact.CRUSH and is_instance_valid(owner_character) and not is_death:
		(owner_character as Plant000Base).show_crush_contact()
	return is_death

## 尝试用当前防护处理 [param scope] 所描述的原生必杀。返回 true 时调用者无需执行原生即死。
func intercept_lethal_plant_hit(scope: CombatHitScope) -> bool:
	var recipient: HpComponentPlant = _impact_recipient(scope.plant_impact) # 先确定实际承伤者。
	if recipient == null:
		return true
	var crush: bool = scope.plant_impact == CombatHitScope.PlantImpact.CRUSH # 只有碾压可用监牢转换。
	if recipient == self and (not crush or crush_health_fraction <= 0.0):
		return false
	var amount: int = get_all_hp() # 代伤保留原目标当下全部可消耗血池。
	if crush and recipient.crush_health_fraction > 0.0:
		amount = floori(recipient.max_hp * recipient.crush_health_fraction)
	recipient._receive_plant_hit(amount, BulletRegistry.AttackMode.Penetration, false, false, true, 0, -1, null, scope)
	return true

## 已经路由的 [param amount] 与同击 [param bonus] 从这里进入原生生命，绕过再次选择护卫。
## [param mode]、[param drop]、[param sfx]、[param extra_drop]、[param bonus_cap] 沿用原生选项。
## [param receipt] 可接收结果，[param scope] 保留攻击者和死因，反伤读取原生确认的实际损失。
func _receive_plant_hit(amount: int, mode: BulletRegistry.AttackMode, drop: bool, sfx: bool,
		extra_drop: bool, bonus: int, bonus_cap: int, receipt: Variant, scope: CombatHitScope) -> void:
	var result: Variant = receipt # 仅当需要反伤且调用者未请求回执时才创建。
	var reflect: bool = reflects_damage and scope != null and scope.attacker_id != 0
	if reflect and not result is Dictionary:
		result = {}
	super.Hp_loss(amount, mode, drop, sfx, extra_drop, bonus, bonus_cap, result, scope)
	if reflect:
		reflect_plant_loss(int(result.get("actual_loss", 0)), scope)

## 把 [param loss] 点实际损失还给 [param scope] 记录的活体来源；僵王反伤比例为十分之一。
func reflect_plant_loss(loss: int, scope: CombatHitScope) -> void:
	if not reflects_damage or loss <= 0 or scope == null or not is_instance_id_valid(scope.attacker_id):
		return
	var attacker := instance_from_id(scope.attacker_id) as Character000Base # 延迟弹体允许来源已经离场。
	if not is_instance_valid(attacker) or attacker.is_death or attacker.is_queued_for_deletion() \
			or not attacker.is_inside_tree() or not (attacker is Zombie000Base or attacker is ZB000Base or attacker is EnemyStructureBase):
		return
	var damage: int = floori(loss * 0.1) if attacker is ZB000Base else loss # 护甲及僵王阶段门禁仍由攻击者本身结算。
	if damage > 0:
		attacker.be_attacked_bullet(damage, BulletRegistry.AttackMode.Norm, true, false)

## 为 [param impact] 选一个真实承伤组件。null 表示直接爆炸被铁铠免疫。
func _impact_recipient(impact: CombatHitScope.PlantImpact) -> HpComponentPlant:
	var victim := owner_character as Plant000Base # 用原目标的正式占格确定守护范围。
	if victim == null or not victim.is_inside_tree() or victim.is_queued_for_deletion():
		return self
	if impact == CombatHitScope.PlantImpact.EXPLOSION:
		if intercepts_explosions:
			return null
		var iron: HpComponentPlant = _closest_explosion_guard(victim) # 专用范围守护优先承接爆炸。
		if iron != null:
			return iron
	for occupied: PlantCell in victim.battle_placement_cells: # 多格植物可由任一实际占格前方的高坚果承伤。
		if not is_instance_valid(occupied) or occupied.board == null:
			continue
		var guard: HpComponentPlant = _guard_in(occupied.board.right_of(occupied), victim) # 向右是正面；沿棋盘拓扑匹配同平台一格。
		if guard != null and guard.guards_rear_cell:
			return guard
	return self

## 为 [param victim] 找周围一格范围内最近的铁铠。同距离优先较早的植物实例。
func _closest_explosion_guard(victim: Plant000Base) -> HpComponentPlant:
	var chosen: HpComponentPlant = null # 当前最合适的承伤者。
	var closest: int = 0 # 最短逻辑格距。
	var chosen_id: int = 0 # 平手时稳定选择。
	for origin: PlantCell in victim.battle_placement_cells: # 每个真实占格至多检查 3×3 个规则地址。
		if not is_instance_valid(origin) or origin.board == null or origin.board_definition == null:
			continue
		for candidate: PlantCell in _explosion_cells(origin): # 显式布局只沿一步邻接查询。
			var iron: HpComponentPlant = _guard_in(candidate, victim) # 同格其他种植层也可由铁铠保护。
			if iron == null or not iron.intercepts_explosions:
				continue
			var difference: Vector2i = candidate.row_col - origin.row_col # 按拓扑格距决定优先级。
			var distance: int = absi(difference.x) + absi(difference.y)
			var identity: int = iron.owner_character.get_instance_id() # 平手只接受较早的真实实体。
			if chosen == null or distance < closest or (distance == closest and identity < chosen_id):
				chosen = iron
				closest = distance
				chosen_id = identity
	return chosen

## 返回 [param origin] 同平台 3×3 的现存格子；稀疏棋盘跳过空地址。
static func _explosion_cells(origin: PlantCell) -> Array[PlantCell]:
	var board: BoardRuntime = origin.board # 使用此刻的棋盘及平台状态。
	if origin.board_definition.explicit_neighbors:
		return board.neighbors(origin)
	var cells: Array[PlantCell] = [] # 普通棋盘至多九次字典查找。
	for row: int in range(-1, 2): # 上一行、当前行、下一行。
		for column: int in range(-1, 2): # 前后只取一步。
			var cell: PlantCell = board.cell_at(origin.row_col + Vector2i(row, column))
			if cell != null and cell.board_definition.surface_id == origin.board_definition.surface_id:
				cells.append(cell)
	return cells

## 检查 [param cell] 普通层的活体守护者；[param victim] 永远不会被视为自己的护卫。
static func _guard_in(cell: PlantCell, victim: Plant000Base) -> HpComponentPlant:
	if cell == null:
		return null
	var entry: Variant = cell.plant_in_cell.get(CharacterRegistry.PlacePlantInCell.Norm) # 高坚果登记在普通占位层。
	if not is_instance_valid(entry) or entry == victim or entry.is_death or entry.is_queued_for_deletion() \
			or not entry.is_inside_tree() or entry.is_being_relocated:
		return null
	return entry.hp_component as HpComponentPlant

## 所有前置减伤先结算，再施加单次上限，最后进入可消耗护甲。
## [param damage] 主伤；[param bonus_damage] 同击附伤；[param bonus_cap] 为附伤上限，-1 不限制。
func resolve_damage(damage: int, bonus_damage: int = 0, bonus_cap: int = -1) -> int:
	var resolved: int = super.resolve_damage(damage, bonus_damage, bonus_cap) # 主伤与附伤共用植物单次上限。
	if _bypass_damage_block or max_single_hit_fraction <= 0.0:
		return resolved
	if crush_health_fraction > 0.0:
		return mini(resolved, floori(float(max_hp) * max_single_hit_fraction))
	return mini(resolved, maxi(1, ceili(float(max_hp) * max_single_hit_fraction)))

## 处决与铲除无视护甲池；当生命被强制清空时一并清除幽灵护甲。
## [param amount] 为强制损失；[param mode]、[param drop]、[param sfx]、[param extra_drop] 沿用基类表现参数。
## [param hit_scope] 只传递本次命中资格和死因，普通铲除无需提供。
func apply_unblocked_loss(amount: int,
		mode: BulletRegistry.AttackMode = BulletRegistry.AttackMode.Norm,
		drop: bool = true, sfx: bool = true, extra_drop: bool = true, hit_scope: CombatHitScope = null) -> void:
	if amount >= curr_hp and bonus_armor > 0:
		bonus_armor = 0
		bonus_armor_changed.emit(0)
		_update_armor_label()
	super.apply_unblocked_loss(amount, mode, drop, sfx, extra_drop, hit_scope)

## 仅在独立技能护甲存在时显示第二行，不改写冰壳或本体标签。
func _update_armor_label() -> void:
	if is_instance_valid(_armor_label):
		_armor_label.visible = bonus_armor > 0
		_armor_label.text = "护甲 %d" % bonus_armor
