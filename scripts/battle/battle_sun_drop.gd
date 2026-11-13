## 战场奖励阳光的共用创建入口；复用原生拾取与寿命，不直接写入余额。
extends RefCounted
class_name BattleSunDrop

## [param game] 是奖励所属战场；[param world_position] 为世界掉落位置。
## [param total_value] 是总价值；[param max_piece_value] 限制单份尺寸，返回实际成功生成的价值。
## 不要求仍在MAIN_GAME，允许已开始的致死攻击同步触发结算后完成其奖励。
static func spawn(game: MainGameManager, world_position: Vector2,
		total_value: int, max_piece_value: int = 50) -> int:
	if total_value <= 0 or max_piece_value <= 0 or not world_position.is_finite() \
			or not is_instance_valid(game) or game != Global.main_game \
			or not game.is_inside_tree() or game.is_queued_for_deletion() \
			or game.get_tree().current_scene != game or not is_instance_valid(game.suns) \
			or not game.suns.is_inside_tree() or game.suns.is_queued_for_deletion():
		return 0
	var remaining: int = total_value # 拆成正常显示尺寸，价值完整保留。
	while remaining > 0:
		var value: int = mini(remaining, max_piece_value) # 本份阳光的实际可收集价值。
		var sun: Sun = SceneRegistry.SUN.instantiate() as Sun # 使用同一原生Sun场景与收集策略。
		if sun == null:
			break
		sun.init_sun(value, game.suns.to_local(world_position))
		game.suns.add_child(sun)
		var motion: Tween = sun.create_tween() # 掉落完成后交给原生自动收集策略。
		motion.tween_property(sun, "position:y", -24.0, 0.23).as_relative().set_trans(Tween.TRANS_QUAD)
		motion.tween_property(sun, "position:y", 28.0, 0.37).as_relative().set_trans(Tween.TRANS_QUAD)
		sun.spawn_sun_tween = motion
		motion.finished.connect(sun.on_sun_tween_finished)
		remaining -= value
	return total_value - remaining
