## 任务教学只派生下一步并保存已看过的教学节点，不发奖励、不解锁功能。
extends RefCounted

## 根据 [param state] 的真实任务状态返回教学节点；重启从尚未完成的节点继续。
static func next_step(state: AdventureState) -> String:
	if not AdventureQuestService.quests_unlocked(state):
		return ""
	if not AdventureQuestService.claimed(state, "first_expedition"):
		return "first_reward" if state.tutorial_steps.get("quest_notice", false) else "quest_notice"
	if AdventureQuestService.completed(state, "first_craft") or state.tutorial_steps.get("research_wall_nut", false):
		return ""
	return "research" if state.tutorial_steps.get("research_dave", false) else "research_dave"

## 将 [param step] 写入 [param state]；验证 [param wallet] 档案归属，通过 [param persist] 保存，失败回滚。
static func mark_step(state: AdventureState, wallet: GlobalGameState, persist: Callable, step: String) -> bool:
	if state == null or wallet == null or wallet.adventure_state != state or not persist.is_valid() or step not in ["quest_notice", "research_dave"]:
		return false
	if state.tutorial_steps.get(step, false):
		return true
	var before: Dictionary = state.tutorial_steps.duplicate() # 不提前消耗可重试的教学节点。
	state.tutorial_steps[step] = true
	if persist.call() != true:
		state.tutorial_steps.assign(before)
		return false
	return true
