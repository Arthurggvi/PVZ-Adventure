## 明灯双形态本体；原画右缘在视窗外，待机、眨眼及平移共用同一锚点。
extends Node2D
class_name MingLanternVisual

## 二阶段星空图集。前两行为原画，后两行为对应的发光遮罩。
const STAR_ATLAS: Texture2D = preload("res://assets/adventure/zombies/ming_lantern/open_atlas.png")
## 黑暗版使用素材包内带原始渐变的透明 PNG 帧。
const DARK_ATLAS: Texture2D = preload("res://assets/adventure/zombies/ming_lantern/dark_atlas.png")
## 星空图集每个格子的像素尺寸。
const STAR_TILE := Vector2i(442, 452)
## 黑暗形态图集每个格子的像素尺寸。
const DARK_TILE := Vector2i(319, 860)
## 两套眼睑各六帧；完全闭眼帧停留略长，方便看清施法时点。
const STAR_BLINK := [0.095, 0.11, 0.085, 0.14, 0.12, 0.14]
## 黑暗形态保持更重的闭合和更慢的回睁。
const DARK_BLINK := [0.11, 0.12, 0.11, 0.15, 0.145, 0.15]
## 星空原画中眼睑上方的像素行。从此处向上延展额头。
const STAR_EYE_TOP := 178
## 星空原画中眼睑下方的像素行。从此处向下延展身体。
const STAR_EYE_BOTTOM := 380
## 分段近似平滑延展曲线，眼睑两端之间只绘制一个完整区块。
const STAR_ROWS := [0, 44, 88, 132, STAR_EYE_TOP, STAR_EYE_BOTTOM, 404, 428, STAR_TILE.y]

## 本体当前显示的阶段。一阶段为黑暗形态，二阶段为星空形态。
var displayed_phase := 1
## 当前演出脉冲额外光量，由入场和撤退时间轴驱动。
var flare := 0.0
## 本体呼吸相位，单位秒。
var _clock := 0.0
## 眨眼帧索引，0 为睁眼待机。
var _frame := 0
## 留在当前眼睑姿势的时长，-1 为待机。
var _blink_left := -1.0
## 与原画分开合成的光缘、溢光及海面反射。
var _light: Node2D

## 建立明暗分离的画布层。
func _ready() -> void:
	_light = MingLanternArt.light_layer(self, _draw_light)

## 显示 [param phase] 对应的形态并复位眼睑，保留演出位置。
func set_phase(phase: int) -> void:
	displayed_phase = phase
	_frame = 0
	_blink_left = -1.0
	queue_redraw()
	if is_instance_valid(_light):
		_light.queue_redraw()

## 播放一次当前形态的六帧眨眼。
func blink() -> void:
	_frame = 0
	_blink_left = float(DARK_BLINK[0] if displayed_phase == 1 else STAR_BLINK[0])

## 本体呼吸和眨眼使用的行动倍率；图鉴以原速播放。
var action_rate := 1.0

## [param delta] 为战斗秒数，随舞台暂停停止。
func _process(delta: float) -> void:
	var step: float = delta * action_rate # 本体帧和演出关键帧保持同步。
	_clock = fposmod(_clock + step, 120.0)
	if _blink_left >= 0.0:
		_blink_left -= step
		while _blink_left <= 0.0:
			_frame += 1
			if _frame == STAR_BLINK.size():
				_frame = 0
				_blink_left = -1.0
				break
			_blink_left += float(DARK_BLINK[_frame] if displayed_phase == 1 else STAR_BLINK[_frame])
	queue_redraw()
	_light.queue_redraw()

## 返回延展前的呼吸姿态，眼睛始终以本体原点附近为锚。
func _body_rect() -> Rect2:
	var breath: float = sin(_clock * TAU / 4.8) # 从边缘展开，右边的截面留在屏幕外。
	var dark: bool = displayed_phase == 1 # 黑暗与星空原画以各自的眼睑位置对齐。
	var size := Vector2(223.0, 600.0) if dark else Vector2(302.0, 309.0) # 保持各自图集比例。
	size *= Vector2(1.0 + breath * 0.025, 1.0 + breath * 0.017)
	return Rect2(Vector2(-size.x, -size.y * (0.603 if dark else 0.645)), size)

## 返回当前帧的图集区块；[param emission] 取对应的发光区块。
func _region(emission: bool) -> Rect2:
	var size: Vector2i = DARK_TILE if displayed_phase == 1 else STAR_TILE # 当前形态在图集中的格距。
	var row: int = (1 if _frame >= 3 else 0) + (2 if emission else 0) # 六帧每三帧换行。
	return Rect2(Vector2(size * Vector2i(_frame % 3, row)), Vector2(size))

## 在 [param canvas] 绘制当前帧，[param emission] 选择发光遮罩，[param tint] 控制亮度。
## 星空版将眼睑上下延展到当前视口边缘外，保持星空眼睛的比例。
func _draw_form(canvas: Node2D, emission: bool, tint: Color) -> void:
	var body: Rect2 = _body_rect() # 未延展的眼睛比例和呼吸偏移。
	var source: Rect2 = _region(emission) # 当前帧原画或遮罩所在的像素矩形。
	if displayed_phase == 1:
		canvas.draw_texture_rect_region(DARK_ATLAS, body, source, tint)
		return
	var screen: Rect2 = get_viewport_rect() # 主战场和图鉴分别以自己的视口取景。
	var local: Transform2D = get_global_transform_with_canvas().affine_inverse() # 同时考虑相机缩放和镜头位置。
	var top: float = (local * screen.position).y # 画面顶部在角色局部坐标中的高度。
	var bottom: float = (local * screen.end).y # 画面底部在角色局部坐标中的高度。
	var margin: float = (bottom - top) * 0.06 # 留出出血，让震屏期间也看不到裁边。
	var extra := Vector2(maxf(0.0, body.position.y - top + margin),
		maxf(0.0, bottom + margin - body.end.y)) # 原画上端和下端各需补足的高度。
	var previous_y: float = body.position.y - extra.x # 从已覆盖视口的上端开始拼接。
	for band: int in range(STAR_ROWS.size() - 1): # 原画与发光遮罩共用相同的连续区块。
		var first: int = STAR_ROWS[band] # 本区块的起始像素行。
		var last: int = STAR_ROWS[band + 1] # 与下一区块共享的结束边界。
		var next_y: float = _star_row_y(last, body, extra) # 相同边界使用同一个结果。
		var target := Rect2(body.position.x, previous_y, body.size.x, next_y - previous_y) # 只改变纵向尺寸。
		var patch := Rect2(source.position + Vector2(1, first), Vector2(source.size.x - 2.0, last - first)) # 两边留一个像素，纵向插值不会串到相邻帧。
		canvas.draw_texture_rect_region(STAR_ATLAS, target, patch, tint, false, false)
		previous_y = next_y

## 将星空图集中的 [param row] 映射到 [param body] 内，[param extra] 是眼睑之外的额外高度。
func _star_row_y(row: int, body: Rect2, extra: Vector2) -> float:
	var y: float = body.position.y + body.size.y * float(row) / STAR_TILE.y # 两个眼睑边界之间保持原画比例。
	if row < STAR_EYE_TOP:
		y -= extra.x * pow(1.0 - float(row) / STAR_EYE_TOP, 1.7)
	elif row > STAR_EYE_BOTTOM:
		y += extra.y * pow(float(row - STAR_EYE_BOTTOM) / (STAR_TILE.y - STAR_EYE_BOTTOM), 1.7)
	return y

## 缓慢呼吸同时压暗原画的暗部，黑暗形态保留纯黑眼心。
func _draw() -> void:
	var breath: float = 0.5 + 0.5 * sin(_clock * TAU / 4.8) # 连续的 0 至 1 呼吸亮度。
	var dark: bool = displayed_phase == 1 # 两种原画使用不同的呼吸明暗曲线。
	var dim: float = (0.32 + 0.65 * pow(breath, 1.5)) if dark else (0.47 + 0.50 * breath) # 呼气时原画退入深水，仍留有眼睑亮边。
	_draw_form(self, false, Color(dim, dim, minf(1.0, dim + 0.075), 1.0))

## 返回眼光强度，将呼吸、眨眼与演出闪光用于原画和实际照明。
func _eye_intensity() -> float:
	var breath: float = 0.5 + 0.5 * sin(_clock * TAU / 4.8) # 亮纹和海面反射使用相同相位。
	var shut: float = [1.0, 0.82, 0.49, 0.23, 0.60, 1.0][_frame] # 闭眼时减弱眼周体积光。
	return minf(1.55, (0.58 + 0.45 * breath) * shut + flare)

## 在 [param lighting] 写入本体投向近处战场的光。退到画面外时自然失去覆盖范围。
func draw_scene_light(lighting: MingLanternLighting) -> void:
	var dark: bool = displayed_phase == 1 # 黑暗和星空的水下投光保留不同主色。
	var tint := Color("917aff") if dark else Color("50bcff") # 岩面与水面接收较原画稍冷的光。
	var eye := Vector2(-160.0 if dark else -97.0, 18.0) # 黑暗版的亮度来自左眼缘。
	lighting.cast(self, eye, Vector2(258.0, 283.0), tint, _eye_intensity() * (0.26 if dark else 0.34))

## 在 [param canvas] 叠加原画亮纹、眼周软光与受海面切开的反射。
func _draw_light(canvas: Node2D) -> void:
	var dark: bool = displayed_phase == 1 # 描边与眼周溢光跟随当前形态。
	var tint: Color = MingLanternArt.VIOLET if dark else MingLanternArt.CYAN # 裂纹与灯条使用有区别的光色。
	var intensity: float = _eye_intensity() # 表面受光与眼本身的亮度同步。
	var eye := Vector2(-178.0 if dark else -96.0, 0.0) # 星空亮光停在眼周，黑暗版偏左保留纯黑眼心。
	MingLanternArt.glow(canvas, eye, Vector2(430, 345), Color(tint, intensity * (0.29 if dark else 0.50)))
	MingLanternArt.glow(canvas, Vector2(-146, 150), Vector2(560, 242), Color(tint, intensity * 0.25))
	_draw_form(canvas, true, Color(tint.lerp(Color.WHITE, 0.49), minf(1.0, 0.34 + intensity * 0.64)))
	for index: int in range(8): # 分层波纹长度逐渐缩短，形成破碎水面倒光。
		var phase: float = _clock * (0.78 + float(index) * 0.08) + float(index) * 1.68 # 各层不同步滑移。
		var point := Vector2(-154.0 - float(index) * 11.0 + sin(phase) * 26.0,
			91.0 + 16.0 * float(index) + sin(phase * 1.19) * 3.5) # 落在本体眼睛以下的地面。
		var size := Vector2(318.0 - 20.0 * float(index), 10.0 + float(index % 3) * 5.0) # 远离光源后见到短碎纹。
		var opacity: float = intensity * (0.050 + 0.034 * sin(phase + 1.0)) # 背景与棋盘线仍可辨认。
		MingLanternArt.glow(canvas, point, size, Color(tint.lerp(Color.WHITE, 0.32), opacity))
