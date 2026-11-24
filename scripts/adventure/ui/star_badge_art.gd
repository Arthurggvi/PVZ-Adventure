## 星章表现层唯一素材解析器：运行时只加载静态 PNG 或预烘焙 RGBA 图集。
## 原版 star_badge_fx.gdshader 保留为人工自测资源，但正式星章绝不依赖。
extends RefCounted

## 保留原有资源根和 1～10 星编号协议。
const ROOT: String = "res://assets/adventure/ui/star_badges/"
## 动态图集仅包括 5～10 星，且一次只加载当前实际星级。
const BAKED_ROOT: String = ROOT + "baked/"
## 由开发工具生成的唯一时间采样表，不对玩家数据做任何解码。
const MANIFEST_PATH: String = BAKED_ROOT + "manifest.json"
## 仅缓存少量固定的时间元数据，不缓存玩家卡片或可变状态。
static var _manifest: Dictionary = {}

## UI 首屏准备时包含静态回退图和当前星级的动画图集。
static func resource_paths(rank: int) -> PackedStringArray:
	var clamped: int = clampi(rank, 0, 10)
	var result := PackedStringArray()
	if clamped == 0:
		return result
	result.append(_body_uri(clamped))
	if clamped >= 5:
		result.append(BAKED_ROOT + "star_%02d_atlas.png" % clamped)
	return result

## 保留已经被其他界面依赖的主体路径生成规则。
static func _body_uri(rank: int) -> String:
	return ROOT + "static/256/star_%02d.png" % rank

## 与原版一样，返回合法星级的静态贴图；缺失时由 View 隐藏自身。
static func body(rank: int) -> Texture2D:
	if rank < 1 or rank > 10:
		return null
	var path: String = _body_uri(rank)
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

## 返回某星级原生 RGBA 动画图集；所有卡面共享 Godot 的 ResourceLoader 缓存。
static func atlas(rank: int) -> Texture2D:
	if rank < 5 or rank > 10:
		return null
	var path: String = BAKED_ROOT + "star_%02d_atlas.png" % rank
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

## 只在第一次需要动态角标时读取静态 manifest；失败时使用静态 PNG。
static func animation_info(rank: int) -> Dictionary:
	if rank < 5 or rank > 10:
		return {}
	if _manifest.is_empty():
		if not FileAccess.file_exists(MANIFEST_PATH):
			return {}
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if not parsed is Dictionary:
			return {}
		_manifest = parsed
	var info: Variant = _manifest.get(str(rank), {})
	if not info is Dictionary or not info.get("times") is Array:
		return {}
	if int(info.get("frames", 0)) != (info.times as Array).size():
		return {}
	if float(info.get("period", 0.0)) <= 0.0 or int(info.get("columns", 0)) <= 0:
		return {}
	return info
