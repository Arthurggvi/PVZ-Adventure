## 管理关卡轮次、普通波次进度和屏幕底部的僵王血条。
extends Control
class_name LevelInfo

## 单个僵王的血条倍率，保留头像和装饰的辨识度。
const SINGLE_BAR_SCALE := 0.34
## 多个僵王时的最大倍率，空间不足时继续等比收缩。
const MULTI_BAR_SCALE := 0.29
## 血条与视口边缘或轮次标签的水平间距，单位为界面像素。
const SIDE_MARGIN := 8.0
## 血条与视口底边的距离，单位为界面像素。
const BOTTOM_MARGIN := 5.0
## 相邻血条之间的最大间距，单位为界面像素。
const BAR_GAP := 8.0

## 每个登场僵王使用同一场景，各自绑定血量和阶段信号。
@export var boss_bar_scene: PackedScene

## 多轮关卡的轮次标签，显示时为其留出独立空间。
@onready var round_label: Label = $RoundLabel
## 原波次进度条的容器，保留子进度条各自的显隐状态。
@onready var wave_progress_root: Control = $WaveProgressRoot

## 按登记顺序保存每个实例的血条，淡出期间继续占用原有位置。
var _boss_bars: Dictionary[int, BossHpProgressBar] = {}


## 视口尺寸变化时重新分配血条宽度，等待锚定的轮次标签更新位置。
func _ready() -> void:
	get_viewport().size_changed.connect(_layout_boss_bars, CONNECT_DEFERRED)
	round_label.resized.connect(_layout_boss_bars, CONNECT_DEFERRED)
	round_label.visibility_changed.connect(_layout_boss_bars, CONNECT_DEFERRED)


## [param curr_round] 当前关卡轮次；更新文字并显示轮次标签。
func set_round(curr_round: int) -> void:
	round_label.text = "当前为第" + str(curr_round) + "轮"
	round_label.visible = true


## [param bosses] 按登记顺序排列的存活僵王快照。[br]
## [param keep_depleted] Boss 击杀判胜时，血条耗尽并淡出，波次进度继续隐藏。[br]
## [param restore_wave] 仍在普通波次战斗时，最后一只僵王离场后恢复波次容器。
func refresh_boss_progress(bosses: Array[ZB000Base], keep_depleted: bool, restore_wave: bool) -> void:
	# 仅记录本次成功绑定的实例，离场血条仍留在字典中直到淡出完成。
	var live_ids: Dictionary[int, bool] = {}
	# 依次同步场上的角色，新角色追加到血条末尾。
	for boss: ZB000Base in bosses:
		if not is_instance_valid(boss) or not boss.is_node_ready() or boss.is_death \
			or not boss.is_inside_tree() or boss.is_queued_for_deletion():
			continue
		if not is_instance_valid(boss.hp_component) or boss.hp_component.max_hp <= 0:
			continue
		# 本局僵王的实例 ID，同种僵王也分别占一个位置。
		var boss_id: int = boss.get_instance_id()
		# 优先复用对应血条，保留受伤和转阶段动画。
		var bar: BossHpProgressBar = _boss_bars.get(boss_id)
		if bar == null:
			bar = boss_bar_scene.instantiate() as BossHpProgressBar
			add_child(bar)
			bar.signal_fade_finished.connect(_remove_boss_bar.bind(boss_id))
			_boss_bars[boss_id] = bar
		bar.bind_boss(boss)
		live_ids[boss_id] = true

	# 对不在新快照中的角色启动淡出，避免立即重排盖住正在离场的血条。
	for boss_id: int in _boss_bars:
		if not live_ids.has(boss_id):
			_boss_bars[boss_id].fade_out(keep_depleted)

	wave_progress_root.visible = live_ids.is_empty() and restore_wave and not keep_depleted
	_layout_boss_bars()


## [param boss_id] 已完成淡出的实例 ID；释放该血条，再用剩余血条重排。
func _remove_boss_bar(boss_id: int) -> void:
	_boss_bars[boss_id].queue_free()
	_boss_bars.erase(boss_id)
	_layout_boss_bars()


## 将血条限制在底部单行。优先居中，空间不足时向左延伸并等比收缩。
func _layout_boss_bars() -> void:
	# 包含淡出中的血条，避免在退场动画结束前覆盖其位置。
	var count: int = _boss_bars.size()
	if count == 0:
		return
	# 使用 CanvasLayer 中的逻辑视口尺寸，不受战场镜头移动影响。
	var viewport_size: Vector2 = get_viewport_rect().size
	# 为普通波次进度预留右侧空间，轮次文字显示时再把边界向左收。
	var right_edge: float = global_position.x - SIDE_MARGIN
	if round_label.visible:
		right_edge = minf(right_edge, round_label.get_global_rect().position.x - SIDE_MARGIN)
	# 在极窄的视口下优先保证整行仍有可用空间。
	var available_width: float = maxf(right_edge - SIDE_MARGIN, 1.0)
	# 数量极多时同步缩小间距，把大部分宽度留给血条本身。
	var gap: float = minf(BAR_GAP, available_width / (count * 8.0))
	# 多只僵王时将装饰占用的高度压低，避免叠到上方战场。
	var max_scale: float = SINGLE_BAR_SCALE if count == 1 else MULTI_BAR_SCALE
	# 所有血条使用同一倍率，保证最后一条也在可用宽度内。
	var bar_scale: float = minf(max_scale,
		(available_width - gap * (count - 1)) / (BossHpProgressBar.DISPLAY_SIZE.x * count))
	# 布局尺寸包含两套阶段素材和头像，单位为界面像素。
	var bar_size: Vector2 = BossHpProgressBar.DISPLAY_SIZE * bar_scale
	# 血条和间距的总宽，用来保持底部居中。
	var row_width: float = bar_size.x * count + gap * (count - 1)
	# 第一条的左上角，后续按实际血条宽度向右递增。
	var slot: Vector2 = Vector2(
		clampf((viewport_size.x - row_width) * 0.5, SIDE_MARGIN, maxf(SIDE_MARGIN, right_edge - row_width)),
		viewport_size.y - BOTTOM_MARGIN - bar_size.y)
	# 字典保留插入顺序，现有 Boss 的相对位置不会随生成和死亡变化。
	for bar: BossHpProgressBar in _boss_bars.values():
		bar.scale = Vector2.ONE * bar_scale
		bar.global_position = slot
		slot.x += bar_size.x + gap
