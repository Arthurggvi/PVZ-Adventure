## 原生状态美术的安全视觉副本；不保留特效原脚本、等待协程或场景外回调。
extends Node2D

## 与角色预览共享白名单复制，避免复制实战方法轨道。
const Actor: GDScript = preload("res://scripts/adventure/ui/buff_preview_actor.gd")
## 按需声明的原生状态资源，字符串不会在图鉴启动时加载。
const PATHS: Dictionary[String, String] = {
	"ice": "res://scenes/fx/ice_effect.tscn",
	"fire": "res://scenes/fx/fire_pea_impact.tscn",
	"butter": "res://scenes/fx/butter_splat.tscn",
}
## 原版阳光纹理只用作示意标记，不创建可拾取对象。
const SUN_PATH: String = "res://assets/reanim/Sun1.png"
## 当前条目所需的纯视觉效果，随此节点一并销毁。
var _visuals: Dictionary[String, Node2D] = {}
## 灼烧的原生单次动画，由舞台手动采样形成循环。
var _fire_player: AnimationPlayer
## 冰解体的原生粒子实例，只有本视口内的视觉数据。
var _shards: GPUParticles2D
## 上一帧的冻结显示状态，用于仅在解冻边界发射一次碎片。
var _was_iced: bool = false

## 返回 [param entry] 的原生效果路径；不请求其他状态、所有角色或音效。
static func required_resource_paths(entry: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray() # 当前条目唯一依赖列表。
	var id: StringName = entry.get("preview_id", &"") # 稳定机制身份。
	if id in [&"ice_freeze", &"freeze_charge", &"negative_immunity"]:
		result.append(PATHS["ice"])
	if id in [&"burn", &"deep_cold"]:
		result.append(PATHS["fire"])
	if id == &"butter":
		result.append(PATHS["butter"])
	if id in [&"sun_infusion", &"sun_yield"]:
		result.append(SUN_PATH)
	return result

## 根据 [param entry] 构建本次所需的原生视觉；必须在资源准备完成后调用。
func build(entry: Dictionary) -> void:
	var requested: PackedStringArray = required_resource_paths(entry) # 仅处理当前条目可见的少量特效。
	for key: String in PATHS: # 目录中的字符串本身不触发加载。
		if not requested.has(PATHS[key]):
			continue
		var packed: PackedScene = load(PATHS[key]) as PackedScene # 该路径已由详情宿主准备。
		var source: Node2D = packed.instantiate() as Node2D # 源特效不入树，不启动原脚本计时。
		var holder: Node2D = Node2D.new() # 独立容器承载纯视觉副本。
		add_child(holder)
		Actor._copy_branch(source, holder)
		var visual: Node2D = holder.get_child(0) as Node2D # 副本根保留原生 Body 相对路径。
		_visuals[key] = holder
		holder.visible = false
		if key == "fire":
			_fire_player = AnimationPlayer.new()
			_fire_player.process_mode = Node.PROCESS_MODE_DISABLED
			visual.add_child(_fire_player)
			_fire_player.add_animation_library(&"", Actor.safe_library(source.get_node(^"AnimationPlayer") as AnimationPlayer, visual))
			_fire_player.play(&"fire_done")
			holder.position = Vector2(0, -54)
			holder.scale = Vector2.ONE * 1.7
		elif key == "butter":
			holder.position = Vector2(0, -101)
			holder.scale = Vector2.ONE * 0.85
		elif key == "ice":
			holder.scale = Vector2(1.25, 1.15)
			_shards = (source.get_node(^"GPUParticles2D") as GPUParticles2D).duplicate() as GPUParticles2D
			_shards.set_script(null)
			_shards.emitting = false
			add_child(_shards)
		source.free()

## 按 [param frame] 与 [param time] 更新本地视觉；只采样原动画，不执行任何命中或解冻逻辑。
func render_frame(frame: Dictionary, time: float) -> void:
	var effect: String = str(frame["effect"]) # 当前应显示的原生状态。
	for key: String in _visuals: # 同一效果复用一个节点，逐帧不会产生新实例。
		_visuals[key].visible = key == effect or (key == "fire" and frame["special"] == "fire_resist" and fposmod(time - 1.0, 2.0) < 0.5)
	if _fire_player != null and _visuals["fire"].visible:
		var clip: Animation = _fire_player.get_animation(&"fire_done") # 循环沿用实战动画时长。
		_fire_player.seek(fposmod(time, maxf(clip.length, 0.01)), true)
	if _was_iced and effect != "ice" and _shards != null:
		_shards.restart()
		_shards.emitting = true
	_was_iced = effect == "ice"
