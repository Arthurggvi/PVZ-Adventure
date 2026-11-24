## 原图集分页驻留；原生 AnimatedSprite2D 仍决定帧序、帧时长、倍速和信号。
## 只替换 AtlasTexture 的底图引用，不改帧矩形、像素或动作时间。
extends AnimatedSprite2D

const Batch := preload("res://scripts/ui/transitions/resource_load_batch.gd")
const PAGE_PATH := "res://assets/adventure/zombies/cailleach/phase2_slow/cailleach_phase2_idle_slow_page_%02d.webp"
const PAGE_COUNT := 5
const FRAMES_PER_PAGE := 12
## 当前实例的占位几何与实际页；不修改共享 SpriteFrames 资源。
var _geometry: PlaceholderTexture2D
var _pages: Dictionary[int, Texture2D] = {}
var _active_page := -1
var _pending_page := -1
var _batch: RefCounted
var _fallback_count := 0

func _ready() -> void:
	var source: SpriteFrames = sprite_frames
	var local := SpriteFrames.new()
	local.add_animation(&"idle")
	local.set_animation_speed(&"idle", source.get_animation_speed(&"idle"))
	local.set_animation_loop(&"idle", source.get_animation_loop(&"idle"))
	_geometry = PlaceholderTexture2D.new()
	_geometry.size = Vector2(2508, 1880)
	for index: int in source.get_frame_count(&"idle"):
		var original: AtlasTexture = source.get_frame_texture(&"idle", index)
		var atlas := AtlasTexture.new()
		atlas.atlas = _geometry
		atlas.region = original.region
		atlas.margin = original.margin
		atlas.filter_clip = original.filter_clip
		local.add_frame(&"idle", atlas, source.get_frame_duration(&"idle", index))
	sprite_frames = local
	animation = &"idle"
	frame_changed.connect(_sync_page)
	_sync_page()

## 同页的十二帧共享同一个已导入纹理；变化不触碰 SpriteFrames 的帧表。
func _install(page: int, texture: Texture2D) -> bool:
	if texture == null or texture.get_size() != _geometry.size:
		push_error("凯莱赫二阶段图集页读取失败：" + str(page))
		return false
	_pages[page] = texture
	for index: int in range(page * FRAMES_PER_PAGE, (page + 1) * FRAMES_PER_PAGE):
		var atlas: AtlasTexture = sprite_frames.get_frame_texture(&"idle", index)
		atlas.atlas = texture
	return true

func _release(page: int) -> void:
	for index: int in range(page * FRAMES_PER_PAGE, (page + 1) * FRAMES_PER_PAGE):
		var atlas: AtlasTexture = sprite_frames.get_frame_texture(&"idle", index)
		atlas.atlas = _geometry
	_pages.erase(page)

func _next_page() -> int:
	return posmod(_active_page + (-1 if speed_scale < 0.0 else 1), PAGE_COUNT)

## 跳帧或首帧优先保证画面真实；常规播放由下一页预热避免同步读取。
func _sync_page() -> void:
	var page: int = floori(float(frame) / FRAMES_PER_PAGE)
	if page == _active_page:
		return
	_poll_pending()
	if not _pages.has(page):
		if _active_page >= 0:
			_fallback_count += 1
		if not _install(page, load(PAGE_PATH % page) as Texture2D):
			return
	_active_page = page
	_reconcile()

func _reconcile() -> void:
	if _active_page < 0:
		return
	var next: int = _next_page()
	if _batch != null and _pending_page != next:
		_cancel()
	for page: int in _pages.keys():
		if page != _active_page and page != next:
			_release(page)
	if _batch == null and not _pages.has(next):
		_batch = Batch.new()
		_pending_page = next
		if _batch.start(PackedStringArray([PAGE_PATH % next])) != OK:
			_cancel()

func _poll_pending() -> void:
	if _batch == null:
		return
	var status: int = _batch.poll()
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	if status == ResourceLoader.THREAD_LOAD_LOADED and not _pages.has(_pending_page):
		_install(_pending_page, _batch.get_resource(PAGE_PATH % _pending_page) as Texture2D)
	_batch = null
	_pending_page = -1

func _process(_delta: float) -> void:
	_poll_pending()
	_reconcile()

func _cancel() -> void:
	if _batch != null:
		_batch.abandon()
	_batch = null
	_pending_page = -1

func _exit_tree() -> void:
	_cancel()
