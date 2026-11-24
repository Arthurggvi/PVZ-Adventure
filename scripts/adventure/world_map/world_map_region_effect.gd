## 新区域效果的公共生命周期：局部资源、原子参数、连续暂停与显式时钟。
## 水域和既有主体沿用自己的实现，本类不改变已验收水面。
extends Node2D

## 事件包络只读取有效动作时间，不拥有另一个时钟。
const SCHEDULE := preload("res://scripts/adventure/world_map/world_map_event_schedule.gd")
## 正式地图资源根；运行时不访问仓外制作目录。
const ROOT := "res://assets/adventure/wonderland/"
## 世界坐标始终独立于高清贴图像素。
const WORLD := Vector2(1774.0, 887.0)
## 各类共享的最小参数默认值；不支持的参数仍由类型白名单拒绝。
const DEFAULTS := {"period_seconds":9.0,"strength":0.5,"amplitude_world":0.0,"count":0,"size_world":0.5,"speed_world":4.0,"color":[1.0,1.0,1.0]}
## 当前区域标识，仅用于诊断与稳定粒子种子。
var effect_id := ""
## 工厂已知的绘制类型与表现样式。
var effect_kind := ""
## 样式只从类型注册表中接纳。
var style := ""
## 当前区域的事件类别；空字符串表示连续环境动作。
var event_kind := ""
## 世界裁切范围，同时供采样和视野剔除使用。
var bounds_world := Rect2()
## 孔口局部中心与半径，其他效果使用裁切范围中心。
var center_world := Vector2.ZERO
## 各轴半径以世界单位表示，不随窗口改变。
var radii_world := Vector2.ONE
## 技术纹理：R覆盖，G响应/光边，B局部深度。
var mask_texture: Texture2D
## 配置声明的实际纹理尺寸，用于拒绝错贴图。
var mask_pixels := Vector2.ZERO
## 当前可见动作参数的独立副本。
var profile: Dictionary = DEFAULTS.duplicate(true)
## 该区域启动时的默认快照，省略参数恢复这里的值。
var _defaults: Dictionary = DEFAULTS.duplicate(true)
## 当前真正绘制的动作秒数。
var seconds := 0.0
## 宿主上次传入的显示秒数。
var _source_seconds := 0.0
## 局部禁用与全局暂停并集的累计时间。
var _paused_seconds := 0.0
## 覆盖层开关，关闭时露出原静态底图。
var effect_enabled := true
## 全局暂停只冻结当前帧，不隐藏覆盖。
var motion_paused := false
## 总线完成跨类型优先级处理后的局部事件强度。
var event_weight := 0.0
## 完整资源和可见节点均准备好后才接受帧更新。
var _configured := false

## [param value] 必须是非布尔、非无穷的数值。
static func finite_number(value: Variant) -> bool:
    return (value is float or value is int) and is_finite(float(value))

## [param value] 为JSON数组；[param count] 指定维数，返回是否全部有限数值。
static func finite_array(value: Variant, count: int) -> bool:
    if not value is Array or value.size() != count:
        return false
    for item: Variant in value: # 不把布尔或字符串隐式转成数值。
        if not finite_number(item):
            return false
    return true

## [param id] 为唯一配置身份；[param assets] 持有只读资源；[param terrain_root] 提供原地形纹理。
## 失败只影响本可选效果；节点尚未绘制，调用方应释放失败实例。
func configure(id: String, assets: RefCounted, terrain_root: Node2D) -> bool:
    effect_id = id
    var region: Dictionary = assets.regions.get("regions", {}).get(id, {}) # 已知类型的区域声明。
    effect_kind = str(region.get("kind", ""))
    style = str(region.get("style", ""))
    event_kind = str(region.get("event", ""))
    var box: Variant = region.get("bounds_world") # 原点和宽高均为世界单位。
    var origin: Variant = region.get("mask_origin_world") # 蒙版独立于地形图块原点。
    var extent: Variant = region.get("mask_extent_world") # 裁切蒙版覆盖的正世界尺寸。
    var pixels: Variant = region.get("mask_pixels") # 纹理尺寸精确匹配，不猜测分辨率。
    if not finite_array(box, 4) or not finite_array(origin, 2) or not finite_array(extent, 2) or not finite_array(pixels, 2):
        return _reject("缺少有效裁切几何")
    bounds_world = Rect2(float(box[0]),float(box[1]),float(box[2]),float(box[3]))
    mask_pixels = Vector2(float(pixels[0]),float(pixels[1]))
    if bounds_world.size.x <= 0 or bounds_world.size.y <= 0 or not Rect2(Vector2.ZERO,WORLD).encloses(bounds_world):
        return _reject("裁切范围越界")
    if Vector2(float(origin[0]),float(origin[1])) != bounds_world.position or Vector2(float(extent[0]),float(extent[1])) != bounds_world.size:
        return _reject("蒙版世界范围不一致")
    if mask_pixels.x < 1 or mask_pixels.y < 1 or mask_pixels != mask_pixels.floor():
        return _reject("蒙版尺寸必须为正整数")
    center_world = bounds_world.get_center()
    radii_world = bounds_world.size * 0.5
    if region.has("center_world") or region.has("radii_world"):
        if not finite_array(region.get("center_world"),2) or not finite_array(region.get("radii_world"),2):
            return _reject("孔口中心或半径无效")
        center_world = Vector2(float(region.center_world[0]),float(region.center_world[1]))
        radii_world = Vector2(float(region.radii_world[0]),float(region.radii_world[1]))
        if not bounds_world.has_point(center_world) or radii_world.x <= 0 or radii_world.y <= 0 or radii_world.x > bounds_world.size.x or radii_world.y > bounds_world.size.y:
            return _reject("孔口几何越界")
    if not event_kind.is_empty() and not SCHEDULE.EVENTS.has(event_kind):
        return _reject("未知事件类型")
    var layer: Variant = region.get("z_index",-70) # 所有环境内容必须低于hover的25层。
    if not finite_number(layer) or float(layer) != floor(float(layer)) or float(layer) < -85 or float(layer) > 21:
        return _reject("层级超出环境范围")
    z_index = int(layer)
    z_as_relative = false
    var path: Variant = region.get("mask") # 新技术图仅接受正式局部目录。
    if not path is String or not path.begins_with("masks/runtime_fx/") or path.contains("..") or path.contains("\\") or not ResourceLoader.exists(ROOT+path,"Texture2D"):
        return _reject("局部技术蒙版路径无效")
    mask_texture = assets.texture(path)
    if mask_texture == null or mask_texture.get_size() != mask_pixels:
        return _reject("局部技术蒙版尺寸不匹配")
    var parameters: Variant = region.get("profile",{}) # 首次默认值也经过参数白名单。
    if not parameters is Dictionary:
        return _reject("profile必须为对象")
    var error: String = validate_profile(parameters) # 此时默认值仍为类的安全初值。
    if not error.is_empty():
        return _reject(error)
    _defaults.merge(parameters.duplicate(true),true)
    profile = _defaults.duplicate(true)
    if not _build_visual(assets,terrain_root):
        return false
    _configured = true
    _update_frame(true)
    return true

## [param data] 为默认值之上的完整覆盖；空字符串表示全部可提交，无状态副作用。
func validate_profile(data: Dictionary) -> String:
    var allowed: Array[String] = ["period_seconds","strength"] # 每种绘制类型只接纳真正使用的参数。
    if effect_kind in ["wind","waterfall","aperture"]:
        allowed.append("amplitude_world")
    if effect_kind == "particle":
        allowed.append_array(["count","size_world","speed_world","color"])
    for key: Variant in data: # 未知字段不能偷偷成为Shader参数。
        if not key is String or not allowed.has(key):
            return "未知区域参数："+str(key)
        if key == "color":
            if not finite_array(data[key],3):
                return "粒子颜色必须为三个有限数值"
            for channel: Variant in data[key]: # 颜色使用显示空间零到一值。
                if float(channel) < 0 or float(channel) > 1:
                    return "粒子颜色越界"
        elif not finite_number(data[key]):
            return "区域参数必须为有限数值："+str(key)
    var candidate: Dictionary = _defaults.duplicate(true) # 完整候选不会污染旧快照。
    candidate.merge(data,true)
    if float(candidate.period_seconds) < 1 or float(candidate.period_seconds) > 180:
        return "周期须在1至180秒之间"
    if float(candidate.strength) < 0 or float(candidate.strength) > 1:
        return "强度须在0至1之间"
    var limit: float = 0.8 if effect_kind == "aperture" else 0.6 # 技术蒙版内缩按最大幅度制作。
    if float(candidate.amplitude_world) < 0 or float(candidate.amplitude_world) > limit:
        return "位移超出安全包络"
    if float(candidate.count) < 0 or float(candidate.count) > 120 or float(candidate.count) != floor(float(candidate.count)):
        return "粒子数量必须为0至120的整数"
    if float(candidate.size_world) <= 0 or float(candidate.size_world) > 2 or float(candidate.speed_world) < 0 or float(candidate.speed_world) > 24:
        return "粒子尺寸或速度超限"
    return ""

## [param data] 完整验证后提交；暂停期间只记录参数，不改变冻结画面。
func apply_profile(data: Dictionary) -> void:
    var error: String = validate_profile(data) # 直接调用也执行同一白名单。
    if not error.is_empty():
        push_error(effect_id+": "+error)
        return
    profile = _defaults.duplicate(true)
    profile.merge(data.duplicate(true),true)
    if _configured and not motion_paused:
        _update_frame()

## [param elapsed] 为宿主显示秒数；支持显式回看，禁用与暂停只扣一次。
func set_animation_seconds(elapsed: float) -> void:
    if not is_finite(elapsed):
        return
    if motion_paused or not effect_enabled:
        _paused_seconds += elapsed-_source_seconds
    elif elapsed < _source_seconds:
        _paused_seconds = 0.0
    _source_seconds = elapsed
    if motion_paused or not effect_enabled:
        return
    seconds = elapsed-_paused_seconds
    if _configured:
        _update_frame()

## [param enabled] 控制可选覆盖；关闭后原图保留，恢复不清零相位。
func set_effect_enabled(enabled: bool) -> void:
    effect_enabled = enabled
    visible = enabled
    if enabled and _configured and not motion_paused:
        _update_frame()

## [param paused] 冻结当前显示；不覆盖区域自己的开关。
func set_motion_paused(paused: bool) -> void:
    if motion_paused == paused:
        return
    if paused and _configured:
        _update_frame(true) # 屏外材质也在冻结点补齐，暂停后拖入视野不能显示旧相位。
    motion_paused = paused

## 返回本组件的原始事件候选，禁用节点不能占用事件优先权。
func get_event_envelope() -> float:
    return SCHEDULE.envelope(event_kind,seconds) if effect_enabled else 0.0

## [param weight] 为总线统一分配的事件强度；暂停时保持冻结的最后一帧。
func set_event_weight(weight: float) -> void:
    if motion_paused or not effect_enabled or is_equal_approx(weight,event_weight):
        return
    event_weight = clampf(weight,0.0,1.0)
    if _configured:
        _update_frame()

## 可见矩形由当前画布反变换得到；视野外停止绘制更新但动作时间仍推进。
func is_region_visible() -> bool:
    var viewport: Viewport = get_viewport() # 相机变换已由Godot应用到画布。
    var view: Rect2 = viewport.get_canvas_transform().affine_inverse()*viewport.get_visible_rect() # 世界矩形不依赖窗口像素密度。
    return view.intersects(bounds_world.grow(8.0))

## [param assets] 与 [param terrain_root] 由具体绘制机制消费；基类不创建空效果。
func _build_visual(_assets: RefCounted, _terrain_root: Node2D) -> bool:
    return _reject("未实现区域绘制")

## [param force] 用于初始化/冻结时提交屏外帧；具体机制不启动自身_process。
func _update_frame(_force: bool = false) -> void:
    pass

## [param reason] 只报告一次构建失败，调用方释放局部实例。
func _reject(reason: String) -> bool:
    push_error("Wonderland "+effect_id+": "+reason)
    return false
