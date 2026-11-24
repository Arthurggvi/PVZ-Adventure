## 炮塔的底盘、炮身与装填弹体保持素材包中的同一坐标系。
extends Node2D
class_name CannonTurretPresentation

## 320 像素素材坐标下，炮身支点相对底盘接地点的静止位置。
const TURRET_REST := Vector2(-7.66, -91.87)
## 炮口朝外的单位方向，内缩和后坐使用反方向。
const BARREL_AXIS := Vector2(-0.94908, -0.31503)
## 膛内弹体停稳时相对炮身支点的位置，单位为贴图像素。
const SHELL_REST := Vector2(-75.79, -118.41)
## 前侧承重轮的底端，供制动和后坐时保持接地，单位为贴图像素。
const TIRE_CONTACT := Vector2(6.6, 2.3)
## 最前与最后轮胎接地点的横坐标，沿用车轮阴影的原画位置。
const AXLE_SPAN := Vector2(-96.0, 88.0)
## 轮胎滚动半径从原素材的 135 像素折算到 320 像素贴图。
const WHEEL_RADIUS: float = 135.0 * 320.0 / 1254.0
## 飞艇跨隙的最大抬升，单位为地面角色本地像素。
const DECK_JUMP_HEIGHT: float = 40.0
## 行驶超过这一段轮相时给出一次承重轻响，单位为轮胎弧度。
const ROLL_CUE_STEP: float = TAU * 1.2
## 复用运输舰部件中短促的机械受力声，给甲板上的实轮接触定位。
const DECK_ROLL_SOUND: AudioStream = preload("res://assets/adventure/zombies/transport_airship/audio/settle.ogg")
## 复用短促的机械锁闭声，装弹图切回时从膛内弹体处播放。
const RELOAD_LOCK_SOUND: AudioStream = preload("res://assets/adventure/zombies/transport_airship/audio/hatch_close.ogg")
## 复用原生的短促低频碰撞声，提示承重轮在甲板上压实。
const DECK_LANDING_SOUND: AudioStream = preload("res://assets/audio/SFX/zombie/gargantuar_thump.ogg")
## 继承战斗机的分段火球、冲击波、烟尘和混音。
const VehicleDeathBlast := preload("res://scripts/character/zombie/vehicle_death_blast.gd")
## 发射后切换空膛图，锁膛后复原装弹图。
const LOADED: Texture2D = preload("res://assets/adventure/zombies/cannon_turret/turret_loaded.png")
const EMPTY: Texture2D = preload("res://assets/adventure/zombies/cannon_turret/turret_empty.png")

## 依次记录秒数和后坐系数，峰值 1，负值表示回弹过冲。
const TURRET_RECOIL: Array[Vector2] = [
	Vector2(0, 0), Vector2(0.105, 1), Vector2(0.31, 0.72),
	Vector2(0.69, -0.21), Vector2(0.83, 0.065), Vector2(1.12, 0),
]
## 底盘比炮身更晚达到后坐峰值，随后独立复位。
const CHASSIS_RECOIL: Array[Vector2] = [
	Vector2(0, 0), Vector2(0.225, 1), Vector2(0.49, 0.52),
	Vector2(0.79, -0.12), Vector2(0.94, 0.04), Vector2(1.12, 0),
]
## 入场制动和悬挂回弹，纵轴为前倾强度。
const BRAKING: Array[Vector2] = [
	Vector2(0, 0), Vector2(1.04, 0), Vector2(1.57, 1),
	Vector2(1.76, 0.76), Vector2(2.06, -0.31), Vector2(2.30, 0.12),
	Vector2(2.75, 0),
]
## 装填推杆的纵轴是距原画装弹姿势的深度，单位为贴图像素。
const RELOAD_DEPTH: Array[Vector2] = [
	Vector2(0, 79), Vector2(0.18, 79), Vector2(0.55, 31),
	Vector2(0.68, 19.4), Vector2(0.76, 18.6), Vector2(0.94, -0.77),
	Vector2(1.06, 0),
]
## 留在地面平面的原生阴影节点，接受轮胎载荷和地形裁切。
@export var contact_shadow: Sprite2D

## 底盘绕车轮接地点旋转，炮塔和弹口随之运动。
@onready var _chassis: Node2D = $ChassisPivot
## 底盘纹理只在轮胎表面和轮毂环内重采样。
@onready var _wheel_material: ShaderMaterial = $ChassisPivot/Chassis.material
## 自有接触轮廓随底盘水平移动，仍维持各地图的地面边界。
@onready var _shadow_material: ShaderMaterial = contact_shadow.material
## 炮身绕底盘上的炮架轴旋转。
@onready var _turret: Node2D = $ChassisPivot/TurretPivot
## 共用支点的空膛、装弹两张贴图。
@onready var _turret_sprite: Sprite2D = $ChassisPivot/TurretPivot/Turret
## 由炮口遮罩裁出的膛内弹体。
@onready var _reload_shell: Sprite2D = $ChassisPivot/TurretPivot/Aperture/ReloadShell
## 导弹诞生在当前炮身姿态的实际弹口。
@onready var _muzzle: Marker2D = $ChassisPivot/TurretPivot/Muzzle
## 主爆点随底盘姿态贴合实际炮台座。
@onready var _blast_origin: Marker2D = $ChassisPivot/DeathBlastOrigin
## 从承重轮下方释放落地灰尘，喷出后留在甲板世界坐标。
@onready var _landing_dust: GPUParticles2D = $LandingDust
## 入场累积的轮胎弧度，静止后保持，不在炮身回弹时归零。
var _wheel_phase: float = 0.0
## 起跳和接地分别发生于滚过的世界距离，地面入场的两个端点均为零。
var _deck_gap: Vector2 = Vector2.ZERO


## [param contact_distance] 是出生点到前承重轮可着陆位置的水平距离。
## 横跨飞艇间隙时腾跃一次，已在甲板边沿附近的出生点直接短距离进场。
func prepare_deck_entry(contact_distance: float) -> void:
	if contact_distance >= 96.0:
		_deck_gap = Vector2(contact_distance * 0.28, contact_distance)


## 从滚过的 [param start]、[param end] 世界距离中取实际接地段。跨越起跳或落地帧时，只返回踏在地面上的部分。
func entry_ground_segments(start: float, end: float) -> Array[Vector2]:
	if _deck_gap == Vector2.ZERO:
		return [Vector2(start, end)]
	var segments: Array[Vector2] = [] # 一个大物理步也可能同时包含起跳前和落地后的路面。
	if start < _deck_gap.x:
		segments.append(Vector2(start, minf(end, _deck_gap.x)))
	if end >= _deck_gap.y:
		segments.append(Vector2(maxf(start, _deck_gap.y), end))
	return segments


## 返回最前到最后轮胎的世界横向偏移，兼容炮塔缩放和镜像。
func axle_offsets() -> Vector2:
	var axis: float = global_transform.x.x # 原画横轴在世界坐标中的投影。
	var first: float = AXLE_SPAN.x * axis # 最前轮的偏移。
	var last: float = AXLE_SPAN.y * axis # 最后轮的偏移。
	return Vector2(minf(first, last), maxf(first, last))


## [param seconds] 为入场动作秒数，[param advance] 为向车头方向滚过的世界像素。
## [param cruise_ratio] 是当前速度与巡航速度之比，停稳后只更新车身回弹。
func pose_entrance(seconds: float, advance: float, cruise_ratio: float) -> void:
	var gap_width: float = _deck_gap.y - _deck_gap.x # 腾跃从敌舰边缘延伸至目标甲板。
	var airborne_distance: float = clampf(advance - _deck_gap.x, 0.0, gap_width) # 已在空中走过的水平距离。
	var flight: float = airborne_distance / maxf(gap_width, 1.0) # 从起跳的零到接地的一。
	var lift: float = 4.0 * flight * (1.0 - flight) # 落地前垂直速度增加，接地后交给悬挂。
	var just_landed: bool = position.y < 0.0 and lift <= 0.0 # 跨过接地点的第一帧喷出灰尘。
	position.y = -DECK_JUMP_HEIGHT * lift
	_shadow_material.set_shader_parameter(&"projection_strength", 1.0 - 0.76 * lift)
	if just_landed:
		_landing_dust.restart()
		_landing_dust.emitting = true
		SoundManager.play_world_sfx(DECK_LANDING_SOUND, self, _landing_dust.global_position,
			-15.0, 0.86, &"cannon_deck_landing", true, 1)

	var radius: float = WHEEL_RADIUS * global_transform.x.length() # 距离折算考虑战斗中的体型。
	var wheel_advance: float = advance - 0.78 * airborne_distance # 腾空时车轮惯性慢转，接地后恢复同步。
	var last_roll_step := floori(_wheel_phase / ROLL_CUE_STEP) # 记录真实轱辘行进段，静止或腾空不发声。
	_wheel_phase = wheel_advance / maxf(radius, 0.001)
	_wheel_material.set_shader_parameter(&"wheel_phase", _wheel_phase)
	var lean: float = _sample(BRAKING, seconds) * (1.0 - lift) # 前倾受力在着陆时完成，停稳后回摆。
	var ripple: float = 0.48 * sin(_wheel_phase * 3.0) * cruise_ratio * (1.0 - lift) # 细小起伏主要在接地时可见。
	var jump_pitch: float = 5.0 * sin(TAU * flight) # 起跳抬头，落地前以车头接近甲板。
	_pose_chassis(0.0, -3.55 * lean + ripple + jump_pitch, lean)
	_turret.rotation_degrees = -5.8 * lean - ripple * 0.48
	_turret.position = TURRET_REST + Vector2(-8.0 * lean, 5.0 * lean)
	if lift <= 0.0 and not just_landed and cruise_ratio > 0.12 \
			and floori(_wheel_phase / ROLL_CUE_STEP) > last_roll_step:
		var audio := SoundManager.world_audio_for(self) # 只有启用花园飞艇声场时才增加滚轮音。
		if audio != null:
			audio.play_at(DECK_ROLL_SOUND, _chassis.to_global(TIRE_CONTACT), -25.0,
				lerpf(0.85, 1.12, clampf(cruise_ratio, 0.0, 1.0)), &"cannon_deck_roll")


## [param horizontal] 为底盘沿轨道的局部位移，[param pitch] 为俯仰角度。
## [param front_load] 为车头受力程度。俯仰和悬挂位移以承重轮接地点为基准。
func _pose_chassis(horizontal: float, pitch: float, front_load: float) -> void:
	_chassis.rotation_degrees = pitch
	var tire_position: Vector2 = TIRE_CONTACT.rotated(_chassis.rotation) # 转动后胎底的偏移。
	_chassis.position = Vector2(horizontal, TIRE_CONTACT.y - tire_position.y)
	_shadow_material.set_shader_parameter(&"vehicle_load", front_load)
	_shadow_material.set_shader_parameter(&"axle_shift", horizontal * scale.x)


## 引爆 [param source] 所在的炮台座，返回可绑定底盘快照的飞艇事件序号。
func play_death_blast(source: Zombie000Base) -> int:
	var size: float = 0.49 * source.transform.x.length() # 与机体及小僵尸缩放保持比例。
	var facing: float = float(source.direction_x_root) # 与底盘一起镜像余爆位置。
	var followups := PackedVector2Array([Vector2(-94.0 * facing, 36.0),
		Vector2(70.0 * facing, 49.0)]) # 两个局部爆心落在前后轮上方。
	var parts := PackedVector2Array([_chassis.to_global(Vector2(-98.0, -80.0)),
		_chassis.to_global(Vector2(96.0, -55.0))]) # 当帧的两处承重轴上方，涵盖原轴滚动和镜像。
	return VehicleDeathBlast.play(source, &"cannon_turret_death_blast", _blast_origin.global_position, size, followups, parts)


## 播放重后坐和装填，返回开火瞬间的炮口世界姿态。
func fire() -> Transform2D:
	var muzzle: Transform2D = _muzzle.global_transform # 出膛和粒子使用后坐之前的真实朝向与位置。
	_turret_sprite.texture = EMPTY
	var animation: Tween = create_tween() # 随战场暂停和炮车释放。
	animation.tween_method(_pose_recoil, 0.0, 1.12, 1.12)
	animation.tween_method(_pose_reload, 0.0, 1.44, 1.44)
	return muzzle


## [param seconds] 为开火后经过的秒数，分别推进炮身和底盘。
func _pose_recoil(seconds: float) -> void:
	var recoil: float = _sample(TURRET_RECOIL, seconds) # 炮身先受力。
	var travel: float = _sample(CHASSIS_RECOIL, seconds) # 底盘延后达到峰值。
	_turret.position = TURRET_REST - BARREL_AXIS * (14.04 * recoil)
	_turret.rotation_degrees = 6.4 * recoil
	var roll_back: float = 14.29 * travel # 底盘可随炮身向后滚动少量距离。
	_pose_chassis(roll_back, 2.1 * travel, -travel * 0.62)
	_wheel_material.set_shader_parameter(&"wheel_phase", _wheel_phase - roll_back / WHEEL_RADIUS)


## [param seconds] 为装填动作秒数。1.06 秒时锁膛并换回完整装弹图。
func _pose_reload(seconds: float) -> void:
	var depth: float = _sample(RELOAD_DEPTH, seconds) # 正值位于炮管深处。
	var light: float = 1.0 - 0.38 * maxf(depth, 0.0) / 79.0 # 向外推送时自然变亮。
	_reload_shell.visible = seconds < 1.06
	_reload_shell.position = SHELL_REST - BARREL_AXIS * depth
	_reload_shell.scale = Vector2.ONE * (1.0 - 0.20 * maxf(depth, 0.0) / 79.0)
	_reload_shell.modulate = Color(light, light, light)
	_turret.rotation_degrees = -2.9 * sin(PI * clampf(seconds / 1.44, 0.0, 1.0))
	if seconds >= 1.06 and _turret_sprite.texture != LOADED:
		_turret_sprite.texture = LOADED
		var audio := SoundManager.world_audio_for(self) # 装弹图锁定的首帧才有机械尾音。
		if audio != null:
			audio.play_at(RELOAD_LOCK_SOUND, _reload_shell.global_position, -18.0, 0.94, &"cannon_reload")


## [param keys] 按秒数排序且至少有两个采样点，[param seconds] 是当前动作时间。
## 返回缓动后的参数值，末帧之后保持原姿势。
static func _sample(keys: Array[Vector2], seconds: float) -> float:
	for index: int in range(1, keys.size()): # 找到包围时间的相邻两个关键帧。
		var next: Vector2 = keys[index] # 区间结束值。
		if seconds <= next.x:
			var previous: Vector2 = keys[index - 1] # 区间开始值。
			return lerpf(previous.y, next.y, smoothstep(previous.x, next.x, seconds))
	return keys[-1].y
