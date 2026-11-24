## Buff 图鉴详情；只读说明与独立演示共用同一条目，关闭时不保留任何效果实例。
extends Control

## 复用图鉴木框与按钮素材。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 效果说明接受滚轮以及直接滑动。
const ContentScroll = preload("res://scripts/ui/content_scroll.gd")
## 状态条目的唯一展示目录。
const Data = preload("res://scripts/adventure/ui/buff_almanac_data.gd")
## 沿用 Boss 档案的纸面卡片与文字层级。
const PageStyle = preload("res://scripts/adventure/ui/boss_almanac_style.gd")
## 不连接战斗或存档的状态舞台。
const Preview = preload("res://scripts/adventure/ui/buff_almanac_preview.gd")
## 由图鉴宿主传入的临时目录序号；0 不对应状态。
var type_id: int = 0
## 当前只读条目快照，避免选中项和演示内容错配。
var _entry: Dictionary = {}
## 仅存活于本详情页的演示舞台。
var _preview: Preview
## 当前条目的强调色，同时用于类别与规则标题。
var _accent: Color = Color("355c67")
## 主动停止后给出明确的播放状态。
var _playback_hint: Label

## 建立左侧可滚动说明、右侧舞台；宿主已完成当前条目的资源准备。
func _ready() -> void:
	size = Vector2(910, 640)
	_entry = Data.profile(type_id)
	if _entry.is_empty():
		PageStyle.label(self, "该效果暂无资料", Rect2(18, 18, 870, 60), 28)
		return
	_accent = _entry.get("color", Color("355c67"))
	PageStyle.label(self, str(_entry.title), Rect2(18, 0, 660, 58), 38, PageStyle.INK, false)
	var category: Label = PageStyle.label(self, str(_entry.category), Rect2(683, 17, 200, 31), 21, _accent) # 类别独立于状态名称。
	category.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	Art.panel(self, "panels/wood_ninepatch.png", Vector2(18, 67), Vector2(874, 4), 2)
	_build_description()
	PageStyle.label(self, "效果演示", Rect2(452, 83, 250, 34), 24, PageStyle.INK, false)
	_preview = Preview.new()
	_preview.position = Vector2(452, 130)
	add_child(_preview)
	Art.panel(self, "panels/outer_frame_ninepatch.png", Vector2(440, 118), Vector2(444, 354), 24)
	Art.action_button(self, "重新演示", "buttons/button", Vector2(452, 486), Vector2(195, 49), _replay)
	Art.action_button(self, "停止演示", "buttons/button", Vector2(664, 486), Vector2(195, 49), _stop)
	_playback_hint = PageStyle.label(self, "正在演示 · 数值与时长使用示例", Rect2(453, 550, 420, 32), 18, PageStyle.MUTED)
	PageStyle.label(self, "具体强度、持续时间及叠加规则请查阅左侧说明。", Rect2(453, 589, 420, 48), 18, PageStyle.MUTED)
	_preview.show_buff(_entry)

## 说明区由内容撑高；长描述、叠加规则和来源仅接受手动滚动。
func _build_description() -> void:
	var scroll := ContentScroll.new() # 演示与操作固定，正文可独立滚动。
	scroll.position = Vector2(18, 84)
	scroll.size = Vector2(404, 550)
	add_child(scroll)
	var sections: VBoxContainer = VBoxContainer.new() # 自动布局保证字体缩放与长中文不重叠。
	sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_theme_constant_override("separation", 12)
	scroll.add_child(sections)
	var overview: VBoxContainer = _section(sections, "效果说明") # 首段直接解释状态对战斗的影响。
	_text(overview, str(_entry.get("summary", "")), 22)
	var stats: Dictionary = _entry.get("stats", {}) # 数值字段按目录顺序显示，不在界面重复计算规则。
	if not stats.is_empty():
		var values: VBoxContainer = _section(sections, "关键数值") # 带单位的完整描述支持换行。
		for key: String in stats: # 不强制两列，兼容较长的持续时间与层数规则。
			_text(values, "%s：%s" % [key, str(stats[key])], 20)
	var groups: Array = _entry.get("effects", []) # 分组由目录定义，保留叠加、免疫等不同规则。
	for group: Dictionary in groups: # 一个组对应一块完整阅读卡。
		var section: VBoxContainer = _section(sections, str(group.get("title", "规则"))) # 标题不由界面推断。
		var options: Dictionary = group.get("options", {}) # 规则名称与正文分开，避免大量长句堆在一行。
		for heading: String in options: # 空名称表示只有正文的规则。
			if not heading.is_empty():
				_text(section, heading, 20, _accent)
			_text(section, str(options[heading]), 20)
	var sources: String = str(_entry.get("sources", "")).strip_edges() # 来源仅表示实例，不把技能时长误写成通用值。
	if not sources.is_empty():
		var origin: VBoxContainer = _section(sections, "常见来源") # 所有条目无需发现条件即可查阅。
		_text(origin, sources, 20)

## 在 [param parent] 添加标题为 [param title] 的纸面分组，返回正文容器。
func _section(parent: Container, title: String) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new() # 内容边距由样式统一承担。
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", PageStyle.card_style(Color(1, 0.96, 0.85, 0.55), Color(0.45, 0.31, 0.17, 0.24)))
	parent.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new() # 分组高度随正文自动增长。
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)
	_text(column, title, 23, _accent)
	return column

## 在 [param parent] 追加可换行的 [param caption]；[param font_size] 与 [param ink] 控制阅读层级。
func _text(parent: Container, caption: String, font_size: int, ink: Color = PageStyle.INK) -> Label:
	var label: Label = PageStyle.label(parent, caption, Rect2(), font_size, ink) # 标签高度交给滚动布局，禁止裁去长文字。
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

## 重播当前条目；不会改变目录选择或左侧滚动位置。
func _replay() -> void:
	if is_instance_valid(_preview):
		_preview.replay()
		_playback_hint.text = "正在演示 · 数值与时长使用示例"
		SoundManager.play_other_SFX(&"tap")

## 停止当前舞台；仍保留完整描述供用户阅读。
func _stop() -> void:
	if is_instance_valid(_preview):
		_preview.stop()
		_playback_hint.text = "演示已停止 · 点击重新演示播放"

## 在切换条目或关闭图鉴的同一帧停掉旧舞台，再由父节点统一释放。
func _exit_tree() -> void:
	if is_instance_valid(_preview):
		_preview.stop()
