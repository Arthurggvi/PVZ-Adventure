## 伤害与增益的双栏示例；不创建生命组件、攻击器、掉落或任何正式战斗对象。
extends RefCounted

## 周期状态共享原生基础比例，缠怨只改变间隔和明度。
const PERIODIC_IDS: Array[StringName] = [&"poison", &"burn", &"resentment"]
## 这些效果用同一输入命中对照承伤，不伪装为实际目标结算。
const DEFENSE_IDS: Array[StringName] = [&"degradation", &"brittleness", &"damage_block", &"damage_reduction", &"damage_transfer", &"temporary_armor", &"immunity", &"hit_cap"]
## 这些效果比较输出大小或攻击节拍。
const ATTACK_IDS: Array[StringName] = [&"bite_boost", &"attack_boost", &"attack_rate", &"dynasty"]

## 为 [param frame] 填充 [param entry] 在 [param time] 秒的数值示意；[param affected] 指施加状态的一侧。
static func apply(frame: Dictionary, entry: Dictionary, time: float, affected: bool) -> void:
	var id: StringName = entry.get("preview_id", &"") # 用稳定身份而不是名称判断机制。
	var values: Dictionary = entry.get("preview", {}) # 已核对的教学示例参数。
	var age: float = maxf(0.0, time - 1.0) # 一秒基线之后开始本轮演示。
	var active: bool = affected and time >= 1.0 # 只改变右侧，左侧始终是对照。
	if PERIODIC_IDS.has(id):
		_periodic(frame, id, values, age, active)
	elif DEFENSE_IDS.has(id):
		_defense(frame, id, values, age, active)
	elif ATTACK_IDS.has(id):
		_attack(frame, id, values, age, active)
	elif id == &"detonation_charge":
		var points: int = mini(10, floori(age / 0.45)) if active else 0 # 十次积累后清零并展示爆发波。
		frame["counter"] = float(points) / 10.0 if points < 10 else 0.0
		frame["metric"] = "引爆值 %d / 10" % points if points < 10 else "十点清零 → 爆炸"
		frame["special"] = "detonation" if points == 10 else ""
		frame["hit"] = maxf(0.0, 1.0 - (age - 4.5) / 0.8) if points == 10 else 0.0
		frame["detail"] = "爆炸伤害由命中来源决定"
	elif id == &"sun_infusion":
		_sun_infusion(frame, values, age, active)
	elif id == &"regeneration":
		var interval: float = maxf(0.25, float(values.get("interval", 1.0))) # 防止错误目录值引起除零。
		var amount: float = float(values.get("amount", 1000.0 * float(values.get("fraction", 0.05)))) # 百分比以示例本体上限计算。
		frame["health_visible"] = true
		frame["health"] = minf(1000.0, 600.0 + floorf(age / interval) * amount) if active else 600.0
		frame["hit"] = _pulse(age, interval) if active else 0.0
		frame["value"] = "+%d" % int(amount) if active else ""
		frame["special"] = "heal" if active else ""
		frame["metric"] = "示例生命 %d / 1000" % int(frame["health"])
		frame["detail"] = "按周期恢复 · 不超过上限"
	elif id == &"sun_yield":
		var amount: int = int(values.get("output", 50)) if active else int(values.get("input", 25)) # 同一生产节拍的收益对照。
		frame["special"] = "sun"
		frame["hit"] = _pulse(age, 2.0)
		frame["aux"] = amount
		frame["metric"] = "示例产量 %d" % amount
		frame["detail"] = "同一次生产 · 产量变化"

## 在 [param frame] 中为 [param id] 按 [param values] 演示周期伤害；[param age] 为状态时间，[param active] 控制是否附加。
static func _periodic(frame: Dictionary, id: StringName, values: Dictionary, age: float, active: bool) -> void:
	var interval: float = maxf(0.1, float(values.get("interval", 1.0 if id == &"resentment" else 0.5))) # 使用真实基础节拍。
	var damage: int = roundi(1000.0 * float(values.get("fraction", 0.02))) # 以示例最大生命1000展示每跳基础值。
	frame["health_visible"] = true
	frame["health"] = maxf(0.0, 1000.0 - floorf(age / interval) * damage) if active else 1000.0
	frame["hit"] = _pulse(age, interval) if active else 0.0
	frame["value"] = "−%d" % damage if active else ""
	frame["metric"] = "每 %s 秒 −%d" % [String.num(interval, 2), damage] if active else "无持续损伤"
	frame["detail"] = "示例本体上限 1000 · 无防护"
	if active and id == &"burn":
		frame["effect"] = "fire"
	if active and id == &"resentment":
		var brightness: float = lerpf(0.12, 2.8, 0.5 - 0.5 * cos(age * TAU / 0.9)) # 和实战相同的黑白往返曲线。
		brightness = lerpf(1.0, brightness, smoothstep(0.0, 0.18, age))
		frame["tint"] = Color(brightness, brightness, brightness)

## 在 [param frame] 用相同输入比较 [param id]；[param values] 给出例值，[param age] 控制节拍，[param active] 选择状态组。
static func _defense(frame: Dictionary, id: StringName, values: Dictionary, age: float, active: bool) -> void:
	var input: int = int(values.get("input", 100)) # 普通攻击的示例原始数值。
	var amount: float = float(values.get("amount", 0.2 if id in [&"degradation", &"brittleness", &"damage_reduction"] else 30.0)) # 比例或固定量由条目身份解释。
	var output: int = input # 中性对照组不带状态。
	var maximum: float = 100.0 if id == &"hit_cap" else 1000.0 # 单次上限条目的例值明确使用最大生命100。
	frame["max_health"] = maximum
	frame["health_visible"] = true
	if active:
		match id:
			&"degradation", &"brittleness": output = int(values.get("output", roundi(input * (1.0 + amount))))
			&"damage_block": output = int(values.get("output", maxi(0, input - int(amount))))
			&"damage_reduction": output = int(values.get("output", roundi(input * (1.0 - amount))))
			&"immunity", &"damage_transfer": output = 0
			&"hit_cap": output = int(values.get("output", mini(input, int(amount))))
	var hits: int = floori(age / 1.3) # 两侧同一瞬间受击，便于对比单击数值与血池。
	frame["health"] = maxf(0.0, maximum - hits * output)
	frame["shot"] = fposmod(age, 1.3) / 1.3
	frame["hit"] = _pulse(age, 1.3)
	frame["value"] = "−%d" % output
	frame["metric"] = "命中 %d → 承伤 %d" % [input, output]
	frame["detail"] = "相同输入的示例对照"
	if not active:
		return
	match id:
		&"degradation":
			frame["tint"] = Color(0.55, 0.57, 0.58)
			frame["detail"] = "自身输出 %d → %d" % [input, roundi(input * maxf(0.0, 1.0 - amount))]
		&"brittleness": frame["detail"] = "承伤增加 · 自身输出不变"
		&"damage_block": frame["tint"] = Color(0.72, 1.0, 0.96)
		&"immunity": frame["tint"] = Color(1.0, 0.35, 0.35)
		&"damage_transfer":
			frame["special"] = "transfer"
			frame["aux"] = maxf(0.0, 1000.0 - hits * input)
			frame["detail"] = "命中转给身旁的合格护卫"
		&"temporary_armor":
			var armor: float = float(values.get("amount", 300.0)) # 蓝条为独立护甲，先消耗护甲再进入本体。
			frame["armor"] = maxf(0.0, armor - hits * input)
			frame["armor_max"] = armor
			frame["health"] = maxf(0.0, 1000.0 - maxf(0.0, hits * input - armor))
			frame["value"] = "−%d" % int(maxf(0.0, hits * input - armor) - maxf(0.0, (hits - 1) * input - armor))
			frame["metric"] = "护甲 %d · 本体 %d" % [int(frame["armor"]), int(frame["health"])]
			frame["special"] = "armor"
			frame["detail"] = "护甲先受损 · 耗尽后伤及本体"

## 在 [param frame] 演示 [param id] 的输出和攻速；[param values] 只含示例，[param age] 与 [param active] 决定节拍。
static func _attack(frame: Dictionary, id: StringName, values: Dictionary, age: float, active: bool) -> void:
	var rate: float = float(values.get("rate", 2.0)) if active and id in [&"attack_rate", &"dynasty"] else 1.0 # 只有攻速类改变节拍。
	var input: int = int(values.get("input", 100)) # 同一次基础攻击的示例值。
	var output: int = int(values.get("output", 200)) if active and id in [&"bite_boost", &"attack_boost"] else input # 输出增益不改变节拍。
	frame["pose"] = &"attack"
	frame["rate"] = rate
	frame["shot"] = fposmod(age * rate, 1.8) / 1.8
	frame["hit"] = _pulse(age * rate, 1.8)
	frame["value"] = str(output)
	frame["metric"] = "输出 %d · 节拍 ×%s" % [output, String.num(rate, 2)]
	frame["detail"] = "只提高攻击节拍" if id in [&"attack_rate", &"dynasty"] else "同一动作 · 单次输出提高"
	frame["special"] = "outgoing"
	frame["outgoing"] = true
	if id == &"bite_boost":
		frame["special"] = "bite"
		frame["shot"] = -1.0
	if id == &"dynasty":
		frame["health_visible"] = true
		frame["health"] = 1000.0 if active else 600.0
		frame["detail"] = "施放时治疗 · 攻速 ×2" if active else "受伤植物 · 原攻速"
		if active and age < 0.6:
			frame["special"] = "heal"
			frame["hit"] = 1.0 - age / 0.6
			frame["value"] = "+400"

## [param frame] 显示 [param values] 指定的光能例值；[param age] 为命中时钟，[param active] 选择是否产光。
static func _sun_infusion(frame: Dictionary, values: Dictionary, age: float, active: bool) -> void:
	var input: int = int(values.get("input", 25)) # 演示25点实伤转换5阳光的基础关系。
	var sun: int = int(values.get("output", 5)) # 目录可使用多层例子，但不生成真实拾取物。
	frame["health_visible"] = true
	frame["health"] = maxf(0.0, 1000.0 - floorf(age / 1.3) * input)
	frame["hit"] = _pulse(age, 1.3)
	frame["shot"] = fposmod(age, 1.3) / 1.3
	frame["value"] = "−%d" % input
	frame["special"] = "sun" if active else ""
	frame["aux"] = sun
	frame["tint"] = Color(1.0, 1.0, 0.35) if active else Color.WHITE
	frame["metric"] = "%d 实伤 → %d 阳光" % [input, sun] if active else "受伤不产光"
	frame["detail"] = "只有实际损伤触发转换"

## 返回 [param age] 在 [param interval] 周期刚结算后的短暂亮度；第一跳之前保持零。
static func _pulse(age: float, interval: float) -> float:
	return maxf(0.0, 1.0 - fposmod(age, interval) / 0.35) if age >= interval else 0.0
