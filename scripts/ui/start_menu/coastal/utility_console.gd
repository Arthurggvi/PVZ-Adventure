extends Control
## 复用已批准功能台贴图，真实按钮独立于背景受光与建筑命中。
## 宿主统一处理动作/阻塞，不在表现层创建业务窗口。
signal action_requested(action: String)
## 保留的已有状态贴图目录。
const ART := "res://assets/adventure/main_menu/v8/art/ui/"
## 场景中使用的原中文字体。
const FONT=preload("res://assets/fonts/方正少儿_GBK.ttf")
## 当前按钮，便于禁用及原生键盘操作。
var buttons: Dictionary={}

## [param layout] 使用功能台设计像素，缩放由同一个场景画布决定。
func configure(layout: Dictionary) -> void:
	position=Vector2(layout.console_origin[0],layout.console_origin[1])
	scale=Vector2.ONE*float(layout.console_scale)
	size=Vector2(538,128)
	mouse_filter=Control.MOUSE_FILTER_STOP
	var body := TextureRect.new() # 原木制外壳只显示，不吞掉真实按钮。
	body.texture=load(ART+"utility_console_body.png")
	body.size=size
	body.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	body.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(body)
	for entry: Dictionary in layout.console_buttons: # 名称、图像、坐标都来自布局配置。
		var button := TextureButton.new() # 与原功能台相同的三态按钮。
		button.name=entry.id
		button.ignore_texture_size=true
		button.stretch_mode=TextureButton.STRETCH_SCALE
		button.position=Vector2(entry.rect[0],entry.rect[1])
		button.size=Vector2(entry.rect[2],entry.rect[3])
		button.texture_normal=load(ART+entry.art+"_blank.png")
		button.texture_hover=load(ART+entry.art+"_hover.png")
		button.texture_pressed=load(ART+entry.art+"_pressed.png")
		button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
		button.pressed.connect(func():action_requested.emit(entry.id))
		add_child(button)
		var caption := Label.new() # 文字随按钮移动和遮挡，不参与背景高亮。
		caption.text=entry.caption
		caption.size=button.size
		caption.position.y=10
		caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		caption.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
		caption.add_theme_font_override("font",FONT)
		caption.add_theme_font_size_override("font_size",30)
		caption.add_theme_color_override("font_color",Color(.95,.81,.55))
		caption.add_theme_color_override("font_outline_color",Color(.1,.06,.02))
		caption.add_theme_constant_override("outline_size",5)
		button.add_child(caption)
		buttons[entry.id]=button
