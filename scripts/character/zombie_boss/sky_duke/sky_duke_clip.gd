## 苍穹公爵蓝、红两阶段共用的帧时序与图集定位数据。
extends Resource

## 素材母版的采样频率，单位为每动作秒的帧数。
const FPS := 30
## 每张图集最多容纳的帧数，按时间顺序排列。
const FRAMES_PER_PAGE := 12
## 每页从左至右排列的列数。
const COLUMNS := 4
## 各帧在块内的透明边距，防止线性采样读到邻帧。
const GUTTER := Vector2i(4, 4)

## 完整时间轴帧数，包含传送末尾的透明帧。
@export var frame_count: int
## 从第一帧起有内容的帧数，其后的透明帧不占图集。
@export var visible_frame_count: int
## 裁掉共同透明边缘后，画面在图集中的尺寸，单位为像素。
@export var region_size: Vector2i
## 图集内相邻帧左上角的间距，包含安全边距和对齐填充。
@export var tile_step: Vector2i
## 裁剪左上角相对原画共同锚点的像素偏移。
@export var draw_offset: Vector2
## 发令或人物消失的时间点，单位为动作秒；0 表示没有事件。
@export var cue_seconds: float

## 返回完整动作时长，单位为动作秒。
func duration() -> float:
	return float(frame_count) / FPS


## 按 [param elapsed] 经过的动作秒数返回零起始帧，结束时取最后一帧。
func frame_at(elapsed: float) -> int:
	return mini(floori(elapsed * FPS + 0.00001), frame_count - 1)


## 返回 [param frame_index] 所在的零起始图集页。
func page_at(frame_index: int) -> int:
	@warning_ignore("integer_division")
	return frame_index / FRAMES_PER_PAGE


## 返回可见帧 [param frame_index] 在图集页内的采样矩形，单位为像素。
func region_at(frame_index: int) -> Rect2:
	var local_index: int = frame_index % FRAMES_PER_PAGE # 页内格位，与时间轴序号分开。
	@warning_ignore("integer_division")
	var grid := Vector2i(local_index % COLUMNS, local_index / COLUMNS) # 页内列和行。
	return Rect2(grid * tile_step + GUTTER, region_size)
