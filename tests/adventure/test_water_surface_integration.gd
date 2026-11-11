## 只测试水域协议、矩形物理探测、渲染计时和原版泳池兼容，不启动正常战斗。
extends Node

var _failed := false

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		push_error("WATER_SURFACE_FAIL: " + message)

func _run() -> void:
	var profile: WaterSurfaceProfile = load("res://resources/water/sewer_water.tres")
	var source := Sprite2D.new()
	source.name = "BattleBackground"
	source.texture = load("res://assets/adventure/environments/battle_backgrounds/05_sewer_interior_water.png")
	source.centered = false
	source.position.x = -210.0
	var bg_canvas := CanvasLayer.new()
	bg_canvas.layer = -10
	add_child(bg_canvas)
	bg_canvas.add_child(source)
	var controller := WaterSurfaceController.new()
	source.add_child(controller)
	controller.configure_background(source, profile)
	_check(profile.validate_regions(source.texture.get_size()).is_empty(), "profile bounds")
	_check(controller.get_child_count() == profile.regions.size() * 2, "visual and physical areas share one region")
	for region: Rect2 in profile.regions:
		var water_found := false
		for child in controller.get_children():
			if child is WaterBodyArea and child.position == region.get_center():
				var shape: RectangleShape2D = child.get_child(0).shape
				water_found = shape.size == region.size
		_check(water_found, "region has exact matching physics volume")
	var material: ShaderMaterial = controller.get_child(0).material
	var t0: float = material.get_shader_parameter("water_time")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(material.get_shader_parameter("water_time") > t0, "water time advances in actual scene frames")
	controller.set_intensity(0.0)
	_check(is_zero_approx(material.get_shader_parameter("ripple_strength")), "intensity freezes flow")
	controller.set_intensity(1.0)
	_check(material.get_shader_parameter("ripple_strength") > 0.0, "intensity resumes flow")
	var detector := Area2D.new()
	detector.name = "ZombieSwimDetector"
	detector.collision_layer = 0
	detector.collision_mask = 1
	var hit := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 20)
	hit.shape = rect
	detector.add_child(hit)
	add_child(detector)
	var entered := [0]
	var exited := [0]
	detector.area_entered.connect(func(area: Area2D) -> void:
		if area is WaterBodyArea:
			entered[0] += 1
	)
	detector.area_exited.connect(func(area: Area2D) -> void:
		if area is WaterBodyArea:
			exited[0] += 1
	)
	detector.position = Vector2(170, 135)
	for i in range(4):
		await get_tree().physics_frame
	_check(entered[0] == 1, "sewer lane collider triggers swimming")
	detector.position = Vector2(170, 320)
	for i in range(4):
		await get_tree().physics_frame
	_check(exited[0] == 1, "sewer lane exit clears swimming")
	detector.position = Vector2(170, 530)
	for i in range(4):
		await get_tree().physics_frame
	_check(entered[0] == 2, "fifth lane collider triggers swimming")
	var pool: Pool = load("res://scenes/main_game_bg/pool.tscn").instantiate()
	_check(pool.get_node("PoolArea2D") is WaterBodyArea, "original pool uses shared water area")
	pool.free()
	print("WATER_SURFACE_RESULT=", "FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)
