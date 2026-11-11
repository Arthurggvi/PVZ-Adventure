## 显示一个僵王的头像、剩余血量和阶段。屏幕布局由 [LevelInfo] 管理。
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
## 从绑定角色读取的头像。
@onready var boss_icon: TextureRect = $BossIcon
## 随阶段过渡渐显的头像边框。
@onready var portrait_frame_phase2: TextureRect = $PortraitFramePhase2

## 本条血条的绑定对象，开始离场淡出后清空。
var _boss: ZB000Base
## 绑定角色的血量组件，离场时解除连接。
var _hp_component: HpComponent
## 上次已同步的真实血量，-1 表示未绑定角色。
var _last_hp: int = -1
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
	if _boss == boss:
		if _last_hp != _hp_component.curr_hp:
			_stop_hp_tween()
			_last_hp = _hp_component.curr_hp
			_apply_remaining_ratio(float(_last_hp) / float(_hp_component.max_hp))
		return
	_unbind_boss()
	_boss = boss
	_hp_component = boss.hp_component
	_last_hp = _hp_component.curr_hp
	_hp_component.signal_hp_loss.connect(_on_boss_hp_loss)
	boss.signal_boss_phase_changed.connect(_on_boss_phase_changed)
	boss_icon.texture = boss.boss_portrait_texture
	_apply_remaining_ratio(float(_last_hp) / float(_hp_component.max_hp))
	_set_phase(boss.boss_phase >= 2, false)
	_enter()


## [param depleted] 为 true 时先清空血量；绑定对象已经死亡时也清空血量。
## 离场期间解绑角色，淡出完成后发出 [signal signal_fade_finished]。
func fade_out(depleted: bool) -> void:
	if _is_fading_out:
		return
	_is_fading_out = true
	# 角色死亡通知可能先于扣血通知发出，离场前主动同步为零血。
	var empty_bar: bool = depleted or (is_instance_valid(_boss) and _boss.is_death)
	_unbind_boss()
	if empty_bar:
		_apply_remaining_ratio(0.0)
	_stop_life_tween()
	_life_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_life_tween.tween_method(_set_life_alpha, _life_alpha, 0.0, death_fade_seconds)
	_life_tween.tween_callback(_finish_fade)


## 开始入场淡入，同一实例重新出现时替换尚未结束的离场动画。
func _enter() -> void:
	_is_fading_out = false
	_stop_life_tween()
	_mouse_alpha = 1.0
	_set_life_alpha(0.0)
	show()
	_life_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_life_tween.tween_method(_set_life_alpha, 0.0, 1.0, entrance_fade_seconds)


## [param value] 入场和离场补间的透明度系数，取值为 0 至 1。
func _set_life_alpha(value: float) -> void:
	_life_alpha = value
	modulate.a = _life_alpha * _mouse_alpha


## 隐藏已淡出的素材，再通知关卡腾出布局空间。
func _finish_fade() -> void:
	hide()
	signal_fade_finished.emit()


## [param remaining] 扣血后的剩余血量；[param _is_drop] 由扣血组件用于掉落逻辑。
func _on_boss_hp_loss(remaining: int, _is_drop: bool) -> void:
	if not is_instance_valid(_hp_component):
		return
	_last_hp = remaining
	# 归一化到 0 至 1，保护裁切容器的宽度。
	var fraction: float = clampf(float(remaining) / float(maxi(_hp_component.max_hp, 1)), 0.0, 1.0)
	_stop_hp_tween()
	if remaining <= 0 or hp_transition_duration <= 0.0:
		_apply_remaining_ratio(fraction)
		return
	_hp_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hp_tween.tween_method(_apply_remaining_ratio, _remaining_ratio, fraction, hp_transition_duration)


## [param phase] 角色的新阶段编号，第二阶段及以上使用二阶段素材。
func _on_boss_phase_changed(phase: int) -> void:
	_set_phase(phase >= 2, true)


## [param second] 是否显示二阶段素材；[param animated] 是否使用叠化补间。
func _set_phase(second: bool, animated: bool) -> void:
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


## [param ratio] 当前要绘制的剩余血量比例；裁切填充纹理，保留原纹理的横向比例。
func _apply_remaining_ratio(ratio: float) -> void:
	_remaining_ratio = clampf(ratio, 0.0, 1.0)
	# 共享裁切宽度，保证切换阶段时血量位置对齐。
	var fill_width: float = HEALTH_FILL_WIDTH * _remaining_ratio
	phase1_fill_clip.size.x = fill_width
	phase2_fill_clip.size.x = fill_width


## 解除血量和阶段信号，保持当前绘制比例以便淡出。
func _unbind_boss() -> void:
	_stop_hp_tween()
	if is_instance_valid(_hp_component) and _hp_component.signal_hp_loss.is_connected(_on_boss_hp_loss):
		_hp_component.signal_hp_loss.disconnect(_on_boss_hp_loss)
	if is_instance_valid(_boss) and _boss.signal_boss_phase_changed.is_connected(_on_boss_phase_changed):
		_boss.signal_boss_phase_changed.disconnect(_on_boss_phase_changed)
	_hp_component = null
	_boss = null
	_last_hp = -1


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
	_unbind_boss()
	_stop_life_tween()
	if is_instance_valid(_phase_tween):
		_phase_tween.kill()
