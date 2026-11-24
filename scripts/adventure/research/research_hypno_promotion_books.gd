## 魅惑菇四阶转职书；每阶只有一个分支随卡进入战斗。
extends RefCounted

## 物种编号为 13，属性和事件都从同一转职快照读取。
const BOOKS: Dictionary = {
	"promotion_hypno_day_awake": {
		"title": "白昼耐性", "summary": "白天保持清醒，种植冷却缩短3秒。", "plant_type": 13, "tier": 1,
		"effects": [{"kind": "hypno_day_awake"}, {"kind": "stat", "stat": "cooldown", "flat": -3}]},
	"promotion_hypno_release": {
		"title": "限制解放", "summary": "魅惑的僵尸提高1阶，最高5阶，并获得3秒无敌。", "plant_type": 13, "tier": 1,
		"effects": [{"kind": "hypno_release", "immune_seconds": 3.0}]},
	"promotion_hypno_splash": {
		"title": "孢子溅射", "summary": "清醒时死亡，魅惑距离最近的四名可魅惑敌方僵尸。", "plant_type": 13, "tier": 2,
		"effects": [{"kind": "hypno_splash", "count": 4}]},
	"promotion_hypno_remodel": {
		"title": "肉体改造", "summary": "魅惑的僵尸移速减半、攻速翻倍，并获得光能。", "plant_type": 13, "tier": 2,
		"effects": [{"kind": "hypno_remodel", "move_rate": 0.5, "attack_rate": 2.0}]},
	"promotion_hypno_illusion": {
		"title": "没入幻觉", "summary": "被唤醒时魅惑周围3×3内的僵尸。白昼耐性或夜晚关卡在种下时发动。", "plant_type": 13, "tier": 3,
		"effects": [{"kind": "hypno_illusion"}]},
	"promotion_hypno_madness": {
		"title": "没入疯狂", "summary": "魅惑的僵尸每损失1%最大生命，伤害提高2%并获得1%免伤，免伤最高80%。", "plant_type": 13, "tier": 3,
		"effects": [{"kind": "hypno_madness", "damage_per_percent": 0.02, "reduction_per_percent": 0.01, "reduction_cap": 0.8}]},
	"promotion_hypno_malice": {
		"title": "恶意", "summary": "魅惑的僵尸走到最后一列末端时引爆周围3×3，造成1000爆炸伤害，对僵王为300。", "plant_type": 13, "tier": 4,
		"effects": [{"kind": "hypno_malice", "damage": 1000, "boss_damage": 300}]},
	"promotion_hypno_infection": {
		"title": "感染", "summary": "魅惑的僵尸每击杀一名敌方僵尸，有20%概率复制自身，继承当前血量与效果。", "plant_type": 13, "tier": 4,
		"effects": [{"kind": "hypno_infection", "chance": 0.2}]},
}
