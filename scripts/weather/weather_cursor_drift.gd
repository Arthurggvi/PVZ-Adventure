## 天气造成的轻微指针漂移；使用真实指针位置，让卡牌预览和点击命中保持一致。
extends Node
class_name WeatherCursorDrift

## 仅允许当前战斗接收风力，预览器未绑定战斗时不会移动桌面指针。
var battle: MainGameManager
## 满沙暴时的水平漂移速度，单位为视口像素/秒；0 禁用。
var speed: float = 0.0
## 小于一个屏幕像素的余量，避免高帧率时被整像素取整吞掉。
var _remainder: Vector2 = Vector2.ZERO


## 消费同一风场的 [param delta] 秒、[param intensity] 强度和 [param gust] 阵风幅度。
## 指针只在有效战场内顺风左移；暂停、失焦、UI 遮挡、按住鼠标及非战斗阶段均停止。
func advance_wind(delta: float, intensity: float, gust: float) -> void:
    if not _can_drift() or intensity <= 0.45:
        _remainder = Vector2.ZERO
        return
    var viewport: Viewport = get_viewport() # 使用视口坐标处理窗口缩放。
    var cursor: Vector2 = viewport.get_mouse_position() # 当前真实指针，不保存或覆盖玩家主动移动。
    if not viewport.get_visible_rect().has_point(cursor):
        _remainder = Vector2.ZERO
        return
    var hovered: Control = viewport.gui_get_hovered_control() # 与手持管理器保持相同的 UI 遮挡规则。
    if hovered != null and not hovered is PlantCell and not hovered.get_parent() is PlantCell:
        _remainder = Vector2.ZERO
        return
    if battle.board == null or battle.board.pick_cell(battle.get_global_mouse_position()) == null:
        _remainder = Vector2.ZERO
        return
    var force: float = smoothstep(0.45, 1.0, intensity) * (0.6 + clampf(gust, 0.0, 1.0) * 0.4) # 起沙时逐渐施力。
    var screen_transform: Transform2D = viewport.get_screen_transform() # 视口到系统屏幕的实际缩放。
    _remainder += screen_transform.basis_xform(Vector2.LEFT * speed * force * clampf(delta, 0.0, 0.05))
    var whole_pixels := Vector2(int(_remainder.x), int(_remainder.y)) # 仅发送可呈现的整屏幕像素位移。
    if whole_pixels.is_zero_approx():
        return
    _remainder -= whole_pixels
    var target: Vector2 = cursor + screen_transform.basis_xform_inv(whole_pixels) # 映射回 Godot 视口。
    target = target.clamp(Vector2.ONE, viewport.get_visible_rect().size - Vector2.ONE)
    viewport.warp_mouse(target)


## 返回当前是否允许风力干预指针；从未捕获、隐藏或锁定用户鼠标。
func _can_drift() -> bool:
    return speed > 0.0 and is_instance_valid(battle) and not battle.is_queued_for_deletion() \
        and get_tree().current_scene == battle and not get_tree().paused and get_window().has_focus() \
        and battle.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
        and Input.mouse_mode in [Input.MOUSE_MODE_VISIBLE, Input.MOUSE_MODE_HIDDEN] \
        and Input.get_mouse_button_mask() == 0
