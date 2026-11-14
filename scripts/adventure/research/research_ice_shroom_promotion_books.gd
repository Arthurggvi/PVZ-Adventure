## 寒冰菇四阶二选一转职书；研究室、背包和出战共用同一目录。
extends RefCounted

## 稳定物品 ID、面向玩家的技能说明及战斗配置。
const BOOKS: Dictionary = {
	"promotion_ice_shroom_cheap_crop": {
		"title": "廉价作物", "summary": "阳光费用降低50，最低为0。", "plant_type": 15, "tier": 1,
		"effects": [{"kind": "stat", "stat": "sun_cost", "flat": -50}]},
	"promotion_ice_shroom_regeneration": {
		"title": "低温再生", "summary": "每冻结一名僵尸，本卡剩余冷却缩短2%。", "plant_type": 15, "tier": 1,
		"effects": [{"kind": "ice_shroom_regeneration", "fraction": 0.02}]},
	"promotion_ice_shroom_deep_cold": {
		"title": "深寒", "summary": "冻结与减速变为不会被火焰解除的特殊寒冷，两种效果各延长2秒。", "plant_type": 15, "tier": 2,
		"effects": [{"kind": "ice_shroom_deep_cold", "extra_seconds": 2.0}]},
	"promotion_ice_shroom_quick_freeze": {
		"title": "速冻", "summary": "本卡冷却缩短2秒，每冻结一名僵尸获得15阳光。", "plant_type": 15, "tier": 2,
		"effects": [{"kind": "stat", "stat": "cooldown", "flat": -2.0},
			{"kind": "ice_shroom_quick_freeze", "sun_per_target": 15}]},
	"promotion_ice_shroom_world": {
		"title": "世界", "summary": "冻结期间，自然刷怪也会暂停。", "plant_type": 15, "tier": 3,
		"effects": [{"kind": "ice_shroom_world"}]},
	"promotion_ice_shroom_echo": {
		"title": "回声", "summary": "除本卡外，所有卡片剩余冷却减半。", "plant_type": 15, "tier": 3,
		"effects": [{"kind": "ice_shroom_echo", "remaining_multiplier": 0.5}]},
	"promotion_ice_shroom_tundra": {
		"title": "冻原", "summary": "非首领僵尸失去相当于最大生命30%的生命，并获得50层脆弱。", "plant_type": 15, "tier": 4,
		"effects": [{"kind": "ice_shroom_tundra", "max_health_fraction": 0.3, "brittleness": 50}]},
	"promotion_ice_shroom_dynasty": {
		"title": "皇朝", "summary": "全场植物恢复50%最大生命，并获得与冻结时间等长的100%攻速提升。", "plant_type": 15, "tier": 4,
		"effects": [{"kind": "ice_shroom_dynasty", "heal_fraction": 0.5, "attack_rate_multiplier": 2.0}]},
}
