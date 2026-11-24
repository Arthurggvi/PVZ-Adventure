## 三线射手四阶书目；高能与动能、终结的互斥条件在研究、存档和战斗共用。
extends RefCounted

## 洪流增加的总发数上限，按三条逻辑弹道计，边路合流在此之后计算。
const MAX_SHOTS_PER_RAY: int = 12
## 每次补种相对原株首次种下时生命上限的增量。
const HEALTH_PER_STACK: float = 0.5

## 叠种入口确认传入的冻结卡已选洪流。
const FLOOD_ID: String = "promotion_threepeater_flood"

## 该物种四阶共八本技能书。
const BOOKS: Dictionary = {
	"promotion_threepeater_high_energy": {
		"title": "高能", "summary": "豌豆改为贯穿整行的激光。光束遇到地形阻挡时截断；每路原有的发数改成各自的连续脉冲。",
		"plant_type": 19, "tier": 1, "effects": [{"kind": "threepeater_laser"}]},
	"promotion_threepeater_flood": {
		"title": "洪流", "summary": "同一张卡可给原株叠种。每次增加每路1发（每路至多12发），生命上限增加初始值的50%，清除自身负面状态并立即回满血。",
		"plant_type": 19, "tier": 1, "effects": [{"kind": "threepeater_flood"}]},
	"promotion_threepeater_assault": {
		"title": "陷阵", "summary": "每路多发射1次，攻速提高50%。命中使目标移动速度降低30%，持续1秒。",
		"plant_type": 19, "tier": 2, "effects": [
			{"kind": "stat", "stat": "attack_rate", "percent": 0.5},
			{"kind": "threepeater_assault", "extra": 1, "slow_ratio": 0.7, "slow_seconds": 1.0}]},
	"promotion_threepeater_kinetic": {
		"title": "动能", "summary": "发射带幻影的动能弹。飞出后持续加速，1.5秒达到最高速度；伤害随速度提升，最高为200%。与高能互斥。",
		"plant_type": 19, "tier": 2, "excludes": "promotion_threepeater_high_energy",
		"effects": [{"kind": "threepeater_kinetic"}]},
	"promotion_threepeater_siege": {
		"title": "鏖战", "summary": "每路多发射1次，攻速提高50%。命中施加30%劣化。",
		"plant_type": 19, "tier": 3, "effects": [
			{"kind": "stat", "stat": "attack_rate", "percent": 0.5},
			{"kind": "threepeater_siege", "extra": 1, "degradation": 0.3}]},
	"promotion_threepeater_sunder": {
		"title": "催折", "summary": "每发弹的首次命中造成击退。同一路连续命中同一敌人时，击退量逐次增加，第6次起最多1格。二类防具与载具免疫击退，且击退止于画面边界。",
		"plant_type": 19, "tier": 3, "effects": [{"kind": "threepeater_sunder", "hits": 6}]},
	"promotion_threepeater_lockdown": {
		"title": "封锁", "summary": "每路多发射1次，攻速提高80%。命中眩晕0.3秒。",
		"plant_type": 19, "tier": 4, "effects": [
			{"kind": "stat", "stat": "attack_rate", "percent": 0.8},
			{"kind": "threepeater_lockdown", "extra": 1, "stun": 0.3}]},
	"promotion_threepeater_finisher": {
		"title": "终结", "summary": "同一路每多发射1颗，末发伤害增加100%，最多12倍。计入边路并入的发数。与高能互斥。",
		"plant_type": 19, "tier": 4, "excludes": "promotion_threepeater_high_energy",
		"effects": [{"kind": "threepeater_finisher", "cap": 12}]},
}
