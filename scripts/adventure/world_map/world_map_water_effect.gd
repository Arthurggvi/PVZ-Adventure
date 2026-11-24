## 地图水域适配层：复用主菜单显式时钟，以局部浅水状态图集和原地形绘制水面。
## 每个区域只持有本场景材质、覆盖节点和参数副本；任何配置错误都保留原静态地图。
extends Node2D

## 主菜单已接受的水面参数校验、材质赋值和显式周期计算，不修改其实现。
const WATER_EFFECT := preload("res://scripts/ui/start_menu/coastal/water_effect.gd")
## 有限数与向量转换复用主菜单契约，禁止把字符串或布尔值当数值。
const VALUES := preload("res://scripts/ui/start_menu/coastal/effect_uniforms.gd")
## Shader 延迟加载，资源不存在时可拒绝本区域而保留静态地图。
const SURFACE_PATH := "res://shaders/adventure/wonderland/water_surface.gdshader"
## 正式资源唯一根目录；技术蒙版只允许从其水域子目录读取。
const ASSET_ROOT := "res://assets/adventure/wonderland/"
## 世界单位仍对应原始1774×887构图，与8K地形像素密度独立。
const MAP_WORLD_SIZE := Vector2(1774.0, 887.0)
## 位移向量的最大世界长度；采样留边按此上限预先校验，调参不能越过。
const MAX_AMPLITUDE_WORLD := 4.0
## 海洋默认配置；空间尺度为世界单位，薄层基准厚度单独使用纳米，周期为秒。
const OCEAN_DEFAULTS: Dictionary = {"water":{"pattern":"drift","period_seconds":18.0},"amplitude_world":3.2,"wavelength_world":[20.0,11.0],"shimmer_strength":0.045,"aurora_strength":0.38,"spectral_strength":0.42,"dream_strength":0.9,"film_thickness_nm":520.0,"aurora_scale_world":[90.0,38.0],"swirl_strength":0.35,"swirl_center_world":[170.0,760.0]}
## 河流与海洋共享十八秒物理时间场；缺省关闭新增谱域反射与极光体色，保留原有水色。
const RIVER_DEFAULTS: Dictionary = {"water":{"pattern":"drift","period_seconds":18.0},"amplitude_world":1.7,"wavelength_world":[14.0,9.0],"shimmer_strength":0.032,"aurora_strength":0.0,"spectral_strength":0.0,"dream_strength":0.0,"film_thickness_nm":520.0,"aurora_scale_world":[90.0,38.0],"swirl_strength":0.0,"swirl_center_world":[170.0,760.0]}
## 当前场景区域默认值；空配置恢复此副本，不引用外部可变字典。
var _defaults: Dictionary = OCEAN_DEFAULTS.duplicate(true)
## 最近一次完整验证并提交的有效参数副本。
var _profile: Dictionary = OCEAN_DEFAULTS.duplicate(true)
## 每项拥有独立覆盖精灵、材质及主菜单水面适配器；原地形纹理只读复用。
var _entries: Array[Dictionary] = []
## 最近收到的宿主显式秒数，不使用系统时间或Shader TIME。
var _source_seconds := 0.0
## 真正提交到材质的区域动作秒数，局部禁用或全局暂停时冻结。
var _seconds := 0.0
## 禁用与暂停的并集时间，只扣除一次，恢复时继续冻结相位。
var _paused_seconds := 0.0
## 区域开关控制覆盖可见性，关闭后原地形保持原样。
var _enabled := true
## 宿主运动开关只冻结当前水面帧，不隐藏仍启用的区域。
var _motion_paused := false

## [param effect_id] 查找水域条目；[param assets] 为本地图资源仓库；[param terrain_root] 按布局顺序持有原图块。
## 先验证配置、蒙版及全部选中图块，再一次替换覆盖；失败返回false，旧状态及原地形不变。
## 本节点与terrain_root应为同一地图节点的直接子节点，以共享同一世界变换。
func configure(effect_id: String, assets: RefCounted, terrain_root: Node2D) -> bool:
    if assets == null or terrain_root == null or not assets.has_method("texture"):
        return _reject("水域缺少场景资源或地形节点")
    var region_data: Variant = assets.get("regions") # 区域JSON本体，在读取子键前先检查类型。
    var layout_data: Variant = assets.get("layout") # 地形和核心裁切声明的唯一来源。
    if not region_data is Dictionary or not layout_data is Dictionary:
        return _reject("水域资源仓库缺少布局字典")
    var catalog: Variant = region_data.get("regions", {}) # 区域ID与配置的映射，不接受非字典条目。
    if not catalog is Dictionary or not catalog.get(effect_id) is Dictionary:
        return _reject("水域不存在：" + effect_id)
    var region: Dictionary = catalog[effect_id] # 当前区域配置，后续只读取不修改。
    if region.get("kind", "") != "water":
        return _reject("区域不是水面：" + effect_id)
    var world: Dictionary = VALUES.decode(region_data.get("world_size"), TYPE_VECTOR2) # 技术纹理共享的世界范围。
    if not world.ok or world.value != MAP_WORLD_SIZE:
        return _reject("水域世界范围必须为1774×887")
    var region_profile: Variant = region.get("profile", {}) # 资源声明允许省略参数，但必须为对象。
    if not region_profile is Dictionary:
        return _reject("水域profile必须为对象")
    var base: Dictionary = RIVER_DEFAULTS if effect_id == "river" else OCEAN_DEFAULTS # 区域缺省值不与调用方共享可变副本。
    var reason: String = _validate_with_defaults(region_profile, base) # 默认配置也完整验证，避免初始化绕过总线契约。
    if not reason.is_empty():
        return _reject(reason)
    var candidate_defaults: Dictionary = _resolve_profile(region_profile, base) # 仅在全部资源就绪后成为本区域默认快照。
    var mask_path: Variant = region.get("mask") # 技术蒙版相对路径，不接受目录穿越或外部资源。
    var flow_path: Variant = region.get("flow") # 连续流场与蒙版使用同一世界分辨率。
    if not _valid_water_path(mask_path) or not _valid_water_path(flow_path):
        return _reject("水域mask或flow路径无效")
    var mask: Texture2D = assets.call("texture", mask_path) as Texture2D # 复用统一切场准备后的区域蒙版。
    var flow: Texture2D = assets.call("texture", flow_path) as Texture2D # 海洋和河流可只读共享同一流场资源。
    if mask == null or flow == null or mask.get_size() != MAP_WORLD_SIZE or flow.get_size() != MAP_WORLD_SIZE:
        return _reject("水域mask和flow必须为1774×887纹理")
    var state: Dictionary = _prepare_surface_state(region, assets) # 状态图集只在本区域校验，缺失时保留静态底图。
    if not state.get("error", "").is_empty():
        return _reject(str(state.error))
    var terrain_data: Variant = layout_data.get("terrain") # 高清地形声明，结构验证后才做数值运算。
    if not terrain_data is Dictionary or not VALUES.finite_number(terrain_data.get("pixels_per_world")):
        return _reject("水域缺少有效地形像素密度")
    var density: float = float(terrain_data["pixels_per_world"]) # 每世界单位的地形纹理像素数。
    var dimensions: Dictionary = VALUES.decode(terrain_data.get("texture_size"), TYPE_VECTOR2) # 完整高清底图的像素边界。
    var tiles: Variant = terrain_data.get("tiles") # 与原地形子节点一一对应的图块声明。
    if density <= 0.0 or not dimensions.ok or not dimensions.value.is_finite() or not dimensions.value.is_equal_approx(MAP_WORLD_SIZE * density):
        return _reject("水域地形尺寸与世界像素密度不一致")
    if not tiles is Array or tiles.is_empty() or terrain_root.get_child_count() != tiles.size():
        return _reject("水域图块声明与原地形节点数量不一致")
    if get_parent() != terrain_root.get_parent():
        return _reject("水域与原地形必须共享地图父节点")
    var selection: Variant = region.get("active_tiles", range(tiles.size())) # 缺省覆盖全部图块；显式索引只构建真正含水的块。
    if not selection is Array or selection.is_empty():
        return _reject("水域active_tiles必须为非空索引数组")
    var prepared: Array[Dictionary] = [] # 全部选中块只收集引用，校验期间尚不创建可见节点。
    var used: Dictionary = {} # 重复索引会叠加同一水面，因此在提交前拒绝。
    for selected: Variant in selection: # JSON整数可能以浮点数载入，必须保持精确整数含义。
        if not VALUES.finite_number(selected) or float(selected) != floor(float(selected)):
            return _reject("水域图块索引必须为整数")
        var index: int = int(selected) # 已验证整数的布局索引。
        if index < 0 or index >= tiles.size() or used.has(index):
            return _reject("水域图块索引重复或越界")
        used[index] = true
        if not tiles[index] is Dictionary:
            return _reject("水域图块声明必须为对象")
        var source: Sprite2D = terrain_root.get_child(index) as Sprite2D # 从实际显示的底图复用纹理、位置和缩放。
        var geometry: Dictionary = _prepare_geometry(tiles[index], source, density, dimensions.value) # 核心区及最大位移采样边一次校验。
        if not geometry.get("error", "").is_empty():
            return _reject("水域图块" + str(index) + "：" + str(geometry.error))
        for previous: Dictionary in prepared: # 核心区若重叠会重复叠加光纹，独立于索引去重进行检查。
            if geometry.core_area.intersects(previous.core_area):
                return _reject("水域图块核心区重叠")
        geometry["source"] = source
        geometry["index"] = index
        prepared.append(geometry)
    if not ResourceLoader.exists(SURFACE_PATH, "Shader"):
        return _reject("地图水面Shader不存在")
    var shader: Shader = load(SURFACE_PATH) as Shader # 只共享着色程序，每个覆盖块拥有独立材质参数。
    if shader == null or shader.get_mode() != Shader.MODE_CANVAS_ITEM:
        return _reject("地图水面Shader类型无效")
    var pending: Array[Dictionary] = [] # 校验完成后离树准备节点，旧覆盖直到提交点仍保持完整。
    for geometry: Dictionary in prepared: # 每块相位相同，只有源像素原点和核心裁切区不同。
        var source: Sprite2D = geometry.source # 原地形资源与变换保持只读。
        var overlay := Sprite2D.new() # 只绘制本区域核心区，采样仍包含原图块留边。
        var material := ShaderMaterial.new() # 材质参数不得在区域或图块之间串改。
        var adapter: RefCounted = WATER_EFFECT.new() # 复用主菜单算法参数与显式周期入口。
        overlay.name = effect_id + "_tile_" + str(geometry.index)
        overlay.centered = source.centered
        overlay.texture = source.texture
        source.texture_changed.connect(_sync_terrain_texture.bind(source,overlay))
        overlay.transform = source.transform
        overlay.texture_filter = source.texture_filter
        overlay.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
        material.shader = shader
        material.set_shader_parameter("region_mask", mask)
        material.set_shader_parameter("flow_field", flow)
        material.set_shader_parameter("surface_state", state.texture)
        for key: String in ["frame_size", "atlas_grid", "frame_count", "padding", "origin_world", "extent_world", "slope_range", "height_range"]: # 状态布局来自元数据，不进入可调动效参数白名单。
            material.set_shader_parameter("state_" + key, state[key])
        material.set_shader_parameter("map_world_size", MAP_WORLD_SIZE)
        material.set_shader_parameter("tile_pixel_origin", geometry.pixel_origin)
        material.set_shader_parameter("pixels_per_world", density)
        material.set_shader_parameter("core_pixel_rect", geometry.core_rect)
        material.set_shader_parameter("effect_strength", 1.0)
        overlay.material = material
        adapter.set("material", material)
        pending.append({"node":overlay,"material":material,"adapter":adapter})
    # 提交点之后不再执行可失败的资源校验；移除旧覆盖不接触原地形。
    for entry: Dictionary in _entries: # 旧节点仅属于本区域，移除后立即释放其独立材质引用。
        var previous: Sprite2D = entry.node # 不等待下一帧，以免新旧覆盖同帧叠加。
        remove_child(previous)
        previous.free()
    _entries = pending
    _defaults = candidate_defaults
    transform = terrain_root.transform
    z_index = -90
    z_as_relative = false
    for entry: Dictionary in _entries: # 所有新覆盖只在完整准备后加入场景树。
        add_child(entry.node)
    apply_profile({})
    visible = _enabled
    return true

## [param profile] 为区域默认值之上的完整覆盖配置；空字符串表示可原子提交，不改变运行状态。
## 幅度范围0至4世界单位、波长与亮纹尺度至少2世界单位、亮纹强度0至0.08。
## aurora_strength控制既有折射色散0至0.6，aurora_scale_world控制介质空间尺度且分量至少8世界单位。
## spectral_strength为表层反射强度0至1；极光模式使用共享体色色偏，零体色模式使用原谱域反射。
## film_thickness_nm为原谱域反射的薄层基准厚度120至1400纳米，不影响统一极光模式。
## dream_strength为极光体色强度0至1，控制随流场搬运的水体颜色，不改变水面运动。
## swirl字段仅兼容旧接口，不独立造波；其强度仍验证0至1，中心使用有限世界坐标。
func validate_profile(profile: Dictionary) -> String:
    return _validate_with_defaults(profile, _defaults)

## [param profile] 覆盖区域默认值；仍独立验证以保护直接调用，失败不改变材质或参数快照。
## water向量先转回数组，以兼容主菜单已接受的apply接口；当前显示秒数保持不变。
func apply_profile(profile: Dictionary) -> void:
    var reason: String = validate_profile(profile) # 总线已校验，直接调用也不得绕过完整参数检查。
    if not reason.is_empty():
        push_error(reason)
        return
    _profile = _resolve_profile(profile, _defaults)
    var water: Dictionary = _profile.water.duplicate(true) # 单独规范化菜单适配器所需的数组，不修改区域快照。
    for key: String in ["shimmer_scale", "ripple_center"]: # 菜单校验允许Vector，但菜单赋值使用数组局部变量。
        if water.get(key) is Vector3:
            var scale_vector: Vector3 = water[key] # 世界单位的三维亮纹尺度。
            water[key] = [scale_vector.x, scale_vector.y, scale_vector.z]
        elif water.get(key) is Vector2:
            var center_vector: Vector2 = water[key] # 世界单位的波纹中心。
            water[key] = [center_vector.x, center_vector.y]
    water["phase_radians"] = fposmod(float(water.get("phase_radians", 0.0)), TAU)
    var wavelength: Dictionary = VALUES.decode(_profile.wavelength_world, TYPE_VECTOR2) # 已验证的世界空间波长。
    var aurora_scale: Dictionary = VALUES.decode(_profile.aurora_scale_world, TYPE_VECTOR2) # 光学厚度场的世界空间尺度，不改变已有波面。
    var swirl_center: Dictionary = VALUES.decode(_profile.swirl_center_world, TYPE_VECTOR2) # 仅保留旧配置接口，不驱动独立波面或光纹扭转。
    for entry: Dictionary in _entries: # 材质分别写入，但使用同一份完整配置和动作秒数。
        var material: ShaderMaterial = entry.material # 当前图块独享材质。
        material.set_shader_parameter("amplitude_world", float(_profile.amplitude_world))
        material.set_shader_parameter("wavelength_world", wavelength.value)
        material.set_shader_parameter("shimmer_strength", float(_profile.shimmer_strength))
        material.set_shader_parameter("aurora_strength", float(_profile.aurora_strength))
        material.set_shader_parameter("spectral_strength", float(_profile.spectral_strength))
        material.set_shader_parameter("dream_strength", float(_profile.dream_strength))
        material.set_shader_parameter("film_thickness_nm", float(_profile.film_thickness_nm))
        material.set_shader_parameter("aurora_scale_world", aurora_scale.value)
        material.set_shader_parameter("swirl_strength", float(_profile.swirl_strength))
        material.set_shader_parameter("swirl_center_world", swirl_center.value)
        entry.adapter.call("apply", water)
    _apply_frame()

## [param seconds] 为宿主显式秒数；忽略非有限输入，暂停与禁用的重叠区间只累计一次。
## 允许宿主确定性回放；重新启用从冻结帧继续，不跳到宿主已前进的相位。
func set_animation_seconds(seconds: float) -> void:
    if not is_finite(seconds):
        return
    if not _enabled or _motion_paused:
        _paused_seconds += seconds - _source_seconds
        _source_seconds = seconds
        return
    _source_seconds = seconds
    _seconds = seconds - _paused_seconds
    _apply_frame()

## [param enabled] 控制区域覆盖可见性；禁用期间原地形完整显示，动作秒数同时冻结。
func set_effect_enabled(enabled: bool) -> void:
    _enabled = enabled
    visible = enabled
    if enabled:
        _apply_frame()

## [param paused] 为宿主全局运动暂停；保留当前可见水面，恢复时同时尊重区域开关。
func set_motion_paused(paused: bool) -> void:
    _motion_paused = paused
    if not paused and _enabled:
        _apply_frame()

## 将同一动作秒数交给每块主菜单适配器；本方法不推进任何独立时钟。
func _apply_frame() -> void:
    for entry: Dictionary in _entries: # 全部图块保持同一显式水面相位。
        entry.adapter.call("set_elapsed", _seconds)

## [param profile] 为外部覆盖值，[param defaults] 为只读区域默认值；返回独立的完整参数字典。
func _resolve_profile(profile: Dictionary, defaults: Dictionary) -> Dictionary:
    var resolved: Dictionary = defaults.duplicate(true) # 防止外部后续改字典影响正在显示的水面。
    var overrides: Dictionary = profile.duplicate(true) # 嵌套数组也独立复制，避免调用方修改波长或水面向量。
    var water: Dictionary = resolved.get("water", {}).duplicate(true) # 水面算法允许逐字段覆盖默认配置。
    water.merge(overrides.get("water", {}), true)
    resolved.merge(overrides, true)
    resolved["water"] = water
    return resolved

## [param profile] 和 [param defaults] 都在副本中验证；返回首个中文错误或空字符串，不创建材质。
func _validate_with_defaults(profile: Dictionary, defaults: Dictionary) -> String:
    for key: Variant in profile: # 非字符串键也必须显式拒绝，避免菜单适配器的类型化循环报错。
        if not key is String or key not in ["water", "amplitude_world", "wavelength_world", "shimmer_strength", "aurora_strength", "spectral_strength", "dream_strength", "film_thickness_nm", "aurora_scale_world", "swirl_strength", "swirl_center_world"]:
            return "未知地图水面参数：" + str(key)
    if profile.has("water") and not profile.water is Dictionary:
        return "地图water必须为对象"
    var candidate: Dictionary = _resolve_profile(profile, defaults) # 缺省值与调用方覆盖值共同接受完整验证。
    for key: String in ["amplitude_world", "shimmer_strength", "aurora_strength", "spectral_strength", "dream_strength", "film_thickness_nm", "swirl_strength"]: # 标量既检查类型也检查有限性。
        if not VALUES.finite_number(candidate.get(key)):
            return key + "必须为有限数值"
    if float(candidate.amplitude_world) < 0.0 or float(candidate.amplitude_world) > MAX_AMPLITUDE_WORLD:
        return "amplitude_world须在0到4世界单位之间"
    if float(candidate.shimmer_strength) < 0.0 or float(candidate.shimmer_strength) > 0.08:
        return "shimmer_strength须在0到0.08之间"
    if float(candidate.aurora_strength) < 0.0 or float(candidate.aurora_strength) > 0.6:
        return "aurora_strength须在0到0.6之间"
    if float(candidate.spectral_strength) < 0.0 or float(candidate.spectral_strength) > 1.0:
        return "spectral_strength须在0到1之间"
    if float(candidate.dream_strength) < 0.0 or float(candidate.dream_strength) > 1.0:
        return "dream_strength须在0到1之间"
    if float(candidate.film_thickness_nm) < 120.0 or float(candidate.film_thickness_nm) > 1400.0:
        return "film_thickness_nm须在120到1400纳米之间"
    if float(candidate.swirl_strength) < 0.0 or float(candidate.swirl_strength) > 1.0:
        return "swirl_strength须在0到1之间"
    var wavelength: Dictionary = VALUES.decode(candidate.get("wavelength_world"), TYPE_VECTOR2) # 波长只接受有限二维向量或数组。
    if not wavelength.ok or not wavelength.value.is_finite() or wavelength.value.x < 2.0 or wavelength.value.y < 2.0:
        return "wavelength_world须为分量至少2世界单位的二维向量"
    var aurora_scale: Dictionary = VALUES.decode(candidate.get("aurora_scale_world"), TYPE_VECTOR2) # 光学厚度场避免细碎噪声，最小尺度固定为8世界单位。
    if not aurora_scale.ok or not aurora_scale.value.is_finite() or aurora_scale.value.x < 8.0 or aurora_scale.value.y < 8.0:
        return "aurora_scale_world须为分量至少8世界单位的二维向量"
    var swirl_center: Dictionary = VALUES.decode(candidate.get("swirl_center_world"), TYPE_VECTOR2) # 允许中心在地图外，但必须是有限世界坐标。
    if not swirl_center.ok or not swirl_center.value.is_finite():
        return "swirl_center_world必须为有限二维世界坐标"
    var water: Dictionary = candidate.water # 菜单负责算法白名单和周期、横向比例等共同边界。
    for key: Variant in water: # 先检查键类型，避免以错误类型进入菜单既有类型化循环。
        if not key is String:
            return "water参数名必须为字符串"
    if water.has("pattern") and not water.pattern is String:
        return "water.pattern必须为字符串"
    var reason: String = WATER_EFFECT.validate(water) # 实际复用既有算法参数验证，不维护另一份菜单规则。
    if not reason.is_empty():
        return reason
    var cycles: float = float(water.get("ripple_cycles", 2.0)) # 整数周数保证菜单周期取模处的波纹首尾连续。
    if cycles != floor(cycles):
        return "地图water.ripple_cycles必须为整数以保证周期连续"
    if water.has("shimmer_scale"):
        var shimmer: Dictionary = VALUES.decode(water.shimmer_scale, TYPE_VECTOR3) # 地图亮纹尺度单位为世界坐标，不是高清像素。
        if not shimmer.value.is_finite() or shimmer.value.x < 2.0 or shimmer.value.y < 2.0 or shimmer.value.z < 2.0:
            return "地图water.shimmer_scale各分量须至少2世界单位"
    if water.has("ripple_center"):
        var center: Dictionary = VALUES.decode(water.ripple_center, TYPE_VECTOR2) # 双精度数组转换为引擎向量后也必须保持有限。
        if not center.value.is_finite():
            return "地图water.ripple_center必须为有限二维世界坐标"
    return ""

## [param path] 仅允许正式水域目录内存在的Texture2D资源；返回false时不尝试额外路径回退。
func _valid_water_path(path: Variant) -> bool:
    return path is String and path.begins_with("masks/water/") and not path.contains("..") and not path.contains("\\") and ResourceLoader.exists(ASSET_ROOT + path, "Texture2D")

## [param region] 提供局部浅水图集路径与布局；[param assets] 复用当前地图纹理缓存。
## 返回已解码的Shader参数及纹理；数据不完整或尺寸不符时只返回error，不影响基础地形。
func _prepare_surface_state(region: Dictionary, assets: RefCounted) -> Dictionary:
    var path: Variant = region.get("surface_state") # 状态图集也限制在正式水域资源目录。
    if not _valid_water_path(path):
        return {"error":"水域surface_state路径无效"}
    var metadata: Variant = region.get("surface_state_info") # 物理网格、图集布局和量化范围均由烘焙声明。
    if not metadata is Dictionary:
        return {"error":"水域surface_state_info必须为对象"}
    var values: Dictionary = {} # 独立的已验证参数，不保留可变配置字典的引用。
    for key: String in ["frame_size", "atlas_grid", "origin_world", "extent_world"]: # 网格像素与世界覆盖范围使用不同单位。
        var decoded: Dictionary = VALUES.decode(metadata.get(key), TYPE_VECTOR2) # JSON数组转换成引擎二维向量。
        if not decoded.ok or not decoded.value.is_finite():
            return {"error":"水域状态" + key + "必须为有限二维向量"}
        var point: Vector2 = decoded.value # 当前元数据中的二元坐标或尺寸。
        if key in ["frame_size", "atlas_grid"] and (point.x < 1.0 or point.y < 1.0 or point.x != floor(point.x) or point.y != floor(point.y)):
            return {"error":"水域状态" + key + "必须使用正整数尺寸"}
        if key == "extent_world" and (point.x <= 0.0 or point.y <= 0.0):
            return {"error":"水域状态世界范围必须为正"}
        values[key] = point
    for key: String in ["frame_count", "padding", "slope_range", "height_range"]: # 统一拒绝布尔、非数和无穷量化范围。
        if not VALUES.finite_number(metadata.get(key)):
            return {"error":"水域状态" + key + "必须为有限数值"}
        values[key] = float(metadata[key])
    if values.frame_count < 2.0 or values.frame_count != floor(values.frame_count) or values.frame_count > values.atlas_grid.x * values.atlas_grid.y:
        return {"error":"水域状态帧数必须为图集容量内至少二帧的整数"}
    if values.padding < 1.0 or values.padding != floor(values.padding):
        return {"error":"水域状态图集必须具有整数像素的采样留边"}
    if values.slope_range <= 0.0 or values.height_range <= 0.0:
        return {"error":"水域状态坡度与高度量化范围必须为正"}
    var texture: Texture2D = assets.call("texture", path) as Texture2D # 两个区域共享现有场景缓存中的同一状态纹理。
    var atlas_size: Vector2 = (values.frame_size + Vector2.ONE * values.padding * 2.0) * values.atlas_grid # 每帧四边留边计入实际图集尺寸。
    if not atlas_size.is_finite() or texture == null or texture.get_size() != atlas_size:
        return {"error":"水域状态图集实际尺寸与元数据不一致"}
    values["texture"] = texture
    return values

## [param spec] 是单块声明，[param source] 是实际原图精灵，[param density] 为像素密度，[param dimensions] 是完整原图像素边界。
## 返回含采样原点和绝对核心裁切框的字典，或error；最大幅度所需留边不足时拒绝覆盖。
func _prepare_geometry(spec: Dictionary, source: Sprite2D, density: float, dimensions: Vector2) -> Dictionary:
    var values: Dictionary = {} # 四个像素坐标向量都要求有限整数，防止半像素核心边界造成接缝。
    for key: String in ["pixel_origin", "pixel_size", "core_pixel_origin", "core_pixel_size"]: # 核心区与含留边的采样区分开声明。
        var decoded: Dictionary = VALUES.decode(spec.get(key), TYPE_VECTOR2) # 配置可来自JSON数组或内存向量。
        if not decoded.ok:
            return {"error":key + "必须为有限二维像素坐标"}
        var point: Vector2 = decoded.value # 单位为完整8K原图的整数像素。
        if not point.is_finite() or point.x != floor(point.x) or point.y != floor(point.y):
            return {"error":key + "必须使用整数像素"}
        values[key] = point
    var origin: Vector2 = values.pixel_origin # 含留边图块左上角。
    var size: Vector2 = values.pixel_size # 含留边图块实际纹理大小。
    var core_origin: Vector2 = values.core_pixel_origin # 不重叠核心区的绝对原图左上角。
    var core_size: Vector2 = values.core_pixel_size # 核心区宽高，不包含相邻块采样留边。
    var end: Vector2 = origin + size # 采样区半开右下界。
    var core_end: Vector2 = core_origin + core_size # 核心区半开右下界。
    if origin.x < 0.0 or origin.y < 0.0 or size.x <= 0.0 or size.y <= 0.0 or end.x > dimensions.x or end.y > dimensions.y:
        return {"error":"采样区超出完整地形"}
    if core_size.x <= 0.0 or core_size.y <= 0.0 or core_origin.x < origin.x or core_origin.y < origin.y or core_end.x > end.x or core_end.y > end.y:
        return {"error":"核心区未包含在采样区内"}
    var gutter: float = ceil(MAX_AMPLITUDE_WORLD * density) + 2.0 # 最大世界位移转成像素，再留两像素双线性采样余量。
    if (core_origin.x > 0.0 and core_origin.x - origin.x < gutter) or (core_origin.y > 0.0 and core_origin.y - origin.y < gutter):
        return {"error":"核心区左侧或上侧采样留边不足"}
    if (core_end.x < dimensions.x and end.x - core_end.x < gutter) or (core_end.y < dimensions.y and end.y - core_end.y < gutter):
        return {"error":"核心区右侧或下侧采样留边不足"}
    if source == null or source.texture == null or source.texture.get_size() != size:
        return {"error":"原地形纹理与图块尺寸不一致"}
    if source.centered or source.region_enabled or source.flip_h or source.flip_v or source.hframes != 1 or source.vframes != 1 or source.offset != Vector2.ZERO:
        return {"error":"原地形必须使用未裁切、未翻转的单帧精灵"}
    if not source.position.is_equal_approx(origin / density) or not source.scale.is_equal_approx(Vector2.ONE / density) or not is_zero_approx(source.rotation) or not is_zero_approx(source.skew):
        return {"error":"原地形变换与世界像素声明不一致"}
    return {"pixel_origin":origin,"core_rect":Vector4(core_origin.x,core_origin.y,core_end.x,core_end.y),"core_area":Rect2(core_origin,core_size)}

## [param reason] 为一次配置失败原因；记录单条诊断并返回false，不改变原地形或旧覆盖。
func _reject(reason: String) -> bool:
    push_error("Wonderland water: " + reason)
    return false

## 源地形换入或离屏释放时，覆盖层必须同帧接管同一纹理。
func _sync_terrain_texture(source: Sprite2D, overlay: Sprite2D) -> void:
    if is_instance_valid(overlay):
        overlay.texture = source.texture
