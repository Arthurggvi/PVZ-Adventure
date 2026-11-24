## 星章公共视图：1～4 星静态；5～10 星 CPU 预烘焙动画，运行时零自定义 Shader。
## 31×31 根节点与外部 configure(rank) 保持不变，45×45 内容允许越界绘制光环。
extends Control

const Art = preload("res://scripts/adventure/ui/star_badge_art.gd")
const CORNER_SIZE: Vector2 = Vector2(31, 31)
const CORNER_OFFSET: Vector2 = Vector2(-3, -4)
const FX_BOUNDS: Vector2 = Vector2(45, 45)
## 动画内的主体位置和原星章坐标一致，十星光环只向外延伸七像素。
const FX_ORIGIN: Vector2 = (CORNER_SIZE - FX_BOUNDS) * 0.5

## 始终保留的静态素材，由禁用特效选项和资源回退使用。
var _body: TextureRect
## 高星图集使用原生 AtlasTexture.region 切帧，不上传每帧像素。
var _animated: TextureRect
## 本控件独占图集区域游标，而 GPU 图集纹理仍按星级共享。
var _region: AtlasTexture
## 纯数据的非均匀采样时间轴，避免细短扫光动作被低帧率吞掉。
var _times: Array = []
## 当前卡片唯一星级；存档模型不在表现层发生任何变更。
var _rank: int = 0
var _columns: int = 1
var _tile_size: int = 64
var _gutter: int = 2
var _inner: int = 60
var _period: float = 8.0
var _last_frame: int = -1

## 保留卡牌、背包和植物根部都依赖的原始 31px 布局。
func _init() -> void:
	name = "AdventureStarBadge"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = CORNER_SIZE
	position = CORNER_OFFSET
	z_index = 4
	_body = _texture_rect("Body", Vector2.ZERO, CORNER_SIZE)
	_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_animated = _texture_rect("BakedAnimation", FX_ORIGIN, FX_BOUNDS)
	_animated.hide()
	set_process(false)

## 唯一在此组件内部创建的图形节点都是普通 TextureRect。
func _texture_rect(label: String, origin: Vector2, dimensions: Vector2) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = label
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.position = origin
	rect.size = dimensions
	add_child(rect)
	return rect

## 响应现有设置服务的即时兼容开关；没有 Shader 释放或驱动状态切换。
func _ready() -> void:
	if is_instance_valid(Global.config_service):
		Global.config_service.optional_rendering_changed.connect(_on_compatibility_changed)
	_apply_display_mode()

## 继续接受既有唯一参数 [param rank]，不修改任何研究、存档与战斗接口。
func configure(rank: int) -> void:
	_rank = clampi(rank, 0, 10)
	visible = _rank > 0
	if not visible:
		set_process(false)
		return
	_body.texture = Art.body(_rank)
	if _body.texture == null:
		push_warning("Missing adventure star badge texture for rank %d" % _rank)
		visible = false
		set_process(false)
		return
	_apply_display_mode()

## 禁用可选渲染时使用 31px 原图；否则使用完全不含 Shader 的图集。
func _apply_display_mode() -> void:
	_animated.hide()
	_animated.texture = null
	_region = null
	_times = [] # 解除当前引用，保留清单里供同星级共用的时间表。
	_last_frame = -1
	_body.show()
	set_process(false)
	if _rank < 5 or _body.texture == null:
		return
	if is_instance_valid(Global.config_service) \
			and Global.config_service.optional_rendering_disabled:
		return
	var info: Dictionary = Art.animation_info(_rank)
	var baked: Texture2D = Art.atlas(_rank)
	if info.is_empty() or baked == null:
		return # 资源缺失时始终保持可读的静态数字，而不是崩溃。
	_columns = int(info.columns)
	_tile_size = int(info.tile)
	_gutter = int(info.gutter)
	_inner = int(info.inner)
	_period = float(info.period)
	_times = info.times
	_region = AtlasTexture.new()
	_region.atlas = baked
	_animated.texture = _region
	_animated.show()
	_body.hide()
	_update_frame()
	set_process(true)

## 所有星章共用单调钟相位；暂停前后台也不会出现长时跳帧计算。
func _process(_delta: float) -> void:
	if is_visible_in_tree():
		_update_frame()

## 对非均匀时间轴二分定位，仅在实际切换帧时改 AtlasTexture.region。
func _update_frame() -> void:
	if _region == null or _times.is_empty():
		return
	var phase: float = fposmod(float(Time.get_ticks_msec()) * 0.001, _period)
	var frame: int = maxi(0, _times.bsearch(phase, false) - 1)
	if frame == _last_frame:
		return
	_last_frame = frame
	var col: int = frame % _columns
	var row: int = frame / _columns
	_region.region = Rect2(col * _tile_size + _gutter, row * _tile_size + _gutter,
		_inner, _inner)

## 当用户调整渲染兼容选项后，仅更新可见表现，不触及卡牌数据。
func _on_compatibility_changed(_disabled: bool) -> void:
	_apply_display_mode()
