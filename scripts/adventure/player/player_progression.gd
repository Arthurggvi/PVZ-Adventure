## 玩家成长纯规则：累计经验为权威，等级和级内进度由同一曲线派生。
extends RefCounted
class_name PlayerProgression

## 经验最大精确存储值，沿用项目 JSON 整数限制。
const MAX_EXPERIENCE: int = PlantCardInstance.MAX_JSON_INTEGER

## [param level] 到下一级需求，按 1500×1.10^(L−1) 四舍五入到百位；不可表示返回 -1。
static func required_experience(level: int) -> int:
	if level < 1 or level > 300:
		return -1
	var amount: float = round(15.0 * pow(1.10, level - 1)) * 100.0 # 正数 .5 向上，避免百位取整歧义。
	return int(amount) if is_finite(amount) and amount < float(MAX_EXPERIENCE) else -1

## 将 [param total] 投影为等级、级内经验和需求；循环受指数曲线及安全整数上限约束。
static func progress(total: int) -> Dictionary:
	var remaining: int = clampi(total, 0, MAX_EXPERIENCE) # 内部展示也不能因异常数值无限循环。
	var level: int = 1 # 初始等级。
	var floor_total: int = 0 # 当前等级的累计经验门槛。
	var required: int = required_experience(level) # 当前单级升级需求。
	while required > 0 and floor_total <= MAX_EXPERIENCE - required and remaining >= required:
		remaining -= required
		floor_total += required
		level += 1
		required = required_experience(level)
	var capped: bool = required < 0 or floor_total > MAX_EXPERIENCE - required # 上限由可存储经验决定。
	return {"level": level, "current": remaining, "required": required if not capped else 0, "capped": capped}

## 增加 [param amount] 经验并同步 [param state] 等级；只改内存，失败不产生任何写入。
static func grant(state: AdventureState, amount: int) -> bool:
	if state == null or amount < 0 or state.experience < 0 or state.experience > MAX_EXPERIENCE - amount:
		return false
	state.experience += amount
	state.player_level = int(progress(state.experience).level)
	return true

## 返回 [param level] 的累计经验门槛；无法表示的等级返回 -1，供明确设置等级的入口使用。
static func threshold(level: int) -> int:
	if level < 1 or level > 300:
		return -1
	var total: int = 0 # 逐级累计使用完全相同的百位取整规则。
	for previous: int in range(1, level): # 不直接使用未取整几何级数。
		var amount: int = required_experience(previous) # 本次累计的单级需求。
		if amount < 0 or total > MAX_EXPERIENCE - amount:
			return -1
		total += amount
	return total
