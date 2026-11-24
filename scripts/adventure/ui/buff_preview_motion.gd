## 控制与行动状态的教学编排；只返回画面参数，不调用角色或战场接口。
extends RefCounted

## 这些条目使用行走、停顿、朝向或原生特殊姿态作对照。
const IDS: Array[StringName] = [&"ice_slow", &"ice_freeze", &"deep_cold", &"freeze_charge", &"stun", &"butter", &"fear", &"silence", &"charm", &"nullification", &"action_slowdown", &"sleep", &"scaredy", &"airborne", &"knockback", &"garlic", &"entangled", &"speed_boost", &"awake", &"fearless", &"world_pause", &"negative_immunity"]

## 为 [param frame] 写入 [param entry] 在 [param time] 秒时的演示；[param affected] 区分对照组。
## 返回是否属于行动演示；全部位置、时钟和颜色只存在于预览节点内。
static func apply(frame: Dictionary, entry: Dictionary, time: float, affected: bool) -> bool:
	var id: StringName = entry.get("preview_id", &"") # 图鉴稳定状态身份。
	if not IDS.has(id):
		return false
	var values: Dictionary = entry.get("preview", {}) # 目录已经核对的示例倍率。
	var active: bool = affected and time >= 1.0 # 先留一秒正常姿态，再施加示意状态。
	var age: float = maxf(0.0, time - 1.0) # 本轮状态演示经过的秒数，不表示实战持续时间。
	var plant_subject: bool = str(values.get("subject", "zombie")) == "plant" # 植物固定在种植位置，不沿僵尸跑道滑动。
	frame["pose"] = &"attack" if plant_subject else &"walk"
	frame["move"] = 0.0 if plant_subject else -1.0
	frame["shot"] = fposmod(time, 1.5) / 1.5 if plant_subject else -1.0
	frame["outgoing"] = plant_subject
	frame["metric"] = "动作 ×1.0"
	frame["detail"] = "正常行动"
	match id:
		&"ice_slow", &"action_slowdown", &"speed_boost":
			if active:
				frame["rate"] = float(values.get("rate", 2.0 if id == &"speed_boost" else 0.5))
				if id == &"action_slowdown":
					frame["rate"] = lerpf(float(frame["rate"]), 1.0, _clock_recovery(clampf(age / 12.0, 0.0, 1.0)))
				frame["move"] = -float(frame["rate"])
				frame["tint"] = Color(0.5, 1.0, 1.0) if id == &"ice_slow" else Color.WHITE
				frame["metric"] = "动作 ×%s" % String.num(float(frame["rate"]), 2)
				frame["detail"] = "加速移动" if id == &"speed_boost" else ("按原恢复曲线逐渐恢复" if id == &"action_slowdown" else "减慢行动")
		&"ice_freeze", &"deep_cold":
			if active:
				var frozen: bool = age < 3.0 # 示例演示先冻三秒，再展示半速，详情写明实际时长由来源决定。
				frame["rate"] = 0.0 if frozen else 0.5
				frame["move"] = -float(frame["rate"])
				frame["tint"] = Color(0.37, 0.66, 1.0) if id == &"deep_cold" else Color(0.5, 1.0, 1.0)
				frame["effect"] = "ice" if frozen and id == &"ice_freeze" else ""
				frame["special"] = "fire_resist" if id == &"deep_cold" and age > 1.5 else ""
				frame["metric"] = "动作 ×0" if frozen else "动作 ×0.5"
				frame["detail"] = "抗火冻结" if frozen and id == &"deep_cold" else ("完全冻结" if frozen else "冻结结束 · 继续减速")
		&"freeze_charge":
			if active:
				var points: int = mini(10, 1 + floori(age / 0.4)) # 依次演示一至十点，超过阈值后点数归零。
				frame["counter"] = float(points) / 10.0
				frame["rate"] = 1.0 if points < 10 else 0.0
				frame["move"] = -(1.0 - points * 0.1) if points < 10 else 0.0
				frame["tint"] = Color.WHITE.lerp(Color(0.08, 0.20, 0.65), points * 0.1) if points < 10 else Color(0.5, 1.0, 1.0)
				frame["effect"] = "ice" if points == 10 else ""
				frame["metric"] = "冻结值 %d / 10" % points if points < 10 else "满十点 → 清零冻结"
				frame["detail"] = "仅移速下降 · 动作不减速" if points < 10 else "原生冰块 · 停止行动"
				if points == 10:
					frame["counter"] = 0.0
				if age >= 6.6:
					frame["rate"] = 0.5
					frame["move"] = -0.5
					frame["effect"] = ""
					frame["metric"] = "冻结值 0 · 冻后半速"
					frame["detail"] = "冰冻结束 · 后续寒冷减速"
		&"stun", &"butter", &"nullification":
			if active:
				frame["rate"] = 0.0
				frame["move"] = 0.0
				frame["shot"] = -1.0
				frame["effect"] = "butter" if id == &"butter" else ""
				frame["special"] = "stun" if id == &"stun" else ""
				frame["tint"] = Color.BLACK if id == &"nullification" else Color.WHITE
				frame["metric"] = "行动停止"
				frame["detail"] = "保留受击与移除入口" if id == &"nullification" else "原姿态暂停"
				if (id == &"butter" and age >= 4.0) or (id == &"stun" and age >= 3.0):
					frame["rate"] = 1.0
					frame["move"] = -1.0
					frame["effect"] = ""
					frame["special"] = ""
					frame["metric"] = "动作恢复"
					frame["detail"] = "本次控制结束"
		&"fear", &"charm":
			if active:
				frame["move"] = 1.0
				frame["flip"] = true
				frame["tint"] = Color(1.0, 0.5, 1.0) if id == &"charm" else Color(0.24, 0.24, 0.24)
				frame["metric"] = "阵营反转" if id == &"charm" else "反向逃跑"
				frame["detail"] = "转身攻击原阵营" if id == &"charm" else "阵营不变 · 禁止攻击"
		&"silence":
			frame["special"] = "skill"
			frame["counter"] = 1.0 / 1.6 if active else fposmod(time, 1.6) / 1.6
			frame["paused"] = active
			frame["tint"] = Color(0.55, 0.55, 0.55) if active else Color.WHITE
			frame["metric"] = "等阶技能暂停" if active else "等阶技能运转"
			frame["detail"] = "原生行动继续" if active else "示意技能节拍"
		&"sleep", &"awake", &"scaredy", &"fearless":
			var sleeping: bool = active if id == &"sleep" else not active and id == &"awake" # 唤醒以睡眠状态为对照。
			var hiding: bool = active if id == &"scaredy" else not active and id == &"fearless" # 无畏以受惊缩头为对照。
			frame["pose"] = &"sleep" if sleeping else (&"scaredy" if hiding else &"attack")
			frame["move"] = 0.0
			frame["special"] = "sleep" if sleeping else ("enemy" if id in [&"scaredy", &"fearless"] else "")
			frame["shot"] = -1.0 if sleeping or hiding else fposmod(time, 1.5) / 1.5
			frame["metric"] = "停止输出" if sleeping or hiding else "正常输出"
			frame["detail"] = "原生睡眠姿态" if sleeping else ("原生缩头姿态" if hiding else "原生射击姿态")
		&"airborne", &"knockback", &"garlic", &"entangled":
			if active:
				var progress: float = clampf((age - 0.4 if id == &"garlic" else age) / 1.2, 0.0, 1.0) # 大蒜先停顿，再演示受控位移。
				frame["move"] = 0.0
				frame["rate"] = 0.0 if id == &"entangled" or (id in [&"airborne", &"garlic"] and progress < 1.0) else 1.0
				frame["offset"] = Vector2(0.0, -sin(progress * PI) * 70.0) if id == &"airborne" else Vector2(42.0 * progress, 0.0)
				if id == &"garlic":
					frame["offset"] = Vector2(0.0, -26.0 * progress)
				if id == &"entangled":
					frame["offset"] = Vector2(0.0, 36.0 * progress)
					frame["alpha"] = 1.0 - progress * 0.85
					frame["special"] = "water"
				frame["metric"] = {&"airborne": "抛起 → 落地", &"knockback": "向后击退", &"garlic": "切换相邻行", &"entangled": "被缠绕并拖下水"}[id]
				frame["detail"] = "位置演示 · 距离为示例"
				if progress >= 1.0 and id in [&"airborne", &"garlic", &"knockback"]:
					frame["move"] = -1.0
					frame["detail"] = "位移结束 · 继续行动"
		&"world_pause":
			frame["special"] = "spawns"
			frame["counter"] = 0.5 if active else fposmod(time, 2.0) / 2.0
			frame["paused"] = active
			frame["metric"] = "自然刷怪暂停" if active else "自然刷怪推进"
			frame["detail"] = "现存僵尸仍然行动"
		&"negative_immunity":
			var frozen: bool = time >= 1.0 and not affected # 同时收到示例控制后，仅未免疫的一侧冻结。
			frame["move"] = 0.0
			frame["pose"] = &"attack"
			frame["rate"] = 0.0 if frozen else 1.0
			frame["tint"] = Color(0.5, 1.0, 1.0) if frozen else Color.WHITE
			frame["effect"] = "ice" if frozen else ""
			frame["special"] = "ward" if active else ""
			frame["metric"] = "拒绝负面状态" if active else ("受到冻结" if frozen else "等待示例命中")
			frame["detail"] = "普通攻击仍然扣血" if active else ("动作暂停 · 仍可受伤" if frozen else "双方同时受到控制")
			frame["health_visible"] = true
			frame["health"] = maxf(0.0, 1000.0 - floorf(age / 1.3) * 100.0)
			frame["outgoing"] = false
			frame["shot"] = fposmod(age, 1.3) / 1.3
	return true

## 读取 [param progress] 的恢复量；复制钟表匠原有 Bézier 采样，仅用于画面速度演示。
static func _clock_recovery(progress: float) -> float:
	var left: float = 0.0 # 曲线参数的二分下界。
	var right: float = 1.0 # 曲线参数的二分上界。
	for _iteration: int in range(16): # 与原生恢复器相同精度，不持有战斗目标。
		var middle: float = (left + right) * 0.5 # 参数不等于横轴时间，须先反解。
		var point: Vector2 = Vector2.ZERO.bezier_interpolate(Vector2(0.60, 0), Vector2(0.88, 0.06), Vector2.ONE, middle) # 原技能控制点。
		if point.x < progress:
			left = middle
		else:
			right = middle
	return Vector2.ZERO.bezier_interpolate(Vector2(0.60, 0), Vector2(0.88, 0.06), Vector2.ONE, (left + right) * 0.5).y
