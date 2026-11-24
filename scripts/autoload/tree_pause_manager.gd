## 汇总游戏暂停因素，并通知需要区分暂停原因的场景节点。
extends Node

## 每次暂停因素更新后发送，即使场景树的聚合暂停状态没有变化。
signal pause_factors_changed

## 游戏暂停因素
enum E_PauseFactor {
	Menu,			## 菜单
	GameOver,		## 游戏结束
	ReChooseCard,	## 重新选卡
	AdventureContinue,	## 冒险阶段结算演出与续战询问
	SaviorCinematic,		## 救主切换机位期间独占的战斗冻结
	CharacterSkillTutorial,	## 首次角色技能说明，确认或暂缓后由本场教学释放
}

## 各暂停因素是否生效；任一值为 true 时暂停场景树。
var curr_pause_factor: Dictionary = {}
## 二阶段等战场规则的所有者 ID，随所属战场离树清理。
var _menu_pause_blocks: Dictionary[int, bool] = {}

## [param owner] 存在于场景树期间，菜单可以打开，战斗不因菜单暂停。
func block_menu_pause(owner: Node) -> void:
	var id: int = owner.get_instance_id() # 同一战场只绑定一次退出清理。
	if _menu_pause_blocks.has(id):
		return
	_menu_pause_blocks[id] = true
	owner.tree_exiting.connect(_remove_menu_pause_block.bind(id), CONNECT_ONE_SHOT)
	if is_paused_for(E_PauseFactor.Menu):
		end_tree_pause(E_PauseFactor.Menu)

## [param id] 是即将离场的规则所有者，其他战场规则不受影响。
func _remove_menu_pause_block(id: int) -> void:
	_menu_pause_blocks.erase(id)

## 查询 [param pause_factor] 当前是否生效，用于区分场景树的暂停原因。
func is_paused_for(pause_factor: E_PauseFactor) -> bool:
	return curr_pause_factor.get(pause_factor, false)

## 更新场景树暂停状态，并通知轮次退场等需要区分暂停原因的逻辑。
func _update_pause_state() -> void:
	get_tree().paused = curr_pause_factor.values().any(func(v): return v)
	if get_tree().paused:
		print("暂停游戏")
	else:
		print("继续游戏")
	# 重新选卡暂停中打开菜单时，树仍暂停，但退雾必须收到新的菜单因素。
	pause_factors_changed.emit()

## 启用 [param pause_factor]，更新场景树并通知暂停因素变化。
func start_tree_pause(pause_factor: E_PauseFactor) -> void:
	if pause_factor == E_PauseFactor.Menu and not _menu_pause_blocks.is_empty():
		return
	curr_pause_factor[pause_factor] = true
	_update_pause_state()

## 解除 [param pause_factor]；其他因素仍生效时场景树保持暂停。
func end_tree_pause(pause_factor: E_PauseFactor) -> void:
	curr_pause_factor[pause_factor] = false
	_update_pause_state()

## 清除所有暂停因素
func end_tree_pause_clear_all_pause_factors() -> void:
	curr_pause_factor.clear()
	_update_pause_state()
