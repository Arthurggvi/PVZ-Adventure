## Targeted acceptance of shared toolbar entry, 11x6 view and save-backed card order.
extends Node
func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var previous: String = Global.user_manager.curr_user_name
	var test_profile_name := "inventory-window-test-%d" % Time.get_ticks_usec() # 与真实用户存档隔离。
	DirAccess.make_dir_recursive_absolute("user://" + test_profile_name)
	Global.user_manager.curr_user_name = test_profile_name
	Global.reload_session_for_current_user()
	var a: String = Global.adventure_inventory.add_card(CharacterRegistry.PlantType.P001PeaShooterSingle)
	var b: String = Global.adventure_inventory.add_card(CharacterRegistry.PlantType.P002SunFlower)
	assert(not a.is_empty() and not b.is_empty())
	assert(Global.save_service.save_now())
	await get_tree().create_timer(0.12).timeout # Allow toolbar _process to refresh post-profile unlock state.
	assert(AdventureToolbar._hooks.has("inventory"))
	assert(AdventureToolbar._can_open_inventory())
	assert(AdventureToolbar._view._available.get("inventory", false))
	AdventureToolbar._view._on_pressed("inventory")
	await _wait_for_inventory()
	var modal: AdventureInventoryWindow = AdventureToolbar.modal_for("inventory")
	assert(is_instance_valid(modal))
	assert(AdventureToolbar._view.get_index() > modal.get_index()) # Toolbar icon stays clickable.
	assert(modal.ui.cells.get_child_count() == 66)
	assert(modal.ui.tabs.size() == 4)
	assert(modal.category == "plants")
	modal._reorder(b, 0)
	assert(Global.adventure_inventory.get_card_order() == [b, a])
	modal.choose_category("materials")
	await _wait_for_content(modal)
	assert(modal.ui.cells.get_child_count() == 66)
	modal.choose_category("items")
	await _wait_for_content(modal)
	assert(modal.ui.cells.get_child_count() == 66)
	AdventureToolbar._view._on_pressed("inventory") # Toggle the same toolbar icon to close.
	await get_tree().create_timer(0.42).timeout
	assert(not is_instance_valid(AdventureToolbar.modal_for("inventory")))
	AdventureToolbar._view._on_pressed("inventory") # Reopen using the actual icon signal path.
	await _wait_for_inventory()
	modal = AdventureToolbar.modal_for("inventory")
	assert(is_instance_valid(modal))
	var close: TextureButton = modal.find_child("InventoryCloseButton", true, false)
	assert(close != null)
	close.pressed.emit()
	await get_tree().create_timer(0.42).timeout
	assert(not is_instance_valid(AdventureToolbar.modal_for("inventory")))
	Global.user_manager.curr_user_name = previous
	Global.reload_session_for_current_user()
	print("INVENTORY_UI_SMOKE_PASS")
	get_tree().quit(0)

## 请求接受不代表窗口已出现，等待相同模态拥有者公开就绪实例。
func _wait_for_inventory() -> void:
	var deadline: int = Time.get_ticks_msec() + 12000 # 仅作为失败上限，不参与性能结论。
	while Time.get_ticks_msec() < deadline and AdventureToolbar.modal_for("inventory") == null:
		await get_tree().process_frame
	assert(AdventureToolbar.modal_for("inventory") != null)

## [param modal] 的分页资源与分帧格子构造完成后才检查原有布局断言。
func _wait_for_content(modal: AdventureInventoryWindow) -> void:
	var deadline: int = Time.get_ticks_msec() + 12000 # 保留原有测试范围，仅修正异步完成边界。
	while Time.get_ticks_msec() < deadline and not modal.is_content_ready():
		await get_tree().process_frame
	assert(modal.is_content_ready())
