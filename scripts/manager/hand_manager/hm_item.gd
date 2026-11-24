extends Node
## 铲子与手套共享棋盘拾取；手套确认落点前植物仍在原格战斗。
class_name HM_Item

## 铲子工具位。
@onready var ui_shovel: UIShovel = %UIShovel
## 跟随鼠标的铲子。
@onready var real_shovel: RealShovel = %RealShovel
## 工具栏图标与选中态。
@onready var _glove_button: Button = %BattleGloveButton
## 按剩余冷却比例覆盖手套槽位。
@onready var _glove_cooldown_mask: ProgressBar = _glove_button.get_node("CooldownMask")
## 跟随鼠标的原版手套贴图。
@onready var _real_glove: Sprite2D = %RealGlove
## 用于挂载跟手植物静态图的战斗预览层。
@onready var _temporary_character: Node2D = %TemporaryCharacter
## 落点多边形按占格数量复用，第一格沿用场景节点。
@onready var _glove_drop_targets: Array[Polygon2D] = [%GloveDropTarget]
## 可放置格用草绿，冲突格用暖红，透明度保留地块和单位的可读性。
const GLOVE_VALID_COLOR := Color(0.62, 0.89, 0.38, 0.34)
## 不兼容地形和占位冲突共用反馈。
const GLOVE_INVALID_COLOR := Color(0.94, 0.36, 0.28, 0.34)
## 单击取株时允许的手抖距离，单位为视口像素。
const GLOVE_DRAG_THRESHOLD := 6.0
## 跟手图相对于植物原尺寸的缩放，露出鼠标所在格及手套图标。
const GLOVE_CARRY_SCALE := 0.8
## 跟手图根节点相对鼠标的偏移量，单位为战斗画布像素。
const GLOVE_CARRY_OFFSET := Vector2(0.0, -10.0)
## 手套成功移株后的冷却时长，单位为战斗秒。
const GLOVE_COOLDOWN_SECONDS := 5.0

## 手持道具状态
enum E_HmItemStatus{
	Null,
	Shovel,
	Glove,
}
## 当前启用的工具；与 HandManager 的手持状态同步清理。
var curr_hm_item_status := E_HmItemStatus.Null

## 当前鼠标所在格子
var curr_plant_cell :PlantCell

## 当前高亮植物；预铲和手套都沿用原生高亮材质。
var _highlighted_plant: Plant000Base
## 当前铲子所在格子植物数量
var curr_shovel_look_plant_num:int = 0
## 已选中但尚未移动的原株；原株死亡后可重新选择。
var _glove_plant: Plant000Base
## 跟手的静态外观，随本次选择销毁。
var _glove_carry_preview: Node2D
## 从棋盘按下左键的视口位置；INF 表示没有等待松开的手势。
var _glove_press_position := Vector2.INF
## 本次按下是否刚取到植物，用于区分单击取株和按住拖放。
var _glove_picked_on_press := false


## 切换到铲子工具；桌面使用随鼠标的光标，触屏显示槽位选中态和地块预铲高亮。
func click_shovel() -> void:
	curr_hm_item_status = E_HmItemStatus.Shovel
	ui_shovel.set_selected(true)
	real_shovel.change_is_using(not OS.has_feature("mobile"))

## 启用手套光标，等待选择原株。
func click_glove() -> void:
	curr_hm_item_status = E_HmItemStatus.Glove
	_glove_button.set_pressed_no_signal(true)
	_real_glove.global_position = BattleEnvironmentLens.mouse_position(_real_glove)
	_real_glove.show()

## 切换道具高亮，先恢复旧目标，再高亮新目标。[br]
## [param candidate] 候选植物，可为空或已释放引用；失效引用按无目标处理。
func _set_highlight(candidate: Variant) -> void:
	# 本次有效的候选植物；先检查引用，再转换为植物类型。
	var next_plant: Plant000Base = null
	if is_instance_valid(candidate):
		next_plant = candidate as Plant000Base

	# 同格刷新仍选中同一植物时，保留现有预铲状态。
	if is_instance_valid(_highlighted_plant) and _highlighted_plant == next_plant:
		return

	if is_instance_valid(_highlighted_plant):
		_highlighted_plant.be_shovel_look_end()

	_highlighted_plant = next_plant
	if is_instance_valid(_highlighted_plant):
		_highlighted_plant.be_shovel_look()

## 同格有多株植物时更新选中层级；手套落点随棋盘移动和战斗状态实时重验。
func item_process() -> void:
	if curr_hm_item_status == E_HmItemStatus.Glove:
		_update_glove_preview()
		return
	if curr_shovel_look_plant_num >= 2 \
			and is_instance_valid(curr_plant_cell):
		_set_highlight(
			curr_plant_cell.return_plant_be_shovel_look()
		)

## [param plant_cell] 当前进入或重新刷新的格子；没有植物时清理旧预铲。
func mouse_enter(plant_cell: PlantCell) -> void:
	curr_plant_cell = plant_cell
	if curr_hm_item_status == E_HmItemStatus.Shovel:
		curr_shovel_look_plant_num = plant_cell.get_curr_plant_num()
		_set_highlight(
			plant_cell.return_plant_be_shovel_look()
		)

## [param plant_cell] 移出的格子，保留接口参数；结束当前预铲并清理格子状态。
@warning_ignore("unused_parameter")
func mouse_exit(plant_cell: PlantCell) -> void:
	curr_plant_cell = null
	curr_shovel_look_plant_num = 0
	if curr_hm_item_status == E_HmItemStatus.Shovel:
		_set_highlight(null)


## 在 [param plant_cell] 使用铲子或通过棋盘按钮确认手套；成功后返回 true 退出手持。
func click_cell(plant_cell: PlantCell) -> bool:
	if curr_hm_item_status == E_HmItemStatus.Glove:
		# 键盘和无障碍按钮激活相当于一次无位移的点击。
		press_glove(plant_cell, Vector2.ZERO)
		return release_glove(plant_cell, Vector2.ZERO)
	if curr_hm_item_status == E_HmItemStatus.Shovel:
		# 确认时用本次点击的位置重新查层位，触屏无需提前悬停。
		_set_highlight(plant_cell.return_plant_be_shovel_look())
		if is_instance_valid(_highlighted_plant):
			SoundManager.play_other_SFX(&"plant2")
			_highlighted_plant.be_shovel_kill()
	return true

## 从 [param cell] 优先取鼠标指向的层；该株不可移动时再查同格其他活株。
func _glove_candidate(cell: PlantCell) -> Plant000Base:
	if not is_instance_valid(cell):
		return null
	var pointed: Plant000Base = cell.return_plant_be_shovel_look() # 与铲子使用相同的分层命中顺序。
	if not is_instance_valid(pointed):
		return null
	if _can_lift_with_glove(pointed):
		return pointed
	for plant: Plant000Base in cell.living_plants(): # 被锁定的层不挡住可搬动的同格植物。
		if plant != pointed and _can_lift_with_glove(plant):
			return plant
	return null

## 查询 [param plant] 主格的迁移资格，覆盖从附属占格拾取的多格植物。
func _can_lift_with_glove(plant: Plant000Base) -> bool:
	return is_instance_valid(plant) and is_instance_valid(plant.plant_cell) and plant.plant_cell.can_lift_plant(plant)

## 在 [param cell] 按下左键，记录 [param pointer_position] 并立即取株或开始瞄准已有植物。
func press_glove(cell: PlantCell, pointer_position: Vector2) -> void:
	_glove_press_position = pointer_position
	_glove_picked_on_press = false
	if _has_lifted_plant():
		return
	_set_glove_plant(_glove_candidate(cell))
	_glove_picked_on_press = is_instance_valid(_glove_plant)
	SoundManager.play_other_SFX(&"seedlift" if _glove_picked_on_press else &"buzzer")

## 返回是否有从棋盘开始且等待松开的左键手势。
func has_glove_press() -> bool:
	return _glove_press_position != Vector2.INF

## 清除未完成的左键手势，保留已经选中的植物。
func clear_glove_press() -> void:
	_glove_press_position = Vector2.INF
	_glove_picked_on_press = false

## 在 [param pointer_position] 松开左键；[param cell] 为空表示指针离开棋盘。
## [param drag_threshold] 为按住取株后判定拖动的最小视口像素距离。
## 返回是否搬移成功。单击取株和无效落点保留选择，点回主格则放回原株。
func release_glove(cell: PlantCell, pointer_position: Vector2, drag_threshold: float = GLOVE_DRAG_THRESHOLD) -> bool:
	var picked_on_press: bool = _glove_picked_on_press # 刚取株时需越过拖动阈值才尝试落下。
	var moved: bool = _glove_press_position.distance_squared_to(pointer_position) >= drag_threshold ** 2 # 轻触松开时继续手持。
	clear_glove_press()
	if not _has_lifted_plant() or not is_instance_valid(cell) or (picked_on_press and not moved):
		return false
	var source: PlantCell = _glove_plant.plant_cell # 多格植物也从其主占格移交真实实例。
	if cell == source:
		if not picked_on_press:
			_set_glove_plant(null)
			SoundManager.play_other_SFX(&"tap2")
		return false
	if not source.relocate_plant(_glove_plant, cell):
		SoundManager.play_other_SFX(&"buzzer")
		return false
	_start_glove_cooldown()
	SoundManager.play_other_SFX(&"plant2")
	return true

## 成功移株后禁用手套，通过一个补间同步推进暗罩和可用状态。
func _start_glove_cooldown() -> void:
	_glove_button.disabled = true
	_glove_cooldown_mask.value = 1.0
	_glove_cooldown_mask.show()
	var cooldown: Tween = _glove_cooldown_mask.create_tween() # 跟随战斗暂停与倍速，手套槽释放时自动停止。
	cooldown.tween_property(_glove_cooldown_mask, "value", 0.0, GLOVE_COOLDOWN_SECONDS)
	cooldown.tween_callback(_finish_glove_cooldown)

## 冷却结束时恢复手套点击区并收起暗罩。
func _finish_glove_cooldown() -> void:
	_glove_cooldown_mask.hide()
	_glove_button.disabled = false

## 原株留在棋盘中，期间可能被击败或移除；失效后回到选株状态。
func _has_lifted_plant() -> bool:
	return is_instance_valid(_glove_plant) and _glove_plant.is_inside_tree() and not _glove_plant.is_death \
		and not _glove_plant.is_queued_for_deletion() and is_instance_valid(_glove_plant.plant_cell)

## 取起 [param plant] 时复用卡面静态外观；传入 null 时清除选株和落点反馈。
func _set_glove_plant(plant: Plant000Base) -> void:
	if is_instance_valid(_glove_carry_preview):
		_glove_carry_preview.hide()
		_glove_carry_preview.queue_free()
		_glove_carry_preview = null
	_hide_glove_targets(0)
	_glove_plant = plant
	_set_highlight(plant)
	if plant == null:
		return
	var reference: ResourceCardReference = ResourceCardReference.create(ResourceCardReference.CardType.Plant,
		plant.spawn_species_id(), plant.is_imitater_material) # 同一物种可以有模仿版外观。
	if not AllCards.is_battle_card(reference):
		return
	var tier: int = plant.plant_spawn_profile.promotion_tier() if plant.plant_spawn_profile != null else 0 # 保留转职外观。
	_glove_carry_preview = AllCards.create_static_preview(reference, tier)
	if _glove_carry_preview == null:
		return
	var art: Node2D = _glove_carry_preview.get_child(0) as Node2D \
		if _glove_carry_preview.get_child_count() > 0 else null # 卡图子节点原本按卡槽缩放。
	if art != null:
		art.scale = Vector2.ONE
	_glove_carry_preview.scale = Vector2.ONE * GLOVE_CARRY_SCALE
	_glove_carry_preview.modulate.a = 0.85
	_glove_carry_preview.z_index = 1
	_temporary_character.add_child(_glove_carry_preview)
	_glove_carry_preview.global_position = BattleEnvironmentLens.mouse_position(_temporary_character) + GLOVE_CARRY_OFFSET

## 选株显示高亮，手持静态图跟随指针；合法落点显示完整的实际占格。
func _update_glove_preview() -> void:
	_real_glove.global_position = BattleEnvironmentLens.mouse_position(_real_glove)
	if not _has_lifted_plant():
		if _glove_plant != null or is_instance_valid(_glove_carry_preview):
			_set_glove_plant(null)
		_set_highlight(_glove_candidate(curr_plant_cell))
		return
	if is_instance_valid(_glove_carry_preview):
		_glove_carry_preview.global_position = _real_glove.global_position + GLOVE_CARRY_OFFSET
	var source: PlantCell = _glove_plant.plant_cell # 手套仍持有原株，同格只显示植物高亮。
	if not is_instance_valid(curr_plant_cell) or curr_plant_cell == source:
		_hide_glove_targets(0)
		return
	var footprint: Array[PlantCell] = source.relocation_footprint(_glove_plant, curr_plant_cell) # 战况变化时重验放置条件。
	if footprint.is_empty():
		_draw_glove_target(_glove_drop_targets[0], curr_plant_cell, GLOVE_INVALID_COLOR)
		_hide_glove_targets(1)
		return
	while _glove_drop_targets.size() < footprint.size():
		var target := Polygon2D.new() # 多格植物首次预览时扩充同一个画布上的反馈节点。
		target.antialiased = true
		_glove_drop_targets[0].get_parent().add_child(target)
		_glove_drop_targets.append(target)
	for index: int in footprint.size(): # 按棋盘返回的实际占格依次描出提示。
		_draw_glove_target(_glove_drop_targets[index], footprint[index], GLOVE_VALID_COLOR)
	_hide_glove_targets(footprint.size())

## 用 [param target] 和 [param color] 显示 [param cell] 的真实边界，并跟随地块运动。
func _draw_glove_target(target: Polygon2D, cell: PlantCell, color: Color) -> void:
	var polygon: PackedVector2Array = cell.board_definition.hit_polygon # 对齐异形地块的真实命中边界。
	if polygon.is_empty():
		var cell_size: Vector2 = cell.size # 矩形地块留两像素内边距，避免染到相邻格。
		polygon = PackedVector2Array([Vector2(2, 2), Vector2(cell_size.x - 2, 2),
			cell_size - Vector2(2, 2), Vector2(2, cell_size.y - 2)])
	target.transform = target.get_canvas_transform().affine_inverse() * cell.get_global_transform_with_canvas()
	target.polygon = polygon
	target.color = color
	target.show()

## 保留前 [param visible_count] 个落点，隐藏多余节点供下次瞄准复用。
func _hide_glove_targets(visible_count: int) -> void:
	for index: int in range(visible_count, _glove_drop_targets.size()): # 从当前预览所需范围之后开始清理。
		_glove_drop_targets[index].hide()


## 退出手持时还原高亮、工具按钮和光标，未提交的植物始终留在原处。
func exit_status() -> void:
	if curr_hm_item_status == E_HmItemStatus.Shovel:
		real_shovel.change_is_using(false)
		ui_shovel.set_selected(false)
	elif curr_hm_item_status == E_HmItemStatus.Glove:
		clear_glove_press()
		_set_glove_plant(null)
		_glove_button.set_pressed_no_signal(false)
		_real_glove.hide()
	curr_hm_item_status = E_HmItemStatus.Null
	_set_highlight(null)
	curr_plant_cell = null
	curr_shovel_look_plant_num = 0
