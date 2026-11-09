## 静态设施的动画适配器；保留角色接口，不依赖不存在的动画播放器。
extends AnimComponentBase
class_name AnimComponentStatic

## 静态角色没有时间轴，原始速度固定为 1。
func _ready() -> void:
	animation_origin_speed = 1.0

## [param _speed_factor_product] 只影响动态角色，静态设施无需更新。
func owner_update_speed(_speed_factor_product: float) -> void:
	pass

## [param _speed_scale] 静态设施无可缩放时间轴。
func update_anim_speed_scale(_speed_scale: float) -> void:
	pass
