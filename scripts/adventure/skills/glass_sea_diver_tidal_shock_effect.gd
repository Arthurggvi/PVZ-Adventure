## 潜水员的一次主动施放；浪与震颤由战场持有，冷却交给共用运行时。
extends CharacterSkillEffect

## 装备技能时才解析水面演出及其素材。
const Tide = preload("res://scripts/adventure/skills/glass_sea_diver_tidal_shock.gd")

## [param context] 属于可操作的战场，且棋盘和演出容器可用时允许施放。
func can_execute(context: CharacterSkillContext) -> bool:
	if context == null or not context.is_active() or context.board.cells().is_empty():
		return false
	var host: Node2D = context.game.bombs # 战场世界层的临时特效容器。
	return is_instance_valid(host) and host.is_inside_tree() and not host.is_queued_for_deletion()

## 在 [param context] 提交演出。空场也会起浪，可碰到途中入场的僵尸。
func execute(context: CharacterSkillContext) -> bool:
	if not can_execute(context):
		return false
	var battle: RepeaterShotContext = context.state_source() # 技能与寒冷状态共用原战局边界。
	var tide := Tide.new(context, battle) # 一次施放只添加一个宿主，所有分路随其清理。
	context.game.bombs.add_child(tide)
	return true
