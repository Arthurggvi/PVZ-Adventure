## 地区仅响应悬停：世界索引确定身份，高清轮廓只负责显示，不发布点击或关卡请求。
extends Node2D

## 指针身份改变时发布地区身份；[param landmark_id] 为空字符串表示离开悬停区域。
signal hovered(landmark_id: String)
## 高清裁切蒙版共用的着色程序，每个高亮持有独立的渐变强度。
const HOVER_MATERIAL := preload("res://shaders/adventure/wonderland/landmark_hover.gdshader")
## 高亮从透明到完整或反向变化的时长，单位为宿主动画秒。
const HOVER_FADE_SECONDS := 0.16
## 悬停只准备当前地标；取消仍由既有批次回收。
const Batch := preload("res://scripts/ui/transitions/resource_load_batch.gd")
var _pending: RefCounted
var _pending_entry: Dictionary = {}
## 资源仓库与运行组件引用，不属于业务资产。
var _assets: RefCounted
## 单张世界悬停索引，包含完整飞艇与码头的共同地区轮廓。
var _hits: RefCounted
## 当前指向的地标 ID，与高亮渐变进度无关。
var _active_id := ""
## 按需创建的裁切高亮，离开时继续淡出，完成后隐藏；不复制全图纹理。
var _highlights: Dictionary = {}
## 各高亮当前强度，范围为 0 到 1，不参与真实命中。
var _strengths: Dictionary = {}
## 宿主上一次传入的动画秒数，仅用来求显示变化量，不另起时钟。
var _last_seconds := 0.0

## [param assets] 为已校验资源仓库；[param hits] 为原世界分辨率的悬停索引。
## 所有地区共用静态世界坐标，飞艇与码头不再拆成另一套主体命中与显示。
func configure(assets: RefCounted, hits: RefCounted) -> void:
    _assets = assets
    _hits = hits

## [param key] 是地区身份；[param path] 是高清蒙版。
## [param origin] 与 [param extent] 均使用世界单位；缺失或零尺寸纹理不创建节点。
func _create_highlight(key: String, mask: Texture2D, origin: Vector2, extent: Vector2) -> void:
    # 仅由高亮精灵持有该纹理，不进入地图永久纹理字典。
    if mask == null or mask.get_width() <= 0 or mask.get_height() <= 0 or extent.x <= 0.0 or extent.y <= 0.0:
        push_error("Wonderland invalid HD hover mask: " + key)
        return
    var material := ShaderMaterial.new() # 独立强度可让旧区域淡出、新区域同时淡入。
    material.shader = HOVER_MATERIAL
    material.set_shader_parameter("strength", 0.0)
    material.set_shader_parameter("effect_seconds", _last_seconds)
    material.set_shader_parameter("mask_pixels_per_world", mask.get_size() / extent)
    var sprite := Sprite2D.new() # 只在访问此区域时创建一张裁切高亮。
    sprite.name = "Hover_" + key
    sprite.centered = false
    sprite.position = origin
    sprite.scale = extent / mask.get_size()
    sprite.texture = mask
    sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    sprite.z_index = 25
    sprite.visible = false
    sprite.material = material
    add_child(sprite)
    _highlights[key] = sprite
    _strengths[key] = 0.0

## [param world] 为 Camera2D 反变换后的世界坐标；返回地区 ID，空字符串表示空白处。
## 此查询仅服务悬停，高清纹理密度和主体动画都不会改变地区范围。
func hit_at(world: Vector2) -> String:
    return _hits.static_hit(world)

## [param world] 为鼠标世界点；身份立即更新，显示沿宿主秒数渐入渐出。
func hover_world(world: Vector2) -> void:
    var next_id: String = hit_at(world) # 所有地区只从同一张世界索引查询身份。
    if next_id == _active_id:
        return
    _active_id = next_id
    _cancel_pending()
    if not next_id.is_empty() and not _highlights.has(next_id):
        _pending_entry = _assets.landmark(next_id)
        var path: String = _assets.ROOT + str(_pending_entry.get("hover_mask_path",""))
        _pending = Batch.new()
        if _pending.start(PackedStringArray([path])) != OK:
            _cancel_pending()
    hovered.emit(next_id)

## [param elapsed] 为宿主统一动画秒数，推进高亮强度并更新呼吸相位，不重新查询命中图。
## 暂停显式时间会冻结渐变；回退时间只重设时间基准，不产生负向强度变化。
func set_animation_seconds(elapsed: float) -> void:
    var delta: float = maxf(0.0, elapsed - _last_seconds) # 只使用宿主推进的正向显示时间。
    _last_seconds = elapsed
    _poll_pending()
    # 仅保留当前悬停及尚未完成淡出的节点；透明后立即释放纹理。
    for key: String in _highlights.keys():
        var sprite: Sprite2D = _highlights[key] # 当前已创建的世界坐标高亮。
        var target: float = 1.0 if key == _active_id else 0.0 # 身份切换只改变目标强度。
        var strength: float = move_toward(float(_strengths[key]), target, delta / HOVER_FADE_SECONDS) # 有界线性渐变。
        var material: ShaderMaterial = sprite.material as ShaderMaterial # 此节点独立的显示材质。
        _strengths[key] = strength
        material.set_shader_parameter("strength", strength)
        material.set_shader_parameter("effect_seconds", elapsed)
        sprite.visible = strength > 0.0
        if strength == 0.0 and key != _active_id:
            _highlights.erase(key)
            _strengths.erase(key)
            sprite.queue_free()

## [param world] 为世界点；返回无动画静态区域身份，供验收与工具使用。
func static_hit_at(world: Vector2) -> String:
    return _hits.static_hit(world)

## 清空指针身份并发出离开信号，已显示的区域在后续宿主帧中自然淡出。
func clear_hover() -> void:
    if not _active_id.is_empty():
        _active_id = ""
        _cancel_pending()
        hovered.emit("")

## 只有仍指向同一地区才接纳已准备的纹理。
func _poll_pending() -> void:
    if _pending == null:
        return
    var status: int = _pending.poll()
    if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
        return
    if status == ResourceLoader.THREAD_LOAD_LOADED:
        var point: Array = _pending_entry.get("hover_mask_origin",[])
        var extent: Array = _pending_entry.get("hover_mask_size",[])
        var path: String = _assets.ROOT + str(_pending_entry.get("hover_mask_path",""))
        if point.size()==2 and extent.size()==2:
            _create_highlight(_active_id,_pending.get_resource(path) as Texture2D,Vector2(float(point[0]),float(point[1])),Vector2(float(extent[0]),float(extent[1])))
    _pending = null
    _pending_entry = {}

func _cancel_pending() -> void:
    if _pending != null:
        _pending.abandon()
    _pending = null
    _pending_entry = {}

func _exit_tree() -> void:
    _cancel_pending()
