## 单次冒险战斗唯一的主动技能运行时：穿越普通、噩梦、终末阶段，不进入玩家存档。
## 只在有效游戏时间推进冷却；UI、效果和技能定义均不拥有冷却计时器。
extends Node
class_name CharacterSkillRuntime

## 绑定技能、冷却或可用性发生变化时发出；HUD 只订阅此投影。
signal state_changed
## [param id] 只在实际效果成功提交后广播，用于独立演出监听。
signal cast_committed(id: StringName)

## 当前唯一战斗场景，不能跨玩家档案与场景保留。
var _game: MainGameManager
## 本局只读技能定义副本；为空表示未装备可用技能。
var _skill: CharacterSkillDefinition
## 战斗进入时冻结的技能 ID。
var _skill_id: StringName = &""
## 冷却剩余的有效游戏秒。
var _remaining: float = 0.0
## 防止阶段切换或重复主战斗事件重新绑定技能、刷新冷却。
var _bound: bool = false
## 禁止连续输入与效果回调重入同一个施放事务。
var _casting: bool = false

## 在 [param battle] 由 MainGameManager 初始化，并在整个战斗场景生命周期内保持。
func setup(battle: MainGameManager) -> void:
	_game = battle
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_physics_process(false)

## 从 [param id] 解析一次技能身份；空 ID 为合法的无技能角色。
## 配置开局冷却的技能从首次开战开始计时。
## 重复调用不影响当前冷却或身份，返回是否成功装配有效技能。
func bind_skill(id: StringName) -> bool:
	if _bound:
		return _skill != null
	_bound = true
	_skill_id = id
	_skill = CharacterSkillCatalog.definition(id)
	_remaining = _skill.cooldown_seconds if _skill != null and _skill.starts_on_cooldown else 0.0
	set_physics_process(_remaining > 0.0) # 只在开局有剩余冷却时启动计时。
	state_changed.emit()
	return _skill != null

## 当前战斗允许技能输入时返回 true；头像、按钮、快捷键与手势使用同一场景门禁。
## 冷却不影响手势的输入所有权，但仍由 [method is_available] 阻止实际施放。
func is_input_enabled() -> bool:
	if _skill == null or not is_instance_valid(_game) or not _game.is_inside_tree() \
			or not CharacterSkillContext.new(_game, _skill_id).is_active():
		return false
	var transition: Node = _game.get_node_or_null(^"SceneTransition") # 切场遮幕期间禁止迟到输入。
	var pause_menu := _game.get_node_or_null(^"%BattlePauseMenu") as Control # 部分Boss菜单不会暂停场景树。
	var dialog := _game.get_node_or_null(^"%Dialog") as Control # 原版未暂停提示仍独占界面输入。
	return (transition == null or not transition.busy) \
		and (pause_menu == null or not pause_menu.is_visible_in_tree()) \
		and (dialog == null or not dialog.is_visible_in_tree())

## 只有输入场景有效、冷却结束且没有重入施放事务时才返回 true。
func is_available() -> bool:
	return not _casting and _remaining <= 0.0 and is_input_enabled()

## 尝试施放一次。效果必须同步返回真正的提交结果；失败、无目标和无效上下文不消耗冷却。
func try_activate() -> bool:
	if not is_available():
		return false
	var context := CharacterSkillContext.new(_game, _skill_id) # 本次施放不可跨后续阶段。
	if not _skill.effect.can_execute(context):
		return false
	_casting = true
	var committed: bool = _skill.effect.execute(context) # 效果业务只在统一执行入口内发生。
	if committed:
		_remaining = _skill.cooldown_seconds
		set_physics_process(_remaining > 0.0) # 只有成功进入冷却才启动本局时钟。
		cast_committed.emit(_skill_id)
	_casting = false
	state_changed.emit()
	return committed

## 仅在当前战斗可操作时消耗 [param delta] 秒，尊重引擎暂停及 2× 游戏速度。
func _physics_process(delta: float) -> void:
	if _skill == null or _remaining <= 0.0:
		set_physics_process(false)
		return
	if not is_instance_valid(_game) or _game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME \
			or not AdventureSession.owns_battle(_game.game_para) \
			or AdventureSession.challenge_state not in [AdventureSession.ChallengeState.NORMAL_ACTIVE, \
				AdventureSession.ChallengeState.NIGHTMARE_ACTIVE, AdventureSession.ChallengeState.TERMINAL_ACTIVE]:
		return
	var previous: float = _remaining # UI 以 0.1 秒为最小刷新单元，避免每物理帧重建控件。
	_remaining = maxf(0.0, previous - delta)
	if _remaining == 0.0:
		set_physics_process(false) # 冷却完成后休眠，直到下一次成功释放。
	if _remaining == 0.0 or floori(previous * 10.0) != floori(_remaining * 10.0):
		state_changed.emit()

## 只读的技能定义；不可把此引用当作可编辑目录项写回磁盘。
func definition() -> CharacterSkillDefinition:
	return _skill

## 冷却剩余时间（游戏秒）；未装备技能时为零。
func remaining_seconds() -> float:
	return _remaining

## 0 表示完全就绪，1 表示满冷却，用于 HUD 图形遮罩。
func cooldown_ratio() -> float:
	return clampf(_remaining / _skill.cooldown_seconds, 0.0, 1.0) \
		if _skill != null and _skill.cooldown_seconds > 0.0 else 0.0

## 场景退出即释放运行态，绝不把技能剩余冷却保存到玩家档案。
func _exit_tree() -> void:
	set_physics_process(false)
	_skill = null
	_game = null
