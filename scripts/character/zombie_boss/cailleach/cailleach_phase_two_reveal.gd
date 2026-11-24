## 凯莱赫的慢速显现。不同深度的实景风雪、镜头白障及原画各按自己的空间运动。
extends CanvasLayer

## 白障最厚时，可从妇人的世界原画切换到山脊后的凯莱赫。
signal covered
## 云墙退去，原画继续慢速待机。
signal finished

## 低处雪雾位于战场实体上方和场景近雪以下。
const AIR_LAYER: int = 1
## 镜头雪花从白障外层掠过，在普通界面以下。
const FLAKE_LAYER: int = 5
## 演出含出雾及余雪的战斗秒数。
const DURATION: float = 6.55
## 镜头白障从卷雪前缘开始漫散射的时刻。
const BLOOM_AT: float = 0.65
## 原画交换在白障峰值后的一拍。
const COVER_AT: float = 1.54
## 狂风在风雾最厚时接近峰值，方向和位移沿用本关天气。
const PEAK_WIND := Vector2(-1580.0, 68.0)
## 狂风达到峰值前的战斗秒数。
const WIND_BUILD: float = 1.06
## 既有独立白障与失焦 FX，渐强时间对齐场景雪墙。
const Whiteout = preload("res://scripts/fx/battle_whiteout.gd")
## 现有云雾素材只做色温、雾厚和裁边转换。
const SNOW_CLOUD: Shader = preload("res://shaders/adventure/wonderland/cailleach_cloud_snow.gdshader")
## 僵尸岛的三种现成风雾，按不同尺度和风速复用。
const FOG_PATHS: Array[String] = [
	"res://assets/adventure/environment_fx/v1/zombie_island/fog/fog_01.png",
	"res://assets/adventure/environment_fx/v1/zombie_island/fog/fog_02.png",
	"res://assets/adventure/environment_fx/v1/zombie_island/fog/fog_03.png",
]
## 显现的低频积风和泛音。天气的暴雪风声继续使用本场原有音轨。
const CUE_PATH: String = "res://resources/adventure/audio/cailleach_phase_two_reveal.ogg"
## 寒冰菇现有的三帧雪花，只复用粒子美术。
const SNOWFLAKES_PATH: String = "res://assets/image/particles/bullet/SnowFlakes.png"
## 雪云的初始中心和宽高，均按视口比例表示。
const NEAR_BANKS: Array[Vector4] = [
	Vector4(0.96, 0.18, 1.52, 0.62), Vector4(1.50, 0.30, 1.60, 0.70),
	Vector4(1.14, 0.51, 1.46, 0.84), Vector4(1.65, 0.66, 1.57, 0.70),
	Vector4(0.80, 0.85, 1.50, 0.67), Vector4(1.49, 0.91, 1.62, 0.69),
	Vector4(2.35, 0.45, 1.37, 0.58), Vector4(2.66, 0.20, 1.26, 0.59),
	Vector4(2.83, 0.71, 1.34, 0.63),
]
## 对应 [constant NEAR_BANKS] 的风速比例。峰值过后，后一股云团仍从右侧穿过。
const NEAR_SPEEDS: Array[float] = [0.73, 0.52, 0.68, 0.80, 0.63, 0.65, 0.76, 0.84, 0.91]
## 雪脊后的高雾在凯莱赫附近移动，被同一段真实地形剪去下缘。
const SKY_BANKS: Array[Vector4] = [
	Vector4(0.70, 0.095, 1.12, 0.34), Vector4(1.19, 0.19, 1.17, 0.37),
	Vector4(1.46, 0.20, 1.31, 0.47), Vector4(1.78, 0.10, 1.01, 0.37),
]
## 高雾走得更慢，与镜头前的雪云形成视差。
const SKY_SPEEDS: Array[float] = [0.24, 0.35, 0.28, 0.43]

## 一片云的初始画面位置、尺寸和随风漂移的倍率。
class Bank:
	## 绘制现成风雾的精灵。
	var sprite: Sprite2D
	## 屏幕归一化中心和宽高。
	var placement: Vector4
	## 共享位移在这一深度的倍率。
	var speed: float
	## 鼓动及轻微翻卷的独立相位。
	var phase: float

## 战场环境提供真实风向和风速，非雪场可以使用备用风。
var _snow: SnowEnvironmentController
## 原画所在的中景画布，远雾自然绘制在地形后。
var _sky_canvas: CanvasLayer
## 远雾容器，属于中景画布但随本次演出移除。
var _sky_air: Node2D
## 所有镜头前云块。
var _near_banks: Array[Bank] = []
## 地形后的高雾云块。
var _sky_banks: Array[Bank] = []
## 在近景维持一个发射器，尾风停发后仍能自行飘远。
var _flakes: GPUParticles2D
## 自起风算起的战斗秒数。
var _age: float = 0.0
## 沿真实风场积分的视口比例位移。
var _travel := Vector2.ZERO
## 被接管升起的原画，原有材质保持正常绘制。
var _pose: AnimatedSprite2D
## 原画的原始局部绘制偏移。
var _base_offset := Vector2.ZERO
## 从雪脊后缓慢上升的距离，单位为图集像素。
var _rise: float = 0.0

## [param snow] 为现有雪场，[param sky_canvas] 为实际位于山脊后的二阶段画布。
func _init(snow: SnowEnvironmentController, sky_canvas: CanvasLayer) -> void:
	_snow = snow
	_sky_canvas = sky_canvas
	name = "CailleachPhaseTwoReveal"

## 配置深浅两组云块并蓄起本场风雪，近景冰粒继续由场景绘制。
func _ready() -> void:
	layer = AIR_LAYER
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var textures: Array[Texture2D] = [] # 只在正式显现时取用三张原有风雾。
	for path: String in FOG_PATHS: # 两组云块复用同一组小贴图。
		textures.append(load(path) as Texture2D)
	var material := ShaderMaterial.new() # 两种深度只使用同一个雾面材质。
	material.shader = SNOW_CLOUD
	_near_banks = _build_banks(self, NEAR_BANKS, NEAR_SPEEDS, textures, material)
	if is_instance_valid(_sky_canvas):
		_sky_air = Node2D.new()
		_sky_air.name = "RidgeSnowClouds"
		_sky_air.z_index = 2
		_sky_canvas.add_child(_sky_air)
		_sky_banks = _build_banks(_sky_air, SKY_BANKS, SKY_SPEEDS, textures, material)
	_build_foreground_snow()
	if is_instance_valid(_snow):
		_snow.play_wind_burst(PEAK_WIND, DURATION, WIND_BUILD)
	var stream: AudioStream = load(CUE_PATH) as AudioStream # 此处只补演出自身的低频与冷色尾音。
	if stream != null:
		var cue := AudioStreamPlayer.new() # 生命周期跟随本次显现及战斗暂停。
		cue.stream = stream
		cue.bus = SoundManager.spatial_sfx_bus(SoundManagerClass.SFXSpace.COMBAT)
		cue.volume_db = -3.5
		add_child(cue)
		cue.play()
	_present(0.0)

## 复用寒冰菇的雪花图集，在白障外的近景给风雪保留可见的深度。
func _build_foreground_snow() -> void:
	var layer_host := CanvasLayer.new() # 保证近处雪花和场景自带雪都画在镜头失焦之后。
	layer_host.layer = FLAKE_LAYER
	add_child(layer_host)
	var art := CanvasItemMaterial.new() # 每片选择一帧不同形状的雪花。
	art.particles_animation = true
	art.particles_anim_h_frames = 3
	var motion := ParticleProcessMaterial.new() # 粒子共用一套向左飞行的物理参数。
	motion.particle_flag_disable_z = true
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.spread = 8.0
	motion.gravity = Vector3(-135.0, 85.0, 0.0)
	motion.angle_min = -180.0
	motion.angle_max = 180.0
	motion.angular_velocity_min = -125.0
	motion.angular_velocity_max = 140.0
	motion.scale_min = 0.20
	motion.scale_max = 0.61
	motion.anim_offset_max = 0.99
	var gradient := Gradient.new() # 雪粒在出生及飞出前留柔边。
	gradient.offsets = PackedFloat32Array([0.0, 0.14, 0.62, 1.0])
	gradient.colors = PackedColorArray([Color(0.70, 0.84, 0.97, 0.0), Color(0.76, 0.87, 0.99, 0.85),
		Color(0.88, 0.96, 1.0, 0.72), Color(0.90, 0.96, 1.0, 0.0)])
	var tint := GradientTexture1D.new() # 发射器统一读取的生命周期色。
	tint.gradient = gradient
	motion.color_ramp = tint
	_flakes = GPUParticles2D.new()
	_flakes.texture = load(SNOWFLAKES_PATH) as Texture2D
	_flakes.material = art
	_flakes.process_material = motion
	_flakes.amount = 84
	_flakes.lifetime = 1.30
	_flakes.emitting = false
	layer_host.add_child(_flakes)

## 将 [param placements] 和 [param speeds] 绑定到 [param host]，复用 [param textures] 与 [param material]。
func _build_banks(host: Node, placements: Array[Vector4], speeds: Array[float],
		textures: Array[Texture2D], material: ShaderMaterial) -> Array[Bank]:
	var result: Array[Bank] = [] # 云块只创建一次，之后沿风移动。
	for index: int in range(placements.size()): # 轮换三种不同形状的原有风雾。
		var cloud := Bank.new() # 层内仅保存布置点、视差系数及精灵。
		cloud.placement = placements[index]
		cloud.speed = speeds[index]
		cloud.phase = float(index) * 1.83
		cloud.sprite = Sprite2D.new()
		cloud.sprite.texture = textures[index % textures.size()]
		cloud.sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		cloud.sprite.material = material
		cloud.sprite.flip_h = index % 3 == 1
		host.add_child(cloud.sprite)
		result.append(cloud)
	return result

## 白障峰值后接管 [param pose] 的抬升，用 [param rise_pixels] 个图集像素定位出雾高度。
func set_pose(pose: AnimatedSprite2D, rise_pixels: float) -> void:
	_pose = pose
	_base_offset = pose.offset
	_rise = rise_pixels
	_present(0.0)

## 死亡或演出结束时立即归还原画位置并撤去天气附加层。
func stop() -> void:
	set_process(false)
	hide()
	_release_pose_and_sky()
	queue_free()

## [param delta] 为战斗秒，在风雾的峰值交接原画，之后缓慢露出地形后的身影。
func _process(delta: float) -> void:
	var step: float = minf(delta, 0.10) # 低帧率保留白障以及露出雪脊的关键帧。
	var previous: float = _age # 每个时序点只穿过一次。
	_age = minf(DURATION, _age + step)
	_present(step)
	if previous < BLOOM_AT and _age >= BLOOM_AT:
		var lens := Whiteout.new() # 场景原有泛光和散焦，仅补足雪云自身的漫反射。
		lens.configure(get_viewport().get_visible_rect().size * Vector2(0.73, 0.31), 3.35, 0.31, 0.87, 0.53)
		add_child(lens)
		lens.layer = AIR_LAYER + 1
	if previous < COVER_AT and _age >= COVER_AT:
		covered.emit()
	if _age >= DURATION:
		stop()
		finished.emit()

## 以 [param delta] 积分实际风向和风速。人物和每团雪云分别在自己的深度内运动。
func _present(delta: float) -> void:
	var view: Rect2 = get_viewport().get_visible_rect() # 使用根视口逻辑坐标，缩放时同步保留画面比例。
	var wind: Vector2 = _snow.get_visual_wind() if is_instance_valid(_snow) else PEAK_WIND * smoothstep(0.0, WIND_BUILD, _age) # 备用风也逐步达到峰值。
	var screen: Vector2 = get_viewport().get_canvas_transform().basis_xform(wind) # 与雪景投影匹配的阵风位移。
	_travel += screen * delta / view.size.max(Vector2.ONE)
	var tilt: float = clampf(-screen.y / maxf(180.0, absf(screen.x)), -0.23, 0.23) # 云层微倾，与雪丝的方向一致。
	var near_density: float = smoothstep(0.06, 1.29, _age) * (1.0 - smoothstep(1.87, 5.67, _age)) # 快云先压到镜头，离场前几股云继续掠过。
	var sky_density: float = smoothstep(0.23, 1.33, _age) * (1.0 - smoothstep(2.98, DURATION, _age)) # 雪脊附近的云留到最后。
	_move_banks(_near_banks, view, tilt, near_density, Color(1.04, 1.066, 1.08))
	_move_banks(_sky_banks, view, tilt, sky_density, Color(0.93, 0.98, 1.04))
	_advance_foreground_snow(view, screen)
	if is_instance_valid(_pose):
		var lift: float = smoothstep(1.55, 4.55, _age) # 原画露出时才越过真实雪脊。
		_pose.offset = _base_offset + Vector2(0.0, _rise * (1.0 - lift))

## 发射器使用 [param view] 的上风侧和 [param screen_wind] 的投影速度。
func _advance_foreground_snow(view: Rect2, screen_wind: Vector2) -> void:
	var motion := _flakes.process_material as ParticleProcessMaterial # 粒子发射速度随实体雪场取样。
	var upper: float = view.size.y * 0.65 # 从不同高度进入战场，靠近镜头的冰粒不共一条直线。
	var speed: float = clampf(screen_wind.length(), view.size.x * 0.55, view.size.x * 1.35) # 保持能横穿视口的速度尺度。
	var direction: Vector2 = screen_wind.normalized() if not screen_wind.is_zero_approx() else Vector2.LEFT # 与真实近雪同时向左拉长。
	_flakes.position = Vector2(view.end.x + 72.0, view.get_center().y - view.size.y * 0.07)
	_flakes.visibility_rect = Rect2(Vector2(-view.size.x * 1.9, -upper * 1.35), view.size * Vector2(2.2, 1.9))
	motion.emission_box_extents = Vector3(68.0, upper, 1.0)
	motion.direction = Vector3(direction.x, direction.y, 0.0)
	motion.initial_velocity_min = speed * 0.68
	motion.initial_velocity_max = speed * 1.22
	_flakes.emitting = _age >= 0.56 and _age < 3.18

## 对 [param banks] 逐个应用 [param view] 的尺寸、当前 [param tilt]、[param density] 和 [param color]。
func _move_banks(banks: Array[Bank], view: Rect2, tilt: float, density: float, color: Color) -> void:
	for cloud: Bank in banks: # 在单独视差下飘过同一片雪场。
		var wave: float = _age * 1.22 + cloud.phase # 各云不同时鼓动和抬升。
		var center: Vector2 = Vector2(cloud.placement.x, cloud.placement.y) + _travel * cloud.speed # 云团中心随实际的风前进。
		center.y += 0.034 * sin(wave)
		var span := Vector2(cloud.placement.z, cloud.placement.w) # 原始形状以视口比例排布。
		span *= Vector2(1.0 + sin(wave * 0.72) * 0.064, 1.0 + cos(wave) * 0.12)
		cloud.sprite.position = view.position + center * view.size
		cloud.sprite.rotation = tilt + sin(wave * 0.65) * 0.054
		cloud.sprite.visible = cloud.sprite.texture != null and density > 0.002 and center.x > -span.x * 0.6
		if cloud.sprite.visible:
			cloud.sprite.scale = span * view.size / cloud.sprite.texture.get_size()
			cloud.sprite.self_modulate = Color(color.r, color.g, color.b, density * (1.23 + sin(wave + 0.8) * 0.24))

## 恢复实际原画并隐藏地形后同画布的云，再随本段退出清理。
func _release_pose_and_sky() -> void:
	if is_instance_valid(_pose):
		_pose.offset = _base_offset
	if is_instance_valid(_sky_air) and not _sky_air.is_queued_for_deletion():
		_sky_air.hide()
		_sky_air.queue_free()

## 战场直接退出时，地形后的云与前景效果仍共享同一生命周期。
func _exit_tree() -> void:
	_release_pose_and_sky()
