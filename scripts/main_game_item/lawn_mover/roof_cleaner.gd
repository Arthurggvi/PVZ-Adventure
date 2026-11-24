extends LawnMover
class_name RoofCleaner

## 屋顶斜坡 移动方向y值修正,移动时,对应y方向的修正,
var move_dir_y_correct_slope:Vector2 = Vector2.ZERO
## 本帧本地水平步长，单位为像素。
var move_x:float
## 所属棋盘的高度入口。多段坡面采样实际跨步的世界坐标。
var _terrain: MainGameSlope

func _ready() -> void:
	super()
	var game: MainGameManager = Global.main_game # 只使用当前清洁车所属战场的坡面。
	if is_instance_valid(game) and game.is_ancestor_of(self):
		_terrain = game.main_game_slope
		if is_instance_valid(_terrain):
			global_position.y += _terrain.get_all_slope_y(global_position.x)


## 用 [param delta] 游戏秒行驶。启用精确高度采样时，跨坡脚、坡顶或平台的步长使用统一地形。
func _process(delta: float) -> void:
	if is_moving and not cheat_fixed_enabled:
		var start_x: float = global_position.x # 横移前的实际世界位置。
		move_x = move_speed * delta
		position.x += move_x

		if is_instance_valid(_terrain) and _terrain.sample_walking_height:
			global_position.y += _terrain.get_all_slope_y(global_position.x) - _terrain.get_all_slope_y(start_x)
		elif move_dir_y_correct_slope != Vector2.ZERO:
			position.y += move_x / move_dir_y_correct_slope.x * move_dir_y_correct_slope.y

		if not screen_rect.has_point(global_position):
			queue_free()


## 更新移动方向修正(斜面时使用)
func update_move_dir_y_correct(curr_move_dir_y_correct_slope:Vector2):
	#print("更新移动方向:", move_dir)
	self.move_dir_y_correct_slope = curr_move_dir_y_correct_slope


## 启动小推车
func _start_mower():
	# 覆盖基类的启动入口也要拦截销毁当帧的延迟信号。
	if is_destroyed or is_queued_for_deletion():
		return
	# 屋顶车复用固定碰撞击杀，不启动坡面移动。
	if cheat_fixed_enabled:
		_mower_run_all_zombie_on_start()
		return
	is_moving = true
	animation_player.play("RoofCleaner")
	SoundManager.play_other_SFX("lawnmower")
	_mower_run_all_zombie_on_start()
