## 按目录顺序生成植物、普通僵尸、僵王及植物模仿卡页面，按可用角色列表筛选。
extends TextureRect
class_name CardSlotCandidate

## 冒险候选卡按库存顺序分帧装配后发送；普通模式在 _ready 内同步完成。
signal content_ready()
## 单次冒险装配的目标预算，单位微秒；单张卡不可拆分，完成后再让出下一帧。
const BUILD_SLICE_USEC := 4000
## 候选卡、页面及索引都已完成，父卡槽此后才能连接点击与恢复预选。
var _content_ready := false

## 普通备选页面的挂载节点。
@onready var all_card_page: Control = $AllCardPage
## 植物页面的占位布局模板。
@onready var grid_container_plant: GridContainer = $AllCardPage/GridContainerPlant
## 普通僵尸和僵王共用的占位布局模板。
@onready var grid_container_zombie: GridContainer = $AllCardPage/GridContainerZombie
## 类型、内容和模仿修饰共同确定的备选容器索引。
var candidate_containers: Dictionary[Vector3i, CardCandidateContainer] = {}
## 冒险使用唯一卡 UID，不能用物种键覆盖同种植物的另一张卡。
var adventure_candidates: Dictionary[String, CardCandidateContainer] = {}
## 至少有一张已解锁卡的普通页面。
var all_show_page: Array[GridContainer] = []
## 普通页面的零起点页码。
var curr_page: int = 0
## 普通页面的页码标签。
@onready var label_page: Label = $LabelPage
## 模仿者选择弹层。
@onready var all_imitater_card: Control = %AllImitaterCard
## 模仿卡页面的挂载节点。
@onready var all_card_page_imitater: Control = $AllImitaterCard/Panel/AllCardPageImitater
## 模仿卡页面的占位布局模板。
@onready var grid_container_plant_imitater: GridContainer = $AllImitaterCard/Panel/AllCardPageImitater/GridContainerPlantImitater
## 独立模仿者入口，只负责打开弹层，不用于出战。
@onready var card_imitater: CardImitater = $ImitaterBG/CardImitater
## 至少有一张已解锁卡的模仿卡页面。
var all_show_page_imitater: Array[GridContainer] = []
## 模仿卡页面的零起点页码。
var curr_page_imitater: int = 0

## 根据目录稳定顺序分页；冒险大量库存按时间预算让帧，普通模式不进入让帧分支。
func _ready() -> void:
	if AdventureSession.owns_battle(Global.game_para):
		card_imitater.hide()
		await _create_candidate_pages(ResourceCardReference.CardType.Plant, grid_container_plant, all_card_page, false, true)
	else:
		await _create_candidate_pages(ResourceCardReference.CardType.Plant, grid_container_plant, all_card_page)
		await _create_candidate_pages(ResourceCardReference.CardType.Zombie, grid_container_zombie, all_card_page)
		await _create_candidate_pages(ResourceCardReference.CardType.Plant, grid_container_plant_imitater, all_card_page_imitater, true)
	if not is_inside_tree() or is_queued_for_deletion():
		return
	if not all_show_page.is_empty():
		all_show_page[0].visible = true
	if not all_show_page_imitater.is_empty():
		all_show_page_imitater[0].visible = true
	label_page.text = "1/" + str(all_show_page.size()) if not all_show_page.is_empty() else "0/0"
	card_imitater.signal_card_click.connect(imitater_card_slot_appear)
	_content_ready = true
	content_ready.emit()

## 返回所有候选页是否完成；查询不会继续构造卡牌或改变页面顺序。
func is_content_ready() -> bool:
	return _content_ready

## 使用 [param card_type] 的目录顺序复制 [param grid_template] 到 [param page_root]。
## [param imitate] 为 true 时为植物创建模仿修饰，不修改目录共享引用。
## 普通僵尸页末尾追加僵王目录，各引用保留自身类别，不受关卡自动出场类型影响。
## [param adventure_mode] 为 true 时按库存快照构造，每片预算用尽后让帧；离场后停止。
func _create_candidate_pages(card_type: int, grid_template: GridContainer, page_root: Control, imitate: bool = false, adventure_mode: bool = false) -> void:
	var page_capacity: int = grid_template.get_child_count() # 保持原占位数量与分页规则。
	if page_capacity <= 0:
		push_error("CardSlotCandidate：备选页面缺少卡片占位。")
		return
	if adventure_mode:
		grid_template.hide() # 跨帧保留在所属场景，切场释放时不会遗留脱树模板。
	else:
		page_root.remove_child(grid_template)
	var pages: Array[GridContainer] = [] # 完成的页保持原库存顺序。
	var records: Array[Dictionary] = [] # 一次性冻结库存数据，跨帧不重新读取玩家卡片。
	if adventure_mode:
		for build: Dictionary in Global.adventure_inventory.list_cards(): # UID 与原顺序同时保留。
			var reference := ResourceCardReference.create(ResourceCardReference.CardType.Plant, int(build["plant_type"])) # 物种只用于选择卡面。
			records.append({"reference": reference, "build": build})
	else:
		var references: Array[ResourceCardReference] = AllCards.get_references(card_type)
		if card_type == ResourceCardReference.CardType.Zombie:
			references.append_array(AllCards.get_references(ResourceCardReference.CardType.ZombieBoss))
		for template: ResourceCardReference in references:
			var reference: ResourceCardReference = template.copy_reference()
			if imitate:
				reference.is_imitater = true
			records.append({"reference": reference})

	var card_index := 0 # 已接纳的卡片数量，决定页面及页内占位。
	var slice_started_usec: int = Time.get_ticks_usec() # 当前构造片段的主线程开始时间。
	for record: Dictionary in records: # 同种植物的多个 UID 始终各自构造独立实例。
		if adventure_mode and card_index > 0 and Time.get_ticks_usec() - slice_started_usec >= BUILD_SLICE_USEC:
			await get_tree().process_frame
			if not is_inside_tree() or is_queued_for_deletion():
				return
			slice_started_usec = Time.get_ticks_usec()
		var reference: ResourceCardReference = record["reference"] # 本卡的基础身份与可选模仿修饰。
		if not AllCards.is_battle_card(reference):
			continue
		var new_card: Card = AllCards.create_card(reference, Card.CardContext.Selection) # 可移动到出战槽的独立卡。
		if new_card == null:
			continue
		if adventure_mode:
			new_card.plant_spawn_profile = AdventureBattleAdapter.profile_for(record["build"])
			if new_card.plant_spawn_profile == null:
				new_card.free()
				continue
		var page_index: int = floori(float(card_index) / float(page_capacity)) # 不因让帧改变分页边界。
		if page_index >= pages.size():
			var page: GridContainer = grid_template.duplicate() as GridContainer # 每页仅复制原有空占位布局。
			page.visible = false
			page_root.add_child(page)
			pages.append(page)
		var container: CardCandidateContainer = SceneRegistry.CARD_CANDIDATE_CONTAINER.instantiate() # 候选占位与本卡共同入树。
		container.init_card_in_seed_chooser(new_card)
		pages[page_index].get_child(card_index % page_capacity).add_child(container)
		container.visible = true if adventure_mode else _is_unlocked(reference)
		if adventure_mode:
			adventure_candidates[str(record["build"]["uid"])] = container
		else:
			candidate_containers[reference.get_selection_key()] = container
		card_index += 1
	for page: GridContainer in pages:
		var has_visible_card := false
		for placeholder: Node in page.get_children():
			if placeholder.get_child_count() > 0 and (placeholder.get_child(0) as Control).visible:
				has_visible_card = true
				break
		if has_visible_card:
			if imitate:
				all_show_page_imitater.append(page)
			else:
				all_show_page.append(page)
	grid_template.queue_free()

## 两种模式统一提供点击连接所需的容器集合。
func get_all_candidates() -> Array[CardCandidateContainer]:
	var result: Array[CardCandidateContainer] = []
	for container: CardCandidateContainer in candidate_containers.values():
		result.append(container)
	for container: CardCandidateContainer in adventure_candidates.values():
		result.append(container)
	return result

func get_adventure_candidate(uid: String) -> CardCandidateContainer:
	return adventure_candidates.get(uid) as CardCandidateContainer

## 返回 [param reference] 是否存在于对应类别的当前可用角色列表。
func _is_unlocked(reference: ResourceCardReference) -> bool:
	match reference.card_type:
		ResourceCardReference.CardType.Plant:
			return Global.global_game_state.curr_plant.has(reference.content_id)
		ResourceCardReference.CardType.Zombie:
			return Global.global_game_state.curr_zombie.has(reference.content_id)
		ResourceCardReference.CardType.ZombieBoss:
			return Global.global_game_state.curr_zombie_boss.has(reference.content_id)
	return false

## 查询 [param reference] 对应的普通或模仿卡容器，未生成内容返回 null。
func get_candidate(reference: ResourceCardReference) -> CardCandidateContainer:
	if reference == null:
		return null
	return candidate_containers.get(reference.get_selection_key()) as CardCandidateContainer

## 显示普通备选卡的上一页。
func _on_last_page_button_pressed() -> void:
	change_page(-1)

## 显示普通备选卡的下一页。
func _on_next_page_button_pressed() -> void:
	change_page(1)

## 按 [param change_num] 循环切换普通页面；空集合不执行切换。
func change_page(change_num: int = 1) -> void:
	if all_show_page.is_empty():
		return
	all_show_page[curr_page].visible = false
	curr_page = posmod(curr_page + change_num, all_show_page.size())
	all_show_page[curr_page].visible = true
	label_page.text = str(curr_page + 1) + "/" + str(all_show_page.size())

## [param _card] 是入口点击信号携带的卡片；仅打开模仿卡弹层。
func imitater_card_slot_appear(_card: Card) -> void:
	all_imitater_card.visible = true

## 关闭模仿卡弹层。
func imitater_card_slot_disappear() -> void:
	all_imitater_card.visible = false

## 真实模仿卡选中后关闭弹层并锁定独立入口。
func imitater_be_choosed() -> void:
	imitater_card_slot_disappear()
	card_imitater.imitater_card_be_choosed()

## 取消真实模仿卡后恢复独立入口。
func imitater_be_choosed_cancel() -> void:
	card_imitater.imitater_card_be_choosed_cancal()

## 显示模仿卡的上一页。
func _on_imitater_last_page_button_pressed() -> void:
	change_page_imitater(-1)

## 显示模仿卡的下一页。
func _on_imitater_next_page_button_pressed() -> void:
	change_page_imitater(1)

## 按 [param change_num] 循环切换模仿卡页面；没有解锁内容时不切换。
func change_page_imitater(change_num: int = 1) -> void:
	if all_show_page_imitater.is_empty():
		return
	all_show_page_imitater[curr_page_imitater].visible = false
	curr_page_imitater = posmod(curr_page_imitater + change_num, all_show_page_imitater.size())
	all_show_page_imitater[curr_page_imitater].visible = true
