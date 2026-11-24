## 播放共享的原动画姿态。每段特效只需要一个节点和一个原生播放时钟。
extends Node2D

## 单个可见图层在某关键帧上的原始显示数据。
class LayerPose:
	## 源图集区域，保留自身的 UV 裁剪。
	var texture: Texture2D
	## 源图层相对于 Rig 的变换。
	var transform: Transform2D
	## 源图层的调制颜色，提交到矩形而非 CanvasItem。
	var tint: Color


## 共享片段姿态和写入姿态编号的原生动画。
class Clip:
	## 源 Rig 的局部变换，仍保留这一层矩阵乘法及绘制层级。
	var rig_transform: Transform2D
	## 按时间和源图层下标排列的姿态。空图层当前不可见。
	var poses: Array[Array] = []
	## 单条离散值轨道驱动姿态。长度与源动画相同。
	var library: AnimationLibrary
	## 该片段实际用到的最后一层及之前的图层总数。
	var layer_count: int


## 原生播放器接管首帧时点、暂停和结束事件。
var player := AnimationPlayer.new()
## 由播放器写入的姿态编号；-1 表示还原到首个动画更新之前。
var pose: int = -1:
	set(value):
		if value != pose:
			_apply_pose(pose, value)
			pose = value
## 当前实例所播放的只读片段。
var _clip: Clip
## 此转职的原始材质；原色片段为 null。
var _material: ShaderMaterial
## 保持源层级变换的绘制父项。
var _rig: RID
## 原顺序排列的渲染图层，按需创建，离场时释放。
var _layers: Array[RID] = []


## [param clip] 提供原动画姿态。[param shader_material] 保留出战等阶的原着色器与参数。
func setup(clip: Clip, shader_material: ShaderMaterial) -> void:
	_clip = clip
	_material = shader_material
	_layers.resize(clip.layer_count)
	_rig = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_rig, get_canvas_item())
	RenderingServer.canvas_item_set_transform(_rig, clip.rig_transform)
	player.add_animation_library(&"", clip.library)
	add_child(player)


## 从 [param previous] 到 [param next] 只提交发生变化的图层，保持原绘制顺序。
func _apply_pose(previous: int, next: int) -> void:
	var before: Array = _clip.poses[previous] if previous >= 0 else [] # 无旧帧时所有图层都隐藏。
	var after: Array = _clip.poses[next] if next >= 0 else [] # 回收重置到隐藏状态。
	for index: int in _layers.size(): # 绘制项与源图层一一对应。
		var old: LayerPose = before[index] if previous >= 0 else null # 上一帧的属性用于跳过重复提交。
		var current: LayerPose = after[index] if next >= 0 else null # 空姿态不产生绘制。
		if old == current:
			continue
		var layer: RID = _layers[index] # 空绘制项在本层第一次出现时才创建。
		if current == null:
			RenderingServer.canvas_item_set_visible(layer, false)
			continue
		if not layer.is_valid():
			layer = RenderingServer.canvas_item_create()
			RenderingServer.canvas_item_set_parent(layer, _rig)
			RenderingServer.canvas_item_set_draw_index(layer, index)
			if _material != null:
				RenderingServer.canvas_item_set_material(layer, _material.get_rid())
			_layers[index] = layer
		if old == null:
			RenderingServer.canvas_item_set_visible(layer, true)
		if old == null or old.transform != current.transform:
			RenderingServer.canvas_item_set_transform(layer, current.transform)
		if old == null or old.texture != current.texture or old.tint != current.tint:
			RenderingServer.canvas_item_clear(layer)
			current.texture.draw(layer, Vector2.ZERO, current.tint)


## [param what] 指明节点即将销毁时的通知。全部绘制项与此战斗实例一起释放。
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for layer: RID in _layers: # 先释放图层，再释放绘制父项。
			if layer.is_valid():
				RenderingServer.free_rid(layer)
		if _rig.is_valid():
			RenderingServer.free_rid(_rig)
