## Buff 图鉴的独立子视口；只拥有纯视觉与示例读数，切换或关闭即停止整套演示。
extends SubViewportContainer

## 每次播放独立创建的舞台，角色源节点从不进入展示树。
const Stage: GDScript = preload("res://scripts/adventure/ui/buff_preview_stage.gd")
## 按需读取样本路径，不预加载所有角色。
const Actor: GDScript = preload("res://scripts/adventure/ui/buff_preview_actor.gd")
## 当前效果的原生视觉依赖查询。
const Effects: GDScript = preload("res://scripts/adventure/ui/buff_preview_fx.gd")
## 共享图鉴中文字库的依赖路径。
const Overlay: GDScript = preload("res://scripts/adventure/ui/buff_preview_overlay.gd")
## 与详情面板一致的固定舞台尺寸，所有示例坐标以此为基准。
const STAGE_SIZE: Vector2i = Vector2i(420, 330)
## 仅渲染当前预览的二维世界，输入与屏幕采样和正式战场隔离。
var _viewport: SubViewport
## 当前完整舞台；重播时整体替换，避免残留粒子或旧计时。
var _stage: Stage
## 当前条目的只读副本，供重播使用。
var _entry: Dictionary = {}

## 返回 [param entry] 的少量样本及效果依赖，供已有异步窗口加载协议准备。
static func required_resource_paths(entry: Dictionary) -> PackedStringArray:
	var subject: String = Actor.subject_for(entry) # 当前状态适用的代表角色。
	var path: String = Actor.SCENES.get(subject, Actor.SCENES["zombie"]) # 未知展示身份回退为普通僵尸。
	var result: PackedStringArray = PackedStringArray([path, Overlay.FONT_PATH]) # 当前角色及共享中文字库。
	for effect_path: String in Effects.required_resource_paths(entry): # 原生特效仅随当前条目读取。
		if not result.has(effect_path):
			result.append(effect_path)
	if entry.get("preview_id", &"") == &"damage_transfer" and not result.has(Actor.SCENES["zombie"]):
		result.append(Actor.SCENES["zombie"])
	return result

## 建立独立二维视口，不接收游戏输入，不使用物理世界和正式战斗相机。
func _ready() -> void:
	custom_minimum_size = Vector2(STAGE_SIZE)
	size = Vector2(STAGE_SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	_viewport = SubViewport.new()
	_viewport.size = STAGE_SIZE
	_viewport.disable_3d = true
	_viewport.world_2d = World2D.new()
	_viewport.gui_disable_input = true
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	set_process(false)
	if not _entry.is_empty():
		show_buff(_entry)

## 展示已完成资源准备的 [param entry]，替换旧舞台；未入树时仅保存条目等待就绪。
func show_buff(entry: Dictionary) -> void:
	stop()
	_entry = entry.duplicate(true)
	if _viewport == null:
		return
	if is_instance_valid(_stage):
		_viewport.remove_child(_stage)
		_stage.queue_free()
	_stage = Stage.new()
	_viewport.add_child(_stage)
	_stage.setup(_entry)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	set_process(true)

## 从头重播当前状态，整组重建保证暂停、位移、粒子和原生动画都回到初始姿态。
func replay() -> void:
	if not _entry.is_empty():
		show_buff(_entry)

## 立即停止本视口的动画与粒子；未配置或正在退出时可安全重复调用。
func stop() -> void:
	set_process(false)
	if is_instance_valid(_stage):
		_stage.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

## 以 [param delta] 推进本地演示，不调整引擎倍速、暂停树或任何全局状态。
func _process(delta: float) -> void:
	if is_instance_valid(_stage):
		_stage.advance(delta)

## 关闭详情时立即取消后续帧，所有视觉与本地资源引用随父节点释放。
func _exit_tree() -> void:
	stop()
