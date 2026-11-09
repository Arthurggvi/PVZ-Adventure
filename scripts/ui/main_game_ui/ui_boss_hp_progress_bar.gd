## One universal boss portrait + long HP bar; binds only the already-existing HpComponent.
## ZB000Base owns phase transitions. LevelInfo owns lifecycle & wave UI switching.
extends Control
class_name BossHpProgressBar

@export_range(0.0, 1.0, 0.01) var hp_transition_duration: float = 0.22
@export_range(0.0, 1.0, 0.01) var entrance_fade_seconds: float = 0.36
@export_range(0.0, 1.0, 0.01) var death_fade_seconds: float = 0.48
@export_range(0.0, 1.0, 0.01) var phase_blend_seconds: float = 0.28
@export_range(0.05, 1.0, 0.05) var mouse_near_opacity: float = 0.13

const DISPLAY_SIZE := Vector2(615, 180)
## 整组 HUD 的显示倍率，覆盖两阶段血条、头像、头像框与名称。
const DISPLAY_SCALE := 0.5
## HUD 底边与视口底边的距离，单位为界面像素。
const BOTTOM_MARGIN := 6.0
const HEALTH_FILL_WIDTH := 370.0
const MOUSE_MARGIN := 40.0

@onready var phase1_fill_clip: Control = $Phase1Bar/FillClip
@onready var phase2_bar: Control = $Phase2Bar
@onready var phase2_fill_clip: Control = $Phase2Bar/FillClip
@onready var boss_icon: TextureRect = $BossIcon
@onready var portrait_frame_phase2: TextureRect = $PortraitFramePhase2
@onready var living_boss_count_label: Label = $BossNameLabel

var _boss: ZB000Base
var _hp_component: HpComponent
var _last_hp: int = -1
var _remaining_ratio: float = 1.0
var _hp_tween: Tween
var _phase_tween: Tween
var _life_tween: Tween
var _life_alpha: float = 0.0
var _mouse_alpha: float = 1.0
var _is_fading_out: bool = false
var _phase_two: bool = false

func _ready() -> void:
    top_level = true
    size = DISPLAY_SIZE
    scale = Vector2.ONE * DISPLAY_SCALE
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    visible = false
    modulate.a = 0.0
    _set_phase(false, false)
    _apply_remaining_ratio(1.0)
    set_living_boss_count(0)
    get_viewport().size_changed.connect(_place_at_screen_bottom)
    _place_at_screen_bottom()

func _place_at_screen_bottom() -> void:
    var viewport_size: Vector2 = get_viewport_rect().size # 当前视口的界面尺寸。
    var scaled_size: Vector2 = DISPLAY_SIZE * DISPLAY_SCALE # 缩放后实际占用的尺寸。
    position = Vector2((viewport_size.x - scaled_size.x) * 0.5,
        maxf(BOTTOM_MARGIN, viewport_size.y - scaled_size.y - BOTTOM_MARGIN))

func _process(delta: float) -> void:
    if not visible:
        return
    var mouse: Vector2 = get_local_mouse_position() # 转为缩放前的 HUD 局部坐标。
    var near: bool = Rect2(Vector2.ZERO, size).grow(MOUSE_MARGIN).has_point(mouse) # 与局部矩形使用同一坐标系。
    var target: float = mouse_near_opacity if near else 1.0
    _mouse_alpha = move_toward(_mouse_alpha, target, delta * 5.0)
    modulate.a = _life_alpha * _mouse_alpha

## Bind latest registered live Boss. Rebinding same Boss never restarts entrance animation.
func bind_boss(boss: ZB000Base) -> bool:
    if not is_instance_valid(boss) or not boss.is_node_ready() or boss.is_queued_for_deletion():
        return false
    if not is_instance_valid(boss.hp_component) or boss.hp_component.max_hp <= 0:
        return false
    if _boss == boss:
        if _last_hp != _hp_component.curr_hp:
            _stop_hp_tween()
            _last_hp = _hp_component.curr_hp
            _apply_remaining_ratio(float(_last_hp) / float(_hp_component.max_hp))
        return true
    unbind_boss()
    _boss = boss
    _hp_component = boss.hp_component
    _last_hp = _hp_component.curr_hp
    _hp_component.signal_hp_loss.connect(_on_boss_hp_loss)
    boss.signal_boss_phase_changed.connect(_on_boss_phase_changed)
    boss_icon.texture = boss.boss_portrait_texture
    _apply_remaining_ratio(float(_last_hp) / float(_hp_component.max_hp))
    _set_phase(boss.boss_phase >= 2, false)
    living_boss_count_label.text = boss.boss_display_name
    _enter()
    return true

func set_living_boss_count(count: int) -> void:
    # Boss name comes from the bound character; count stays in the same text line.
    if is_instance_valid(_boss):
        living_boss_count_label.text = "%s  ×%d" % [_boss.boss_display_name, maxi(count, 0)]
    elif count <= 0:
        living_boss_count_label.text = ""

func unbind_boss() -> void:
    _stop_hp_tween()
    if is_instance_valid(_hp_component) and _hp_component.signal_hp_loss.is_connected(_on_boss_hp_loss):
        _hp_component.signal_hp_loss.disconnect(_on_boss_hp_loss)
    if is_instance_valid(_boss) and _boss.signal_boss_phase_changed.is_connected(_on_boss_phase_changed):
        _boss.signal_boss_phase_changed.disconnect(_on_boss_phase_changed)
    _hp_component = null
    _boss = null
    _last_hp = -1

func show_depleted() -> void:
    unbind_boss()
    _apply_remaining_ratio(0.0)

func fade_out() -> void:
    if not visible or _is_fading_out:
        return
    _is_fading_out = true
    _stop_life_tween()
    _life_tween = create_tween()
    _life_tween.tween_method(_set_life_alpha, _life_alpha, 0.0, death_fade_seconds)
    _life_tween.tween_callback(_hide_if_unbound)

func _enter() -> void:
    _is_fading_out = false
    _stop_life_tween()
    _life_alpha = 0.0
    _mouse_alpha = 1.0
    visible = true
    _life_tween = create_tween()
    _life_tween.tween_method(_set_life_alpha, 0.0, 1.0, entrance_fade_seconds)

func _set_life_alpha(value: float) -> void:
    _life_alpha = clampf(value, 0.0, 1.0)
    modulate.a = _life_alpha * _mouse_alpha

func _hide_if_unbound() -> void:
    if _boss == null:
        visible = false
        _life_alpha = 0.0

func _on_boss_hp_loss(remaining: int, _is_drop: bool) -> void:
    if not is_instance_valid(_hp_component):
        return
    _last_hp = remaining
    var fraction: float = clampf(float(remaining) / float(maxi(_hp_component.max_hp, 1)), 0.0, 1.0)
    _stop_hp_tween()
    if remaining <= 0 or hp_transition_duration <= 0.0:
        _apply_remaining_ratio(fraction)
        return
    _hp_tween = create_tween()
    _hp_tween.tween_method(_apply_remaining_ratio, _remaining_ratio, fraction, hp_transition_duration)

func _on_boss_phase_changed(phase: int) -> void:
    _set_phase(phase >= 2, true)

func _set_phase(second: bool, animated: bool) -> void:
    if is_instance_valid(_phase_tween):
        _phase_tween.kill()
    _phase_two = second
    var target: float = 1.0 if second else 0.0
    if not animated or phase_blend_seconds <= 0.0:
        phase2_bar.modulate.a = target
        portrait_frame_phase2.modulate.a = target
        return
    _phase_tween = create_tween()
    _phase_tween.tween_property(phase2_bar, "modulate:a", target, phase_blend_seconds)
    _phase_tween.parallel().tween_property(portrait_frame_phase2, "modulate:a", target, phase_blend_seconds)

func _apply_remaining_ratio(ratio: float) -> void:
    _remaining_ratio = clampf(ratio, 0.0, 1.0)
    # Two original full-size fill textures are clipped by their shared fill-window,
    # never compressed/scaled. At 0% no red pixel remains; at 100% full span is visible.
    var fill_width: float = HEALTH_FILL_WIDTH * _remaining_ratio
    phase1_fill_clip.size.x = fill_width
    phase2_fill_clip.size.x = fill_width

func _stop_hp_tween() -> void:
    if is_instance_valid(_hp_tween):
        _hp_tween.kill()
    _hp_tween = null

func _stop_life_tween() -> void:
    if is_instance_valid(_life_tween):
        _life_tween.kill()
    _life_tween = null

func _exit_tree() -> void:
    unbind_boss()
    _stop_life_tween()
    if is_instance_valid(_phase_tween):
        _phase_tween.kill()
