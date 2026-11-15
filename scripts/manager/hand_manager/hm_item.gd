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
## 放下前显示当前目标格的半透明反馈。
@onready var _glove_drop_target: Polygon2D = %GloveDropTarget
## 可放置格用草绿，冲突格用暖红，透明度保留地块和单位的可读性。
const GLOVE_VALID_COLOR := Color(0.62, 0.89, 0.38, 0.27)
## 不兼容地形和占位冲突共用反馈。
const GLOVE_INVALID_COLOR := Color(0.94, 0.36, 0.28, 0.24)
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


## 切换到铲子工具并显示光标。
func click_shovel() -> void:
	curr_hm_item_status = E_HmItemStatus.Shovel
	real_shovel.change_is_using(true)

## 启用手套光标，等待选择原株。
func click_glove() -> void:
	curr_hm_item_status = E_HmItemStatus.Glove
	_glove_button.set_pressed_no_signal(true)
	_real_glove.global_position = _real_glove.get_global_mouse_position()
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


## 点击 [param plant_cell] 操作当前工具；返回 true 时退出手持。手套失败时仍可改选落点。
func click_cell(plant_cell: PlantCell) -> bool:
	if curr_hm_item_status == E_HmItemStatus.Glove:
		return _use_glove(plant_cell)
	if curr_hm_item_status == E_HmItemStatus.Shovel and is_instance_valid(_highlighted_plant):
		SoundManager.play_other_SFX(&"plant2")
		_highlighted_plant.be_shovel_kill()
	return true

## 从 [param cell] 按鼠标位置查找可移动的植物，兼容普通层、壳层和伴生。
func _glove_candidate(cell: PlantCell) -> Plant000Base:
	if not is_instance_valid(cell):
		return null
	var plant: Plant000Base = cell.return_plant_be_shovel_look() # 复用原版工具的分层命中顺序。
	if not is_instance_valid(plant) or not is_instance_valid(plant.plant_cell):
		return null
	return plant if plant.plant_cell.can_lift_plant(plant) else null

## 第一次点击 [param cell] 选择原株，第二次尝试落下；点回原格取消本次移动。
func _use_glove(cell: PlantCell) -> bool:
	if not _has_lifted_plant():
		_glove_plant = _glove_candidate(cell)
		_set_highlight(_glove_plant)
		SoundManager.play_other_SFX(&"seedlift" if _glove_plant != null else &"buzzer")
		return false
	var source: PlantCell = _glove_plant.plant_cell # 多格植物也从其主占格移交真实实例。
	if cell == source:
		return true
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
	return is_instance_valid(_glove_plant) and not _glove_plant.is_death \
		and not _glove_plant.is_queued_for_deletion() and is_instance_valid(_glove_plant.plant_cell)

## 选株用高亮，放置用落点颜色，不依赖即时消息或浮动文字。
func _update_glove_preview() -> void:
	_real_glove.global_position = _real_glove.get_global_mouse_position()
	if not _has_lifted_plant():
		_glove_drop_target.hide()
		_glove_plant = null
		_set_highlight(_glove_candidate(curr_plant_cell))
		return
	var source: PlantCell = _glove_plant.plant_cell # 手套仍持有原株，同格只显示植物高亮。
	if not is_instance_valid(curr_plant_cell) or curr_plant_cell == source:
		_glove_drop_target.hide()
		return
	var polygon: PackedVector2Array = curr_plant_cell.board_definition.hit_polygon # 对齐异形地块的真实命中边界。
	if polygon.is_empty():
		var cell_size: Vector2 = curr_plant_cell.size # 矩形地块留两像素内边距，避免染到相邻格。
		polygon = PackedVector2Array([Vector2(2, 2), Vector2(cell_size.x - 2, 2),
			cell_size - Vector2(2, 2), Vector2(2, cell_size.y - 2)])
	_glove_drop_target.transform = _glove_drop_target.get_canvas_transform().affine_inverse() \
		* curr_plant_cell.get_global_transform_with_canvas()
	_glove_drop_target.polygon = polygon
	_glove_drop_target.color = GLOVE_INVALID_COLOR if source.relocation_footprint(_glove_plant, curr_plant_cell).is_empty() \
		else GLOVE_VALID_COLOR
	_glove_drop_target.show()


## 退出手持时还原高亮、工具按钮和光标，未提交的植物始终留在原处。
func exit_status() -> void:
	if curr_hm_item_status == E_HmItemStatus.Shovel:
		real_shovel.change_is_using(false)
		ui_shovel.ui_shovel_appear()
	elif curr_hm_item_status == E_HmItemStatus.Glove:
		_glove_plant = null
		_glove_button.set_pressed_no_signal(false)
		_real_glove.hide()
		_glove_drop_target.hide()
	curr_hm_item_status = E_HmItemStatus.Null
	_set_highlight(null)
	curr_plant_cell = null
	curr_shovel_look_plant_num = 0
