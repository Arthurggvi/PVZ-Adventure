## 图鉴目录；角色头像只按可见范围装配，Buff 使用无资源依赖的符号卡。
extends Control

## 选择条目时通知宿主；编号 0 保留给空目录。
signal selected(type_id: int)
## 复用羊皮纸界面的文字与卡面素材。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 统一选择按钮与节点清理。
const Style = preload("res://scripts/adventure/ui/almanac_style.gd")
## 目录接受滚轮和直接滑动，排版前更新原生滚动范围。
const ContentScroll = preload("res://scripts/ui/content_scroll.gd")
## 无战斗行为的角色缩略图。
const Preview = preload("res://scripts/adventure/ui/almanac_preview.gd")
## Boss 头像读取沿用原独立目录。
const BossData = preload("res://scripts/adventure/ui/boss_almanac_data.gd")
## 三列头像卡的尺寸，预留滚动条后仍能放下三列。
const TILE_SIZE: Vector2 = Vector2(121, 140)
## Boss 四列卡片共用一行，给下方轶事留出空间。
const BOSS_TILE_SIZE: Vector2 = Vector2(90, 140)
## 当前目录类别决定头像呈现方式。
var _kind: String = "plant"
## 只在此范围内请求尚未装配的头像。
var _scroll: ScrollContainer
## 按目录顺序排列卡片。
var _grid: GridContainer
## 空目录或搜索无结果时显示状态。
var _empty: Label
## 目录底部的收录数量。
var _count: Label
## 按稳定编号索引的当前目录按钮。
var _tiles: Dictionary[int, Button] = {}
## 已处理头像的编号；失败项也登记，避免逐帧重复请求。
var _drawn: Dictionary[int, bool] = {}
## 头像容器与稳定按钮分开；滚出邻近区域即可释放视觉节点。
var _portraits: Dictionary[int, Control] = {}

## 建立固定目录区域；条目数据由宿主稍后传入。
func _ready() -> void:
	size = Vector2(397, 500)
	_scroll = ContentScroll.new()
	_scroll.size = Vector2(397, 462)
	add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 9)
	_grid.add_theme_constant_override("v_separation", 9)
	_scroll.add_child(_grid)
	_empty = Art.label(self, "", Vector2(0, 164), Vector2(397, 60), 24, Color("796347"))
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count = Art.label(self, "", Vector2(5, 470), Vector2(385, 38), 20, Color("6a5035"))

## 用 [param entries] 重建 [param kind] 的目录；[param search] 只影响空状态与计数文案，不修改玩家记录。
func rebuild(entries: Array[Dictionary], kind: String, search: String) -> void:
	Style.clear(_grid)
	_kind = kind
	_tiles.clear()
	_drawn.clear()
	_portraits.clear()
	var boss_directory: bool = kind == "boss" # Boss 目录在轶事卡上方只占一行。
	var tile_size: Vector2 = BOSS_TILE_SIZE if boss_directory else TILE_SIZE # 名称区与卡片共用宽度。
	_grid.columns = 4 if boss_directory else 3
	_count.text = ("已收录 %d 项效果" if kind == "buff" else "已收录 %d 种") % entries.size()
	if not search.strip_edges().is_empty():
		_count.text = "%d 项结果" % entries.size()
	for entry: Dictionary in entries: # 仅为当前筛选结果创建按钮，不同步加载角色。
		var type_id: int = int(entry.type_id) # 完整目录中的稳定编号不随搜索变化。
		var title: String = str(entry.title) # 长名称仍可通过悬停与辅助功能读取。
		var button: Button = Style.selection_button(_grid, "", "slots/plant_slot", selected.emit.bind(type_id)) # 卡面和名称共用点击目标。
		button.mouse_filter = Control.MOUSE_FILTER_PASS # 从卡片开始滑动时交由目录接管。
		button.custom_minimum_size = tile_size
		button.tooltip_text = title
		button.accessibility_name = title
		var caption: Label = Art.label(button, str(entry.get("caption", title)), Vector2(10, 102), Vector2(tile_size.x - 20, 26), 18) # 名称在卡片底部居中。
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_tiles[type_id] = button
		if kind == "buff":
			_draw_buff_tile(button, entry)
			_drawn[type_id] = true
	# 新卡片全部挂载后再更新视口，分类变化时据新目录计算范围。
	_scroll.size.y = 150 if boss_directory else 462
	_scroll.queue_sort()
	_empty.position.y = (_scroll.size.y - _empty.size.y) * 0.5
	_empty.visible = entries.is_empty()
	_empty.text = "暂无条目" if search.strip_edges().is_empty() else "无匹配结果"

## 返回当前目录是否包含 [param type_id]，阻止失效的按钮选择影响详情。
func has_type(type_id: int) -> bool:
	return _tiles.has(type_id)

## 高亮 [param type_id]；空目录传入 0 时所有卡片均取消选中。
func set_selected(type_id: int) -> void:
	for candidate: int in _tiles: # 保留按钮节点与键盘焦点。
		_tiles[candidate].set_pressed_no_signal(candidate == type_id)

## 分类或搜索改变时回到目录起点。
func reset_scroll() -> void:
	_scroll.scroll_vertical = 0

## 返回首个可见且尚未处理的头像编号；0 表示当前视口已准备完成。
func next_portrait_id() -> int:
	var bounds: Rect2 = _scroll.get_global_rect() # 视口外头像不创建资源请求。
	var retain: Rect2 = bounds.grow(140.0 * _scroll.get_global_transform_with_canvas().get_scale().y) # 留一行避免抖动。
	for id: int in _portraits.keys():
		if not retain.intersects(_tiles[id].get_global_rect()):
			_portraits[id].queue_free()
			_portraits.erase(id)
			_drawn.erase(id)
	for type_id: int in _tiles: # 每次只交付一个候选，由宿主限制每帧装配次数。
		if not _drawn.has(type_id) and bounds.intersects(_tiles[type_id].get_global_rect()):
			return type_id
	return 0

## 在 [param type_id] 卡片中装配已准备头像；[param loaded] 为 false 时保留名称并继续其他条目。
func draw_portrait(type_id: int, loaded: bool) -> void:
	if not _tiles.has(type_id):
		return
	_drawn[type_id] = true
	if not loaded or _kind == "buff":
		return
	var button: Button = _tiles[type_id]
	# 独立可释放容器不改变按钮、文字、焦点及点击范围。
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(holder)
	_portraits[type_id] = holder
	if _kind != "boss":
		Preview.draw_thumbnail(holder, _kind, type_id, Rect2(15, 13, 91, 86))
		return
	var texture: Texture2D = BossData.portrait(type_id) # 只读小头像，不实例化战斗根。
	if texture == null:
		return
	var portrait: TextureRect = TextureRect.new() # Boss 资源只在其头像进入视口后读取。
	portrait.texture = texture
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(portrait)
	portrait.position = Vector2(6, 13)
	portrait.size = Vector2(BOSS_TILE_SIZE.x - 12, 86)

## 根据 [param entry] 的强调色、符号与类别绘制 [param button]；不创建角色或战斗对象。
func _draw_buff_tile(button: Button, entry: Dictionary) -> void:
	var accent: Color = entry.get("color", Color("7c7147")) # 每种状态沿用目录自己的视觉识别色。
	var card: Panel = Panel.new() # 浅色底保证符号在木质按钮上清晰可读。
	var surface: StyleBoxFlat = StyleBoxFlat.new() # 纯色样式不引入任何额外贴图请求。
	surface.bg_color = accent.lightened(0.68)
	surface.border_color = accent.darkened(0.18)
	surface.set_border_width_all(2)
	surface.set_corner_radius_all(12)
	card.add_theme_stylebox_override("panel", surface)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(card)
	card.position = Vector2(29, 13)
	card.size = Vector2(63, 57)
	var symbol: Label = Art.label(button, str(entry.get("symbol", "效")), Vector2(15, 14), Vector2(91, 55), 34, accent.darkened(0.4)) # 使用文字符号，不依赖角色图集。
	symbol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	symbol.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var category: Label = Art.label(button, str(entry.get("category", "状态")), Vector2(8, 77), Vector2(105, 22), 15, Color("654b30")) # 分类作为短标签帮助区分同类效果。
	category.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	category.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.tooltip_text = "%s · %s" % [str(entry.title), str(entry.get("category", "状态"))]
