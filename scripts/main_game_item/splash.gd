extends Node2D
class_name Splash

## 播放水花时触发的声音；默认沿用僵尸入水音效。
var sfx_name: StringName = &"zombie_entering_water"

## 在 [param parent] 中按世界坐标 [param at] 生成一次水花，使用 [param zoom] 缩放、
## [param sound] 音效及相对父节点的 [param draw_order] 图层。[br]水花独立播放至结束。
static func spawn(parent: CanvasItem, at: Vector2, zoom: float = 1.0,
		sound: StringName = &"zombie_entering_water", draw_order: int = 0) -> void:
	var splash: Splash = SceneRegistry.SPLASH.instantiate() # 先配置位置与声音，入树后立即开播。
	splash.position = parent.get_global_transform().affine_inverse() * at
	splash.scale = Vector2.ONE * zoom
	splash.sfx_name = sound
	splash.z_index = draw_order
	parent.add_child(splash)

## 播放一次水花后释放节点。
func _ready() -> void:
	SoundManager.play_other_SFX(sfx_name)
	var splash_anim: AnimationPlayer = $AnimLib # 原版水花分件的播放器。
	splash_anim.play(&"ALL_ANIMS")
	await splash_anim.animation_finished
	queue_free()
