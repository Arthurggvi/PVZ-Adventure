## 唯一类型表同时服务首屏资源准备和场景实例化；不建立第二套加载器。
extends RefCounted

## 水域继续使用原适配器；新表面和粒子只有各自一份生命周期实现。
const WATER := preload("res://scripts/adventure/world_map/world_map_water_effect.gd")
## 新表面机制按局部Shader处理风、孔口、落水与光雾。
const SURFACE := preload("res://scripts/adventure/world_map/world_map_surface_effect.gd")
## 少量粒子由显式时间解析求位姿。
const PARTICLES := preload("res://scripts/adventure/world_map/world_map_particle_effect.gd")
## 每种类型的资源字段、允许样式和着色程序是同一份权威定义。
const TYPES := {
    "water":{"fields":["mask","flow","surface_state"],"styles":[],"shader":""},
    "wind":{"fields":["mask"],"styles":["grass","canopy","mushroom","garden"],"shader":"region_wind"},
    "waterfall":{"fields":["mask"],"styles":["fall"],"shader":"region_waterfall"},
    "aperture":{"fields":["mask"],"styles":["portal","furnace"],"shader":"region_aperture"},
    "atmosphere":{"fields":["mask"],"styles":["sunset","darkness","window","mist","ice_mist","dust_mist","ridge","smoke"],"shader":"region_atmosphere"},
    "particle":{"fields":["mask"],"styles":["snow","ground_snow","spore","dust","leaf","petal","ember","spray"],"shader":"region_particle"}
}

## [param region] 为区域声明；只枚举已启用已存在的资源，返回正式完整路径并去重。
static func resource_paths(region: Dictionary) -> PackedStringArray:
    var result := PackedStringArray() # 交给既有SceneTransition，不在这里加载资源。
    var kind: String = str(region.get("kind","")) # 未实现类型不创建假节点。
    if not bool(region.get("enabled",false)) or not TYPES.has(kind):
        return result
    for field: String in TYPES[kind].fields: # 水域和新类型共享收集入口，校验仍由各自适配器完成。
        var relative: Variant = region.get(field,"") # 原始路径保持相对正式资源根。
        if relative is String and not relative.is_empty() and not relative.contains("..") and not relative.contains("\\"):
            var path: String = "res://assets/adventure/wonderland/"+relative # 不访问外部制作路径。
            if ResourceLoader.exists(path,"Texture2D") and not result.has(path):
                result.append(path)
    var shader: String = str(TYPES[kind].shader) # 轻量Shader也纳入已有动态资源准备。
    if not shader.is_empty():
        var path: String = "res://shaders/adventure/wonderland/"+shader+".gdshader" # 路径完全来自固定表。
        if ResourceLoader.exists(path,"Shader"):
            result.append(path)
    return result

## [param region] 校验类型与样式后返回离树实例；未知类型返回null。
static func create(region: Dictionary) -> Node2D:
    var kind: String = str(region.get("kind","")) # 类型决定机制，地区只描述数据。
    if not bool(region.get("enabled",false)) or not TYPES.has(kind):
        return null
    if kind == "water":
        return WATER.new()
    var styles: Array = TYPES[kind].styles # 样式名不能变成任意脚本/Shader路径。
    var style: String = str(region.get("style","")) # 缺失或错误样式局部拒绝。
    if not styles.has(style):
        push_error("Wonderland unsupported style: "+kind+"/"+style)
        return null
    if kind == "particle":
        return PARTICLES.new()
    var effect: Node2D = SURFACE.new() # 同一表面组件持有多个原地形图块引用。
    effect.shader_path = "res://shaders/adventure/wonderland/"+str(TYPES[kind].shader)+".gdshader"
    effect.style_index = styles.find(style)
    return effect
