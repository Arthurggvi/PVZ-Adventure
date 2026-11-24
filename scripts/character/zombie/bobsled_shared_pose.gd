## 雪橇乘客共享姿态：由Body2原动画驱动另外两名乘客，不删角色节点、贴图或动作帧。
## 只针对已经证明三人关键帧完全相同的推车/上车片段，遇到其它动画资源时回退原播放器。
extends Node

## 本角色允许姿态同步的两段原生四人动作，不触碰死亡和其他状态机片段。
const SHARED_CLIPS: Array[StringName] = [&"Zombie_bobsled_push", &"Zombie_bobsled_jump"]
## 只允许姿态复制器实际同步的属性；未来资源若新增其它轨道立即回退四人原动画。
const SHARED_PROPERTIES: Array[StringName] = [
	&"position", &"rotation", &"scale", &"skew", &"visible", &"texture", &"self_modulate"
]
## 须在普通AnimationPlayer求值之后同步至可见分件，防止后一帧才更新。
const SYNC_PRIORITY: int = 100

## 同一辆雪橇的Body2原播放器，保留全速、完整关键帧与原本的动作通知。
var _driver: AnimationPlayer
## 已去重的Body2分件引用，均由其原生动画保持更新。
var _source: Array[Node2D] = []
## Body3的对应原始分件，保留其整体站位和继承的环境色。
var _middle: Array[Node2D] = []
## Body4的对应原始分件，保留其整体站位和继承的环境色。
var _rear: Array[Node2D] = []
## 标记这条分件路径是否是Sprite2D，只有精灵才同步其贴图和自身乘色。
var _sprite_paths := PackedByteArray()

## 先保持休眠；若本车的骨架路径不匹配，回退时绝不执行残缺的姿态映射。
func _ready() -> void:
	set_process(false)

## 原播放器已经由当前等阶美术缓存完成绑定后才执行；遇到不一致即拒绝优化。
## [param players] 为Body、Body2、Body3、Body4的原播放器顺序。
static func supports(players: Array[AnimationPlayer]) -> bool:
	if players.size() != 4:
		return false
	for clip: StringName in SHARED_CLIPS:
		if not players[1].has_animation(clip):
			return false
		var source: Animation = players[1].get_animation(clip) # 同一辆车的权威乘客动作。
		for track: int in range(source.get_track_count()):
			var route: NodePath = source.track_get_path(track) # 只支持已有的分件单属性动画。
			if source.track_get_type(track) != Animation.TYPE_VALUE or route.is_absolute() \
					or route.get_subname_count() != 1 or not SHARED_PROPERTIES.has(route.get_subname(0)):
				return false # 后续新增音效/方法/自定义属性时，必须保留三套原生求值。
		for follower_index: int in [2,3]:
			if not players[follower_index].has_animation(clip):
				return false
			var target: Animation = players[follower_index].get_animation(clip) # 可能已有独立等阶库。
			if source == target:
				continue # 同一只读Animation资源不必逐轨比较。
			if source.length != target.length or source.loop_mode != target.loop_mode \
					or source.get_track_count() != target.get_track_count():
				return false
			for track: int in range(source.get_track_count()):
				if source.track_get_type(track) != target.track_get_type(track) \
						or source.track_get_path(track) != target.track_get_path(track) \
						or source.track_get_key_count(track) != target.track_get_key_count(track) \
						or source.track_get_interpolation_type(track) != target.track_get_interpolation_type(track) \
						or source.track_is_enabled(track) != target.track_is_enabled(track):
					return false
				for key: int in range(source.track_get_key_count(track)):
					if source.track_get_key_time(track,key) != target.track_get_key_time(track,key) \
							or source.track_get_key_value(track,key) != target.track_get_key_value(track,key) \
							or source.track_get_key_transition(track,key) != target.track_get_key_transition(track,key):
						return false

	return true

## 装配同辆雪橇的三人分件映射，返回是否成功。仅完整装配后才停用两个冗余播放器。
## [param players] 需提前通过 [method supports] 验证，与真实已生成的角色一一对应。
func configure(players: Array[AnimationPlayer]) -> bool:
	_driver = players[1]
	var source_root: Node = _driver.get_node(_driver.root_node) # Body2真实AnimationPlayer根。
	var mid_player: AnimationPlayer = players[2] # Body3仍保留原播放器和动画库。
	var rear_player: AnimationPlayer = players[3] # Body4仍保留原播放器和动画库。
	var mid_root: Node = mid_player.get_node(mid_player.root_node)
	var rear_root: Node = rear_player.get_node(rear_player.root_node)
	var seen: Dictionary[StringName, bool] = {} # 两个片段共享的分件路径只登记一次。
	for clip: StringName in SHARED_CLIPS:
		var animation: Animation = _driver.get_animation(clip)
		for track: int in range(animation.get_track_count()):
			var route: NodePath = animation.track_get_path(track) # 目标节点:原生属性。
			var subpath: StringName = StringName(route.get_concatenated_names())
			if seen.has(subpath):
				continue
			seen[subpath] = true
			var node_path: NodePath = NodePath(subpath)
			var a: Node2D = source_root.get_node_or_null(node_path) as Node2D
			var b: Node2D = mid_root.get_node_or_null(node_path) as Node2D
			var c: Node2D = rear_root.get_node_or_null(node_path) as Node2D
			if a == null or b == null or c == null or (a is Sprite2D) != (b is Sprite2D) \
					or (a is Sprite2D) != (c is Sprite2D):
				return false # 没有100%映射时不动原播放器，避免残缺的队员。
			_source.append(a)
			_middle.append(b)
			_rear.append(c)
			_sprite_paths.append(1 if a is Sprite2D else 0)
	mid_player.active = false # 原动画仍保留，停止本帧重复求值。
	rear_player.active = false
	process_priority = SYNC_PRIORITY
	_copy_pose() # 装配当帧立即跟上，不留下闪白或旧帧。
	set_process(true)
	return true

## 在完整动画已经更新本帧身体后，按已校验的对应关系同步另外两名乘客。
func _process(_delta: float) -> void:
	_copy_pose()

## 只有变更的Transform2D、贴图、可见性和自身乘色才提交到CanvasItem。
## 不覆盖Body3/Body4的根坐标、全局环境色或本车逻辑碰撞。
func _copy_pose() -> void:
	if not is_instance_valid(_driver):
		set_process(false)
		return
	for index: int in range(_source.size()):
		var source: Node2D = _source[index] # Body2已求值的真实当前分件。
		var middle: Node2D = _middle[index] # Body3的同名分件。
		var rear: Node2D = _rear[index] # Body4的同名分件。
		var transform: Transform2D = source.transform # 合并原位置、旋转、缩放和偏斜。
		if middle.transform != transform:
			middle.transform = transform
		if rear.transform != transform:
			rear.transform = transform
		var visible: bool = source.visible # 每分件实际local visible，不覆盖父身体的可见性。
		if middle.visible != visible:
			middle.visible = visible
		if rear.visible != visible:
			rear.visible = visible
		if _sprite_paths[index] != 0:
			var src: Sprite2D = source as Sprite2D # 原动画中纹理和自发光的独立属性。
			var mid: Sprite2D = middle as Sprite2D
			var end: Sprite2D = rear as Sprite2D
			if mid.texture != src.texture:
				mid.texture = src.texture
			if end.texture != src.texture:
				end.texture = src.texture
			if mid.self_modulate != src.self_modulate:
				mid.self_modulate = src.self_modulate
			if end.self_modulate != src.self_modulate:
				end.self_modulate = src.self_modulate
