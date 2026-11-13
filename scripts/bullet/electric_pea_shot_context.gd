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
## 电球所在的地面行，屋顶高度不改变行身份。
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


## 从实际出手的 [param plant] 捕获本枚电球；原战场已失效时返回空。
static func capture(plant: Plant000Base) -> ElectricPeaShotContext:
	if not is_instance_valid(plant) or not is_instance_valid(plant.plant_cell):
		return null
	var shot := ElectricPeaShotContext.new() # 每枚电球独占快照及共享词条的击杀账本。
	shot.game = Global.main_game
	if not is_instance_valid(shot.game) or not shot.game.is_ancestor_of(plant):
		return null
	shot.board = shot.game.board
	shot.round_index = shot.game.curr_game_round
	shot.phase = AdventureSession.get_active_phase(shot.game.game_para)
	if not shot.is_active():
		return null
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


## 对仍合法的 [param target] 结算 [param base_damage]，保留护甲、保护者转伤和真实击杀归属。
## 伤害采用项目电击使用的 Real 路由，绕过二类盾牌但仍经过一类防具、减伤及无敌。
func hit(target: Character000Base, base_damage: int) -> void:
	if not is_active() or not ElectricPeaFlightQuery.can_hit(target):
		return
	var damage: int = attack_context.modify_damage(base_damage, target) if attack_context != null else base_damage # 逐次电击修饰一次。
	var casualty: Character000Base = null # 保护者可能成为本次真实死亡者。
	if target is Zombie000Base:
		var armor: float = attack_context.armor_multiplier if attack_context != null else 1.0 # 共享词条只影响装备防具。
		casualty = (target.hp_component as HpComponentZombie).apply_hit(damage,
			BulletRegistry.AttackMode.Real, true, false, true, armor)
		if is_instance_valid(target) and is_instance_valid(target.body):
			target.body.body_light()
	else:
		var alive: bool = not target.is_death # 设施不产击杀阳光，僵王仍通过专属受击入口。
		target.be_attacked_bullet(damage, BulletRegistry.AttackMode.Real, true, false)
		if alive and is_instance_valid(target) and target is ZB000Base and target.is_death:
			casualty = target
	if attack_context != null:
		attack_context.resolve_kill(casualty)
