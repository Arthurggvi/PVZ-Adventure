## 石像僵尸专属视觉：固壳静止，破壳后独立绘制厚石块并自动回收。
class_name StoneStatueVisual
extends Node2D

## 石像实际使用时才载入的小型绘制脚本。
const Renderer = preload("res://scripts/character/zombie/stone_statue/stone_statue_renderer.gd")
## 与绘制共享旋转和接地轮廓的运动脚本。
const Motion = preload("res://scripts/character/zombie/stone_statue/stone_statue_motion.gd")
## 仅使用二维图元的入场和落尘效果。
const Effects = preload("res://scripts/character/zombie/stone_statue/stone_statue_effects.gd")
## 166×260 素材对应原始普僵 4 倍采样的 320×500 画布。
const ART_SCALE: Vector2 = Vector2(80.0 / 166.0, 125.0 / 260.0)
## 由普通僵尸 idle 第 0 帧的部件包围盒和 14 像素留白校准。
const ART_OFFSET: Vector2 = Vector2(-52.8, -110.7)
## 碎块和落尘的最长独立生命周期，单位为秒。
const DEBRIS_LIFETIME: float = 1.2
## 五款等概率抽取的皮肤，名称对应随游戏交付的图集与碎块数据。
const SKINS: Array[String] = ["hollow", "howling", "faceless", "split_face", "chiseled"]
## 皮肤专用随机流；装扮抽样不消耗战斗的全局随机序列。
static var _skin_rng: RandomNumberGenerator = RandomNumberGenerator.new()
## 本实例选中的皮肤资源；壳面、裂纹和碎块共用同一张图集。
var _assets: Dictionary = {}
## 当前石像独有的碎块运动；固壳阶段保持为空。
var _motions: Array[Dictionary] = []
## 壳完整度，仅决定裂纹显示，不参与伤害计算。
var _integrity: float = 1.0
## 入场已经过去的秒数；负值表示未播放。
var _arrival_age: float = -1.0
## 碎裂已经过去的秒数；负值表示仍然是完整石像。
var _break_age: float = -1.0

## 出生时等概率选一次皮肤。完整石像无需持续逐帧刷新，破壳时沿用已选皮肤。
func _ready() -> void:
	var skin: String = SKINS[_skin_rng.randi_range(0, SKINS.size() - 1)] # 抽样与等阶、行列及先前结果独立。
	_assets = Renderer.load_assets(skin)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	set_process(false)
	queue_redraw()

## 突然出场的短地纹和灰尘；位置与受击状态由控制器先行设置。
func play_arrival() -> void:
	if _break_age >= 0.0:
		return
	_arrival_age = 0.0
	visible = true
	set_process(true)
	queue_redraw()

## 直接显示静止的石壳，结束入场地纹、扬尘与闪光。圣堂在复光前的全黑帧使用。
func finish_arrival() -> void:
	if _arrival_age < 0.0:
		return
	_arrival_age = -1.0
	set_process(false)
	queue_redraw()

## 更新外壳裂纹；[param ratio] 被限制在零到一，不能影响本体血量。
func set_integrity(ratio: float) -> void:
	if is_nan(ratio) or _break_age >= 0.0:
		return
	_integrity = clampf(ratio, 0.0, 1.0)
	queue_redraw()

## 立即脱离旧壳角色并保留世界变换；[param world_parent] 应为旧角色所在战斗层。
func shatter(world_parent: Node) -> void:
	if _break_age >= 0.0 or not is_inside_tree():
		return
	if not is_instance_valid(world_parent) or world_parent == self or is_ancestor_of(world_parent):
		push_error("StoneStatue: 碎块目标父节点无效")
		return
	var saved_transform: Transform2D = global_transform # 旧壳随后销毁，碎石仍留在破碎位置。
	if get_parent() != world_parent:
		reparent(world_parent, true)
	global_transform = saved_transform
	_motions = Motion.create(_assets.get("parts", []))
	_break_age = 0.0
	_arrival_age = -1.0
	visible = true
	set_process(true)
	queue_redraw()

## 仅在入场或破壳期间更新；[param delta] 使用引擎实际经过的秒数。
func _process(delta: float) -> void:
	if _break_age >= 0.0:
		_break_age += delta
		if _break_age >= DEBRIS_LIFETIME:
			queue_free()
			return
	elif _arrival_age >= 0.0:
		_arrival_age += delta
		if _arrival_age >= 0.65:
			finish_arrival()
			return
	queue_redraw()

## 在素材坐标系绘制，外部场景不需要额外设置缩放或偏移。
func _draw() -> void:
	draw_set_transform(ART_OFFSET, 0.0, ART_SCALE)
	if _assets.is_empty():
		return
	if _break_age < 0.0:
		_draw_shell()
		return
	var poses: Array[Dictionary] = [] # 本帧只采样一次运动，阴影和实体共用结果。
	for state: Dictionary in _motions: # 每块碎石有自己的接地高度。
		var pose: Dictionary = Motion.sample(state, _break_age) # 解析位置，不受帧率积分误差影响。
		poses.append(pose)
		Effects.fragment_shadow(self, state, pose)
	for index: int in range(_motions.size()): # 不透明表面靠实际移开露出普僵，不做整体淡出。
		Renderer.draw_piece(self, _motions[index].part, poses[index], _assets.atlas)
	for index: int in range(_motions.size()): # 石块碰地后才出现对应的粉尘。
		Effects.impact_dust(self, _motions[index], poses[index])

## 固壳保持同一幅画；裂纹与入场粉尘只是小幅覆盖。
func _draw_shell() -> void:
	Effects.arrival_ground(self, _arrival_age)
	var flash: float = maxf(0.0, 1.0 - _arrival_age / 0.09) * 0.10 if _arrival_age >= 0.0 else 0.0 # 极短低亮度石灰闪现。
	draw_texture(_assets.statue, Vector2.ZERO, Color(1.0 + flash, 1.0 + flash, 1.0 + flash * 0.5))
	if _integrity < 0.72 and _assets.has("cracks"):
		var crack_alpha: float = clampf((0.72 - _integrity) / 0.72, 0.0, 1.0) # 随壳受损渐进加深。
		draw_texture(_assets.cracks, Vector2.ZERO, Color(1.0, 1.0, 1.0, crack_alpha))
	Effects.arrival_dust(self, _arrival_age)
