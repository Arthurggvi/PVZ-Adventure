## 将伊芙的六发星弹提交给当前战场。冷却、当前角色及 Cut-in 仍由共用运行时负责。
extends CharacterSkillEffect

## 装备技能后才加载星弹和它的材质。
const Starfall = preload("res://scripts/adventure/skills/eve_aurora_starfall.gd")

## [param context] 的战局、棋盘和世界特效层都有效时允许尝试施放。
func can_execute(context: CharacterSkillContext) -> bool:
	return context != null and context.is_active() and is_instance_valid(context.game.bombs) \
		and context.game.bombs.is_inside_tree() and not context.game.bombs.is_queued_for_deletion() \
		and not context.board.cells().is_empty()

## 为 [param context] 发动六发索敌星弹。没有合法的备用落点时拒绝提交，不开始冷却。
func execute(context: CharacterSkillContext) -> bool:
	if not can_execute(context):
		return false
	var candidates: Array[PlantCell] = [] # 既有棋盘索引是合法落点的唯一来源。
	for cell: PlantCell in context.board.cells(): # 草坪、水路和移动地块由同一身份检查。
		if Starfall.is_landing_cell(context.board, cell):
			candidates.append(cell)
	if candidates.is_empty():
		return false
	var battle: RepeaterShotContext = context.state_source() # 深寒及延时表现共用原战局边界。
	if battle == null:
		return false
	var cast := Starfall.new(context, battle, candidates, randi()) # 每次施放独立保存抽样。
	context.game.bombs.add_child(cast)
	return true
