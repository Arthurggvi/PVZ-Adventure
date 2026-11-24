## 关卡预览的固定标题与原生滚动视口，不持有悬停状态或战斗数据来源。
extends Control

## 通用文字绘制沿用现有预览样式。
const Art = preload("res://scripts/adventure/ui/stage_preview_art.gd")
## 视口保留滚轮和触摸共用的滚动范围。
const ContentScroll = preload("res://scripts/ui/content_scroll.gd")
## 所有可滚动内容由同一个展示组件构造。
const Content = preload("res://scripts/adventure/ui/stage_preview_content.gd")
## 面板四周留白，单位为地图设计像素。
const PADDING := 24.0
## 标题、类型、通关提示均保留在滚动区外。
const HEADER_HEIGHT := 150.0
## 底部固定滚动说明占用的高度。
const FOOTER_HEIGHT := 36.0

## 当前关卡标题。
var _title: Label
## 根据关卡权威配置显示的类型。
var _type: Label
## 通关与触摸进入提示。
var _status: Label
## 未开放地区的短介绍。
var _description: Label
## 内容与标题间的分隔线。
var _divider: ColorRect
## 原生容器统一处理滚轮、滚动条、触摸与键盘滚动。
var _scroll: ContentScroll
## 本次展示的配方摘要与阶段详情。
var _content: VBoxContainer
## 可发现的操作提示，短介绍模式隐藏。
var _hint: Label

## 创建一次固定骨架，后续请求只更新内容。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = Art.text(self, "", Rect2(24, 16, 592, 50), 40, Color("ffe8b0"), HORIZONTAL_ALIGNMENT_LEFT, true)
	_type = Art.text(self, "", Rect2(24, 68, 592, 30), 24, Color("e8ca85"))
	_status = Art.text(self, "", Rect2(24, 104, 592, 28), 22, Color("b9c9bf"))
	_description = Art.text(self, "", Rect2(24, 118, 592, 160), 26, Color("f2f6ee"))
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_divider = ColorRect.new()
	_divider.color = Color(0.78, 0.68, 0.44, 0.45)
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_divider)
	_scroll = ContentScroll.new()
	_scroll.name = "ManualScroll"
	_scroll.mouse_force_pass_scroll_events = false
	_scroll.scroll_deadzone = 8
	_scroll.scroll_vertical_custom_step = 64.0
	_scroll.focus_mode = Control.FOCUS_ALL
	_scroll.add_theme_constant_override("scrollbar_h_separation", 8)
	_scroll.style_vertical_bar(Color("263b31"), Color("bea36a"), Color("f0cf83"), 24)
	_scroll.get_v_scroll_bar().mouse_force_pass_scroll_events = false
	add_child(_scroll)
	_content = Content.new()
	_scroll.add_child(_content)
	_hint = Art.text(self, "", Rect2(24, 0, 592, 26), 20, Color("b9c9bf"), HORIZONTAL_ALIGNMENT_CENTER)
	_hint.text = "上下滑动查看关卡情报" if OS.has_feature("android") else "滚轮或拖动右侧滚动条查看情报"

## 用 [param data] 更新内容；[param panel_size] 与外层面板保持一致，仅切换关卡时归顶。
func show_data(data: Dictionary, panel_size: Vector2) -> void:
	size = panel_size
	var region: bool = data.get("state") == "region" # 地区模式沿用原来的紧凑标题布局。
	_title.text = str(data.get("title", ""))
	_type.text = "关卡类型：%s" % str(data.get("type_text", ""))
	_type.visible = not region
	_status.text = str(data.get("subtitle", "地区情报 · 战斗暂未开放" if region else "普通阶段已通关"))
	_status.position.y = 68.0 if region else 104.0
	_description.text = str(data.get("description", ""))
	_description.visible = region
	_divider.position = Vector2(PADDING, 106.0 if region else HEADER_HEIGHT - 10.0)
	_divider.size = Vector2(size.x - PADDING * 2.0, 1.0)
	_scroll.visible = not region
	_hint.visible = not region
	_scroll.position = Vector2(PADDING, HEADER_HEIGHT)
	_scroll.size = Vector2(size.x - PADDING * 2.0, size.y - HEADER_HEIGHT - PADDING - FOOTER_HEIGHT)
	_hint.position.y = size.y - PADDING - 24.0
	_content.rebuild(data)
	_scroll.scroll_vertical = 0
