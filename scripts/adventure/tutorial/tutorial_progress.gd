## 任务与战斗教学共用的完成标记事务；只更新当前玩家档案，不保存界面或战斗运行态。
extends RefCounted

## 允许独立确认完成的教学节点；技能操作按桌面和手机分别记录首次观看。
const ALLOWED_STEPS := [
	"quest_notice", "research_dave", "library_tour", "shop_dave",
	"character_skill_desktop", "character_skill_mobile",
]

## 将 [param step] 写入 [param state]；验证 [param wallet] 档案归属，通过 [param persist] 保存。
## 已完成的合法步骤直接返回 true；非法输入或保存失败返回 false，保存失败恢复原教学标记。
static func mark_step(state: AdventureState, wallet: GlobalGameState, persist: Callable, step: String) -> bool:
	if state == null or wallet == null or wallet.adventure_state != state or not persist.is_valid() \
			or step not in ALLOWED_STEPS:
		return false
	if state.tutorial_steps.get(step, false):
		return true
	var before: Dictionary = state.tutorial_steps.duplicate() # 不提前消耗可重试的教学节点。
	state.tutorial_steps[step] = true
	if persist.call() != true:
		state.tutorial_steps.assign(before)
		return false
	return true
