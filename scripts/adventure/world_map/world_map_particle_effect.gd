## 小量确定性粒子：固定实例批次、显式动作秒数、局部逐片元遮挡。
extends "res://scripts/adventure/world_map/world_map_region_effect.gd"

## 解析粒子的唯一Shader，不依赖内置粒子时钟。
const SHADER_PATH := "res://shaders/adventure/wonderland/region_particle.gdshader"
## 粒子样式对应形状与运动机制。
const STYLES := ["snow","ground_snow","spore","dust","leaf","petal","ember","spray"]
## 当前区域固定MultiMesh，不逐帧增加场景节点。
var _batch: MultiMeshInstance2D
## 逐片元技术蒙版与颜色设置。
var _material: ShaderMaterial
## 已分配实例容量，数量改变才重配。
var _count := -1
## 每个实例固定的种子，来自区域ID和索引，不随帧率改变。
var _seeds: Array[Vector4] = []

## [param assets] 与 [param terrain_root] 不需复制；粒子使用局部技术蒙版与一份解析四边形。
func _build_visual(_assets: RefCounted, _terrain_root: Node2D) -> bool:
    if not ResourceLoader.exists(SHADER_PATH,"Shader") or not STYLES.has(style):
        return _reject("粒子Shader或样式无效")
    _material = ShaderMaterial.new()
    _material.shader = load(SHADER_PATH) as Shader
    _material.set_shader_parameter("region_mask",mask_texture)
    _material.set_shader_parameter("mask_origin_world",bounds_world.position)
    _material.set_shader_parameter("mask_extent_world",bounds_world.size)
    _material.set_shader_parameter("shape",1 if style in ["leaf","petal"] else 0)
    _batch = MultiMeshInstance2D.new()
    _batch.material = _material
    var instances := MultiMesh.new() # 显式二维变换和颜色，容量有界。
    instances.transform_format = MultiMesh.TRANSFORM_2D
    instances.use_colors = true
    instances.use_custom_data = true
    var quad := QuadMesh.new() # 所有粒子共用单位四边形，Shader解析圆/叶片覆盖。
    quad.size = Vector2.ONE
    instances.mesh = quad
    _batch.multimesh = instances
    add_child(_batch)
    return true

## 只在配置的粒子数改变时分配；所有随机值在这里固定下来。
func _resize_batch() -> void:
    var count: int = int(profile.count) # 经参数验证的零到120容量。
    if count == _count:
        return
    _count = count
    _batch.multimesh.instance_count = count
    _seeds.clear()
    var random := RandomNumberGenerator.new() # 独立固定种子，避免污染项目全局随机。
    random.seed = absi(effect_id.hash()) + 7193
    for index: int in range(count): # 每粒子的空间偏移、相位和尺度偏差。
        _seeds.append(Vector4(random.randf(),random.randf(),random.randf(),random.randf()))
        _batch.multimesh.set_instance_custom_data(index,Color(1.0 if index % 3 == 0 or style != "snow" else 0.0,0.0,0.0,1.0)) # 三分之二雪粒使用后景遮挡，其他类型使用本区覆盖。

## [param force] 允许冻结时补齐屏外实例；位置由时间解析，无独立粒子时钟。
func _update_frame(force: bool = false) -> void:
    if _batch == null:
        return
    _resize_batch()
    if not force and not is_region_visible():
        return
    var color_data: Array = profile.color # 颜色只在此处解码一次，不逐实例读配置。
    var tint := Color(float(color_data[0]),float(color_data[1]),float(color_data[2]),1.0) # 低对比环境色。
    var lifetime: float = float(profile.period_seconds) # 每个实例相位错开，循环端透明。
    var speed: float = float(profile.speed_world) # 世界单位每秒。
    var gust: float = 0.8 + 0.2*cos(seconds*TAU/18.0) # 与表面风场同一阵风周期。
    for index: int in range(_count): # 实例数恒定，屏外不做逐实例写入。
        var seed: Vector4 = _seeds[index] # 四维固定随机偏移。
        var phase: float = fposmod(seconds/lifetime+seed.z,1.0) # 生命周期0..1，循环处先淡出。
        var age: float = phase*lifetime # 当前粒子的解析年龄。
        var alpha: float = smoothstep(0.0,0.15,phase)*(1.0-smoothstep(0.72,1.0,phase))*float(profile.strength) # 淡入淡出避免跳回出生点。
        var point := bounds_world.position+Vector2(seed.x,seed.y)*bounds_world.size # 固定种子决定每一轮发射位置。
        var angle: float = seed.w*TAU + age*0.25 # 雪粒近圆，叶片缓慢翻滚。
        if style == "ember":
            var radius: float = 0.92*(1.0-phase) # 粒子向黑心收束并在中心之前淡出。
            angle = seed.x*TAU + age*.65
            point = center_world + Vector2(cos(angle),sin(angle))*radii_world*radius
            alpha *= 1.0-smoothstep(.55,.85,phase)
        elif style == "spore":
            point += Vector2(sin(age*.3+seed.w*TAU)*5.0+age*speed*.3,-age*speed)
        elif style == "spray":
            point += Vector2(age*speed*.25,-age*speed+age*age*.9)
        else:
            point.x += age*speed*gust
            point.y += age*speed*(.42 if style in ["snow","petal"] else .06)
            point.y += sin(age*.7+seed.w*TAU)*(1.6 if style in ["leaf","petal"] else .5)
        if style in ["leaf","petal","dust"]:
            var burst: float = fposmod(seconds/lifetime,1.0) # 稀疏事件只在循环部分时段出现。
            alpha *= smoothstep(.1,.22,burst)*(1.0-smoothstep(.6,.85,burst))
        var size: float = float(profile.size_world)*2.0*(.7+seed.w*.6) # QuadMesh边长；单位为世界坐标。
        if style == "snow" and index % 3 != 0:
            size *= .65
        var stretch: float = .5+.5*absf(sin(age+seed.w*TAU)) if style in ["leaf","petal"] else 1.0 # 轻微叶片翻面。
        var transform := Transform2D(Vector2(cos(angle),sin(angle))*size,Vector2(-sin(angle),cos(angle))*size*stretch,point) # 变换同时包含尺寸与朝向。
        _batch.multimesh.set_instance_transform_2d(index,transform)
        tint.a = alpha
        _batch.multimesh.set_instance_color(index,tint)
