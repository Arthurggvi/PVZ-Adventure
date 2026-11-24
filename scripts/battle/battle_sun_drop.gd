## 战场奖励阳光的共用创建入口；复用原生拾取与寿命，不直接写入余额。
extends RefCounted
class_name BattleSunDrop

## [param game] 是奖励所属战场；[param world_position] 为世界掉落位置。
## [param total_value] 是总价值；[param max_piece_value] 限制单份尺寸，返回实际成功生成的价值。
## 不要求仍在MAIN_GAME，允许已开始的致死攻击同步触发结算后完成其奖励。
static func spawn(game: MainGameManager, world_position: Vector2,
		total_value: int, max_piece_value: int = 50) -> int:
	if total_value <= 0 or max_piece_value <= 0 or not world_position.is_finite() or not _has_drop_layer(game):
		return 0
	var remaining: int = total_value # 拆成正常显示尺寸，价值完整保留。
	while remaining > 0:
		var value: int = mini(remaining, max_piece_value) # 本份阳光的实际可收集价值。
		var sun: Sun = _create_sun(game, world_position, value) # 使用同一原生 Sun 场景与收集策略。
		if sun == null:
			break
		var motion: Tween = sun.create_tween() # 掉落完成后交给原生自动收集策略。
		motion.tween_property(sun, "position:y", -24.0, 0.23).as_relative().set_trans(Tween.TRANS_QUAD)
		motion.tween_property(sun, "position:y", 28.0, 0.37).as_relative().set_trans(Tween.TRANS_QUAD)
		sun.spawn_sun_tween = motion
		motion.finished.connect(sun.on_sun_tween_finished)
		remaining -= value
	return total_value - remaining

## 在 [param game] 将一份 [param value] 的阳光从 [param origin] 落到 [param landing]。
## 起落点为世界坐标，[param seconds] 为下落游戏秒；落地沿用原生自动收集，不计入自然天降。
static func spawn_falling(game: MainGameManager, origin: Vector2, landing: Vector2,
		value: int, seconds: float) -> void:
	if value <= 0 or not origin.is_finite() or not landing.is_finite() \
			or not is_finite(seconds) or seconds <= 0.0 or not _has_drop_layer(game):
		return
	var sun: Sun = _create_sun(game, origin, value) # 天降奖励与其他掉落共用价值和点击交互。
	if sun == null:
		return
	var motion: Tween = sun.create_tween() # 提前拾取时由阳光终止运动。
	sun.spawn_sun_tween = motion
	motion.tween_property(sun, ^"position", game.suns.to_local(landing), seconds) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	motion.finished.connect(sun.on_sun_tween_finished)

## 判断 [param game] 是否仍持有当前场景中可挂载阳光的掉落层。
static func _has_drop_layer(game: MainGameManager) -> bool:
	return is_instance_valid(game) and game == Global.main_game \
		and game.is_inside_tree() and not game.is_queued_for_deletion() \
		and game.get_tree().current_scene == game and is_instance_valid(game.suns) \
		and game.suns.is_inside_tree() and not game.suns.is_queued_for_deletion()

## 为已验证的 [param game] 在世界坐标 [param world_position] 创建 [param value] 阳光。
static func _create_sun(game: MainGameManager, world_position: Vector2, value: int) -> Sun:
	var sun: Sun = SceneRegistry.SUN.instantiate() as Sun # 保留原生寿命、价值尺寸和收集信号。
	if sun != null:
		sun.init_sun(value, game.suns.to_local(world_position))
		game.suns.add_child(sun)
	return sun
