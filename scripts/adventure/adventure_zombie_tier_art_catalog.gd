## 冒险僵尸等阶贴图目录：按物种与等阶合并原版纹理替换表。
## 只有冒险出生绑定器调用；无美术配置时返回空表，不改变原版画面。
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
	var species: Variant = types.get(str(zombie_type), {})
	if not species is Dictionary:
		push_warning("僵尸等阶物种目录必须为对象：" + str(zombie_type))
		return {}
	var specific: Variant = species.get(tier_key, {})
	if not specific is Dictionary:
		push_warning("僵尸等阶物种贴图映射必须为对象：" + tier_key)
		return {}
	source_paths.merge(specific, true)
	if source_paths.is_empty():
		return {}
	var textures: Dictionary = {}
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
		var replacement: Texture2D = load(replacement_path) as Texture2D
		if replacement == null:
			push_warning("僵尸等阶贴图格式错误：" + replacement_path)
			return {}
		textures[original_path] = replacement
	return textures

## 在首次冒险僵尸出生时读取唯一 manifest。
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
