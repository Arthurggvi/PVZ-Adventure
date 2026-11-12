extends CanvasLayer
## 录制标注与可见鼠标，不参与命中或窗口生命周期；实际输入另由录制器发送。
## 当前标题与可见指针。
var caption: Label
var pointer: Polygon2D
## 点击时的短色彩反馈。
var pressed := false

## 在 [param font] 下建立透明标注层，不给UI拦截鼠标。
func configure(font: Font) -> void:
	layer=200
	caption=Label.new()
	caption.position=Vector2(360,7)
	caption.size=Vector2(690,52)
	caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_override("font",font)
	caption.add_theme_font_size_override("font_size",18)
	caption.add_theme_constant_override("outline_size",4)
	caption.add_theme_color_override("font_outline_color",Color("201b17"))
	caption.add_theme_color_override("font_color",Color("fff0ce"))
	add_child(caption)
	pointer=Polygon2D.new()
	pointer.polygon=PackedVector2Array([Vector2(0,0),Vector2(2,23),Vector2(8,17),Vector2(14,27),Vector2(18,25),Vector2(12,15),Vector2(21,14)])
	pointer.color=Color("fff6d5")
	add_child(pointer)
	var edge:=Line2D.new() # 指针边线只是录像可视标记。
	edge.points=pointer.polygon+PackedVector2Array([Vector2.ZERO])
	edge.width=2
	edge.default_color=Color("2f271e")
	pointer.add_child(edge)

## [param point] 同实际注入位置；[param down] 显示按下状态，不生成输入。
func show_pointer(point: Vector2, down: bool=false) -> void:
	pointer.position=point
	pointer.color=Color("f5bd58") if down else Color("fff6d5")
