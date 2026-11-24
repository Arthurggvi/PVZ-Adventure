## 局部表面效果复用原地形贴图；光雾独立混合，不覆盖成另一张静态原图。
extends "res://scripts/adventure/world_map/world_map_region_effect.gd"

## 固定工厂给出的Shader路径，不接受配置中的任意资源代码。
var shader_path := ""
## 固定类型表内的样式序号。
var style_index := 0
## 当前区域材质列表；每个材质只关联一个地形核心或局部矩形。
var _materials: Array[ShaderMaterial] = []

## [param assets] 持有原生图块；[param terrain_root] 用于确认共享世界变换和实际纹理。
func _build_visual(assets: RefCounted, terrain_root: Node2D) -> bool:
    if not ResourceLoader.exists(shader_path,"Shader"):
        return _reject("局部Shader缺失")
    var shader: Shader = load(shader_path) as Shader # 切场已准备的着色程序，材质保持独立。
    if shader == null:
        return _reject("局部Shader无效")
    if effect_kind == "atmosphere":
        var sprite := Sprite2D.new() # 技术图只提供矩形几何和覆盖，颜色由Shader生成。
        sprite.centered = false
        sprite.texture = mask_texture
        sprite.position = bounds_world.position
        sprite.scale = bounds_world.size / mask_pixels
        sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        var material: ShaderMaterial = _make_material(shader) # 无静态底图采样，保存已在下方绘制的风动。
        material.set_shader_parameter("local_origin_world",bounds_world.position)
        material.set_shader_parameter("local_extent_world",bounds_world.size)
        sprite.material = material
        add_child(sprite)
        return true
    if terrain_root == null or terrain_root.get_parent() != get_parent():
        return _reject("区域与原地形未共享世界节点")
    var terrain: Dictionary = assets.layout.get("terrain",{}) # 复用经资源仓库验证的核心和采样留边。
    var density: float = float(terrain.get("pixels_per_world",0.0)) # 原生像素到世界的唯一换算。
    var tiles: Array = terrain.get("tiles",[]) # 与地形子节点顺序保持一致。
    if density <= 0 or tiles.size() != terrain_root.get_child_count():
        return _reject("原地形图块声明不一致")
    for index: int in range(tiles.size()): # 只创建与区域相交的原纹理引用，绝不复制8K图片。
        var spec: Dictionary = tiles[index] # 核心边界半开裁切，采样区仍含留边。
        var point := Vector2(float(spec.core_pixel_origin[0]),float(spec.core_pixel_origin[1])) # 原图像素坐标。
        var extent := Vector2(float(spec.core_pixel_size[0]),float(spec.core_pixel_size[1])) # 原图像素宽高。
        if not Rect2(point/density,extent/density).intersects(bounds_world):
            continue
        var source: Sprite2D = terrain_root.get_child(index) as Sprite2D # 已经验证的原地形节点。
        if source == null or source.texture == null:
            return _reject("原地形纹理无效")
        var sprite := Sprite2D.new() # 与原图共用Texture2D，不额外解码。
        sprite.centered = false
        sprite.texture = source.texture
        source.texture_changed.connect(_sync_terrain_texture.bind(source,sprite))
        sprite.transform = source.transform
        sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        var material: ShaderMaterial = _make_material(shader) # 每块保留自己的原点和核心半开边。
        material.set_shader_parameter("tile_pixel_origin",Vector2(float(spec.pixel_origin[0]),float(spec.pixel_origin[1])))
        material.set_shader_parameter("pixels_per_world",density)
        material.set_shader_parameter("core_pixel_rect",Vector4(point.x,point.y,point.x+extent.x,point.y+extent.y))
        sprite.material = material
        add_child(sprite)
    return not _materials.is_empty()

## [param shader] 为固定机制的着色程序；返回本区域独享的已绑定材质。
func _make_material(shader: Shader) -> ShaderMaterial:
    var material := ShaderMaterial.new() # 资源参数不在地区间串改。
    material.shader = shader
    material.set_shader_parameter("region_mask",mask_texture)
    material.set_shader_parameter("mask_origin_world",bounds_world.position)
    material.set_shader_parameter("mask_extent_world",bounds_world.size)
    material.set_shader_parameter("center_world",center_world)
    material.set_shader_parameter("radii_world",radii_world)
    material.set_shader_parameter("style",style_index)
    _materials.append(material)
    return material

## [param force] 保证屏外初始化和暂停快照完整；正常屏外只跳过材质更新，不停计时。
func _update_frame(force: bool = false) -> void:
    if not force and not is_region_visible():
        return
    for material: ShaderMaterial in _materials: # 每个区域只更新实际相交的少数图块。
        material.set_shader_parameter("effect_seconds",seconds)
        material.set_shader_parameter("period_seconds",float(profile.period_seconds))
        material.set_shader_parameter("effect_strength",float(profile.strength))
        material.set_shader_parameter("amplitude_world",float(profile.amplitude_world))
        material.set_shader_parameter("event_weight",event_weight)
        material.set_shader_parameter("wind_angle",fposmod(seconds/18.0,1.0)*TAU)

## 区域着色覆盖与基础图块共享真实纹理驻留。
func _sync_terrain_texture(source: Sprite2D, overlay: Sprite2D) -> void:
    if is_instance_valid(overlay):
        overlay.texture = source.texture
