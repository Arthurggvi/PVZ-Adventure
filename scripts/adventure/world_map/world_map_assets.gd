## 地图只读资源仓库：所有路径以正式 res:// 为准，不读取外部制作目录。
## 地图布局、地标身份与动态区域是独立数据，不缓存存档或关卡进度。
extends RefCounted

## 地图声明及纹理的唯一运行资源根目录。
const ROOT := "res://assets/adventure/wonderland/"
## 同一类型表负责资源枚举与实例化，不额外建立加载器。
const EFFECT_FACTORY := preload("res://scripts/adventure/world_map/world_map_effect_factory.gd")
## 初始相机地形清单和运行时驻留策略共用同一几何计算。
const TERRAIN := preload("res://scripts/adventure/world_map/world_map_terrain_residency.gd")
## 大陆世界布局，包含坐标、分件枢轴和允许的运动包络。
var layout: Dictionary = {}
## 地标显示数据，不对 stage_reference 作任何推断。
var landmarks: Dictionary = {}
## 区域特效的技术蒙版入口，运行效果由其他组件注册。
var regions: Dictionary = {}
## 当前地图实例持有纹理引用；切场准备的资源由 Godot 缓存直接复用。
var _textures: Dictionary = {}

## [param name] 是根目录相对 JSON 路径；失败返回空字典并记录原因。
func read_json(name: String) -> Dictionary:
    var path: String = ROOT + name # 运行资源路径，禁止外部绝对路径回退。
    if not FileAccess.file_exists(path):
        push_error("Wonderland resource missing: " + path)
        return {}
    var parser := JSON.new() # 保留真正的 JSON 解析错误，而不是吞掉错误。
    if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
        push_error("Wonderland invalid JSON: " + path)
        return {}
    return parser.data

## 只读取 JSON 清单并返回去重的首屏资源全路径，不加载纹理、不创建全局缓存。
## 由场景根脚本的静态资源声明在统一切场准备阶段调用。
func initial_resource_paths() -> PackedStringArray:
    var art: Dictionary = read_json("config/art_layout.json") # 高清图块与主体的声明来源。
    var catalog: Dictionary = read_json("config/landmarks.json") # 命中图与地标显示蒙版的声明来源。
    var effects: Dictionary = read_json("config/fx_regions.json") # 所有已启用可选区域按同一工厂枚举资源。
    var relative_paths: Array[String] = [] # 尚未添加资源根目录的本次准备清单。
    # 只准备初始镜头与邻近留边的原尺寸图块，其他块由相机驻留器加载。
    if not art.is_empty():
        var terrain: Dictionary = art.get("terrain", {})
        var visible: Rect2 = TERRAIN.initial_rect(art).grow(TERRAIN.PRELOAD_MARGIN)
        for tile: Dictionary in terrain.get("tiles", []):
            if TERRAIN.tile_rect(tile,float(terrain.pixels_per_world)).intersects(visible):
                relative_paths.append(str(tile.get("path", "")))
    # 主体字典值只提供路径和世界布局，不实例化任何绘制节点。
    for spec: Dictionary in art.get("subjects", {}).values():
        relative_paths.append(str(spec.get("path", "")))
    # 固定塔架等前景遮挡层也在切场阶段准备，缺省布局允许没有此类分件。
    for occluder: Dictionary in art.get("static_occluders", []):
        relative_paths.append(str(occluder.get("path", "")))
    # 高亮由实际悬停触发，首屏不装配十一份轮廓。
    # 可选效果只准备已存在资源；错误路径由适配器局部拒绝，不能阻断切场。
    for region: Dictionary in effects.get("regions", {}).values():
        for path: String in EFFECT_FACTORY.resource_paths(region): # 工厂返回正式完整路径，包含类型固定的Shader。
            relative_paths.append(path)
    relative_paths.append(str(art.get("moving_hover_source", "")))
    relative_paths.append(str(art.get("airship_motion_mask", "")))
    relative_paths.append(str(catalog.get("hit_source", "")))
    relative_paths.append(str(catalog.get("moving_source", "")))
    var paths := PackedStringArray() # 提交给已有 ResourceBatch 的去重全路径列表。
    # 空路径不会变成目录资源；同一纹理在本批次只准备一次。
    for relative: String in relative_paths:
        var path: String = relative if relative.begins_with("res://") else ROOT + relative # 工厂的完整路径与既有相对美术路径共用最终去重。
        if not relative.is_empty() and not paths.has(path):
            paths.append(path)
    return paths

## 读取 schema 3 布局，验证地形核心范围及基础高清分件尺寸。
## 地标索引沿用 schema 2，区域声明沿用 schema 1；任何必需配置缺失返回 false。
## 可选水体的路径和尺寸由其适配器局部校验，错误时保留静态地图。
func configure() -> bool:
    layout = read_json("config/art_layout.json")
    landmarks = read_json("config/landmarks.json")
    regions = read_json("config/fx_regions.json")
    if layout.is_empty() or landmarks.is_empty() or regions.is_empty():
        return false
    var size: Array = layout.get("original_size", []) # 世界单位沿用原始构图，独立于高清纹理像素。
    if size.size() != 2 or size != landmarks.get("source_size", []) or size != regions.get("world_size", []):
        push_error("Wonderland map size mismatch")
        return false
    if float(size[0]) <= 0.0 or float(size[1]) <= 0.0:
        push_error("Wonderland invalid world size")
        return false
    if int(layout.get("schema_version", 0)) != 3 or int(landmarks.get("schema_version", 0)) != 2 or int(regions.get("schema_version", 0)) != 1:
        push_error("Unsupported Wonderland layout schema")
        return false
    var terrain: Dictionary = layout.get("terrain", {}) # 高清地形声明，保留图块重叠边的原始尺寸。
    var dimensions: Array = terrain.get("texture_size", []) # 整张高清美术的像素宽高，不是世界范围。
    var density: float = float(terrain.get("pixels_per_world", 0.0)) # 每个世界单位对应的纹理像素数。
    var tiles: Array = terrain.get("tiles", []) # 实际用于绘制的全部分块声明。
    if dimensions.size() != 2 or density <= 0.0 or tiles.is_empty():
        push_error("Wonderland missing HD terrain layout")
        return false
    var texture_size := Vector2(float(dimensions[0]), float(dimensions[1])) # 完整纹理的像素边界。
    if texture_size.x <= 0.0 or texture_size.y <= 0.0 or not texture_size.is_equal_approx(world_size() * density):
        push_error("Wonderland terrain density mismatch")
        return false
    # 每块独立验证像素边界和已导入纹理尺寸，绝不要求高清纹理等于世界尺寸。
    for tile: Dictionary in tiles:
        var relative: String = str(tile.get("path", "")) # 当前分块的正式资源相对路径。
        var origin: Array = tile.get("pixel_origin", []) # 包括重叠边的分块左上角，单位为纹理像素。
        var pixels: Array = tile.get("pixel_size", []) # 包括重叠边的实际 PNG 宽高。
        if relative.is_empty() or origin.size() != 2 or pixels.size() != 2:
            push_error("Wonderland invalid terrain tile declaration")
            return false
        var point := Vector2(float(origin[0]), float(origin[1])) # 当前分块在完整纹理内的像素原点。
        var extent := Vector2(float(pixels[0]), float(pixels[1])) # 当前分块的像素尺寸。
        if point.x < 0.0 or point.y < 0.0 or extent.x <= 0.0 or extent.y <= 0.0 or point.x + extent.x > texture_size.x or point.y + extent.y > texture_size.y:
            push_error("Wonderland terrain tile outside texture: " + relative)
            return false
        var core_origin: Array = tile.get("core_pixel_origin", []) # 核心绘制区在完整底图内的像素原点，不包含采样扩展边。
        var core_pixels: Array = tile.get("core_pixel_size", []) # 核心实际绘制宽高；相邻核心不得依靠重叠重复着色。
        if core_origin.size() != 2 or core_pixels.size() != 2:
            push_error("Wonderland invalid terrain core declaration: " + relative)
            return false
        var core_point := Vector2(float(core_origin[0]), float(core_origin[1])) # 全图纹理像素坐标，与图块原点使用同一空间。
        var core_extent := Vector2(float(core_pixels[0]), float(core_pixels[1])) # 该图块应显示的正像素尺寸。
        var core_rect := Rect2(core_point, core_extent) # 核心范围同时受图块及完整世界的纹理边界约束。
        if core_extent.x <= 0.0 or core_extent.y <= 0.0 or not Rect2(point, extent).encloses(core_rect) or not Rect2(Vector2.ZERO, texture_size).encloses(core_rect):
            push_error("Wonderland terrain core outside tile or world: " + relative)
            return false
        if not ResourceLoader.exists(ROOT + relative, "Texture2D"):
            push_error("Wonderland terrain tile missing: " + relative)
            return false
        # 原尺寸验证由每块纹理首次真正驻留时执行，避免验证过程强制解码整张大陆。
    # 固定前景保持独立世界布局，此处仅校验实际显示纹理而不改变原始命中图。
    for occluder: Dictionary in layout.get("static_occluders", []):
        var relative: String = str(occluder.get("path", "")) # 当前固定遮挡层的正式资源相对路径。
        var pixels: Array = occluder.get("texture_size", []) # 高清裁切纹理声明的实际像素宽高。
        if relative.is_empty() or pixels.size() != 2:
            push_error("Wonderland invalid static occluder declaration")
            return false
        var extent := Vector2(float(pixels[0]), float(pixels[1])) # 与世界尺寸独立的高清像素尺寸。
        if extent.x <= 0.0 or extent.y <= 0.0:
            push_error("Wonderland invalid static occluder size: " + relative)
            return false
        if not ResourceLoader.exists(ROOT + relative, "Texture2D"):
            push_error("Wonderland static occluder missing: " + relative)
            return false
        var occluder_texture: Texture2D = texture(relative) # 复用统一加载已准备的固定前景纹理。
        if occluder_texture == null or occluder_texture.get_size() != extent:
            push_error("Wonderland static occluder size mismatch: " + relative)
            return false
    var motion_path: String = str(layout.get("airship_motion_mask", "")) # 艇体内部微形变专用采样蒙版。
    var body_pixels: Array = subject("airship_body").get("texture_size", []) # 蒙版必须与艇体 RGB 裁切一一对应。
    if motion_path.is_empty() or body_pixels.size() != 2:
        push_error("Wonderland missing airship motion mask declaration")
        return false
    var body_extent := Vector2(float(body_pixels[0]), float(body_pixels[1])) # 艇体局部采样使用的真实纹理宽高。
    if body_extent.x <= 0.0 or body_extent.y <= 0.0 or not ResourceLoader.exists(ROOT + motion_path, "Texture2D"):
        push_error("Wonderland invalid airship motion mask: " + motion_path)
        return false
    var motion_texture: Texture2D = texture(motion_path) # 复用切场已准备的内部软蒙版，不读取命中图。
    if motion_texture == null or motion_texture.get_size() != body_extent:
        push_error("Wonderland airship motion mask size mismatch: " + motion_path)
        return false
    return true

## [param relative] 是运行资源路径；空路径及资源类型错误不会伪装成功。
func texture(relative: String) -> Texture2D:
    if relative.is_empty():
        return null
    if _textures.has(relative):
        return _textures[relative]
    var loaded: Resource = load(ROOT + relative) # Godot 资源导入/导出管线负责载入。
    if not loaded is Texture2D:
        push_error("Wonderland texture missing or invalid: " + relative)
        return null
    _textures[relative] = loaded
    return loaded

## 返回声明式世界边界；相机和点击逻辑共用这一尺寸。
func world_size() -> Vector2:
    var values: Array = layout["original_size"] # 两个正世界尺寸由 configure 约束，与贴图密度无关。
    return Vector2(float(values[0]), float(values[1]))

## [param subject_id] 是 art_layout 的主体身份；读取分件唯一元数据。
func subject(subject_id: String) -> Dictionary:
    return layout.get("subjects", {}).get(subject_id, {})

## [param landmark_id] 从配置查询一个地标，不包含当前存档的解锁状态。
func landmark(landmark_id: String) -> Dictionary:
    # 当前数组项只含只读显示及命中配置，不读取业务状态。
    for entry: Dictionary in landmarks.get("landmarks", []):
        if str(entry.get("id", "")) == landmark_id:
            return entry
    return {}
