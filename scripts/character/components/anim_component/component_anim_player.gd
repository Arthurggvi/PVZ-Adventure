extends AnimComponentBase
class_name AnimComponentPlayer
## 只使用AnimationPlayer和自定义状态机处理动画

## 主体动画播放器的路径；默认沿用角色根节点下的播放器，也可指向独立美术场景。
@export_node_path("AnimationPlayer") var animation_player_path: NodePath = ^"../AnimationPlayer"
## 负责播放主体动画并应用角色速度倍率的播放器。
@onready var animation_player: AnimationPlayer = get_node(animation_player_path) as AnimationPlayer

func _ready() -> void:
	animation_origin_speed = animation_player.speed_scale
	animation_player.animation_finished.connect(_on_animation_finished)

## 更新动画速度
## [param speed_factor_product] 角色各速度因素的乘积，乘以初始动画速度后得到实际播放速度。
func owner_update_speed(speed_factor_product:float):
	animation_player.speed_scale = animation_origin_speed * speed_factor_product

## 更新动画速度(动画播放速度)
## [param speed_scale] 直接应用到动画系统的播放速度倍率，0 表示停止推进动画。
func update_anim_speed_scale(speed_scale:float):
	animation_player.speed_scale = speed_scale

## 停止动画
func stop_anim():
	animation_player.pause()
