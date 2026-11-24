## 大喷菇四阶转职书；书内以短句说明玩法，数值由冻结事件提供。
extends RefCounted

## 物种11沿用原生大喷菇，每阶两条路线互斥。
const BOOKS: Dictionary = {
	"promotion_fume_day_patience": {
		"title": "白昼耐性", "summary": "白天保持清醒，照常喷射。本卡冷却缩短40%。", "plant_type": 11, "tier": 1,
		"effects": [{"kind": "fume_day_awake"}, {"kind": "stat", "stat": "cooldown", "percent": -0.4}]},
	"promotion_fume_decay_energy": {
		"title": "腐能利用", "summary": "种植少花25阳光，攻击速度提高20%。", "plant_type": 11, "tier": 1,
		"effects": [{"kind": "stat", "stat": "sun_cost", "flat": -25}, {"kind": "fume_attack_rate", "bonus": 0.2}]},
	"promotion_fume_surge": {
		"title": "涌潮", "summary": "喷雾延伸至同排前方，攻击整条通路上的敌人。每次攻击叠加10%攻速，最多100%，失去目标时重置。", "plant_type": 11, "tier": 2,
		"effects": [{"kind": "fume_full_row", "attack_rate_per_stack": 0.1, "max_stacks": 10}]},
	"promotion_fume_interception": {
		"title": "阻击", "summary": "对带有防具的僵尸伤害提高100%。每次命中轻微击退僵尸，载具免疫击退。", "plant_type": 11, "tier": 2,
		"effects": [{"kind": "fume_knockback", "distance": 12.0}, {"kind": "stat", "stat": "armored_target_damage", "percent": 1.0}]},
	"promotion_fume_hell_touch": {
		"title": "地狱之触", "summary": "命中使敌人劣化50%，并灼烧2秒；灼烧每半秒削去2%最大生命。", "plant_type": 11, "tier": 3,
		"effects": [{"kind": "fume_hell_touch", "degradation": 0.5, "burn_seconds": 2.0}]},
	"promotion_fume_ice_touch": {
		"title": "冰封之触", "summary": "命中使敌人减速并积累2点冻结值，每点额外减速10%。满10点冻结，解冻后1秒内不再积累。", "plant_type": 11, "tier": 3,
		"effects": [{"kind": "fume_ice_touch", "slow_seconds": 5.0, "freeze_points": 2.0}]},
	"promotion_fume_yog_sothoth": {
		"title": "犹格索托斯", "summary": "每次喷射随机附带一种异变：中毒、劣化、恐惧、魅惑、灼烧、减速、冻结值、眩晕、局部爆炸、沉默或光能。", "plant_type": 11, "tier": 4,
		"effects": [{"kind": "fume_yog"}]},
	"promotion_fume_poseidon": {
		"title": "海神", "summary": "范围内有敌人时持续喷涌，基础伤害间隔为0.5秒，受攻速影响，每次伤害照常触发命中效果。无目标时停喷。", "plant_type": 11, "tier": 4,
		"effects": [{"kind": "fume_poseidon"}]},
}
