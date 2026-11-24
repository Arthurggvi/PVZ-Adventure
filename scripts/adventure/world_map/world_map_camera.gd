## 固定近景地图镜头：鼠标可边缘平移，鼠标或手指可以按住拖动画布。
## 世界坐标始终沿用地图逻辑尺寸；高清贴图密度不改变地标、命中或镜头中心。
extends Camera2D

## 仅在地图上完成短按且从未进入拖动时发出；[param world_position] 是释放处世界坐标。
signal world_clicked(world_position: Vector2)

## 地图逻辑画布尺寸，单位为世界像素；配置时保证两轴至少为一。
var map_size := Vector2.ONE
## 固定可见世界高度，让主体比上一版缩小约百分之七且避免 1440p 放大采样；极宽窗口仍优先保证不露图外。
var visible_world_height := 336.0
## 画框内触发边缘平移的宽度，单位为视口像素。
var edge_margin_px := 28.0
## 边缘平移的最大屏幕速率，单位为视口像素每秒。
var pan_screen_px_per_second := 480.0
## 短按允许的最大位移，单位为视口像素；达到阈值后本次手势不能再点击。
var drag_threshold_px := 6.0
## 按住达到此毫秒数即进入拖动，静止长按释放也不会选中地标。
var hold_milliseconds := 180
## 宿主提供的模态或切场阻塞查询；空回调表示没有额外阻塞。
var _blocked: Callable
## 配置完成前不响应相机输入，也不读取尚未就绪的地图边界。
var _configured := false
## 仅记录从地图空闲区域开始的左键手势，UI 上按下不会置位。
var _pressed := false
## 当前由地图接管的手指索引，-1 表示没有原生触摸手势。
var _touch_index := -1
## 位移或按住时间已经越过拖动阈值，保持到释放或取消。
var _dragging := false
## 本帧是否存在边缘平移意图，供宿主暂停地标悬停反馈。
var _edge_panning := false
## 手势按下处的视口坐标，用于累计位移阈值而非逐事件判定。
var _press_position := Vector2.ZERO
## 上次已应用拖动的视口坐标；跨过阈值时补上此前的小幅位移。
var _last_drag_position := Vector2.ZERO
## 手势开始的单调毫秒时间，不受动画暂停或系统日历调整影响。
var _press_milliseconds := 0
## 窗口离开信号用于屏蔽鼠标离窗后可能残留的边缘坐标。
var _pointer_inside_window := false

## [param bounds] 是地图逻辑尺寸；[param settings] 提供固定视野、初始中心及鼠标阈值。
## [param blocked] 只查询全局模态或切场阻塞；普通 UI 遮挡由本镜头独立处理。
## 应在进入场景树后调用；重复配置会取消旧手势，不会重复连接窗口信号。
func configure(bounds: Vector2, settings: Dictionary, blocked: Callable = Callable()) -> void:
    cancel_gesture()
    map_size = bounds.max(Vector2.ONE)
    visible_world_height = maxf(1.0, float(settings.get("visible_world_height", 336.0)))
    edge_margin_px = maxf(1.0, float(settings.get("edge_margin_px", 28.0)))
    pan_screen_px_per_second = maxf(0.0, float(settings.get("pan_screen_px_per_second", 480.0)))
    drag_threshold_px = maxf(1.0, float(settings.get("drag_threshold_px", 6.0)))
    hold_milliseconds = maxi(1, int(settings.get("hold_milliseconds", 180)))
    _blocked = blocked
    var initial: Variant = settings.get("initial_center_world", [270.0, 620.0]) # 接受资源 JSON 数组及运行时 Vector2。
    position = Vector2(270.0, 620.0)
    if initial is Vector2:
        position = initial
    elif initial is Array and initial.size() >= 2:
        position = Vector2(float(initial[0]), float(initial[1]))
    enabled = true
    position_smoothing_enabled = false
    drag_horizontal_enabled = false
    drag_vertical_enabled = false
    offset = Vector2.ZERO
    process_priority = -1 # 先于地图宿主更新镜头，悬停查询使用本帧世界位置和导航状态。
    _configured = true
    _pointer_inside_window = get_viewport_rect().has_point(get_viewport().get_mouse_position())
    _on_resize()
    if not get_viewport().size_changed.is_connected(_on_resize):
        get_viewport().size_changed.connect(_on_resize)
    if not get_window().mouse_entered.is_connected(_on_window_mouse_entered):
        get_window().mouse_entered.connect(_on_window_mouse_entered)
        get_window().mouse_exited.connect(_on_window_mouse_exited)
        get_window().focus_exited.connect(cancel_gesture)
    set_process(true)
    set_process_input(true)
    set_process_unhandled_input(true)

## 窗口变化时重新计算唯一倍率；正常宽高比下可见世界高度保持不变。
## 超宽或极小窗口始终先保证两轴都由地图覆盖，且取消旧尺寸下的鼠标手势。
func _on_resize() -> void:
    cancel_gesture()
    var viewport_size: Vector2 = get_viewport_rect().size.max(Vector2.ONE) # 使用与鼠标事件相同的视口坐标单位。
    var coverage_zoom: float = maxf(viewport_size.x / map_size.x, viewport_size.y / map_size.y) # 两轴覆盖地图的最低倍率。
    var fixed_zoom: float = maxf(viewport_size.y / visible_world_height, coverage_zoom) # 无滚轮或键盘入口可改变此倍率。
    zoom = Vector2.ONE * fixed_zoom
    _clamp_center()

## 根据当前视口及固定倍率钳制中心，并立即同步画布变换，避免同帧命中使用旧镜头。
func _clamp_center() -> void:
    var half: Vector2 = get_viewport_rect().size * 0.5 / zoom # 镜头覆盖区域的世界半径。
    var min_center: Vector2 = half.min(map_size * 0.5) # 极端宽高比下退化到对应轴地图正中。
    var max_center: Vector2 = (map_size - half).max(map_size * 0.5) # 保证钳制上下界不会反向。
    position = position.clamp(min_center, max_center)
    force_update_scroll()

## [param delta] 为显示帧间隔，单位为秒；卡顿后的单帧平移最多使用五十毫秒。
## 地图手势优先于边缘平移，UI 上按住左键再移出也不会启动背景导航。
func _process(delta: float) -> void:
    _edge_panning = false
    if not _navigation_allowed():
        cancel_gesture()
        return
    if _touch_index >= 0:
        return # 手指只在实际拖动事件到达时更新镜头。
    if not _mouse_navigation_allowed():
        cancel_gesture()
        return
    var pointer: Vector2 = get_viewport().get_mouse_position() # 当前画框内的视口坐标。
    if _pressed:
        if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
            cancel_gesture()
            return
        _apply_drag(pointer)
        return
    if OS.has_feature("android") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or _pointer_over_ui():
        return
    var viewport_size: Vector2 = get_viewport_rect().size # 画框尺寸决定四边热区。
    var display_factor: float = viewport_size.y/1080.0 # 速率与热区按窗口高度适配，避免高分屏手感变慢。
    var margin: Vector2 = Vector2.ONE * maxf(edge_margin_px,viewport_size.y*0.075) # 默认约81px/1080p的渐变热区。
    margin = margin.min(viewport_size * 0.2)
    var direction := Vector2.ZERO # 越靠近画框边界速度越高；对角方向保持同样的最高速率。
    if pointer.x < margin.x:
        direction.x = (pointer.x - margin.x) / maxf(margin.x, 0.001)
    elif pointer.x > viewport_size.x - margin.x:
        direction.x = (pointer.x - viewport_size.x + margin.x) / maxf(margin.x, 0.001)
    if pointer.y < margin.y:
        direction.y = (pointer.y - margin.y) / maxf(margin.y, 0.001)
    elif pointer.y > viewport_size.y - margin.y:
        direction.y = (pointer.y - viewport_size.y + margin.y) / maxf(margin.y, 0.001)
    direction = Vector2(signf(direction.x)*pow(absf(direction.x),1.7),signf(direction.y)*pow(absf(direction.y),1.7)) # 内缘细调、外缘快速跨区，连续无速度台阶。
    _edge_panning = not direction.is_zero_approx() and pan_screen_px_per_second > 0.0
    if _edge_panning:
        position += direction.limit_length() * pan_screen_px_per_second * 1.5 * display_factor * minf(delta, 0.05) / zoom.x
        _clamp_center()

## [param event] 必须从未被 GUI 消费的左键或原生触摸按下开始。
func _unhandled_input(event: InputEvent) -> void:
    if _pressed or event.device == InputEvent.DEVICE_ID_EMULATION:
        return
    if not (event is InputEventScreenTouch or event is InputEventMouseButton) or not _navigation_allowed():
        return
    if event is InputEventScreenTouch:
        var touch: InputEventScreenTouch = event # 手势只由第一个在地图空白处按下的手指控制。
        if touch.pressed and get_viewport_rect().has_point(touch.position):
            _touch_index = touch.index
            _begin_gesture(touch.position)
        return
    if not event is InputEventMouseButton:
        return
    var mouse: InputEventMouseButton = event # 按下位置来自视口，不使用受镜头变化影响的世界坐标。
    if mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed:
        return
    if not get_viewport_rect().has_point(mouse.position) or not _mouse_navigation_allowed() or _pointer_over_ui():
        return
    _begin_gesture(mouse.position)

## 以 [param pointer] 的视口坐标记录按下位置，供拖动阈值及短按计算。
func _begin_gesture(pointer: Vector2) -> void:
    _pressed = true
    _dragging = false
    _edge_panning = false
    _press_position = pointer
    _last_drag_position = pointer
    _press_milliseconds = Time.get_ticks_msec()
    get_viewport().set_input_as_handled()

## [param event] 为正在进行的地图手势接管移动和释放，保证释放落在 UI 上也能结束手势。
## 只有未拖动的短按可以发出点击；失焦、模态、移出画框或 UI 遮挡均取消选择。
func _input(event: InputEvent) -> void:
    if not _pressed:
        return
    if not _navigation_allowed():
        cancel_gesture()
        return
    if _touch_index >= 0:
        if event is InputEventScreenDrag and event.index == _touch_index:
            _apply_drag(event.position)
            get_viewport().set_input_as_handled()
        elif event is InputEventScreenTouch and event.index == _touch_index and not event.pressed:
            _finish_gesture(event.position, event.canceled)
        return
    if event.device == InputEvent.DEVICE_ID_EMULATION:
        return
    if event is InputEventMouseMotion:
        var motion: InputEventMouseMotion = event # 使用绝对视口位移，避免事件合并造成拖动阈值丢失。
        if not get_viewport_rect().has_point(motion.position):
            cancel_gesture()
            return
        _apply_drag(motion.position)
        get_viewport().set_input_as_handled()
    elif event is InputEventMouseButton:
        var mouse: InputEventMouseButton = event # 仅左键释放能结束由地图开始的手势。
        if mouse.button_index != MOUSE_BUTTON_LEFT or mouse.pressed:
            return
        _finish_gesture(mouse.position, mouse.canceled)

## 在 [param pointer] 结束手势；[param canceled] 为系统取消时不发送点击。
func _finish_gesture(pointer: Vector2, canceled: bool) -> void:
    var short_click: bool = not canceled and not _dragging \
        and Time.get_ticks_msec() - _press_milliseconds < hold_milliseconds # 长按之后不触发地图点击。
    short_click = short_click and pointer.distance_to(_press_position) < drag_threshold_px
    short_click = short_click and get_viewport_rect().has_point(pointer) and not _pointer_over_ui()
    var world_position: Vector2 = get_canvas_transform().affine_inverse() * pointer # 使用最新画布变换还原世界坐标。
    cancel_gesture()
    get_viewport().set_input_as_handled()
    if short_click:
        world_clicked.emit(world_position)

## [param pointer] 是当前视口鼠标点；一旦位移或时间过阈值，后续不再退回点击候选。
func _apply_drag(pointer: Vector2) -> void:
    if not _dragging:
        _dragging = pointer.distance_to(_press_position) >= drag_threshold_px or Time.get_ticks_msec() - _press_milliseconds >= hold_milliseconds
    if _dragging:
        position -= (pointer - _last_drag_position) / zoom
        _last_drag_position = pointer
        _clamp_center()

## 返回当前是否允许背景导航；暂停、模态、失焦和隐藏均阻断。
func _navigation_allowed() -> bool:
    if not _configured or not is_inside_tree() or not enabled or not is_visible_in_tree():
        return false
    if get_tree().paused or not get_window().has_focus():
        return false
    return not (_blocked.is_valid() and bool(_blocked.call()))

## 检查鼠标是否在窗口内；原生触摸不依赖窗口鼠标进入事件。
func _mouse_navigation_allowed() -> bool:
    return _pointer_inside_window and get_viewport_rect().has_point(get_viewport().get_mouse_position())

## 返回鼠标是否位于真实 GUI 控件上；引擎在分发 [method _input] 前已更新悬停。
## 此处保持纯查询，避免刷新光标时投递内部移动事件并重入正在判定的释放手势。
func _pointer_over_ui() -> bool:
    return get_viewport().gui_get_hovered_control() != null

## 返回是否正在等待地图手势释放或执行边缘平移，宿主可据此清除地标悬停。
func is_navigating() -> bool:
    return _pressed or _edge_panning

## 清除全部导航状态，不发出点击；可由宿主在切场或弹窗开始时主动调用。
func cancel_gesture() -> void:
    _pressed = false
    _touch_index = -1
    _dragging = false
    _edge_panning = false
    _press_position = Vector2.ZERO
    _last_drag_position = Vector2.ZERO
    _press_milliseconds = 0

## 鼠标重回窗口仅恢复导航资格，不恢复先前按住的手势。
func _on_window_mouse_entered() -> void:
    _pointer_inside_window = true

## 鼠标离开窗口时丢弃边缘平移与拖动，禁止窗口外释放后产生迟到点击。
func _on_window_mouse_exited() -> void:
    _pointer_inside_window = false
    if _touch_index < 0:
        cancel_gesture()

## [param what] 是引擎生命周期通知；暂停时即使处理回调停止，手势也会立即清除。
func _notification(what: int) -> void:
    if what in [NOTIFICATION_PAUSED, NOTIFICATION_DISABLED, NOTIFICATION_EXIT_TREE, NOTIFICATION_APPLICATION_FOCUS_OUT]:
        cancel_gesture()

## [param point] 是目标世界坐标；立即定位并约束到地图边界，固定倍率保持不变。
func focus_world(point: Vector2) -> void:
    cancel_gesture()
    position = point
    _clamp_center()
