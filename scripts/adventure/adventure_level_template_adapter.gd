## 新冒险阶段与原版 ResourceLevelData 的边界；不参与实际波次、奖励或 Boss AI。
extends RefCounted
class_name AdventureLevelTemplateAdapter

## 拒绝已由原版特殊模式接管备战/刷怪/胜负的模板，避免双控制器竞争。
static func validate(template: ResourceLevelData) -> PackedStringArray:
	var errors := PackedStringArray()
	if template == null:
		errors.append("原版关卡模板不存在。")
		return errors
	if template.card_mode != ConstLevelData.E_CardMode.Norm:
		errors.append("冒险强制备战需要原版普通卡槽。")
	if template.monster_mode != ConstLevelData.E_MonsterMode.Norm:
		errors.append("冒险阶段需要正常波次模式。")
	if template.game_round != 1:
		errors.append("普通/噩梦是两个独立阶段，不使用原版多轮存档。")
	if template.max_wave < 2:
		errors.append("原版波次进度条要求 max_wave >= 2。")
	if template.has_boss() or template.win_on_boss_death:
		errors.append("新 Boss 遭遇必须由阶段事件控制，原版模板不得自动生成/结算 Boss。")
	if template.is_pot_mode or template.is_zombie_mode or template.is_hammer:
		errors.append("当前适配器不支持接管选卡的特殊战斗模式。")
	if template.save_game_data_main_game != null:
		errors.append("冒险阶段不使用原版轮间存档。")
	return errors

## 只复制模板并强制启用预览、选卡，修改结果绝不污染资源原件。
## max_slots 由阶段配置决定，超过原版卡槽上限必须明确拒绝。
static func build(template: ResourceLevelData, max_slots: int) -> ResourceLevelData:
	if max_slots < 1 or max_slots > 15 or not validate(template).is_empty():
		return null
	var runtime: ResourceLevelData = template.duplicate(true) as ResourceLevelData
	if runtime == null:
		return null
	runtime.look_show_zombie = true
	runtime.can_choosed_card = true
	runtime.prechosen_cards.clear()
	runtime.max_choosed_card_num = max_slots
	return runtime
