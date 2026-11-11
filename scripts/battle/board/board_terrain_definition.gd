## 地形的静态种植能力；运行时状态属于各格子实例，禁止修改共享资源。
extends Resource
class_name BoardTerrainDefinition

## 布局内唯一的地形 ID，存档与动态地形操作使用此值。
@export var terrain_id: StringName = &"grass"
## 兼容原有植物资源的种植能力位；草地默认含无地形要求位。
@export_flags("任意", "草地", "花盆", "水", "睡莲", "裸地") var planting_flags: int = 3
## 有承托物时的种植能力；0 表示保留原地形能力。
@export var supported_flags: int = 4
## 局部水陆生成要求，整行是否容纳该物种由 BoardLaneDefinition 决定。
@export var spawn_type: CharacterRegistry.ZombieRowType = CharacterRegistry.ZombieRowType.Land
## 原有表现分类，仅供坑洞图片等兼容读取，不作为地形身份。
@export_enum("草地", "水池", "屋顶") var presentation_kind: int = 0
## 地形固有禁种；特殊植物也不能绕过。
@export var blocks_planting: bool = false
## 可组合能力标签，供新植物声明需求，无须增加地形枚举分支。
@export var tags: Array[StringName] = []
## 自定义布局是否从格子矩形生成 WaterBodyArea；旧泳池由现有水面区域负责。
@export var water_contact: bool = false
## 可选独立实例行为/表现；根必须继承 BoardTerrainBehavior。
@export var behavior_scene: PackedScene

## 返回配置错误，不修改 [member planting_flags]。
func validate() -> PackedStringArray:
	var errors := PackedStringArray() # 累积静态错误。
	if str(terrain_id).strip_edges().is_empty() or planting_flags < 0 or supported_flags < 0:
		errors.append("地形 ID 或种植能力无效。")
	if spawn_type not in [CharacterRegistry.ZombieRowType.Land, CharacterRegistry.ZombieRowType.Pool]:
		errors.append("单格生成地形只能为 Land 或 Pool；Both 属于攻击行能力。")
	if presentation_kind < 0 or presentation_kind > 2:
		errors.append("地形表现分类无效。")
	if behavior_scene != null:
		var instance: BoardTerrainBehavior = create_behavior() # 所有入口复用同一离树构造边界。
		if instance == null:
			errors.append("地形行为场景不可实例化或根类型错误。")
		else:
			instance.free()
	return errors

## 为旧场景的 [param kind] 创建等价能力；不生成重复水体。
static func legacy(kind: int) -> BoardTerrainDefinition:
	var result := BoardTerrainDefinition.new() # 运行时私有的旧地形定义。
	result.presentation_kind = kind
	match kind:
		1:
			result.terrain_id = &"pool"
			result.spawn_type = CharacterRegistry.ZombieRowType.Pool
			result.planting_flags = 9
			result.supported_flags = 17
			result.tags = [&"water"]
		2:
			result.terrain_id = &"roof"
			result.planting_flags = 33
			result.tags = [&"roof"]
		_:
			result.tags = [&"land"]
	return result


## 唯一行为构造入口；空场景、实例化失败、错误根类型均返回 null，不操作活场景。
func create_behavior() -> BoardTerrainBehavior:
	if behavior_scene == null or not behavior_scene.can_instantiate():
		return null
	var node: Node = behavior_scene.instantiate() # 尚未进入场景树的候选。
	if not node is BoardTerrainBehavior:
		if is_instance_valid(node):
			node.free()
		return null
	return node as BoardTerrainBehavior
