## 绝望的祷告只提供手势聚滴，其他祷告仍能投出原有黑泪。
extends SceneTree

## 启动后检查正式祷告资源的两种表现。
func _initialize() -> void:
	call_deferred("_run")

## 用同一个格和同一个抬掌点复现两种祷告的释放。
func _run() -> void:
	var prayer: GDScript = load("res://scripts/fx/savior_prayer_effect.gd") # 读取真实组件的表现契约。
	var profiles: Dictionary = prayer.get_script_constant_map().get("Profile", {}) # 旧版没有区分掌间和地面的能力。
	if not profiles.has("PALMS_ONLY") or not profiles.has("GROUND_MARKS"):
		_fail("绝望没有仅掌间聚滴的祷告表现")
		return
	var scene: PackedScene = load("res://scenes/fx/savior_prayer_effect.tscn") # 原来的祷告渲染场景。
	var palms := Marker2D.new() # 固定可见的实际手部锚点。
	palms.position = Vector2(270, 190)
	root.add_child(palms)
	var target: Array[Rect2] = [Rect2(407, 236, 64, 69)] # 两个施法变体选同一块石砖。
	var ground = scene.instantiate() # 其他技能沿用的完整祷告。
	var hands = scene.instantiate() # 绝望共享同一资源及手势。
	if not ground.prepare(palms, target, profiles["GROUND_MARKS"]) or not hands.prepare(palms, target, profiles["PALMS_ONLY"]):
		_fail("两个正式祷告变体都应能接受同一落点")
		return
	root.add_child(ground)
	root.add_child(hands)
	if not ground.release() or not hands.release() or hands.release():
		_fail("原画抬手帧应只释放每种表现一次")
		return
	var original: MultiMesh = ground.get_node("GroundMarks").multimesh # 原黑泪留下的真实地面记号。
	var hand_marks: MultiMesh = hands.get_node("GroundMarks").multimesh # 绝望不会提交提前着地的印记。
	if original.instance_count != 1 or hand_marks.instance_count != 0:
		_fail("地面记号只能由原祷告变体产生")
		return
	await create_timer(0.32).timeout
	if is_instance_valid(hands) or not is_instance_valid(ground):
		_fail("在原黑泪着地时绝望的掌间效果应已结束")
		return
	palms.queue_free()
	ground.queue_free()
	print("DESPAIR_PRAYER_OK")
	quit()

## [param reason] 提示失败的祷告表现。
func _fail(reason: String) -> void:
	push_error("DESPAIR_PRAYER: " + reason)
	quit(1)
