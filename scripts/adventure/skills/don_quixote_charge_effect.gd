## 为每条可出战的实际棋盘行排定一匹血马，由冒险战局持有本次冲锋。
extends CharacterSkillEffect

## 技能绑定时才加载冲锋和它的美术、音效。
const Charge = preload("res://scripts/adventure/skills/don_quixote_charge.gd")

## [param context] 必须属于当前可施放战场、有特效层，且至少有一条实际棋盘行。
func can_execute(context: CharacterSkillContext) -> bool:
	return context != null and context.is_active() and is_instance_valid(context.game.bombs) \
		and context.game.bombs.is_inside_tree() and not context.game.bombs.is_queued_for_deletion() \
		and not context.board.cells().is_empty()

## 在 [param context] 提交整次冲锋；棋盘上暂时没有僵尸时仍允许预判施放。
func execute(context: CharacterSkillContext) -> bool:
	if not can_execute(context):
		return false
	var battle: RepeaterShotContext = context.state_source() # 演出拥有和其来源相同的轮次与阶段边界。
	var charge := Charge.new(context, battle) # 行号按棋盘稳定攻击顺序，和僵尸的行登记一致。
	if not charge.has_runs():
		charge.free()
		return false
	context.game.bombs.add_child(charge)
	return true
