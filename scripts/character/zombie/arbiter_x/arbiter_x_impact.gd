## 机体爆炸表现，支持仲裁者触地坠毁和轻型战斗机空中击毁。
extends Node2D
class_name ArbiterXImpact

## 只有明确配置的关卡才将现有烟尘接入气流。
const BattleWind := preload("res://scripts/battle/environment/battle_wind_visual.gd")

## 演出在碎屑、烟尘与最后一段燃烧声之后回收，单位为秒。
const DURATION: float = 2.59
## 让爆炸瞬态先响，再放入燃烧尾声，单位为秒。
const FIRE_DELAY: float = 0.16
## 局部强闪到火球完全收束的时间，单位为秒。
const BLOOM_SECONDS: float = 0.73
## 由主爆起算的三个次爆时点，单位为秒。
const FOLLOWUP_TIMES: Vector3 = Vector3(0.24, 0.52, 0.86)
## 各次爆相对主爆的视觉和音量强度。
const FOLLOWUP_POWER: Vector3 = Vector3(0.87, 0.72, 0.62)
## 次爆声依次降低音高，从较脆的响声过渡到闷响。
const FOLLOWUP_PITCH: Vector3 = Vector3(1.17, 1.07, 0.89)
## 单次次爆火球的可见时长，单位为秒。
const FOLLOWUP_BLOOM_SECONDS: float = 0.49
## 离地碎片由擦滑结束后的短促爆声强调。
const FOLLOWUP_SFX: AudioStream = preload("res://assets/adventure/zombies/arbiter_x/audio/impact_followup.ogg")
## 白热核心，复用工程已有的描边爆炸素材。
const HOT_CORE: Texture2D = preload("res://assets/image/particles/BossExplosion1.png")
## 爆炸的火球轮廓，分别着色、推开和膨胀。
const FLAME_LOBE: Texture2D = preload("res://assets/image/particles/BossExplosion2.png")
## 闪光外缘的不规则喷发纹理。
const RAYS: Texture2D = preload("res://assets/image/particles/BossExplosion3.png")

## 近地爆光，与随后升高的火球使用不同的衰减。
@onready var _glare: Sprite2D = $Glare
## 贴地扫过的擦地火星，已经甩出的火星留在世界空间。
@onready var _scrape_sparks: GPUParticles2D = $ScrapeSparks
## 擦滑时贴着接触线卷起的尘土。
@onready var _dust: GPUParticles2D = $Dust
## 触地摩擦声随正在滑动的机头播放。
@onready var _scrape_audio: AudioStreamPlayer2D = $ScrapeAudio
## 主爆与次爆共用的火花样式，次爆使用独立发射器以保留前一团火星。
@onready var _sparks: GPUParticles2D = $Sparks
## 主火球后卷起的烟柱，次爆复用此材质但缩小烟团。
@onready var _smoke: GPUParticles2D = $Smoke
## 主爆和次爆各自抛出的金属碎屑。
@onready var _fragments: GPUParticles2D = $Fragments
## 只在主爆短暂扫过屏幕的暖色光。
@onready var _screen_light: ColorRect = $ScreenFlash/Light
## 正式 SFX 总线中的触地爆炸。
@onready var _blast: AudioStreamPlayer2D = $Blast
## 爆声后保留的燃烧和爆裂声。
@onready var _fire: AudioStreamPlayer2D = $Burning
## 主火球的局部起火点，地面冲击波仍以此节点的原点为中心。
var _burst_center: Vector2
## 轻型机体的爆炸比例，同步衰减全屏闪光、镜头震动与次爆声。
var _strength: float = 1.0
## 空中击毁时相对主爆心的次爆偏移，以特效未缩放的局部像素计。
var _airburst_offsets: PackedVector2Array = PackedVector2Array()
## 爆炸发生之前只显示擦地烟尘，不绘制火球。
var _burst_started: bool = false
## 从主爆炸触发开始累计的场景秒数。
var _elapsed: float = 0.0
## 已触发的次爆中心，保存为相对于固定接地点的坐标。
var _followup_centers: PackedVector2Array = PackedVector2Array()


## 粒子和声音由擦滑和主爆炸的各自入口启动。
func _ready() -> void:
	set_process(false)
	var bus: StringName = SoundManager.spatial_sfx_bus() # 遵守当前场景的音效路由与响度。
	_scrape_audio.bus = bus
	_blast.bus = bus
	_fire.bus = bus


## [param direction] 为擦滑的水平符号，火星沿相反方向拖出，起火点位于机头后方。
func begin_scrape(direction: float) -> void:
	var behind: float = 1.0 if direction <= 0.0 else -1.0 # 正常左行时，碎屑拖在机体右后侧。
	_burst_center = Vector2(behind * 46.0, -25.0)
	_scrape_sparks.scale.x = behind
	BattleWind.before_emit(self, global_position, [_scrape_sparks, _dust])
	_scrape_sparks.emitting = true
	_dust.emitting = true
	SoundManager.play_attached_sfx(_scrape_audio, &"touchdown", 3)


## 立即从 [param world_center] 起爆。[param size] 为正的特效缩放倍率。
## [param followup_offsets] 是相对主爆心的局部像素偏移，最多播放前三个次爆。
func play_airburst(world_center: Vector2, size: float, followup_offsets: PackedVector2Array) -> void:
	if _burst_started:
		return
	scale *= size
	_strength = size
	_burst_center = to_local(world_center)
	_airburst_offsets = followup_offsets
	_blast.volume_db += linear_to_db(size)
	_fire.volume_db += linear_to_db(size)
	for emitter: GPUParticles2D in [_sparks, _smoke, _fragments]: # 轻型机体同步缩减粒子数量。
		emitter.amount = maxi(1, roundi(emitter.amount * size))
	burst()


## 引爆机体，保留触地版本已经离开发射器的灰尘和火星。
func burst() -> void:
	_burst_started = true
	_scrape_sparks.emitting = false
	_dust.emitting = false
	_glare.position = _burst_center
	_blast.position = _burst_center
	_fire.position = _burst_center
	_sparks.position = _burst_center
	_smoke.position = _burst_center
	_fragments.position = _burst_center
	BattleWind.before_emit(self, to_global(_burst_center), [_sparks, _smoke, _fragments], true)
	_sparks.emitting = true
	_smoke.emitting = true
	_fragments.emitting = true
	SoundManager.play_attached_sfx(_blast, &"vehicle_burst", 3)
	set_process(true)
	queue_redraw()
	_shake_camera(Vector2(4.7, 6.6), 0.19)


## [param seconds] 为主爆后的场景秒数，跨过次爆时点时补发对应火球。
## [param original_origin] 可从原机体轨迹取得位置；否则按 [param airframe] 的残片或空爆偏移定位。
func fire_followups(seconds: float, airframe: ArbiterXAirframe = null,
		original_origin: Callable = Callable()) -> void:
	var count: int = 3 if airframe != null or original_origin.is_valid() else mini(3, _airburst_offsets.size()) # 共用的次爆时间轴。
	while _followup_centers.size() < count:
		var index: int = _followup_centers.size() # 已生成的位置本身就是一次性触发记录。
		if seconds < FOLLOWUP_TIMES[index]:
			return
		var center: Vector2 # 固定空爆锚点或这一帧在原坠毁路径上的残片位置。
		if original_origin.is_valid():
			center = to_local(original_origin.call(index))
		elif airframe != null:
			center = to_local(airframe.wreck_burst_origin(index))
		else:
			center = _burst_center + _airburst_offsets[index]
		_followup_centers.append(center)
		var power: float = FOLLOWUP_POWER[index] # 次爆的大小、声压和余震随序列衰减。
		_add_particle_burst(_sparks, center, 0.61 * power, 0.59, 0.82 * power)
		_add_particle_burst(_smoke, center, 0.57 * power, 1.31, 0.53 + 0.28 * power)
		_add_particle_burst(_fragments, center, 0.62 * power, 0.86, 0.74 * power)
		_play_followup(center, power, FOLLOWUP_PITCH[index])
		_shake_camera(Vector2(2.7, 4.2) * power, 0.145)


## 在 [param center] 复制 [param source] 的发射参数。
## [param density] 是原数量的倍率，[param lifetime] 为秒，[param size] 为发射器的尺寸倍率。
func _add_particle_burst(source: GPUParticles2D, center: Vector2, density: float,
		lifetime: float, size: float) -> void:
	var emitter: GPUParticles2D = source.duplicate(0) as GPUParticles2D # 材质共用，粒子系统互不重启。
	emitter.emitting = false
	emitter.position = center
	emitter.scale *= size
	emitter.amount = maxi(1, roundi(source.amount * density))
	emitter.lifetime = lifetime
	add_child(emitter)
	emitter.finished.connect(emitter.queue_free, CONNECT_ONE_SHOT)
	emitter.emitting = true


## [param center] 为次爆位置，[param power] 为相对强度，[param pitch] 为音高倍率。
func _play_followup(center: Vector2, power: float, pitch: float) -> void:
	if SoundManager.world_audio_for(self) != null:
		SoundManager.play_world_sfx(FOLLOWUP_SFX, self, to_global(center), -7.0 + linear_to_db(power * _strength),
			pitch, &"vehicle_followup", false, 1)
		return
	var echo := AudioStreamPlayer2D.new() # 短爆声空间化，主爆和燃烧继续播放。
	echo.stream = FOLLOWUP_SFX
	echo.bus = _blast.bus
	echo.position = center
	echo.volume_db = -7.0 + linear_to_db(power * _strength)
	echo.pitch_scale = pitch
	echo.max_distance = _blast.max_distance
	add_child(echo)
	echo.finished.connect(echo.queue_free, CONNECT_ONE_SHOT)
	echo.play()


## 请求当前镜头震动。[param amplitude] 使用相机像素，[param span] 为场景秒。
func _shake_camera(amplitude: Vector2, span: float) -> void:
	var game: MainGameManager = Global.main_game # 独立图鉴预览无需战斗镜头。
	if is_instance_valid(game) and game.is_ancestor_of(self):
		EventBus.push_event(MainGameCamera.SHAKE_EVENT, [amplitude * _strength, span, 21.0])


## 返回主爆后 [param seconds] 时的光强，关联世界中的爆光与屏幕上的微光。
static func flash_at(seconds: float) -> float:
	return smoothstep(0.0, 0.053, seconds) * (1.0 - smoothstep(0.059, 0.28, seconds))


## [param seconds] 为爆炸时间轴的秒数，返回当前最强的一束残骸反光。
static func reflected_heat(seconds: float) -> float:
	var light: float = flash_at(seconds) # 主爆包络也是第一束反光。
	for index: int in range(3): # 三处次爆分别照亮附近机壳。
		light = maxf(light, flash_at((seconds - FOLLOWUP_TIMES[index]) * 1.53) * FOLLOWUP_POWER[index])
	return light


## [param delta] 推进火球与冲击波，爆炸声与燃烧声只有各自一次起声。
func _process(delta: float) -> void:
	var crossed_fire: bool = _elapsed < FIRE_DELAY and _elapsed + delta >= FIRE_DELAY # 低帧率也不漏掉声尾。
	_elapsed += delta
	if crossed_fire:
		SoundManager.play_attached_sfx(_fire, &"wreck_fire", 1)
	if not _airburst_offsets.is_empty():
		fire_followups(_elapsed)
	var flare: float = clampf(_elapsed / 0.24, 0.0, 1.0) # 近地闪光在四分之一秒内扩散并退去。
	_glare.scale = Vector2(1.42, 0.96) * lerpf(0.55, 1.52, ease(flare, 0.44))
	_glare.modulate.a = 0.82 * flash_at(_elapsed)
	_screen_light.color.a = 0.065 * _strength * flash_at(_elapsed)
	_screen_light.visible = _screen_light.color.a > 0.001
	if _elapsed - delta <= FOLLOWUP_TIMES.z + FOLLOWUP_BLOOM_SECONDS:
		queue_redraw() # 跨过最后一个火球的末帧也清除上一次绘制。
	if _elapsed >= DURATION:
		queue_free()


## 由低到高叠加地面冲击波、橙红火冠和中心爆光。
func _draw() -> void:
	if not _burst_started:
		return
	if _elapsed < 0.66:
		var wave: float = clampf(_elapsed / 0.66, 0.0, 1.0) # 地面冲击波尽早扩展、随后减速。
		var radius: float = lerpf(31.0, 288.0, ease(wave, 0.35)) # 世界像素半径。
		var opacity: float = smoothstep(0.0, 0.14, wave) * pow(1.0 - wave, 1.45) # 触地火光亮起再推出冲击线。
		_draw_wave(Vector2.ZERO, radius, Color(1.0, 0.48, 0.13, opacity * 0.62), 10.0)
		_draw_wave(Vector2.ZERO, radius * 0.91, Color(1.0, 0.91, 0.64, opacity * 0.97), 3.0)
	if _elapsed < BLOOM_SECONDS:
		var time: float = _elapsed / BLOOM_SECONDS # 火团上升并炸开，白芯先于外沿隐去。
		var spread: float = ease(time, 0.52) # 火球从触地点向两侧分裂。
		var hot: float = smoothstep(0.0, 0.14, time) * pow(1.0 - time, 1.3) # 火团从擦滑火星里逐渐亮起。
		_draw_sprite(RAYS, _burst_center + Vector2(0, -11), lerpf(133.0, 387.0, spread), time * 0.25,
			Color(1.0, 0.79, 0.32, hot * 0.84))
		_draw_sprite(FLAME_LOBE, _burst_center + Vector2(-89, -44) * spread + Vector2(-20, 0),
			lerpf(80.0, 208.0, spread), -0.45 - time,
			Color(1.0, 0.34 + hot * 0.26, 0.11 + hot * 0.14, hot * 0.85))
		_draw_sprite(FLAME_LOBE, _burst_center + Vector2(94, -54) * spread + Vector2(16, -6),
			lerpf(85.0, 225.0, spread), 0.28 + time,
			Color(1.0, 0.44 + hot * 0.30, 0.13 + hot * 0.17, hot * 0.90))
		_draw_sprite(FLAME_LOBE, _burst_center + Vector2(5, lerpf(-7.0, -89.0, spread)),
			lerpf(120.0, 270.0, spread), time * 0.65,
			Color(1.0, 0.42 + hot * 0.33, 0.10 + hot * 0.21, hot * 0.98))
		_draw_sprite(HOT_CORE, _burst_center + Vector2(0, -45.0 * spread), lerpf(109.0, 283.0, spread), -time * 0.5,
			Color(1.0, 0.94, 0.63, smoothstep(0.0, 0.088, time) * (1.0 - smoothstep(0.13, 0.69, time))))
	if _elapsed > 0.28 and _elapsed < 1.23:
		var ember: float = smoothstep(0.28, 0.45, _elapsed) * (1.0 - smoothstep(0.58, 1.23, _elapsed)) # 贴地的燃烧余亮。
		_draw_sprite(HOT_CORE, _burst_center + Vector2(-15, 7), 74.0 + sin(_elapsed * 23.0) * 7.0, _elapsed * 0.3,
			Color(1.0, 0.46, 0.16, ember * 0.53))
	_draw_followups()


## 每一处次爆拥有自己的火球、膨胀方向和次级冲击环。
func _draw_followups() -> void:
	for index: int in range(_followup_centers.size()): # 只绘制实际触发过的次爆。
		var phase: float = (_elapsed - FOLLOWUP_TIMES[index]) / FOLLOWUP_BLOOM_SECONDS # 相对本次起爆的进度。
		if phase < 0.0 or phase >= 1.0:
			continue
		var anchor: Vector2 = _followup_centers[index] # 同一团尘烟离开残片后固定在场地上。
		var power: float = FOLLOWUP_POWER[index] # 余爆半径逐次缩短。
		var spread: float = ease(phase, 0.48) # 火球外沿扩张后缓下来。
		var hot: float = smoothstep(0.0, 0.14, phase) * pow(1.0 - phase, 1.24) # 每处都具有独立的亮起段。
		var crown: Vector2 = anchor + Vector2(0.0, -29.0 * spread * power) # 火球从残片向上卷。
		_draw_wave(anchor, lerpf(19.0, 125.0, spread) * power,
			Color(1.0, 0.67, 0.27, hot * 0.72), 3.0)
		_draw_sprite(RAYS, anchor, lerpf(90.0, 221.0, spread) * power, float(index) * 0.79 + phase * 0.5,
			Color(1.0, 0.73, 0.32, hot * 0.89))
		_draw_sprite(FLAME_LOBE, crown, lerpf(63.0, 193.0, spread) * power, -phase * 0.70,
			Color(1.0, 0.38 + 0.37 * hot, 0.10 + 0.20 * hot, hot))
		_draw_sprite(HOT_CORE, crown, lerpf(61.0, 163.0, spread) * power, phase,
			Color(1.0, 0.88, 0.59, hot * (1.0 - smoothstep(0.19, 0.64, phase))))


## 绕 [param center] 展开半径 [param radius] 的椭圆，[param color] 与 [param width] 为线条外观。
func _draw_wave(center: Vector2, radius: float, color: Color, width: float) -> void:
	var points := PackedVector2Array() # 闭合的地面波纹。
	for step: int in range(57): # 小段圆弧足以在棋盘尺寸下保持平滑。
		var angle: float = TAU * float(step) / 56.0 # 当前点的弧度。
		points.append(center + Vector2(cos(angle) * radius, sin(angle) * radius * 0.31))
	draw_polyline(points, color, width, true)


## 绘制局部爆炸裁片。[param texture] 位于 [param center]，边长为 [param size]。
## [param angle] 控制角度，[param tint] 为火焰的颜色与透明度。
func _draw_sprite(texture: Texture2D, center: Vector2, size: float, angle: float, tint: Color) -> void:
	draw_set_transform(center, angle)
	draw_texture_rect(texture, Rect2(Vector2.ONE * -size * 0.5, Vector2.ONE * size), false, tint)
	draw_set_transform(Vector2.ZERO)
