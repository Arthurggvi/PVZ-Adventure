## 把图鉴条目变成当前演示帧；本模块只计算图形和明确标注的示例数值。
extends RefCounted

## 行动和控制演示的独立编排。
const Motion: GDScript = preload("res://scripts/adventure/ui/buff_preview_motion.gd")
## 承伤、输出、持续伤害和收益的独立编排。
const Combat: GDScript = preload("res://scripts/adventure/ui/buff_preview_combat.gd")
## 一个教学循环的秒数，重置不代表永久状态会自行到期。
const CYCLE_SECONDS: float = 10.0

## 返回 [param entry] 的演示周期；钟表匠留足十二秒恢复，其余条目使用短循环。
static func cycle_seconds(entry: Dictionary) -> float:
	return 14.0 if entry.get("preview_id", &"") == &"action_slowdown" else CYCLE_SECONDS

## 生成 [param entry] 在 [param elapsed] 秒的画面快照；[param affected] 选择是否施加状态。
## 返回字段仅供图鉴消费，全部生命、护甲、攻击与收益都是本地示例。
static func frame(entry: Dictionary, elapsed: float, affected: bool) -> Dictionary:
	var time: float = fposmod(elapsed, cycle_seconds(entry)) # 所有演示节点共用同一有界时钟。
	var result: Dictionary = { # 中性值使未知条目也能展示原生待机，而不捏造玩法。
		"pose": &"idle", "rate": 1.0, "move": 0.0, "offset": Vector2.ZERO,
		"flip": false, "tint": Color.WHITE, "alpha": 1.0,
		"health": 1000.0, "max_health": 1000.0, "health_visible": false, "armor": 0.0, "counter": -1.0,
		"shot": -1.0, "hit": 0.0, "value": "", "effect": "", "special": "",
		"metric": "正常状态", "detail": "纯视觉示意", "aux": 0.0, "outgoing": false, "paused": false,
	}
	if not Motion.apply(result, entry, time, affected):
		Combat.apply(result, entry, time, affected)
	return result
