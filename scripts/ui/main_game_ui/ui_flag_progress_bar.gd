extends Control
class_name FlagProgressBar
## 使用真实进度值和追赶进度值，使进度条平滑移动

## 真实进度值 (0-100)
var real_value: float = 0.0
## 追赶进度值 (0-100)
var chase_value: float = 0.


## 进度条
@onready var texture_progress_bar: TextureProgressBar = $TextureProgressBar
## 小僵尸头表示进度条
@onready var mini_zombie: TextureRect = $MiniZombie
## 旗帜
@onready var flag: FlagProgressBarFlag = $Flag

## 小僵尸的起始位置
var start_minizombie :float = 142
## 小僵尸的结束位置
var end_minizombie :float = -4
## 小僵尸的当前位置
var curr_minizombie : float
## 进度条开始位置，用于生成旗帜
var start_flag = start_minizombie + 6
## 进度条结束位置，用于生成旗帜
var end_flag = end_minizombie + 6
## 存储生成的旗帜
var flag_arr : Array[FlagProgressBarFlag] = []
## 当前旗帜的索引
#@export var curr_flag_i : int = 0


func _ready() -> void:
	curr_minizombie = start_minizombie
	set_progress(0)
	texture_progress_bar.value = 0
	mini_zombie.position.x = start_minizombie


## 根据旗帜数量生成旗帜，并删除原本的旗帜
## 原版仍按每十波生成一面旗，位置和原计算一致。
func create_flag(flag_num: int) -> void:
	var positions: Array[float] = []
	var total_distance: float = start_flag - end_flag
	for index: int in range(1, flag_num + 1):
		positions.append(start_flag - total_distance * ((index * 10.0 - 1.0) / (flag_num * 10.0 - 1.0)))
	_build_flag_nodes(positions)

func init_flag_from_wave(wave_num: int) -> void:
	assert(wave_num % 10 == 0, "原版关卡波次数必须为10的倍数")
	create_flag(wave_num / 10)

## 冒险波次无十波要求；旗帜对应 WaveProfile 标记的大波和最后一波。
func init_flag_from_adventure_profile(profile: WaveProfile) -> void:
	if profile == null or profile.wave_count < 2:
		push_error("冒险旗帜要求至少两波。")
		return
	var marks: Array[int] = profile.flag_waves.duplicate()
	if not marks.has(profile.wave_count):
		marks.append(profile.wave_count)
	marks.sort()
	var positions: Array[float] = []
	var total_distance: float = start_flag - end_flag
	for wave_number: int in marks:
		positions.append(start_flag - total_distance * float(wave_number - 1) / float(profile.wave_count - 1))
	_build_flag_nodes(positions)

func _build_flag_nodes(positions: Array[float]) -> void:
	for old: FlagProgressBarFlag in flag_arr:
		if is_instance_valid(old):
			old.queue_free()
	flag_arr.clear()
	for x: float in positions:
		var new_flag: FlagProgressBarFlag = flag.duplicate() as FlagProgressBarFlag
		add_child(new_flag)
		move_child(new_flag, 1)
		new_flag.position.x = x
		flag_arr.append(new_flag)
	flag.queue_free()

## 开始下一轮游戏,进度条更新数据
func start_next_game_flag_progress_bar_update():
	set_progress(0, -1)
	texture_progress_bar.value = 0
	for curr_flag:FlagProgressBarFlag in flag_arr:
		curr_flag.down_flag()


## 设置真实进度
func set_progress(value: float, flag_i:int = -1):
	real_value = clamp(value, 0.0, 100.0)

	if flag_i != -1:
		flag_arr[flag_i].up_flag()


## 设置每秒进度增加
func set_progress_add_every_sec(add_value:float):
	var value = real_value + add_value
	real_value = clamp(value, 0.0, 100.0)


# 动画追赶进度
func _process(delta):
	# 在1秒内追赶真实进度
	if abs(chase_value - real_value) > 0.1:
		# 计算追赶速度 (每秒10单位)
		var speed = 10.0 * delta

		if chase_value < real_value:
			chase_value = min(chase_value + speed, real_value)
		else:
			# 如果真实进度减小，追赶进度也会减小
			chase_value = max(chase_value - speed, real_value)

		# 更新UI
		texture_progress_bar.value = chase_value
		curr_minizombie = start_minizombie + chase_value * (end_minizombie - start_minizombie) * 0.01
		mini_zombie.position.x = curr_minizombie

	else:
		# 如果非常接近，直接设为相等
		if chase_value != real_value:
			chase_value = real_value

			texture_progress_bar.value = chase_value
			curr_minizombie = start_minizombie + chase_value * (end_minizombie - start_minizombie) * 0.01
			mini_zombie.position.x = curr_minizombie
