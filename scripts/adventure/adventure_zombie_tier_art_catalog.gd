## 冒险僵尸等阶贴图目录：按物种与等阶合并原版纹理替换表。
## 冒险出生绑定器与图鉴静态预览共用；无美术配置时返回空表，不改变原版画面。
extends RefCounted
class_name AdventureZombieTierArtCatalog

## 唯一美术映射文件；所有键和值均为 res:// PNG 路径。
const MANIFEST_PATH := "res://assets/adventure/zombies/tier_art_map.json"

## 解析后的只读目录；每次游戏运行最多解析一次。
static var _manifest: Dictionary = {}
## 是否已完成首次目录读取，避免每个出生实例访问磁盘。
static var _loaded := false

## [param zombie_type] CharacterRegistry 中的原版僵尸类型整数。
## [param tier_id] AdventureZombieTierCatalog 的等阶 ID。
## 返回原版纹理路径至替代 Texture2D 的映射；缺图或配置非法时整组回退。
static func textures_for(zombie_type: int, tier_id: StringName) -> Dictionary:
	var source_paths: Dictionary = _source_paths(zombie_type, tier_id) # 与准备清单共用继承、覆盖和路径校验。
	var textures: Dictionary = {} # 整组成功后才返回，保留缺图时的原版回退。
	for original_path: String in source_paths: # 解析器已确认两侧路径均为合法纹理路径。
		var replacement_path: String = source_paths[original_path] # 调用方提前准备的最终替代纹理。
		var replacement: Texture2D = load(replacement_path) as Texture2D # 已准备时只取引擎资源缓存。
		if replacement == null:
			push_warning("僵尸等阶贴图格式错误：" + replacement_path)
			return {}
		textures[original_path] = replacement
	return textures

## 返回 [param zombie_type]、[param tier_id] 实际使用的替代纹理路径，不加载或实例化资源。
## 共享部件、物种继承与覆盖均沿用实际装配的同一解析器。
static func resource_paths(zombie_type: int, tier_id: StringName) -> PackedStringArray:
	var result := PackedStringArray() # 不提前准备其他阶级或其他物种。
	for path: String in _source_paths(zombie_type, tier_id).values(): # 多个原分件可能共用一张替代纹理。
		if not result.has(path):
			result.append(path)
	return result

## 校验并解析 [param zombie_type]、[param tier_id] 的原图到替代路径映射，不读取 Texture2D。
static func _source_paths(zombie_type: int, tier_id: StringName) -> Dictionary:
	if tier_id == &"base":
		return {}
	_load_once()
	if _manifest.is_empty():
		return {}
	# shared 适用于同源 PNG 的多个原版僵尸；zombies 覆盖物种特例。
	var shared: Variant = _manifest.get("shared", {})
	var types: Variant = _manifest.get("zombies", {})
	if not (shared is Dictionary and types is Dictionary):
		push_warning("僵尸等阶美术目录字段类型无效")
		return {}
	var tier_key: String = str(tier_id)
	var source_paths: Dictionary = {}
	var common: Variant = shared.get(tier_key, {})
	if not common is Dictionary:
		push_warning("僵尸等阶共享贴图映射必须为对象：" + tier_key)
		return {}
	source_paths.merge(common)
	# 物种可声明 inherits=父物种编号，复用父物种已登记的全部分件。
	# 只继承美术映射，不改变僵尸场景、行为或属性。
	var resolved: Dictionary = _species_mapping(types, str(zombie_type), tier_key, {})
	if not bool(resolved.get("ok", false)):
		return {}
	source_paths.merge(resolved["paths"], true)
	if source_paths.is_empty():
		return {}
	for original_path: Variant in source_paths:
		var replacement_path: Variant = source_paths[original_path]
		if not (original_path is String and replacement_path is String):
			push_warning("僵尸等阶贴图路径必须为字符串")
			return {}
		if not original_path.begins_with("res://") or not replacement_path.begins_with(
				"res://assets/adventure/zombies/"):
			push_warning("僵尸等阶贴图路径不符合资源边界：" + original_path)
			return {}
		if not ResourceLoader.exists(original_path, "Texture2D") or not ResourceLoader.exists(
				replacement_path, "Texture2D"):
			push_warning("僵尸等阶贴图缺失：" + original_path + " / " + replacement_path)
			return {}
	return source_paths

## 递归解析物种映射：父物种在先，子物种在后；防止循环继承。
## 任何无效继承关系都整组拒绝，不在游戏中使用部分替换。
static func _species_mapping(
		types: Dictionary, species_key: String, tier_key: String,
		visited: Dictionary) -> Dictionary:
	if visited.has(species_key):
		push_warning("僵尸等阶美术目录存在循环继承：" + species_key)
		return {"ok": false}
	var species: Variant = types.get(species_key, {})
	if not species is Dictionary:
		push_warning("僵尸等阶物种目录必须为对象：" + species_key)
		return {"ok": false}
	visited[species_key] = true
	var paths: Dictionary = {}
	var parent: Variant = species.get("inherits", "")
	if not parent is String:
		push_warning("僵尸等阶美术 inherits 必须为物种编号字符串：" + species_key)
		return {"ok": false}
	if not parent.is_empty():
		if not types.has(parent):
			push_warning("僵尸等阶美术缺少继承物种：" + parent)
			return {"ok": false}
		var base: Dictionary = _species_mapping(types, parent, tier_key, visited)
		if not bool(base.get("ok", false)):
			return {"ok": false}
		paths.merge(base["paths"], true)
	var specific: Variant = species.get(tier_key, {})
	if not specific is Dictionary:
		push_warning("僵尸等阶美术映射必须为对象：" + species_key + "/" + tier_key)
		return {"ok": false}
	paths.merge(specific, true)
	return {"ok": true, "paths": paths}


## 在首次冒险僵尸出生或图鉴预览时读取唯一 manifest。
static func _load_once() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_warning("缺少僵尸等阶美术目录：" + MANIFEST_PATH)
		return
	var content: String = FileAccess.get_file_as_string(MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(content)
	if not parsed is Dictionary or parsed.get("schema_version", 0) != 1:
		push_warning("僵尸等阶美术目录无效或 schema_version 不支持")
		return
	_manifest = parsed
