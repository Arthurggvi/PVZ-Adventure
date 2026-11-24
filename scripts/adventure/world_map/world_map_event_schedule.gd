## 地图局部事件的确定性候选表；只有宿主动作秒数，没有后台计时器或每帧随机。
extends RefCounted

## 三分钟循环首尾均留出衰减时间，避免循环接缝突然亮灭。
const LOOP_SECONDS := 180.0
## 事件起点、快速进入、保持、缓慢退出；全部单位为动作秒。
const EVENTS := {
    "church": {"starts":[15.0,75.0,135.0],"attack":0.6,"hold":2.4,"release":3.5},
    "portal": {"starts":[35.0,57.0,95.0,117.0,155.0,175.0],"attack":1.0,"hold":0.8,"release":1.4},
    "furnace": {"starts":[25.0,47.0,85.0,107.0,145.0,167.0],"attack":1.0,"hold":0.5,"release":1.5}
}

## [param event] 为事件类型；[param seconds] 为组件有效动作秒数，返回连续的零到一包络。
static func envelope(event: String, seconds: float) -> float:
    if not EVENTS.has(event) or seconds < 12.0:
        return 0.0
    var spec: Dictionary = EVENTS[event] # 静态候选表不受镜头位置影响。
    var phase: float = fposmod(seconds, LOOP_SECONDS) # 固定循环中没有首尾跨越的事件。
    for start: float in spec.starts: # 每项最多六个候选，查询开销固定。
        var local: float = phase - start # 当前候选发生后的动作秒数。
        if local < 0.0:
            continue
        if local < float(spec.attack):
            return smoothstep(0.0, float(spec.attack), local)
        if local < float(spec.attack) + float(spec.hold):
            return 1.0
        if local < float(spec.attack) + float(spec.hold) + float(spec.release):
            return 1.0 - smoothstep(0.0, float(spec.release), local - float(spec.attack) - float(spec.hold))
    return 0.0
