## 咖啡豆四阶转职书；即时效果与额外冷却由同次使用结果结算。
extends RefCounted

## 咖啡豆沿用物种36，每阶两种选择互斥。
const BOOKS: Dictionary = {
	"promotion_coffee_lightweight": {
		"title": "轻装上阵", "summary": "使用少花25阳光。", "plant_type": 36, "tier": 1,
		"effects": [{"kind": "stat", "stat": "sun_cost", "flat": -25}]},
	"promotion_coffee_clearance": {
		"title": "清仓日", "summary": "冷却时间减半。", "plant_type": 36, "tier": 1,
		"effects": [{"kind": "stat", "stat": "cooldown", "percent": -0.5}]},
	"promotion_coffee_spread": {
		"title": "丰收日", "summary": "一杯咖啡作用于周围九宫格内的合适植物。", "plant_type": 36, "tier": 2,
		"effects": [{"kind": "coffee_area", "radius": 1}]},
	"promotion_coffee_solar": {
		"title": "光能亲和", "summary": "也可浇给阳光生产者，使其阳光价值永久提高50%，同类效果不叠加。", "plant_type": 36, "tier": 2,
		"effects": [{"kind": "coffee_solar", "bonus": 0.5}]},
	"promotion_coffee_caffeine": {
		"title": "咖啡因", "summary": "清醒的目标消耗10%最大生命，获得10秒的50%攻速提升。", "plant_type": 36, "tier": 3,
		"effects": [{"kind": "coffee_haste", "hp_cost_fraction": 0.1, "bonus": 0.5, "seconds": 10.0}]},
	"promotion_coffee_chlorogenic": {
		"title": "绿原酸", "summary": "清醒的目标消耗10%最大生命，获得10秒的50%攻击力提升。", "plant_type": 36, "tier": 3,
		"effects": [{"kind": "coffee_damage", "hp_cost_fraction": 0.1, "bonus": 0.5, "seconds": 10.0}]},
	"promotion_coffee_analgesia": {
		"title": "强效阵痛", "summary": "目标立刻消耗20%最大生命并获得2000护甲；授予成功后，本次冷却增加5秒。", "plant_type": 36, "tier": 4,
		"effects": [{"kind": "coffee_armor", "hp_cost_fraction": 0.2, "armor": 2000, "cooldown_extra": 5.0}]},
	"promotion_coffee_necromancy": {
		"title": "亡灵诅咒", "summary": "在空闲种植位复生该格最近死亡的植物，最大生命减半；成功后，本次冷却增加5秒。", "plant_type": 36, "tier": 4,
		"effects": [{"kind": "coffee_revive", "health_ratio": 0.5, "cooldown_extra": 5.0}]},
}
