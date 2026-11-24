## 共享帧图集上的飞行球与方向电光，由弹体物理步给出表现时钟。
extends Sprite2D

## 电豌豆的配色入口，和矩阵及短放电共用同一色表。
const PromotionArt = preload("res://scripts/adventure/plant_art/adventure_electric_peashooter_promotion_art.gd")
## 合成图集路径，首次准备实际战斗植株时读取。
const ATLAS_PATH: String = "res://assets/adventure/plants/electric_peashooter/flight_atlas.png"
## 每档材质只重建三色与透明度，不读取电球实例的世界坐标。
const FLIGHT_SHADER: Shader = preload("res://shaders/electric_pea_flight.gdshader")
## 图集每行十格，每种球面六行，片段的帧格高依半径递增。
const ATLAS_COLUMNS: int = 10
## 每种球的帧格高度，含缩退后的轮廓及防串色边界，单位为图集像素。
const TILE_HEIGHTS: Array[int] = [44, 64, 84]
## 图集里三种球的纵向像素起点，依小、中、大球的六行布局排列。
const ATLAS_TOPS: Array[int] = [0, 264, 648]
## 每格左边额外预留的尾迹像素宽度；球心在其余正方形部分的中心。
const TAIL_ROOM: int = 22
## 原飞行循环的帧数与每秒采样帧数。
const BODY_FRAMES: int = 40
## 原飞行循环每游戏秒采样帧数。
const BODY_FPS: float = 30.0
## 出膛与分裂的逐帧电光每游戏秒采样帧数。
const ACCENT_FPS: float = 60.0
## 十帧普通出膛后紧接七帧分裂电光。
const SPLIT_START: int = 50
## 两种电光各自的最后一格仅保留稳定白芯和尾迹。
const STEADY_FRAME: int = 57

## 同一会话内按需保留一张小型图集，供所有在飞电球和等阶共用。
static var _atlas: Texture2D
## 各等阶的材质只初始化一次，飞行期间不改着色参数。
static var _materials: Dictionary[int, ShaderMaterial] = {}

## 当前电球在图集中的格宽，包含左侧尾迹。
var _tile_width: int
## 当前电球在图集中的格高，单位为图集像素。
var _tile_height: int
## 当前片段在图集中的纵向起点，单位为图集像素。
var _atlas_top: int
## 上次提交的球面帧索引；相同显示帧不重复写纹理区域。
var _last_body_frame: int = -1
## 上次提交的强调层帧索引；稳定飞行时不再改纹理区域。
var _last_accent_frame: int = -1
## 分裂小球使用较短且略淡的出膛效果。
var _child_ball: bool
## 白芯、细尾和短脉冲共用一个随实际速度方向旋转的精灵。
var _accent: Sprite2D
## 当前显示帧尚未提交的最新物理快照。
var _visual_pending: bool = false
## 最新物理步的电球累计游戏秒数。
var _pending_age: float = 0.0
## 最新物理步的世界速度，包括屋顶坡面的高度变化。
var _pending_velocity: Vector2 = Vector2.ZERO


## 在植株入场或首发前准备共享图集；[param rank] 可同时准备指定等阶的材质。
static func prepare(rank: int = -1) -> void:
	if _atlas == null:
		_atlas = load(ATLAS_PATH) as Texture2D
	if rank < 0:
		return
	var safe_rank: int = mini(rank, PromotionArt.EFFECT_PALETTES.size() - 1) # 材质缓存只接受合法等阶。
	if _materials.has(safe_rank):
		return
	var colors: Dictionary = PromotionArt.effect_colors(safe_rank) # 与植株及放电相同的颜色。
	var shared := ShaderMaterial.new() # 这份材质在此阶所有球及强调层之间共享。
	shared.shader = FLIGHT_SHADER
	shared.set_shader_parameter(&"rim_tone", colors.rim)
	shared.set_shader_parameter(&"core_tone", colors.core)
	shared.set_shader_parameter(&"glow_tone", colors.glow)
	_materials[safe_rank] = shared


## 绑定 [param rank] 配色、[param child_ball] 出生电光和 [param clip] 的共享飞行帧。
## 配置在入树前完成，缩放由弹体统一设置。
func configure(rank: int, child_ball: bool, clip: StringName) -> void:
	var safe_rank: int = clampi(rank, 0, PromotionArt.EFFECT_PALETTES.size() - 1) # 兼容未配置色阶的展示弹体。
	prepare(safe_rank)
	var variant: int = 0 # 默认普通球使用最小半径的第一段。
	match clip:
		&"projectile2":
			variant = 1
		&"projectile3":
			variant = 2
	_child_ball = child_ball
	_tile_height = TILE_HEIGHTS[variant]
	_tile_width = _tile_height + TAIL_ROOM
	_atlas_top = ATLAS_TOPS[variant]
	texture = _atlas
	material = _materials[safe_rank]
	centered = false
	offset = -Vector2(_tile_height * 0.5 + TAIL_ROOM, _tile_height * 0.5)
	region_enabled = true
	region_filter_clip_enabled = true
	_accent = Sprite2D.new()
	_accent.texture = _atlas
	_accent.use_parent_material = true
	_accent.centered = false
	_accent.offset = offset
	_accent.region_enabled = true
	_accent.region_filter_clip_enabled = true
	add_child(_accent)


## [param elapsed] 为弹体累计游戏秒数，[param frame_velocity] 为包含坡面位移的世界速度。
## 出生时立即设置纹理区域，后续物理步只保留下一显示帧使用的快照。
func advance_visual(elapsed: float, frame_velocity: Vector2) -> void:
	if _last_body_frame < 0:
		_apply_visual(elapsed, frame_velocity)
		return
	_pending_age = elapsed
	_pending_velocity = frame_velocity
	_visual_pending = true


## [param _delta] 不参与时钟，显示帧仅提交最新有效物理快照。
func _process(_delta: float) -> void:
	if _visual_pending:
		_visual_pending = false
		_apply_visual(_pending_age, _pending_velocity)


## [param elapsed] 维持原图集相位，仅强调层随 [param frame_velocity] 的真实方向旋转。
func _apply_visual(elapsed: float, frame_velocity: Vector2) -> void:
	var body_frame: int = posmod(floori(elapsed * BODY_FPS + 0.00001), BODY_FRAMES) # 在两物理步间重复使用同一原画帧。
	if body_frame != _last_body_frame:
		region_rect = _frame_rect(body_frame)
		_last_body_frame = body_frame
	var age_frame: int = floori(elapsed * ACCENT_FPS + 0.00001) # 出膛脉冲只在出生前几步变换。
	var accent_frame: int = STEADY_FRAME # 默认取母球稳定飞行的尾迹。
	if _child_ball:
		accent_frame = SPLIT_START + age_frame if age_frame < STEADY_FRAME - SPLIT_START else STEADY_FRAME + 1
	elif age_frame < SPLIT_START - BODY_FRAMES:
		accent_frame = BODY_FRAMES + age_frame
	if accent_frame != _last_accent_frame:
		_accent.region_rect = _frame_rect(accent_frame)
		_last_accent_frame = accent_frame
	if frame_velocity.length_squared() > 0.01:
		var local_velocity: Vector2 = frame_velocity # 根节点未附着时保持原方向。
		var bullet := get_parent() as Node2D # 只剔除父弹祖先的旋转和缩放。
		if bullet != null and not is_zero_approx(bullet.global_transform.determinant()):
			local_velocity = bullet.global_transform.basis_xform_inv(frame_velocity)
		var heading: float = local_velocity.angle() # 尾光以此对齐真实斜向或反向轨迹。
		if not is_equal_approx(_accent.rotation, heading):
			_accent.rotation = heading


## 返回 [param frame] 在当前片段所占的图集像素区域。
func _frame_rect(frame: int) -> Rect2:
	@warning_ignore("integer_division")
	var row: int = frame / ATLAS_COLUMNS # 同一片段内的局部整数行号。
	return Rect2(frame % ATLAS_COLUMNS * _tile_width, _atlas_top + row * _tile_height, _tile_width, _tile_height)
