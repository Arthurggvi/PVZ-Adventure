## 完整飞艇、桨、藤蔓、阴影和索具保留在底图；本层只绘制艇体内部微形变与独立布料。
## 世界坐标始终以1774×887布局为准，高清分件仅增加纹理采样密度。
## 飞艇轮廓与命中枢轴保持固定；材质使用显式秒数和独立周期，禁用时冻结而不归零。
extends Node2D

## 布料只采样显式相位，不读取Shader内置TIME。
const CLOTH := preload("res://shaders/adventure/wonderland/world_cloth_wind.gdshader")
## 仅在内缩安全蒙版内采样原图RGB，透明度与固定边界均不随相位改变。
const SURFACE := preload("res://shaders/adventure/wonderland/airship_surface.gdshader")
## 固定轮廓模式的缺省配置；幅度为世界像素，周期为秒，相位为弧度，不支持旧漂浮或旋转字段。
const DEFAULTS: Dictionary = {"ship_seconds":8.4,"hull_amplitude_px":0.3,"cloth_seconds":TAU/0.78,"cloth_amplitude_px":4.0,"ship_phase_radians":0.0,"cloth_phase_radians":0.0}
## 艇体采样位移不超过半个世界像素；布料继续遵守独立清理区域的原4像素包络。
const MAX_AMPLITUDES: Dictionary = {"hull_amplitude_px":0.5,"cloth_amplitude_px":4.0}
## 布料从固定带到自由边的响应距离，单位为世界像素。
const CLOTH_DEPTH_WORLD := 36.0
## 兼容原布料波长，单位为每世界像素的弧度。
const CLOTH_WAVE_WORLD := 0.10
## 固定飞艇枢轴，供原图命中与独立hover使用，运行时不平移或旋转。
var ship_root: Node2D
## 当前场景独享的艇体表面材质，不拥有底图中的外轮廓、阴影或索具。
var _surface_material: ShaderMaterial
## 原图裁切纹理每世界像素对应的x/y像素数，分别保留裁切取整差。
var _surface_density := Vector2.ONE
## 每块布料独立材质及沿变形方向的纹理像素密度。
var _cloth_entries: Array[Dictionary] = []
## 仅引用当前场景唯一已校验的素材仓库。
var _assets: RefCounted
## 主体原始世界枢轴。
var _ship_pivot := Vector2.ZERO
## 原图船体贴图左上角，供世界命中转换使用。
var _body_origin := Vector2.ZERO
## 场景布局的默认动作配置；外部配置为空时恢复此副本。
var _defaults: Dictionary = DEFAULTS.duplicate(true)
## 完整验证后提交的有效配置，独立于调用方持有的字典。
var _profile: Dictionary = DEFAULTS.duplicate(true)
## 当前真正显示的显式动作秒数，禁用期间保持不变。
var _seconds := 0.0
## 最近一次收到的宿主秒数，用于局部禁用时扣除暂停区间。
var _source_seconds := 0.0
## 累计局部禁用时间；宿主也暂停时此值不变。
var _paused_seconds := 0.0
## 只冻结当前材质帧，不隐藏可见实体、不改变动画时钟起点。
var _enabled := true

## [param id] 查唯一分件；[param parent] 为显示父节点；[param base] 为其世界原点。
## 返回按布局世界尺寸缩放的精灵，高清PNG的裁切取整不会改变枢轴或命中尺度。
func _spawn(id: String, parent: Node2D, base: Vector2) -> Sprite2D:
    var spec: Dictionary = _assets.subject(id) # 位置、尺寸和纹理只读。
    var node := Sprite2D.new() # 每个运行分件仅创建一次。
    var origin: Array = spec["origin"] # 布局世界左上角。
    var size: Array = spec["size"] # 布局世界尺寸，与PNG像素尺寸独立。
    node.name = id
    node.centered = false
    node.texture = _assets.texture(str(spec["path"]))
    node.scale = Vector2(size[0],size[1])/node.texture.get_size()
    node.position = Vector2(origin[0],origin[1])-base
    parent.add_child(node)
    return node

## [param assets] 为已校验的场景资源仓库；配置错误时拒绝构建，不读取存档或重置时钟。
func configure(assets: RefCounted) -> void:
    _assets = assets
    _defaults.merge(assets.layout.get("motion_defaults",{}),true)
    var error: String = validate_profile({}) # 布局默认值也必须经过同一完整校验。
    if not error.is_empty():
        push_error(error)
        return
    _profile = _defaults.duplicate(true)
    var loc: Dictionary = assets.subject("airship_body") # 唯一艇体枢轴和左上角。
    var pivot: Array = loc["pivot_world"] # 世界枢轴，不随纹理分辨率变化。
    var origin: Array = loc["origin"] # 艇体世界左上角。
    _ship_pivot = Vector2(pivot[0],pivot[1])
    _body_origin = Vector2(origin[0],origin[1])
    ship_root = Node2D.new()
    ship_root.name = "AirshipRoot"
    ship_root.z_index = 8
    ship_root.position = _ship_pivot
    add_child(ship_root)
    var surface: Sprite2D = _spawn("airship_body",ship_root,_ship_pivot) # 完整原图RGB裁切，透明度全部交由内缩蒙版。
    _surface_density = Vector2.ONE/surface.scale
    _surface_material = ShaderMaterial.new()
    _surface_material.shader = SURFACE
    _surface_material.set_shader_parameter("motion_mask",assets.texture(str(assets.layout["airship_motion_mask"])))
    surface.material = _surface_material
    surface.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    for piece_id: String in ["school_flag","dock_banner"]: # 两块布料共享风周期，固定边各自独立。
        var cloth: Sprite2D = _spawn(piece_id,self,Vector2.ZERO) # 地面附属物不继承飞艇偏移。
        var material := ShaderMaterial.new() # 每块布料独享固定边与采样参数。
        var data: Dictionary = assets.subject(piece_id) # 当前布料的世界几何。
        var bitmap_origin: Array = data["origin"] # 纹理裁切区世界左上角。
        var start: Vector2 # 固定边起点的世界坐标。
        var finish: Vector2 # 固定边终点的世界坐标。
        var angled: bool = piece_id == "dock_banner" # 旗帜固定左边，布幔固定斜上边。
        if angled:
            var endpoints: Array = data["pinned_axis"]["line_world"] # 布幔原图固定轴。
            start = Vector2(endpoints[0][0],endpoints[0][1])
            finish = Vector2(endpoints[1][0],endpoints[1][1])
        else:
            var root: Array = data["pinned_axis"]["origin_world"] # 旗杆连接点。
            start = Vector2(root[0],root[1])
            finish = start+Vector2(0,24)
        var offset := Vector2(bitmap_origin[0],bitmap_origin[1]) # 世界坐标转换到裁切区局部坐标。
        var density := Vector2.ONE/cloth.scale # 每世界像素对应的x/y纹理像素，分别保留裁切取整差。
        var axis: Vector2 = (finish-start).normalized() # 原固定轴在世界空间的方向。
        var normal := Vector2(-axis.y,axis.x) if angled else Vector2.RIGHT # 波沿固定边法向传播。
        var normal_density: float = 1.0/(normal/density).length() # 非等比缩放后的法向距离换算。
        var amplitude_density: float = density.x if angled else density.y # 布幔横移、旗帜纵移的像素密度。
        cloth.z_index = 10
        material.shader = CLOTH
        material.set_shader_parameter("pin_a_px",(start-offset)*density)
        material.set_shader_parameter("pin_b_px",(finish-offset)*density)
        material.set_shader_parameter("pin_band_px",float(data["pinned_axis"].get("pin_width",4))*normal_density)
        material.set_shader_parameter("cloth_depth_px",CLOTH_DEPTH_WORLD*normal_density)
        material.set_shader_parameter("wave_radians_per_px",CLOTH_WAVE_WORLD/normal_density)
        material.set_shader_parameter("angled_pin",angled)
        cloth.material = material
        _cloth_entries.append({"material":material,"amplitude_density":amplitude_density})
    _apply_frame()

## [param data] 为可省略字段的完整覆盖配置；空字符串表示全部有效，不改变任何运行状态。
## 周期范围为0.1至3600秒；艇体幅度不超过0.5世界像素，布料不超过4世界像素。
## 旧漂浮、升沉、滚转及螺旋桨字段不再属于契约，和其他未知字段、非有限数值一起拒绝。
func validate_profile(data: Dictionary) -> String:
    var candidate: Dictionary = _defaults.duplicate(true) # 在副本验证默认值与调用方覆盖值。
    candidate.merge(data,true)
    for key: Variant in candidate: # 字段名必须属于明确契约，不能任意写Shader参数。
        if not DEFAULTS.has(key):
            return "未知主体动效参数："+str(key)
        if not (candidate[key] is float or candidate[key] is int) or not is_finite(float(candidate[key])):
            return "主体动效参数必须为有限数值："+str(key)
    for key: String in ["ship_seconds","cloth_seconds"]: # 艇体内部采样与独立布料分别取周期。
        var period: float = float(candidate[key]) # 单位秒。
        if period < 0.1 or period > 3600.0:
            return "主体动效周期须在0.1至3600秒之间："+key
    for key: String in MAX_AMPLITUDES: # 禁止通过调参越过内缩蒙版和布料清理区域的安全范围。
        var amplitude: float = float(candidate[key]) # 最大采样位移，单位为世界像素。
        if amplitude < 0.0 or amplitude > float(MAX_AMPLITUDES[key]):
            return "主体动效幅度超出安全范围："+key
    return ""

## [param data] 先完整校验再一次提交；失败保留原配置，成功不重置秒数或暂停状态。
## 省略字段恢复布局默认值；暂停期间只保存配置，下一次恢复动作时才更新姿态。
func apply_profile(data: Dictionary) -> void:
    var error: String = validate_profile(data) # 即使绕过总线直接调用也不能部分提交。
    if not error.is_empty():
        push_error(error)
        return
    var candidate: Dictionary = _defaults.duplicate(true) # 复制避免外部字典修改污染已提交状态。
    candidate.merge(data,true)
    _profile = candidate
    if _enabled:
        _apply_frame()

## [param period] 为已验证的周期秒数；[param phase] 为弧度相位，返回当前动作角度。
func _angle(period: float, phase: float) -> float:
    return fposmod(_seconds/period,1.0)*TAU+fposmod(phase,TAU)

## 只提交艇体内部采样和布料材质帧；不修改任何节点变换，初始化前调用无副作用。
func _apply_frame() -> void:
    if _surface_material == null:
        return
    var ship_angle: float = _angle(float(_profile["ship_seconds"]),float(_profile["ship_phase_radians"])) # 艇体内部微形变的独立相位。
    var cloth_angle: float = _angle(float(_profile["cloth_seconds"]),float(_profile["cloth_phase_radians"])) # 兼容原风速的独立相位。
    _surface_material.set_shader_parameter("surface_angle",ship_angle)
    _surface_material.set_shader_parameter("amplitude_px",_surface_density*float(_profile["hull_amplitude_px"]))
    for entry: Dictionary in _cloth_entries: # 材质相位同步，但每块布料的纹理密度独立。
        var material: ShaderMaterial = entry["material"] # 当前分件材质不会被其他场景复用。
        material.set_shader_parameter("cloth_angle",cloth_angle)
        material.set_shader_parameter("wind_angle",fposmod(_seconds/18.0,1.0)*TAU)
        material.set_shader_parameter("amplitude_px",float(_profile["cloth_amplitude_px"])*float(entry["amplitude_density"]))

## [param seconds] 为宿主显式秒数；非有限值忽略，支持确定性回放，不依赖帧数或系统TIME。
## 局部禁用期间记录宿主时间差以保持姿态冻结，恢复时从冻结秒数连续前进。
func set_animation_seconds(seconds: float) -> void:
    if not is_finite(seconds):
        return
    if not _enabled:
        _paused_seconds += seconds-_source_seconds
        _source_seconds = seconds
        return
    _source_seconds = seconds
    _seconds = seconds-_paused_seconds
    _apply_frame()

## [param enabled] 为效果总线契约：冻结或恢复本组材质，完整飞艇始终由底图保持可见。
func set_effect_enabled(enabled: bool) -> void:
    if _enabled == enabled:
        return
    _enabled = enabled
    if _enabled:
        _apply_frame()

## [param enabled] 为地图宿主旧接口；委托同一冻结路径，不重置时间或返回零姿态。
func set_motion_enabled(enabled: bool) -> void:
    set_effect_enabled(enabled)

## [param world] 为鼠标反投影世界坐标；返回原图尺度的飞艇左上角局部像素。
## 枢轴保持固定，内部RGB微形变不影响轮廓和命中，不需要额外逆向形变。
func ship_hit_local(world: Vector2) -> Vector2:
    return ship_root.to_local(world)-(_body_origin-_ship_pivot)
