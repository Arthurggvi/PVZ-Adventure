extends CanvasLayer
## 菜单独有档案/帮助/退出窗口；业务档案仍由原User和SaveService负责。
## 退出确认通过宿主处理，不在UI中直接销毁游戏树。
signal exit_confirmed
## 原有完整档案选择器。
const Selector=preload("res://scenes/ui/profile_selector.tscn")
## 已有纸面和木框素材。
const Art=preload("res://scripts/adventure/ui/inventory_skin.gd")
## 与游戏一致的中文字体。
const FONT=preload("res://assets/fonts/方正少儿_GBK.ttf")
## 全屏阻挡和既有选择器，不重复实现保存事务。
var surface: Control
var selector: Control
var panel: Panel
var message: Label
var confirm: Button
## 当前小窗口类型，空值表示没有帮助/退出窗口。
var mode := ""

func _ready() -> void:
	layer=65
	surface=Control.new()
	add_child(surface)
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new() # 顶层全屏GUI阻挡，档案菜单没有穿透区。
	shade.color=Color(0,0,0,.55)
	surface.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	selector=Selector.instantiate()
	surface.add_child(selector)
	selector.visibility_changed.connect(_sync)
	panel=Panel.new()
	surface.add_child(panel)
	panel.size=Vector2(660,390)
	panel.add_theme_stylebox_override("panel",Art.texture_style("panels/outer_frame_ninepatch.png",31))
	Art.panel(panel,"panels/parchment_ninepatch.png",Vector2(25,25),Vector2(610,340),20)
	message=Label.new()
	message.position=Vector2(48,42)
	message.size=Vector2(564,252)
	message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_override("font",FONT)
	message.add_theme_font_size_override("font_size",23)
	message.add_theme_color_override("font_color",Color("3b2d1e"))
	panel.add_child(message)
	confirm=Art.action_button(panel,"确认退出","buttons/action_neutral",Vector2(343,307),Vector2(250,50),func():exit_confirmed.emit())
	confirm.name="ConfirmExit"
	var close := Art.action_button(panel,"返回","buttons/action_neutral",Vector2(65,307),Vector2(250,50),close_panel) # 不执行存档副作用。
	close.name="Close"
	panel.hide()
	surface.resized.connect(_fit)
	_fit()
	_sync()

## 返回当前顶层状态，供工具栏和建筑输入同源阻断。
func is_open() -> bool:
	return is_instance_valid(selector) and (selector.visible or not mode.is_empty())

## 打开原有档案流程；不创建、修改或切换任何档案，直到用户实际操作。
func open_profiles() -> void:
	if is_open():
		return
	selector.show()
	_sync()

## [param kind] 为help或exit；文本与按钮依模式配置，不改变功能解锁。
func open_panel(kind: String) -> void:
	if is_open():
		return
	mode=kind
	message.text="操作帮助\n\n鼠标移到建筑上查看名称与状态，左键点击进入。\n图书馆：图鉴；研究室：合成、强化、转职；港口：地图。\n左上角可切换存档，右下工具栏可打开已有功能。\n未解锁入口会显示条件；家园与商店尚未开放。" if kind=="help" else "退出游戏\n\n退出前会保存当前已成功加载的档案。\n保存失败时将留在菜单，不会覆盖无效档案。"
	confirm.visible=kind=="exit"
	panel.show()
	_sync()

## 仅关闭当前小窗口；原档案选择器由自己的确认/取消事务关闭。
func close_panel() -> void:
	mode=""
	panel.hide()
	_sync()

## [param text] 让保存失败明确可见，不自动退出或写空档。
func show_error(text: String) -> void:
	message.text="无法退出\n\n"+text
	confirm.hide()

func _fit() -> void:
	if panel!=null:
		panel.position=(surface.size-panel.size)*.5

func _sync() -> void:
	surface.visible=is_open()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_open():
		if not mode.is_empty():
			close_panel()
		elif selector.visible:
			selector._on_button_cancel_pressed() # 原选择器保持未选择档案时的拒绝逻辑。
		get_viewport().set_input_as_handled()
