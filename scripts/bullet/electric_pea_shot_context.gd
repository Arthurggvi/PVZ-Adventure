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
	return cell.row_col.x if is_instance_valid(cell) else lane


## 对 [param target] 结算 [param base_damage]，保留防具、保护者、免疫及击杀归属。
## [param kind] 区分直击、原弧、跳跃、分裂撞击和持续帧伤；[param scope] 按实际承伤者去重。
## [param hit_receipt] 可选输出实际承伤者。返回实扣的本体和防具生命总量；零不触发派生效果。
func hit(target: Character000Base, base_damage: int, kind: HitKind,
		scope: CombatHitScope = null, hit_receipt: Dictionary = {}) -> int:
	if not is_active() or game.get_tree().paused or not ElectricPeaFlightQuery.can_hit(target) or base_damage <= 0:
		HpComponent.reset_hit_receipt(hit_receipt, null)
		return 0
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
	if loss > 0 and kind != HitKind.FIELD and is_active():
		var seconds: float = promotions.stun_seconds # 继承过载；母球首次实伤时可额外使用分裂眩晕。
		if kind == HitKind.SPLIT:
			seconds = maxf(seconds, promotions.split_stun)
		var recipient: Variant = receipt.get("recipient") # 眩晕给真正承伤者，统一入口排除僵王和设施。
		if seconds > 0.0 and is_instance_valid(recipient):
			AdventurePlantNegativeEffects.apply(recipient, AdventurePlantNegativeEffects.Kind.STUN,
				source_id, seconds)
	return loss
