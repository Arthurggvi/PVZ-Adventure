extends Node2D
class_name Sun

@export var sun_value := 25

## 阳光存在时间
@export var exist_time:float = 10.0
var collected := false  # 是否已被点击收集
## 生产阳光移动的tween
var spawn_sun_tween:Tween

func _ready() -> void:
	add_to_group(&"touch_collectibles")
	_sun_scale(sun_value)
	## 启动一个10秒定时器
	await get_tree().create_timer(exist_time, false).timeout

	# 如果还没被点击收集，自动销毁
	if not collected and is_instance_valid(self):
		_start_fade_out()

## 初始化阳光的价值 [param curr_sun_value] 和局部坐标 [param pos]。
## [param visual_material] 只应用到动画精灵，空值使用场景原色。
func init_sun(curr_sun_value: int, pos: Vector2, visual_material: Material = null) -> void:
	sun_value = curr_sun_value
	position = pos
	if visual_material != null:
		$body.material = visual_material

func _sun_scale(new_sun_value:int):
	var new_scale = new_sun_value/25.0
	scale = Vector2(new_scale,new_scale)


## 收集阳光，由手动点击或装备触发。同一份阳光只结算一次。
func collect() -> void:
	if spawn_sun_tween:
		spawn_sun_tween.kill()

	if collected:
		return  # 防止重复点击

	collected = true  # 设置已被收集
	var target_position := Vector2.ZERO # 没有活跃战场时保留原点回收表现。
	SoundManager.play_other_SFX("points")
	if is_instance_valid(Global.main_game):
		var target: Marker2D = Global.main_game.marker_2d_sun_target # 当前卡槽的实际回收点。
		if not is_instance_valid(target):
			target = Global.main_game.marker_2d_sun_target_default
		# 经视口坐标跨越卡槽和战场画布，同时考虑镜头缩放与位移。
		target_position = get_canvas_transform().affine_inverse() * target.get_global_transform_with_canvas().origin

		EventBus.push_event("add_sun_value", [sun_value])

	var tween:Tween = get_tree().create_tween()
	# 将节点从当前位置移动到(100, 200)，耗时0.5秒
	tween.tween_property(self, "global_position", target_position, 0.3).set_ease(Tween.EASE_OUT)
	$Button.queue_free()
	await tween.finished
	## 到达位置，变透明
	tween = create_tween()
	tween.set_parallel()
	tween.tween_property(self, "modulate:a", 0, 0.5)
	await tween.finished
	queue_free()


func _start_fade_out() -> void:
	var tween = get_tree().create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 1.0)  # 🌫️ 1秒淡出
	tween.finished.connect(func():
		if not collected and is_instance_valid(self):
			self.queue_free()
	)

func on_sun_tween_finished():
	if BattleCollectionPolicy.allows(true):
		collect()
