## 阳光豆式光能：按实际战斗血池损失累积阳光，余数保留，重复授予增加转换层数。
extends Node
class_name AdventureSunBeanEffect

## 每个角色只持有一个受伤产光节点，不重复连接生命事件。
const NODE_NAME: StringName = &"AdventureSunBeanEffect"
## 一层每25点实伤对应5阳光；整数伤害积分避免浮点余数不断丢失。
const DAMAGE_PER_PACKET: int = 25
## 每份结算单位的阳光价值；较大掉落由统一入口合并为正常尺寸。
const SUN_PER_PACKET: int = 5
## 通过实际损失的战斗血池产光的角色。
var _target: Character000Base
## 授予状态的战场，拒绝跨场景沿用。
var _game: MainGameManager
## 冻结的轮次与冒险阶段，普通进入噩梦不会沿用旧状态。
var _round_index: int = -1
## 阶段资源身份；非冒险为null。
var _phase: StagePhaseDefinition
## 每次光能赋予增加一层转换效率，不创建第二个节点或第二条监听。
var _stacks: int = 0
## 肉体改造在魅惑后单独施加友军光能。
var _allied: bool = false
## 加权实际损伤积分；不足一个5阳光单位的部分留待下次。
var _damage_credit: int = 0
## 同步死亡通知可能早于最后一次损失通知，仅允许该帧的真实损失完成结算。
var _death_frame: int = -1

## 为 [param target] 赋予光能。[param allied] 显式允许肉体改造的魅惑友军。
## [param stacks] 和 [param credit] 可继承已有层数和未兑现积分，默认授予一层。
static func apply_to(target: Character000Base, allied: bool = false, stacks: int = 1, credit: int = 0) -> bool:
	var game: MainGameManager = Global.main_game # 不通过全局轮询查找受伤目标。
	if not is_instance_valid(target) or not (target is Zombie000Base or target is ZB000Base) \
			or not target.can_receive_negative_effects() \
			or target.is_death or target.is_hypno != allied or target.is_queued_for_deletion() or stacks <= 0 \
			or not target.is_inside_tree() or not is_instance_valid(target.hp_component) \
			or target.character_init_type != Character000Base.E_CharacterInitType.IsNorm \
			or not is_instance_valid(game) or not game.is_inside_tree() or game.is_queued_for_deletion() \
			or game.get_tree().current_scene != game or not game.is_ancestor_of(target) \
			or game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME \
			or TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
			or TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false):
		return false
	var effect: AdventureSunBeanEffect = target.get_node_or_null(NodePath(NODE_NAME)) as AdventureSunBeanEffect # 同目标复用已有监听。
	if effect == null:
		effect = AdventureSunBeanEffect.new()
		effect.name = NODE_NAME
		effect._target = target
		target.add_child(effect)
	if not effect._same_battle():
		effect.clear()
	effect._game = game
	effect._round_index = game.curr_game_round
	effect._phase = AdventureSession.get_active_phase(game.game_para)
	effect._allied = allied
	effect._stacks += stacks
	effect._damage_credit += maxi(0, credit)
	effect._death_frame = -1
	effect._set_tint(true)
	effect.set_physics_process(true)
	return true

## 返回实际在场的层数和未兑现积分；复制个体据此独立继续产光。
func copy_charge() -> Vector2i:
	return Vector2i(_stacks, _damage_credit) if _same_battle() else Vector2i.ZERO

## 伤害事件来自真实生命结算，死亡先撤表现但保留本帧最后一次伤害的兑现资格。
func _ready() -> void:
	set_physics_process(false)
	_target.hp_component.combat_health_lost.connect(_on_damage)
	_target.signal_character_death.connect(_on_death)
	_target.signal_character_be_hypno.connect(clear)

## [param amount] 是本次真实损失，含装备与临时护甲；强制卸甲和过量伤害不会进入此信号。
func _on_damage(amount: int) -> void:
	if amount <= 0 or _stacks <= 0 or not _same_battle() or _target.is_hypno != _allied \
			or (_target.is_death and _death_frame != Engine.get_process_frames()):
		return
	var finishing_hit: bool = _target.is_death and _death_frame == Engine.get_process_frames() # 只给当前同步末击保留结算窗口。
	if not finishing_hit and not _battle_active():
		return
	_damage_credit += amount * _stacks
	var value: int = floori(float(_damage_credit) / float(DAMAGE_PER_PACKET)) * SUN_PER_PACKET # 仅释放完整5点单位。
	if value > 0:
		var dropped: int = BattleSunDrop.spawn(_game, _target.global_position, value) # 未生成部分仍保留积分。
		_damage_credit -= roundi(float(dropped) / float(SUN_PER_PACKET)) * DAMAGE_PER_PACKET

## [param _delta] 仅用于场景生命周期检查；状态没有自发产光时钟。
func _physics_process(_delta: float) -> void:
	if not _battle_active() or _target.is_death or _target.is_hypno != _allied:
		clear()

## 真实死亡不会重新授予光能；延后清理给当前同步HP通知留出一次结算机会。
func _on_death() -> void:
	_death_frame = Engine.get_process_frames()
	_set_tint(false)
	set_physics_process(false)
	clear.call_deferred()

## 清空余数和来源层数，停止后续结算；节点可由同一角色未来再次复用。
func clear() -> void:
	_stacks = 0
	_damage_credit = 0
	_death_frame = -1
	_set_tint(false)
	set_physics_process(false)

## [param enabled] 仅写光能的黄色滤镜通道，不覆盖冰、恐惧或沉默。
func _set_tint(enabled: bool) -> void:
	if is_instance_valid(_target) and is_instance_valid(_target.body):
		_target.body.set_other_color(BodyCharacter.E_ChangeColors.SunInfusion,
			Color(1.0, 1.0, 0.35) if enabled else Color.WHITE)

## 换轮与普通/噩梦阶段分别校验；不因同一场景恢复处理而复活旧状态。
func _same_battle() -> bool:
	return is_instance_valid(_target) and _target.is_inside_tree() \
		and is_instance_valid(_game) and _game == Global.main_game \
		and _game.is_inside_tree() and not _game.is_queued_for_deletion() \
		and _game.get_tree().current_scene == _game and _game.is_ancestor_of(_target) \
		and _game.curr_game_round == _round_index \
		and AdventureSession.get_active_phase(_game.game_para) == _phase

## 新伤害只有正式战斗才能兑现；同步末击另有严格的同帧窗口。
func _battle_active() -> bool:
	return _same_battle() and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false)

## 大蒜换行只是可逆重挂，保留光能层数和余数；真正离场才回收。
func _exit_tree() -> void:
	if _target is Zombie000Base and (_target as Zombie000Base).is_changing_lane:
		return
	clear()
