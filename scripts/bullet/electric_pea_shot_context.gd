## 电能豌豆单枚电球的出手快照；已离手电球不依赖母株继续存活。
extends RefCounted
class_name ElectricPeaShotContext

## 原关卡、棋盘、轮次及冒险阶段共同限制电球生命周期。
var game: MainGameManager
## 发射时的棋盘实例，换板后旧弹立即失效。
var board: BoardRuntime
## 发射时的关卡轮次。
var round_index: int = -1
## 发射时的冒险阶段资源；普通关卡为空。
var phase: StagePhaseDefinition
## 命中来源决定能否触发攻击眩晕；矩阵持续帧伤总是绕过控制。
enum HitKind {
	CONTACT, ## 电球与目标真实碰撞。
	ARC, ## 半秒放电的原始电弧。
	JUMP, ## 从原始电弧派生的一次跳跃。
	SPLIT, ## 母球首个实际命中的分裂撞击。
	FIELD, ## 矩阵持续帧伤。
}

## 同一同步查询区间已确认的组件和受击监听。各承伤层只在实际访问时记录。
enum FieldAuditFlag { BASE = 1, BODY = 2, ARMOR = 4 }

## 矩阵候选附带的监听核对结果。一次未知回调后随世界几何一起作废。
class FieldAudit:
	## 对应矩阵原候选槽位的 [enum FieldAuditFlag] 位标记。
	var flags := PackedByteArray()

## 同一株实际出战实例的身份，母株死亡后仍用于合并矩阵。
var source_id: int = 0
## 本轮离手的电球规则；所有路线及后代共享。
var promotions: ElectricPeaPromotions
## 矩阵每帧伤害，包含一次出战输出修正。
var matrix_damage: int = 0
## 发射的地面行，屋顶高度不改变行身份。
var lane: int = -1
## 原地格的世界间距，用于把原版格数范围换算为本项目坐标。
var cell_pitch: Vector2 = Vector2(80.0, 100.0)
## 已含卡片、光环及通用输出修正的穿透伤害。
var contact_damage: int = 5
## 已含卡片、光环及通用输出修正的邻近电击伤害。
var bolt_damage: int = 20
## 冻结的转职配色档，零为原始贴图。
var appearance_rank: int = 0
## 发射时冻结的共享攻击词条，命中时只计算动态目标因素。
var attack_context: PlantAttackContext


## 从实际出手的 [param plant] 捕获一次离手；[param rules] 为冻结的转职参数。原战场已失效时返回空。
static func capture(plant: Plant000Base, rules: ElectricPeaPromotions) -> ElectricPeaShotContext:
	if not is_instance_valid(plant) or not is_instance_valid(plant.plant_cell):
		return null
	var shot := ElectricPeaShotContext.new() # 同一次离手共享伤害与击杀账本。
	shot.game = Global.main_game
	if not is_instance_valid(shot.game) or not shot.game.is_ancestor_of(plant):
		return null
	shot.board = shot.game.board
	shot.round_index = shot.game.curr_game_round
	shot.phase = AdventureSession.get_active_phase(shot.game.game_para)
	if not shot.is_active():
		return null
	shot.source_id = plant.get_instance_id()
	shot.promotions = rules
	if rules.matrix_damage > 0:
		shot.matrix_damage = plant.battle_damage(rules.matrix_damage)
	shot.lane = plant.lane
	shot.cell_pitch = shot.board.local_pitch(plant.plant_cell).abs()
	shot.cell_pitch.x = maxf(1.0, shot.cell_pitch.x)
	shot.cell_pitch.y = maxf(1.0, shot.cell_pitch.y)
	shot.contact_damage = plant.battle_damage(5)
	shot.bolt_damage = plant.battle_damage(20)
	shot.appearance_rank = plant.plant_spawn_profile.promotion_tier() if plant.plant_spawn_profile != null else 0
	shot.attack_context = plant.capture_attack_context()
	return shot


## 返回本枚电球是否仍属于原战场的有效战斗；普通暂停保留弹体但不推进时钟。
func is_active() -> bool:
	return is_instance_valid(game) and game.is_inside_tree() and not game.is_queued_for_deletion() \
		and game == Global.main_game and game.get_tree().current_scene == game \
		and board != null and game.board == board and game.curr_game_round == round_index \
		and AdventureSession.get_active_phase(game.game_para) == phase \
		and game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false)


## 返回 [param target] 的攻击行；根节点与机甲落点分离时按 [param impact] 查当前棋盘。
func target_lane(target: Character000Base, impact: Vector2) -> int:
	if not target is ZB000Base:
		return target.lane
	var cell: PlantCell = board.nearest_cell(impact) # 僵王落点可能同时覆盖多行。
	return cell.combat_lane if is_instance_valid(cell) else lane


## 用本球快照对 [param target] 结算矩阵场伤，[param scope] 按实际承伤者去重。
## [param audit] 仅在矩阵同步区间复用已验证的 [param slot] 监听；省略时逐次核对。
## 返回本击是否可能经同步回调改变后续候选的受击几何。
func hit_field(target: Character000Base, scope: CombatHitScope, audit: FieldAudit = null, slot: int = 0) -> bool:
	if matrix_damage <= 0 or not is_active() or game.get_tree().paused:
		return false
	if attack_context != null or not target is Zombie000Base:
		hit(target, matrix_damage, HitKind.FIELD, scope)
		return true
	var zombie: Zombie000Base = target as Zombie000Base # 矩阵在精确相交前已核对仍可命中。
	var hp: HpComponentZombie = zombie.hp_component as HpComponentZombie # 真实伤害仍由原生命组件处理。
	var resolved: int = _resolved_stable_field_damage(zombie, hp, scope, audit, slot) # 负值表示必须即时结算并刷新几何。
	var hit_game: MainGameManager = game # 回调前后成对处理同一战场，即使期间切换关卡。
	if resolved < 0:
		ElectricPeaFlightQuery.begin_sync_hit(hit_game)
	hp.apply_hit(matrix_damage, BulletRegistry.AttackMode.Real,
		true, false, true, 1.0, 0, -1, null, scope, resolved)
	if resolved < 0:
		ElectricPeaFlightQuery.end_sync_hit(hit_game)
	return resolved < 0


## 仅在 [param zombie] 的普通受击路径不会运行未知回调或触发阶段改变时，允许复用候选几何。
## [param hp] 和 [param scope] 对应本次真实承伤入口。未知组件、代伤和可见血条走保守路径。
## [param audit] 记录同一同步区间内 [param slot] 的稳定监听。返回已减伤的伤害，-1 交给完整入口。
func _resolved_stable_field_damage(zombie: Zombie000Base, hp: HpComponentZombie, scope: CombatHitScope,
		audit: FieldAudit, slot: int) -> int:
	if hp.is_visible_in_tree() or hp.bonus_armor != 0 or hp._bypass_damage_block or hp._resolving_hit \
			or hp._handling_transferred_hit or hp.armor1_fixed_damage_per_hit != 0 \
			or (scope != null and (scope.before_death.is_valid() or scope.get_script() != CombatHitScope)):
		return -1
	var checked: int = audit.flags[slot] if audit != null else 0 # 只复用本候选及本同步区间的成功检查。
	var stage: HpStageChangeComponent = zombie.hp_stage_change_component # 血量和阶段阈值始终使用本击即时数据。
	if not (checked & FieldAuditFlag.BASE):
		if not _has_native_field_observers(zombie, hp, stage):
			return -1
		checked |= FieldAuditFlag.BASE
	if hp.damage_transfer.has_sources():
		return -1
	var damage: int = hp.resolve_damage(matrix_damage) # 已核对受击监听，正式生命入口复用本次结果。
	if damage > 0:
		if hp.curr_hp_armor1 > 0:
			# 一倍倍率的防具减伤只降低此上限。无法证明安全的临界情况沿用原入口。
			var armor_ceiling: int = roundi(float(damage)) # 与原护甲分流使用相同的整数到浮点取整。
			if hp.armor_1_control.is_visible_in_tree() or hp.curr_hp_armor1 <= armor_ceiling \
					or not _stays_in_hp_stage(hp.curr_hp_armor1 - armor_ceiling,
						stage.curr_hp_armor1_stage, stage.boundary_value_hp_armor1):
				return -1
			if not (checked & FieldAuditFlag.ARMOR):
				if hp.armor1_reduction == null or hp.armor1_reduction.get_script().resource_path \
						!= "res://scripts/character/components/damage_reduction_effect.gd" \
						or not _only_field_listener(hp.signal_hp_armor1_loss, stage.judge_body_change_armor.bind(true)):
					return -1
				checked |= FieldAuditFlag.ARMOR
		else:
			if hp.curr_hp - damage <= hp.death_hp or not _stays_in_hp_stage(hp.curr_hp - damage,
					stage.curr_hp_stage, stage.boundary_value_hp):
				return -1
			if not (checked & FieldAuditFlag.BODY):
				if not _only_field_listener(hp.signal_hp_loss, stage.judge_body_change):
					return -1
				checked |= FieldAuditFlag.BODY
	if audit != null:
		audit.flags[slot] = checked
	return damage


## 验证 [param zombie]、[param hp]、[param stage] 使用已核对的原生组件及同步监听。
## 成功结果可保留到这批矩阵遇到未知回调为止；此处不冻结血量、减伤或阶段阈值。
func _has_native_field_observers(zombie: Zombie000Base, hp: HpComponentZombie, stage: HpStageChangeComponent) -> bool:
	if zombie.get_script().resource_path != "res://scripts/character/zombie/zombie_001_norm.gd" \
			or hp.get_script().resource_path != "res://scripts/character/components/hp_component/component_hp_zombie.gd" \
			or hp.owner_character != zombie or hp.owner != zombie \
			or hp.received_attack.has_connections() or hp.combat_health_lost.has_connections():
		return false
	if hp.damage_transfer == null or hp.damage_transfer.get_script().resource_path \
			!= "res://scripts/character/components/damage_transfer_effect.gd" \
			or hp.damage_block == null or hp.damage_block.get_script().resource_path \
			!= "res://scripts/character/components/damage_block_effect.gd" \
			or hp.damage_reduction == null or hp.damage_reduction.get_script().resource_path \
			!= "res://scripts/character/components/damage_reduction_effect.gd":
		return false
	if not is_instance_valid(stage) or stage.get_script().resource_path \
			!= "res://scripts/character/components/hp_component/component_hp_stage_change.gd":
		return false
	if not _only_field_listener(hp.signal_zombie_hp_loss, zombie._relay_zombie_hp_loss):
		return false
	if not zombie.signal_zombie_hp_loss.has_connections():
		return true
	var roster: ZombieManager = game.zombie_manager # 原生刷新状态只读取当前战场。
	if not is_instance_valid(roster) or not is_instance_valid(roster.zombie_wave_manager) \
			or roster.get_script().resource_path != "res://scripts/manager/zombie_manager/zombie_manager.gd":
		return false
	var manager: ZombieWaveRefreshManager = roster.zombie_wave_manager.zombie_wave_refresh_manager # 原生残半统计延迟发布下一波。
	return is_instance_valid(manager) and manager.zombie_manager == roster and manager.get_script().resource_path \
		== "res://scripts/manager/zombie_manager/zm_zombie_wave_refresh_manager.gd" \
		and _only_field_listener(zombie.signal_zombie_hp_loss, manager.judge_half_refresh)


## [param remaining] 保守的最低剩余生命；以 [param stage_index] 和 [param thresholds] 检查原阶段监听是否为空操作。
static func _stays_in_hp_stage(remaining: int, stage_index: int, thresholds: Array[int]) -> bool:
	for index: int in range(maxi(0, stage_index + 1), thresholds.size()): # 检查所有尚未到达的阶段，兼容非单调配置。
		if remaining <= thresholds[index]:
			return false
	return true


## [param hook] 只允许已核对的同步回调 [param listener]；动态增加的监听器会切回即时几何查询。
static func _only_field_listener(hook: Signal, listener: Callable) -> bool:
	for connection: Dictionary in hook.get_connections(): # 比较完整 Callable，包含绑定参数。
		if connection["callable"] != listener:
			return false
	return true


## 对 [param target] 结算 [param base_damage]，保留防具、保护者、免疫及击杀归属。
## [param kind] 区分直击、原弧、跳跃、分裂撞击和持续帧伤；[param scope] 按实际承伤者去重。
## [param hit_receipt] 可选输出实际承伤者。返回实扣的本体和防具生命总量；零不触发派生效果。
func hit(target: Character000Base, base_damage: int, kind: HitKind,
		scope: CombatHitScope = null, hit_receipt: Dictionary = {}) -> int:
	if not is_active() or game.get_tree().paused or not ElectricPeaFlightQuery.can_hit(target) or base_damage <= 0:
		HpComponent.reset_hit_receipt(hit_receipt, null)
		return 0
	# 伤害信号可同步改变受击盒或棋盘，后续电球按新世界几何查询。
	var hit_game: MainGameManager = game # 回调前后成对处理同一战场。
	ElectricPeaFlightQuery.begin_sync_hit(hit_game)
	var damage: int = attack_context.modify_damage(base_damage, target) if attack_context != null else base_damage # 动态目标修饰只执行一次。
	var receipt: Dictionary = hit_receipt # 生命入口先清空回执，再写入真实承伤者、损血及死亡者。
	if target is Zombie000Base:
		var armor: float = attack_context.armor_multiplier if attack_context != null else 1.0 # 共享修饰只改变装备防具。
		(target.hp_component as HpComponentZombie).apply_hit(damage, BulletRegistry.AttackMode.Real,
			true, false, true, armor, 0, -1, receipt, scope)
		if kind != HitKind.FIELD and is_instance_valid(target) and is_instance_valid(target.body):
			target.body.body_light()
	else:
		target.be_attacked_bullet(damage, BulletRegistry.AttackMode.Real, true, false, 0, -1, receipt, scope)
	if attack_context != null:
		attack_context.resolve_kill(receipt.get("casualty"))
	var loss: int = int(receipt.get("actual_loss", 0)) # 免疫、格挡和零伤害均不派发实伤效果。
	if (loss > 0 or kind == HitKind.SPLIT) and kind != HitKind.FIELD and is_active():
		var seconds: float = promotions.stun_seconds # 继承过载；母球首次实伤时可额外使用分裂眩晕。
		if kind == HitKind.SPLIT:
			seconds = maxf(seconds, promotions.split_stun)
		var recipient: Variant = receipt.get("recipient") # 眩晕给真正承伤者，统一入口排除僵王和设施。
		if seconds > 0.0 and is_instance_valid(recipient):
			AdventurePlantNegativeEffects.apply(recipient, AdventurePlantNegativeEffects.Kind.STUN,
				source_id, seconds)
	ElectricPeaFlightQuery.end_sync_hit(hit_game)
	return loss
