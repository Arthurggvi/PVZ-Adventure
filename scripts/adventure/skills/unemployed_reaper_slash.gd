## 莫伊的一次落斩。前景刀锋与脚下裂痕共享图集、坐标和时间轴。
extends Node2D

## 用户动画的 6×4 透明图集；各 256 像素原帧外有 2 像素透明边距。
const SLASH_ATLAS: Texture2D = preload("res://assets/adventure/environment_fx/reaper_slash.png")
## 同一材质定义负责刀锋和地面两个局部绘制层。
const SLASH_SHADER: Shader = preload("res://shaders/adventure/unemployed_reaper_slash.gdshader")
## 斩风与低频冲击共用一段短音轨，低频起拍贴合落斩。
const IMPACT_SOUND: AudioStream = preload("res://assets/adventure/audio/unemployed_reaper_slash.ogg")
## Cut-in 退场刚开始时显露棋盘预兆，以下演出均使用实际秒。
const WINDUP_START: float = 0.92
## Cut-in 收净后，刀锋最亮的一帧同时结算伤害、闪屏和震屏。
const IMPACT_TIME: float = 1.25
## 同一峰值帧为表现与碰撞提供轮廓。
const ImpactFootprint = preload("res://scripts/adventure/skills/unemployed_reaper_impact_footprint.gd")
## 刀光由左下向右上，角度以竖直方向为基准。
const BLADE_LEAN_DEGREES: float = 30.0
## 刀风先掠过这一小段实际秒，低频起拍与闪屏对齐。
const IMPACT_AUDIO_LEAD: float = 0.040
## 在地图底图与原生卡槽之间铺光，角色、刀锋与界面都在亮幕前。
const IMPACT_FLASH_LAYER: int = -2
## 落斩时淡紫色反光的峰值颜色和透明度。
const IMPACT_FLASH_COLOR := Color(0.96, 0.88, 1.0, 0.40)
## 地面裂口在世界画布上，低于种植格、角色与棋盘内道具。
const GROUND_Z_INDEX: int = 2
## 刀锋主图退出前景的实际秒数。
const BLADE_TAIL: float = 1.24
## 地面裂缝与余火完全收净的实际秒数。
const GROUND_TAIL: float = 1.94
## 完整保留撞击声的尾音，节点随后回收。
const SOUND_TAIL: float = 2.28
## 一次落斩的基础伤害，仍走通常防御和伤害分流。
const IMPACT_DAMAGE: int = 3000

## 允许普通暂停但禁止跨轮、棋盘和冒险阶段兑现的来源。
var _battle: RepeaterShotContext
## 只用于读取当前敌方目标及其资格的主动技能上下文。
var _context: CharacterSkillContext
## 出手时确定的实际列地块，落斩时重新读取世界坐标。
var _cells: Array[PlantCell]
## 由渲染带宽、高度和剪切量构成，落斩帧用于还原刀光的世界几何。
var _blade_to_world: Transform2D
## 从角色前掠过的刀身和瞬时高光。
var _blade: Sprite2D
## 可被角色和地块道具遮挡的落点、震波与余烬。
var _ground: Sprite2D
## 确保跨过命中时点时只兑现一次。
var _struck: bool = false

## 绑定 [param battle]、[param context] 和目标列 [param cells]，场景接纳后开始计时。
func _init(battle: RepeaterShotContext, context: CharacterSkillContext, cells: Array[PlantCell]) -> void:
	_battle = battle
	_context = context
	_cells = cells

## 准备延迟时间轴；暂停时冻结演出，但仍能响应战斗结束。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_blade = _add_visual(false)
	_ground = _add_visual(true)
	var timeline: Tween = create_tween().set_ignore_time_scale(true).set_pause_mode(Tween.TWEEN_PAUSE_STOP) # 与 Cut-in 同步，不随倍速抢拍。
	timeline.tween_interval(WINDUP_START)
	timeline.tween_method(_animate, WINDUP_START, IMPACT_TIME + SOUND_TAIL, IMPACT_TIME + SOUND_TAIL - WINDUP_START)
	timeline.parallel().tween_callback(_play_impact_sound).set_delay(IMPACT_TIME - WINDUP_START - IMPACT_AUDIO_LEAD)
	timeline.finished.connect(queue_free)

## 创建单个局部绘制层；[param on_ground] 使用绝对世界深度，刀锋则沿用战场爆炸层。
func _add_visual(on_ground: bool) -> Sprite2D:
	var visual := Sprite2D.new() # 两个层共用一张已导入的帧图集。
	visual.texture = SLASH_ATLAS
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var material := ShaderMaterial.new() # 一层只计算自身的成像分支。
	material.shader = SLASH_SHADER
	material.set_shader_parameter(&"ground_pass", on_ground)
	visual.material = material
	if on_ground:
		visual.z_as_relative = false
		visual.z_index = GROUND_Z_INDEX
	visual.hide()
	add_child(visual)
	return visual

## [param _delta] 不推进动画；暂停及结算期间只检查原战局是否仍有效。
func _process(_delta: float) -> void:
	if not _battle.is_active():
		queue_free()

## 在实际秒 [param elapsed] 更新预兆、首击与收束，命中时锁定刀光的世界几何。
func _animate(elapsed: float) -> void:
	if not _battle.is_active() or is_queued_for_deletion():
		return
	var after_hit: float = elapsed - IMPACT_TIME # 负值表示刀光尚在蓄势。
	if _struck and after_hit >= GROUND_TAIL:
		_blade.hide()
		_ground.hide()
		return
	if not _struck and not _update_blade_geometry():
		queue_free()
		return
	var impacts_now: bool = not _struck and after_hit >= 0.0 # 无论本帧跨过多少时间，只兑现一次大落斩。
	var visual_age: float = 0.0 if impacts_now else after_hit # 首个命中画面总能收到完整的亮核。
	var charge: float = clampf(inverse_lerp(WINDUP_START, IMPACT_TIME, elapsed), 0.0, 1.0) # 源图开头逐帧提亮。
	var ground_material := _ground.material as ShaderMaterial # 脚下余火在刀锋退场后继续收束。
	ground_material.set_shader_parameter(&"windup", charge)
	ground_material.set_shader_parameter(&"after_hit", visual_age)
	_ground.show()
	_blade.visible = visual_age < BLADE_TAIL
	if _blade.visible:
		var blade_material := _blade.material as ShaderMaterial # 前景只推进刀身的源动画。
		var frame: int = mini(23, ImpactFootprint.ATLAS_FRAME + floori(maxf(0.0, visual_age) * 12.0)) # 亮核随余震转入尾帧。
		if visual_age < 0.0:
			frame = mini(ImpactFootprint.ATLAS_FRAME - 1, 1 + floori(pow(charge, 2.4) * float(ImpactFootprint.ATLAS_FRAME - 1)))
		blade_material.set_shader_parameter(&"frame_tile", Vector2(frame % 6, floori(float(frame) / 6.0)))
		blade_material.set_shader_parameter(&"windup", charge)
		blade_material.set_shader_parameter(&"after_hit", visual_age)
	if impacts_now:
		_struck = true
		_strike()

## 从倒数第三列读取中心和尺寸，将预兆、斩击与碰撞投影到同一个世界范围。
func _update_blade_geometry() -> bool:
	var bounds := Rect2() # 合并各行地块，用同一个中心锚住斩击与残留。
	for cell: PlantCell in _cells: # 动态平台在落斩前可继续移动。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion() or not cell.is_visible_in_tree():
			continue
		var rect: Rect2 = cell.get_global_rect() # 当前世界落点，不以格号筛目标。
		bounds = bounds.merge(rect) if bounds.has_area() else rect
	if not bounds.has_area():
		return false
	var band_size: Vector2 = bounds.size * Vector2(4.25, 1.28) # 保证刀锋长度不随倾角缩短，横向留空间给火翼。
	var lean_width: float = band_size.y * tan(deg_to_rad(BLADE_LEAN_DEGREES)) # 上下端在世界坐标上的水平跨度。
	var canvas_size: Vector2 = band_size + Vector2(lean_width, 0.0) # 覆盖倾斜前后完整外接范围，避免两端裁切。
	var mapping: Vector2 = Vector2(canvas_size.x, lean_width) / band_size.x # 两层以同一斜线对齐地面切口。
	_blade_to_world = Transform2D(Vector2(band_size.x, 0.0), Vector2(-lean_width, band_size.y), bounds.get_center())
	for visual: Sprite2D in [_blade, _ground]: # 两层一直使用相同世界范围，保持刀口与裂纹对位。
		visual.global_position = _blade_to_world.origin
		visual.scale = canvas_size / SLASH_ATLAS.get_size()
		var material := visual.material as ShaderMaterial # 把共同坐标映射提交给各自材质。
		material.set_shader_parameter(&"blade_mapping", mapping)
	return true

## 提前送出音轨的刀风前沿，低频撞击跟随真正落斩。
func _play_impact_sound() -> void:
	if is_queued_for_deletion() or not _context.is_active():
		return
	var sound := AudioStreamPlayer.new() # 跟随本次演出的生命周期，离场即停。
	sound.process_mode = Node.PROCESS_MODE_PAUSABLE
	sound.bus = SoundManager.spatial_sfx_bus()
	sound.stream = IMPACT_SOUND
	sound.volume_db = -2.5
	add_child(sound)
	sound.play()

## 兑现落斩的单次闪光，短促衰减会在暂停菜单打开后继续收净。
func _flash_impact() -> void:
	var layer := CanvasLayer.new() # 屏幕坐标不随落斩震屏移动。
	layer.layer = IMPACT_FLASH_LAYER
	add_child(layer)
	var flash := ColorRect.new() # 纯光照层全程放行鼠标和触摸。
	flash.color = IMPACT_FLASH_COLOR
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fade: Tween = layer.create_tween().set_ignore_time_scale(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS) # 一次峰值后平滑回落。
	fade.tween_interval(0.018)
	fade.tween_property(flash, ^"color:a", 0.0, 0.115).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fade.finished.connect(layer.queue_free)

## 刀光最强帧触发闪屏和震屏，再经常规管线一次性结算目标。
func _strike() -> void:
	if not _context.is_active():
		queue_free()
		return
	_flash_impact()
	EventBus.push_event(MainGameCamera.SHAKE_EVENT, [Vector2(4.0, 9.0), 0.22, 23.0])
	var footprint := ImpactFootprint.new(_blade_to_world) # 峰值刀光的凸片只在落斩这一帧用于结算。
	var scope := CombatHitScope.new() # 同一实际承伤者只处理一次，包含保护者转伤。
	var receipt: Dictionary = {} # 复用回执容器，逐击读取真实承伤者。
	for target: Character000Base in _context.hostile_targets(): # 候选以落斩瞬间为准，排除友方与敌方设施。
		if not _battle.is_active():
			break
		if not CharacterSkillTargetQuery.is_valid_hostile(_context, target) \
				or not ElectricPeaFlightQuery.can_hit(target):
			continue
		if not footprint.overlaps(target.hurt_box_component.hurt_box_real):
			continue
		target.be_attacked_bullet(IMPACT_DAMAGE, BulletRegistry.AttackMode.Norm, true, false, 0, -1, receipt, scope)
		var recipient: Variant = receipt.get("recipient") # 上一击可能已同步击杀或移除该角色。
		if int(receipt.get("actual_loss", 0)) > 0 and is_instance_valid(recipient) and _battle.is_active():
			UnemployedReaperBurn.ignite(recipient, _battle)
