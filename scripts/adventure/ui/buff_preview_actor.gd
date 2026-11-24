## 图鉴的纯视觉骨架；源角色始终离树，只保留身体精灵及视觉属性动画。
extends Node2D

## 少量示例角色的路径，选择条目后才加载所需的一种。
const SCENES: Dictionary[String, String] = {
	"zombie": "res://scenes/character/zombie/zombie_001_norm.tscn",
	"plant": "res://scenes/character/plant/plant_001_pea_shooter_single.tscn",
	"mushroom": "res://scenes/character/plant/plant_014_scaredy_shroom.tscn",
	"sunflower": "res://scenes/character/plant/plant_002_sun_flower.tscn",
}
## 动画仅能修改这些纯画面属性，方法调用、声音和战斗轨道全部丢弃。
const VISUAL_PROPERTIES: PackedStringArray = ["position", "rotation", "scale", "skew", "texture", "visible", "modulate", "self_modulate", "frame", "offset"]
## 保留原 Body 路径的视觉根，统一取景与染色。
var _visual: Node2D
## 仅含已筛选属性轨道的独立播放器，由舞台手动推进。
var _player: AnimationPlayer
## 当前原生动作名，重复设置不重启动作。
var _clip: StringName = &""
## 示例物种决定原生动作名称，不参与任何玩法注册。
var _subject: String = "zombie"

## 依据 [param entry] 选择适合机制的示例角色；睡眠与胆怯使用真实胆小菇。
static func subject_for(entry: Dictionary) -> String:
	var id: StringName = entry.get("preview_id", &"") # 独立于界面显示名称的机制身份。
	if id in [&"sleep", &"awake", &"scaredy", &"fearless"]:
		return "mushroom"
	if id == &"sun_yield":
		return "sunflower"
	if id in [&"nullification", &"attack_boost", &"attack_rate", &"dynasty", &"regeneration", &"negative_immunity"]:
		return "plant"
	return str((entry.get("preview", {}) as Dictionary).get("subject", "zombie"))

## 在已入树的视觉壳上构建 [param subject]；[param height] 是取景高度，失败返回 false。
## 源节点不进入场景树，故不运行角色初始化、发现登记、掉落或战斗组件。
func build(subject: String, height: float = 122.0) -> bool:
	_subject = subject if SCENES.has(subject) else "zombie"
	var packed: PackedScene = load(SCENES[_subject]) as PackedScene # 调用方已通过窗口资源协议准备此路径。
	if packed == null:
		return false
	var source: Node = packed.instantiate() # 离树样本只用来读取原生层级和动画资源。
	var body: Node2D = source.get_node_or_null(^"Body") as Node2D # 不复制根角色及组件。
	if body == null:
		source.free()
		return false
	_visual = Node2D.new()
	add_child(_visual)
	_copy_branch(body, _visual)
	_player = AnimationPlayer.new()
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_visual.add_child(_player)
	_player.add_animation_library(&"", safe_library(source.get_node_or_null(^"AnimationPlayer") as AnimationPlayer, _visual))
	source.free()
	pose(&"idle")
	var bounds: Rect2 = _extent(_visual, Transform2D.IDENTITY) # 原生首帧的可见轮廓，不把隐藏部件算入。
	if not bounds.has_area():
		return false
	var factor: float = minf(height / bounds.size.y, 94.0 / bounds.size.x) # 两侧留出位移、状态和护卫空间。
	_visual.scale = Vector2.ONE * factor
	_visual.position = -Vector2(bounds.get_center().x, bounds.end.y) * factor
	return true

## 复制 [param source] 到 [param target]，仅新建无脚本的 Node2D 和 Sprite2D。
static func _copy_branch(source: Node2D, target: Node2D) -> void:
	var copy: Node2D = Sprite2D.new() if source is Sprite2D else Node2D.new() # 子类的碰撞、信号与脚本不会被复制。
	copy.name = source.name
	copy.transform = source.transform
	copy.visible = source.visible
	copy.modulate = source.modulate
	copy.self_modulate = source.self_modulate
	copy.z_index = source.z_index
	copy.z_as_relative = source.z_as_relative
	if source is Sprite2D:
		var sprite: Sprite2D = copy as Sprite2D # 纹理资源共享只读，其余视觉状态逐项复制。
		sprite.texture = source.texture
		sprite.centered = source.centered
		sprite.offset = source.offset
		sprite.hframes = source.hframes
		sprite.vframes = source.vframes
		sprite.frame = source.frame
		sprite.flip_h = source.flip_h
		sprite.flip_v = source.flip_v
		sprite.region_enabled = source.region_enabled
		sprite.region_rect = source.region_rect
	target.add_child(copy)
	for child: Node in source.get_children(): # 路径保持原样，非二维视觉节点直接跳过。
		if child is Node2D:
			_copy_branch(child as Node2D, copy)

## 从 [param source] 复制指向 [param target] 的安全视觉轨道，返回独立动画库；不改写实战资源。
static func safe_library(source: AnimationPlayer, target: Node2D) -> AnimationLibrary:
	var library: AnimationLibrary = AnimationLibrary.new() # 仅属于本预览的动画库。
	if source == null:
		return library
	for clip: StringName in source.get_animation_list(): # 保留原生名字，供不同角色选择待机、攻击、睡眠和胆怯。
		var animation: Animation = source.get_animation(clip).duplicate() as Animation # 共享纹理，但动画轨道本身独立。
		for index: int in range(animation.get_track_count() - 1, -1, -1): # 倒序移除以保持剩余索引有效。
			var path: NodePath = animation.track_get_path(index) # 相对原角色根的视觉节点与属性路径。
			if animation.track_get_type(index) != Animation.TYPE_VALUE or path.get_subname_count() != 1 \
					or not VISUAL_PROPERTIES.has(String(path.get_subname(0))) \
					or target.get_node_or_null(NodePath(path.get_concatenated_names())) == null:
				animation.remove_track(index)
		if animation.get_track_count() > 0:
			animation.loop_mode = Animation.LOOP_LINEAR
			library.add_animation(clip, animation)
	return library

## 将 [param name] 映射到原生动作；无对应动作时保留待机，切换姿态会应用首帧。
func pose(name: StringName) -> void:
	if _player == null:
		return
	var clip: StringName = &"Zombie_idle" # 僵尸默认动作。
	match _subject:
		"zombie":
			clip = &"Zombie_walk" if name == &"walk" else (&"Zombie_eat" if name == &"attack" else &"Zombie_idle")
		"plant":
			clip = &"Head_Attack" if name == &"attack" else &"Idle"
		"mushroom":
			clip = {&"sleep": &"ScaredyShroom_sleep", &"scaredy": &"ScaredyShroom_scaredidle", &"attack": &"ScaredyShroom_shooting"}.get(name, &"ScaredyShroom_idle")
		"sunflower":
			clip = &"SunFlower_idle"
	if clip != _clip and _player.has_animation(clip):
		_clip = clip
		_player.play(clip)
		_player.advance(0.0)

## 以 [param delta] 秒推进纯视觉，再应用 [param tint]；[param flip] 仅改变朝向。
func advance(delta: float, tint: Color, flip: bool = false) -> void:
	if _player != null:
		_player.advance(maxf(0.0, delta))
	if _visual != null:
		_visual.modulate = tint
	scale.x = -absf(scale.x) if flip else absf(scale.x)

## 返回 [param node] 在 [param transform] 中的可见精灵范围；隐藏分支完全排除。
static func _extent(node: Node2D, transform: Transform2D) -> Rect2:
	if not node.visible:
		return Rect2()
	var result: Rect2 = transform * node.get_rect() if node is Sprite2D and node.texture != null else Rect2() # 当前部件范围。
	for child: Node in node.get_children(): # 新视觉树中没有非视觉脚本可被调用。
		if child is Node2D:
			var bounds: Rect2 = _extent(child as Node2D, transform * (child as Node2D).transform) # 将后代统一换算到根坐标。
			if bounds.has_area():
				result = result.merge(bounds) if result.has_area() else bounds
	return result
