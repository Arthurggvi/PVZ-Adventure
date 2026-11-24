## 地形与全部采样覆盖共用原尺寸纹理；相机外图块释放，近邻通过统一资源批次预热。
extends Node2D

const Batch = preload("res://scripts/ui/transitions/resource_load_batch.gd")
## 预热与释放使用不同世界距离，防止相机在边界来回摆动反复读盘。
const PRELOAD_MARGIN := 48.0
const RETAIN_MARGIN := 80.0
var _tiles: Array[Dictionary] = []
var _batch: RefCounted
var _pending_index := -1
var _root_path := ""
var _density := 1.0
## 每块地形同时服务的关卡按钮世界锚点；只保存坐标，不保存额外纹理。
var _icon_anchors: Dictionary = {}

## 返回与固定镜头配置一致的初始世界视野；用于切场前只准备真正可见的地形。
static func initial_rect(layout: Dictionary) -> Rect2:
	var bounds := _vec(layout.original_size)
	var settings: Dictionary = layout.get("zoom", {})
	var viewport_size := Vector2(1066,600)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		viewport_size = tree.root.get_visible_rect().size.max(Vector2.ONE)
	var zoom_value: float = maxf(viewport_size.y / maxf(1.0,float(settings.get("visible_world_height",336.0))), maxf(viewport_size.x/bounds.x,viewport_size.y/bounds.y))
	var half: Vector2 = viewport_size / (2.0*zoom_value)
	var center: Vector2 = _vec(settings.get("initial_center_world",[270,620])).clamp(half.min(bounds*0.5),(bounds-half).max(bounds*0.5))
	return Rect2(center-half,half*2.0)

static func _vec(values: Array) -> Vector2:
	return Vector2(float(values[0]),float(values[1]))

## [param spec] 的采样边也计入可见范围；与原地形精灵保持完全一致。
static func tile_rect(spec: Dictionary, density: float) -> Rect2:
	return Rect2(_vec(spec.pixel_origin)/density,_vec(spec.pixel_size)/density)

## [param layout] 的所有图块维持原始索引、位置及尺寸；离屏几何占位不分配原尺寸像素。
func configure(layout: Dictionary, root_path: String) -> bool:
	_root_path=root_path
	var terrain: Dictionary=layout.terrain
	_density=float(terrain.pixels_per_world)
	var visible: Rect2=initial_rect(layout)
	for spec: Dictionary in terrain.tiles:
		var rect: Rect2=tile_rect(spec,_density)
		var sprite := Sprite2D.new()
		sprite.centered=false
		sprite.position=rect.position
		sprite.scale=Vector2.ONE/_density
		sprite.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
		# 仅用于初始水面/风场几何验证，不为离屏块解码像素。
		var placeholder := PlaceholderTexture2D.new()
		placeholder.size=_vec(spec.pixel_size)
		sprite.texture=placeholder
		add_child(sprite)
		var index: int=_tiles.size()
		_tiles.append({"spec":spec,"rect":rect,"node":sprite})
		if rect.intersects(visible.grow(PRELOAD_MARGIN)) and not _load_exact(index):
			return false
	return true

## 实际纹理已预热时直接复用；尺寸不符不提交错误纹理。
func _install(index: int, texture: Texture2D) -> bool:
	var entry: Dictionary=_tiles[index]
	if texture==null or texture.get_size()!=_vec(entry.spec.pixel_size):
		push_error("Wonderland terrain texture invalid: "+str(entry.spec.path))
		return false
	entry.node.texture=texture
	return true

func _load_exact(index: int) -> bool:
	return _install(index,ResourceLoader.load(_root_path+str(_tiles[index].spec.path)) as Texture2D)

func _resident(index: int) -> bool:
	var texture: Texture2D=_tiles[index].node.texture
	return texture!=null and not texture is PlaceholderTexture2D

## [param index] 是图标采样地形索引；[param anchor] 是图标真实世界位置。
func register_icon(index: int, anchor: Vector2) -> void:
	if not _icon_anchors.has(index):
		_icon_anchors[index]=[]
	_icon_anchors[index].append(anchor)

## 图块本身或使用它的图标可见时均需保留原分辨率资源。
func _required(index: int, area: Rect2) -> bool:
	if _tiles[index].rect.intersects(area):
		return true
	for anchor: Vector2 in _icon_anchors.get(index,[]):
		if area.has_point(anchor):
			return true
	return false

## [param camera] 的当前实际视野优先；快速跳到未预热区域时同步读取原图，不显示低清替代。
func update_camera(camera: Camera2D) -> void:
	var extent: Vector2=camera.get_viewport_rect().size/camera.zoom
	var visible := Rect2(camera.get_screen_center_position()-extent*0.5,extent)
	var preload_rect: Rect2=visible.grow(PRELOAD_MARGIN)
	var retain_rect: Rect2=visible.grow(RETAIN_MARGIN)
	_poll_pending(retain_rect)
	for index: int in _tiles.size():
		var entry: Dictionary=_tiles[index]
		if _required(index,visible):
			if not _resident(index):
				_load_exact(index)
		elif not _required(index,retain_rect):
			entry.node.texture=null # texture_changed 使所有同块覆盖同时释放。
		elif entry.node.texture is PlaceholderTexture2D:
			entry.node.texture=null
	if _batch!=null:
		return
	for index: int in _tiles.size():
		if not _resident(index) and _required(index,preload_rect):
			_batch=Batch.new()
			_pending_index=index
			if _batch.start(PackedStringArray([_root_path+str(_tiles[index].spec.path)]))!=OK:
				_cancel()
			break

## [param retain_rect] 外的过时结果不再提交；复用原统一批次的取消/终态回收。
func _poll_pending(retain_rect: Rect2) -> void:
	if _batch==null:
		return
	if not _required(_pending_index,retain_rect):
		_cancel()
		return
	var status: int=_batch.poll()
	if status==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	if status==ResourceLoader.THREAD_LOAD_LOADED and not _resident(_pending_index):
		_install(_pending_index,_batch.get_resource(_root_path+str(_tiles[_pending_index].spec.path)) as Texture2D)
	_batch=null
	_pending_index=-1

func _cancel() -> void:
	if _batch!=null:
		_batch.abandon()
	_batch=null
	_pending_index=-1

## 可见图块必须全部原分辨率驻留；供图形验收读取。
func resident_count() -> int:
	var count:=0
	for index: int in _tiles.size():
		if _resident(index):
			count+=1
	return count

func _exit_tree() -> void:
	_cancel()
