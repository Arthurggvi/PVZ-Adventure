## 毁灭菇四阶转职书，费用和战斗规则由同一出战配置冻结。
extends RefCounted

## 灰烬伤害按先加算后末乘分别结算普通僵尸和僵王。
const BOOKS: Dictionary = {
	"promotion_doom_day": {
		"title": "昼", "summary": "白天保持清醒，冷却缩短2秒，爆炸后不留下弹坑。", "plant_type": 16, "tier": 1,
		"effects": [{"kind": "doom_day"}, {"kind": "stat", "stat": "cooldown", "flat": -2}]},
	"promotion_doom_screen": {
		"title": "尽", "summary": "主爆覆盖整个可见战场。", "plant_type": 16, "tier": 1,
		"effects": [{"kind": "doom_screen"}]},
	"promotion_doom_fear": {
		"title": "惧", "summary": "冷却增加2秒。爆炸命中施加100层脆弱、30%劣化、5秒恐惧和5秒灼烧。", "plant_type": 16, "tier": 2,
		"effects": [{"kind": "doom_fear", "stacks": 100, "degradation": 0.3, "seconds": 5.0},
			{"kind": "stat", "stat": "cooldown", "flat": 2}]},
	"promotion_doom_might": {
		"title": "灭", "summary": "冷却增加2秒，爆炸基础伤害增加100%，对僵王增加20%。", "plant_type": 16, "tier": 2,
		"effects": [{"kind": "doom_damage", "normal": 1.0, "boss": 0.2}, {"kind": "stat", "stat": "cooldown", "flat": 2}]},
	"promotion_doom_cross": {
		"title": "焚", "summary": "冷却增加2秒。炸死的僵尸引燃十字线，造成主爆50%的伤害，对僵王为5%。", "plant_type": 16, "tier": 3,
		"effects": [{"kind": "doom_cross", "normal": 0.5, "boss": 0.05}, {"kind": "stat", "stat": "cooldown", "flat": 2}]},
	"promotion_doom_purge": {
		"title": "涤", "summary": "冷却增加2秒，爆炸基础伤害增加100%，对僵王增加20%。", "plant_type": 16, "tier": 3,
		"effects": [{"kind": "doom_damage", "normal": 1.0, "boss": 0.2}, {"kind": "stat", "stat": "cooldown", "flat": 2}]},
	"promotion_doom_burst": {
		"title": "空", "summary": "冷却增加2秒。炸死的僵尸在周围3×3内再爆一次，造成主爆50%的伤害，对僵王为5%。", "plant_type": 16, "tier": 4,
		"effects": [{"kind": "doom_burst", "normal": 0.5, "boss": 0.05}, {"kind": "stat", "stat": "cooldown", "flat": 2}]},
	"promotion_doom_final": {
		"title": "荡", "summary": "爆炸最终伤害翻倍，对僵王的最终伤害增加30%。", "plant_type": 16, "tier": 4,
		"effects": [{"kind": "doom_final", "normal": 2.0, "boss": 1.3}]},
}
