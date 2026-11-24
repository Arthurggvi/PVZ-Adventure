## 选择三个后场落点和一个前场落点，交给本局双圈散射演出。
extends CharacterSkillEffect

## 按棋盘逻辑列计数，最靠刷怪侧的四列构成后场。
const REAR_COLUMNS: int = 4
## 前三爆依次从后场无放回抽取。
const REAR_BURSTS: int = 3
## 延时散射只在此时装成功绑定后加载。
const Barrage = preload("res://scripts/adventure/skills/spring_cattail_barrage.gd")

## [param context] 必须仍属于可施放的战斗，且能接纳散射节点。
func can_execute(context: CharacterSkillContext) -> bool:
	return context != null and context.is_active() and is_instance_valid(context.game.bullets) \
		and context.game.bullets.is_inside_tree() and not context.game.bullets.is_queued_for_deletion()

## 在 [param context] 所属棋盘抽取落点并提交技能。棋盘无法满足分区时保留可用状态。
func execute(context: CharacterSkillContext) -> bool:
	var source: RepeaterShotContext = context.state_source() # 离场、结算和续战按原有战局身份撤销。
	if source == null:
		return false
	var rear: Array[PlantCell] = [] # 后四逻辑列的有效地块。
	var front: Array[PlantCell] = [] # 四列以外的有效地块只用于末爆。
	var boundary: int = context.board.extent.y - REAR_COLUMNS # 不按屏幕像素或镜头位置猜测列号。
	for cell: PlantCell in context.board.cells(): # 地块可以空置、有植株或位于水面。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion() or not cell.is_visible_in_tree():
			continue
		if cell.row_col.y >= boundary:
			rear.append(cell)
		else:
			front.append(cell)
	if rear.size() < REAR_BURSTS or front.is_empty():
		return false
	var random := RandomNumberGenerator.new() # 独立抽样，演出不消耗自然刷怪的随机流。
	var targets: Array[PlantCell] = [] # 末项是唯一的前场爆点。
	for _index: int in range(REAR_BURSTS): # 每个实际格子只能入选一次。
		targets.append(rear.pop_at(random.randi_range(0, rear.size() - 1)))
	targets.append(front[random.randi_range(0, front.size() - 1)])
	var barrage := Barrage.new() # 整次施放共用一个命中节点和两批绘制。
	barrage.configure(source, targets, random)
	context.game.bullets.add_child(barrage)
	return true
