## 高坚果的四阶技能书，同一目录供研究、掉落和冻结卡片使用。
extends RefCounted

## 一至四转各两种选择；生命倍率由公共出生修饰器叠乘。
const BOOKS: Dictionary = {
	"promotion_tallnut_taishan": {
		"title": "泰山", "summary": "最大生命变为3倍。",
		"plant_type": 24, "tier": 1, "effects": [{"kind": "stat", "stat": "max_health", "final_multiplier": 3.0}]},
	"promotion_tallnut_undying": {
		"title": "不灭", "summary": "每秒获得当前生命值10%的护甲，最多累积至最大生命的300%。",
		"plant_type": 24, "tier": 1, "effects": [{"kind": "tallnut_armor_growth"}]},
	"promotion_tallnut_guard": {
		"title": "到我身后", "summary": "替身后一格的植物承受伤害。",
		"plant_type": 24, "tier": 2, "effects": [{"kind": "tallnut_guard_rear"}]},
	"promotion_tallnut_thorns": {
		"title": "荆棘血", "summary": "将实际损失的护甲和生命作为反伤打回给攻击者。对僵王只反伤10%。",
		"plant_type": 24, "tier": 2, "effects": [{"kind": "tallnut_thorns"}]},
	"promotion_tallnut_jail": {
		"title": "监牢", "summary": "单次伤害最多为自身最大生命的10%，即死碾压改为最大生命10%的伤害。",
		"plant_type": 24, "tier": 3, "effects": [{"kind": "tallnut_crush_cap", "fraction": 0.1}]},
	"promotion_tallnut_iron": {
		"title": "铁铠", "summary": "免疫直接打到自己的爆炸伤害，替周围3×3格内其他植物承受爆炸伤害。",
		"plant_type": 24, "tier": 3, "effects": [{"kind": "tallnut_absorb_blasts"}]},
	"promotion_tallnut_blessing": {
		"title": "神圣庇佑", "summary": "免疫所有负面状态。",
		"plant_type": 24, "tier": 4, "effects": [{"kind": "negative_effect_immunity"}]},
	"promotion_tallnut_tyr": {
		"title": "提尔", "summary": "最大生命变为9倍，可与泰山叠乘。",
		"plant_type": 24, "tier": 4, "effects": [{"kind": "stat", "stat": "max_health", "final_multiplier": 9.0}]},
}
