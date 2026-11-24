## 显示一个僵王或一次遭遇的头像、剩余血量和阶段。屏幕布局由 [LevelInfo] 管理。
extends Control
class_name BossHpProgressBar

## 离场淡出结束后通知关卡释放该血条并重排。
signal signal_fade_finished

## 血条场景未缩放时的完整尺寸，单位为界面像素。
const DISPLAY_SIZE := Vector2(556.0, 136.0)
## 两套阶段填充纹理共用的裁切宽度，单位为缩放前的界面像素。
const HEALTH_FILL_WIDTH := 370.0
## 指针在血条外多少界面像素内也触发淡出，与血条的缩放倍率无关。
const MOUSE_MARGIN := 9.0

## 每次血量变化的补间时长，单位为秒。
@export_range(0.0, 1.0, 0.01) var hp_transition_duration: float = 0.22
## 血条初次显示的淡入时长，单位为秒。
@export_range(0.0, 1.0, 0.01) var entrance_fade_seconds: float = 0.24
## 僵王离场后的淡出时长，单位为秒。
@export_range(0.0, 1.0, 0.01) var death_fade_seconds: float = 0.34
## 转阶段时，两套装饰和血条纹理叠化的时长，单位为秒。
@export_range(0.0, 1.0, 0.01) var phase_blend_seconds: float = 0.28
## 鼠标靠近血条时的目标透明度，方便查看下方战场。
@export_range(0.05, 1.0, 0.05) var mouse_near_opacity: float = 0.13

## 一阶段填充裁切容器，宽度随血量变化。
@onready var phase1_fill_clip: Control = $Phase1Bar/FillClip
## 叠加在一阶段之上的二阶段血条素材容器。
@onready var phase2_bar: Control = $Phase2Bar
## 二阶段填充裁切容器，与一阶段同步更新宽度。
@onready var phase2_fill_clip: Control = $Phase2Bar/FillClip
## 绑定时从首个角色读取的头像，分组内成员离场后继续使用。
@onready var boss_icon: TextureRect = $BossIcon
## 随阶段过渡渐显的头像边框。
@onready var portrait_frame_phase2: TextureRect = $PortraitFramePhase2
## 有阶段称谓的 Boss 在血条上方显示当前名称。
@onready var boss_name: Label = $BossName

## 本条血条当前绑定的存活角色，离场淡出时解除连接并清空。
var _members: Array[ZB000Base] = []
## 绑定的遭遇编号，0 为独立僵王。淡出期间保留编号以接回同组成员。
var _group_id: int = 0
## 上次同步的剩余生命合计，-1 表示需要重新计算。
var _last_hp: int = -1
## 上次同步的显示上限，与剩余生命一起判断比例是否改变。
var _last_max_hp: int = 0
## 是否已切换到二阶段素材，成员更替时保留同组遭遇的阶段。
var _second_phase: bool = false
## 当前绘制的剩余血量比例，补间期间可与真实血量不同。
var _remaining_ratio: float = 1.0
## 血量变化补间，连续受伤时从当前绘制比例重启。
var _hp_tween: Tween
## 阶段叠化补间，重新绑定时取消。
var _phase_tween: Tween
## 入场与离场共用的透明度补间。
var _life_tween: Tween
## 由入场或离场动画控制的透明度系数。
var _life_alpha: float = 0.0
## 由鼠标靠近程度控制的透明度系数。
var _mouse_alpha: float = 1.0
## 是否已经在执行离场淡出，防止重复快照重启动画。
var _is_fading_out: bool = false


## 使用 HUD 图层坐标，由关卡在成功绑定时定位并显示。
func _ready() -> void:
	top_level = true
	size = DISPLAY_SIZE
	hide()


## [param delta] 距上一帧的秒数；鼠标靠近时平滑降低本条血条的透明度。
func _process(delta: float) -> void:
	if not visible:
		return
	# 先缩放布局矩形，再扩张固定的界面像素，确保紧凑血条也能及时让开。
	var near: bool = get_global_rect().grow(MOUSE_MARGIN).has_point(get_global_mouse_position())
	# 指针移开后恢复原有亮度，靠近时保留可辨识的血条轮廓。
	var target: float = mouse_near_opacity if near else 1.0
	_mouse_alpha = move_toward(_mouse_alpha, target, delta * 7.0)
	modulate.a = _life_alpha * _mouse_alpha


## [param boss] 已初始化且最大血量大于零的僵王；重复绑定保持现有动画。
func bind_boss(boss: ZB000Base) -> void:
	bind_bosses([boss])


## [param bosses] 至少一个已初始化的存活成员，多人必须属于同一分组。
## 分组内成员变化时保留头像和阶段，按最新总血量补间。
func bind_bosses(bosses: Array[ZB000Base]) -> void:
	if bosses.is_empty():
		return
	var group_id: int = bosses[0].boss_encounter_group_id() # 首个成员提供本组稳定编号。
	var members_changed: bool = _members != bosses # 只在名单变化时更新信号连接。
	var new_binding: bool = group_id != _group_id or (group_id == 0 and members_changed) # 新遭遇或独立实例。
	if members_changed:
		_sync_member_signals(bosses)
	_group_id = group_id
	if new_binding:
		boss_icon.texture = bosses[0].boss_portrait_texture
		boss_name.visible = not bosses[0].phase_two_display_name.is_empty()
		_last_hp = -1
		_set_phase(bosses[0].boss_phase >= 2, false)
	if group_id != 0 and not _second_phase:
		for boss: ZB000Base in bosses: # 任一成员进入二阶段即可切换同一条血条的外观。
			if boss.boss_phase >= 2:
				_set_phase(true, not new_binding)
				break
	_sync_hp(group_id != 0 and not new_binding)
	if new_binding or _is_fading_out:
		_enter(not new_binding)


## [param depleted] 为 true 或全部绑定成员已死亡时，先清空血量。
## 离场期间解除全部信号连接，淡出完成后发出 [signal signal_fade_finished]。
func fade_out(depleted: bool) -> void:
	if _is_fading_out:
		return
	_is_fading_out = true
	# 死亡通知先于最后的扣血通知，需要在全员死亡时主动清空。
	var empty_bar: bool = depleted
	if not empty_bar and not _members.is_empty():
		empty_bar = true
		for boss: ZB000Base in _members: # 未死亡而离场的角色淡出时保留此前比例。
			if not is_instance_valid(boss) or not boss.is_death:
				empty_bar = false
				break
	_sync_member_signals([])
	_last_hp = -1
	_stop_hp_tween()
	if empty_bar:
		_apply_remaining_ratio(0.0)
	_stop_life_tween()
	_life_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_life_tween.tween_method(_set_life_alpha, _life_alpha, 0.0, death_fade_seconds)
	_life_tween.tween_callback(_finish_fade)


## 开始入场淡入，[param resume] 为 true 时从同组淡出时的透明度接着播放。
func _enter(resume: bool) -> void:
	_is_fading_out = false
	_stop_life_tween()
	if not resume:
		_mouse_alpha = 1.0
		_set_life_alpha(0.0)
	show()
	_life_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_life_tween.tween_method(_set_life_alpha, _life_alpha, 1.0, entrance_fade_seconds)


## [param value] 入场和离场补间的透明度系数，取值为 0 至 1。
func _set_life_alpha(value: float) -> void:
	_life_alpha = value
	modulate.a = _life_alpha * _mouse_alpha


## 隐藏已淡出的素材，再通知关卡腾出布局空间。
func _finish_fade() -> void:
	hide()
	signal_fade_finished.emit()


## [param _remaining] 为单个成员剩余生命，[param _is_drop] 为该成员的掉落开关。
## 总值重新读取存活成员的组件，以纳入扣血期间的同步增援或退场。
func _on_boss_hp_loss(_remaining: int, _is_drop: bool) -> void:
	if not _members.is_empty():
		_sync_hp(true)


## 从存活成员的组件合计血量，[param animated] 指定是否从当前绘制比例补间。
## 遭遇指定的固定满值优先于组件最大值，成员离场时分母保持不变。
func _sync_hp(animated: bool) -> void:
	var remaining: int = 0 # 在场成员的实际剩余生命。
	var maximum: int = 0 # 未指定固定满值时使用的组件最大生命之和。
	var fixed_maximum: int = 0 # 由遭遇提供的显示满值，0 表示使用组件数据。
	for boss: ZB000Base in _members: # 管理器死亡回调先移除对应成员，扣血信号稍后发出。
		if not is_instance_valid(boss) or boss.is_death or not is_instance_valid(boss.hp_component):
			continue
		remaining += boss.hp_component.curr_hp
		maximum += boss.hp_component.max_hp
		fixed_maximum = maxi(fixed_maximum, boss.boss_encounter_maximum_hp())
	if fixed_maximum > 0:
		maximum = fixed_maximum
	if remaining == _last_hp and maximum == _last_max_hp:
		return
	_last_hp = remaining
	_last_max_hp = maximum
	# 归一化到 0 至 1，保护裁切容器的宽度。
	var fraction: float = clampf(float(remaining) / float(maxi(maximum, 1)), 0.0, 1.0)
	_stop_hp_tween()
	if not animated or remaining <= 0 or hp_transition_duration <= 0.0:
		_apply_remaining_ratio(fraction)
		return
	_hp_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hp_tween.tween_method(_apply_remaining_ratio, _remaining_ratio, fraction, hp_transition_duration)


## [param phase] 角色的新阶段编号，第二阶段及以上使用二阶段素材。
func _on_boss_phase_changed(phase: int) -> void:
	if _group_id != 0 and (_second_phase or phase < 2):
		return
	_set_phase(phase >= 2, true)


## [param second] 是否显示二阶段素材；[param animated] 是否使用叠化补间。
func _set_phase(second: bool, animated: bool) -> void:
	_second_phase = second
	_refresh_boss_name()
	if is_instance_valid(_phase_tween):
		_phase_tween.kill()
	# 二阶段素材覆盖在一阶段上，只需改变叠加层透明度。
	var target: float = 1.0 if second else 0.0
	if not animated or phase_blend_seconds <= 0.0:
		phase2_bar.modulate.a = target
		portrait_frame_phase2.modulate.a = target
		return
	_phase_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_phase_tween.tween_property(phase2_bar, "modulate:a", target, phase_blend_seconds)
	_phase_tween.parallel().tween_property(portrait_frame_phase2, "modulate:a", target, phase_blend_seconds)

## 独立 Boss 提供当前已公开的称谓，分组血条仍显示整个遭遇的阶段名称。
func _refresh_boss_name() -> void:
	if not boss_name.visible or _members.is_empty() or not is_instance_valid(_members[0]):
		return
	var boss: ZB000Base = _members[0] # 血条继承绑定成员的称谓规则。
	var phase: int = 0 if _group_id == 0 else (2 if _second_phase else 1) # 零表示请角色读取实战名。
	boss_name.text = boss.get_boss_display_name(phase)


## [param ratio] 当前要绘制的剩余血量比例；裁切填充纹理，保留原纹理的横向比例。
func _apply_remaining_ratio(ratio: float) -> void:
	_remaining_ratio = clampf(ratio, 0.0, 1.0)
	# 共享裁切宽度，保证切换阶段时血量位置对齐。
	var fill_width: float = HEALTH_FILL_WIDTH * _remaining_ratio
	phase1_fill_clip.size.x = fill_width
	phase2_fill_clip.size.x = fill_width


## 同步 [param bosses] 的血量、阶段和称谓连接，保留在场成员原有的连接顺序。
func _sync_member_signals(bosses: Array[ZB000Base]) -> void:
	for boss: ZB000Base in _members: # 从快照中移除的成员不再更新血条。
		if not is_instance_valid(boss) or bosses.has(boss):
			continue
		if is_instance_valid(boss.hp_component) and boss.hp_component.signal_hp_loss.is_connected(_on_boss_hp_loss):
			boss.hp_component.signal_hp_loss.disconnect(_on_boss_hp_loss)
		if boss.signal_boss_phase_changed.is_connected(_on_boss_phase_changed):
			boss.signal_boss_phase_changed.disconnect(_on_boss_phase_changed)
		if boss.signal_boss_display_name_changed.is_connected(_refresh_boss_name):
			boss.signal_boss_display_name_changed.disconnect(_refresh_boss_name)
	for boss: ZB000Base in bosses: # 新成员接入同一条血条的更新入口。
		if not _members.has(boss):
			boss.hp_component.signal_hp_loss.connect(_on_boss_hp_loss)
			boss.signal_boss_phase_changed.connect(_on_boss_phase_changed)
			boss.signal_boss_display_name_changed.connect(_refresh_boss_name)
	_members.assign(bosses)


## 停止现有血量补间，保留最后绘制的裁切宽度。
func _stop_hp_tween() -> void:
	if is_instance_valid(_hp_tween):
		_hp_tween.kill()
	_hp_tween = null


## 停止现有入场或离场补间，并取消其后续回调。
func _stop_life_tween() -> void:
	if is_instance_valid(_life_tween):
		_life_tween.kill()
	_life_tween = null


## 关卡退出时断开信号并取消未完成的动画。
func _exit_tree() -> void:
	_sync_member_signals([])
	_stop_hp_tween()
	_stop_life_tween()
	if is_instance_valid(_phase_tween):
		_phase_tween.kill()
