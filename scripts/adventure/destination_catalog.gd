## 将唯一 v1.2 布局适配为展示目录；路由许可由代码注册，不执行 JSON 中的字符串。
extends RefCounted

## 本轮唯一资源根目录，不回退到旧版或合成预览。
const ROOT := "res://assets/adventure/destination_picker/v1_2/"
## 已实现地区的动作契约，选择器与导航层共用此许可。
const ROUTES := {
	"zombie_island": "reuse_existing_zombie_island_entry",
	"town": "return_to_main_menu",
}
## 最近一次布局错误，交给界面显示。
var error_message := ""
## 本次验证通过的布局纹理路径；不加载资源，不跨界面缓存。
var resource_paths := PackedStringArray()

## 返回已验证并附加显式 rect 的目录；失败返回空字典，不修改玩家状态。
func load_layout() -> Dictionary:
	error_message = ""
	resource_paths.clear()
	var parser := JSON.new() # 实例解析保证错误可以展示而不会静默替换布局。
	if parser.parse(FileAccess.get_file_as_string(ROOT + "layout.json")) != OK:
		return _invalid("v1.2 layout.json 缺失或格式错误。")
	var data: Variant = parser.data # 只接受当前资源包的结构。
	if not data is Dictionary or data.get("schema_version") != 3 \
		or not _numbers(data.get("logical_canvas"), 2):
		return _invalid("v1.2 布局版本或画布无效。")
	if not data.get("paper") is Dictionary or not _numbers(data.paper.get("rect"), 4) \
		or not data.get("card") is Dictionary or not data.get("close") is Dictionary \
		or not data.get("slots") is Dictionary or not data.slots.get("positions") is Array \
		or not data.get("destinations") is Array:
		return _invalid("v1.2 布局缺少纸张、卡片或地区配置。")
	for key: String in ["rect_size", "preview_offset", "preview_size", "label_rect_local"]: # 卡片局部矩形来自配置。
		if not _numbers(data.card.get(key), 4 if key == "label_rect_local" else 2):
			return _invalid("v1.2 卡片尺寸无效。")
	if not data.card.get("label_font_size") is float and not data.card.get("label_font_size") is int:
		return _invalid("v1.2 名称字号无效。")
	if not _numbers(data.close.get("rect"), 4) or not data.close.get("assets") is Dictionary:
		return _invalid("v1.2 关闭按钮配置无效。")
	var canvas := Rect2(Vector2.ZERO, Vector2(data.logical_canvas[0], data.logical_canvas[1])) # 安全区边界。
	var paper := rect(data.paper.rect) # 卡片必须完整位于纸张范围。
	if canvas.size.x <= 0 or canvas.size.y <= 0 or not canvas.encloses(paper) \
		or not canvas.encloses(rect(data.close.rect)):
		return _invalid("v1.2 纸张或关闭按钮超出画布。")
	var assets: Array = [data.paper.get("asset")] # 启动前检查本页全部必需纹理。
	for state: String in ["normal", "hover", "pressed"]: # 关闭按钮三个独立状态。
		assets.append(data.close.assets.get(state))
	var positions: Dictionary = {} # 位置以 slot 标识关联，绝不使用固定网格。
	for slot: Variant in data.slots.positions: # 将配置位置索引为完整卡片矩形。
		if not slot is Dictionary or not _numbers(slot.get("rect"), 4) or positions.has(slot.get("slot")):
			return _invalid("v1.2 地区位置缺失或重复。")
		positions[slot.get("slot")] = slot.rect
	var used: Array[Rect2] = [] # 防止完整卡片交叠或超出纸张。
	var ids: Dictionary = {} # 稳定地区 ID 不允许重复。
	for destination: Variant in data.destinations: # 动态生成同一个 Card 场景的数据。
		if not destination is Dictionary or not destination.get("id") is String \
			or not destination.get("name") is String or not destination.get("enabled") is bool \
			or ids.has(destination.id) or not positions.has(destination.get("slot")):
			return _invalid("v1.2 地区 ID、名称或位置无效。")
		destination["rect"] = positions[destination.slot]
		var bounds := rect(destination.rect) # 完整相框同时也是交互矩形。
		if not paper.encloses(bounds) or bounds.size != Vector2(data.card.rect_size[0], data.card.rect_size[1]):
			return _invalid("v1.2 卡片越界或尺寸不一致。")
		for previous: Rect2 in used: # 配置新增地区时避免遮挡已有入口。
			if previous.intersects(bounds):
				return _invalid("v1.2 卡片位置重叠。")
		used.append(bounds)
		ids[destination.id] = true
		assets.append_array([destination.get("preview"), destination.get("frame")])
		if destination.has("states_prefix"):
			for state: String in ["normal", "hover", "pressed"]: # normal 即便透明也必须存在。
				assets.append(str(destination.states_prefix) + state + ".png")
		if destination.has("disabled_overlay"):
			assets.append(destination.disabled_overlay)
	if not ids.has("zombie_island") or not ids.has("town"):
		return _invalid("v1.2 必需地区配置缺失。")
	for asset: Variant in assets: # 全部限定在包内，不允许外部脚本或任意资源路径。
		if not asset is String or not asset.begins_with("art/") or ".." in asset \
			or not asset.ends_with(".png") or not ResourceLoader.exists(ROOT + asset, "Texture2D"):
			return _invalid("v1.2 资源缺失或路径无效：%s" % str(asset))
		var path: String = ROOT + asset # 与展示校验共用权威清单，只移交去重后的路径。
		if not resource_paths.has(path):
			resource_paths.append(path)
	return data

## [param destination] 必须同时在配置中开放、已实现且动作契约匹配。
static func can_enter(destination: Dictionary) -> bool:
	return destination.get("enabled", false) == true and ROUTES.has(destination.get("id")) \
		and ROUTES[destination.id] == destination.get("selection_action")

## 将 [param values] 的四项设计坐标转换为矩形；调用前由加载器验证结构。
static func rect(values: Array) -> Rect2:
	return Rect2(values[0], values[1], values[2], values[3])

## [param value] 必须包含 [param count] 项数字；用于拒绝损坏的布局数据。
func _numbers(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	for number: Variant in value: # JSON 数值允许整数或浮点。
		if not number is float and not number is int:
			return false
	return true

## 保存 [param message] 并返回空目录，让错误界面仍可关闭。
func _invalid(message: String) -> Dictionary:
	error_message = message
	return {}
