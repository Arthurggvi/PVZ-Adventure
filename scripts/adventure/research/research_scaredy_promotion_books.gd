## 胆小菇四阶转职书；简短说明与冻结规则由统一目录读取。
extends RefCounted

## 白昼耐性为自身卡片和获得共生词条的卡片提供相同的冷却缩短比例。
const DAY_COOLDOWN_REDUCTION: float = 0.4

## 物种14沿用原生胆小菇；每一阶的两本书互斥选择。
const BOOKS: Dictionary = {
	"promotion_scaredy_day_patience": {
		"title": "白昼耐性", "summary": "白天保持清醒，照常攻击。本卡冷却缩短40%。", "plant_type": 14, "tier": 1,
		"effects": [{"kind": "scaredy_day_awake", "cooldown_reduction": DAY_COOLDOWN_REDUCTION},
			{"kind": "stat", "stat": "cooldown", "percent": -DAY_COOLDOWN_REDUCTION}]},
	"promotion_scaredy_decay_energy": {
		"title": "腐能利用", "summary": "种植少花25阳光，攻击速度提高20%。", "plant_type": 14, "tier": 1,
		"effects": [{"kind": "stat", "stat": "sun_cost", "flat": -25},
			{"kind": "scaredy_cost", "discount": 25, "attack_rate_bonus": 0.2}]},
	"promotion_scaredy_fission": {
		"title": "菌核裂变", "summary": "攻击速度提高80%，对带有防具的僵尸伤害提高100%。", "plant_type": 14, "tier": 2,
		"effects": [{"kind": "scaredy_attack_rate", "bonus": 0.8, "armored_target_multiplier": 2.0}]},
	"promotion_scaredy_decay_hunger": {
		"title": "腐食渴望", "summary": "不再害怕靠近的僵尸，目标越近伤害越高，贴脸时达到双倍。每次射击额外在60°扇形内散射1～4发胆小菇子弹。", "plant_type": 14, "tier": 2,
		"effects": [{"kind": "scaredy_close_damage", "count_min": 1, "count_max": 4, "spread_degrees": 60.0}]},
	"promotion_scaredy_colony": {
		"title": "菌系群落", "summary": "自身及周围一圈内，每有一种蘑菇，射速提高50%；同种只计一次。", "plant_type": 14, "tier": 3,
		"effects": [{"kind": "scaredy_colony", "per_species": 0.5}]},
	"promotion_scaredy_corrosive_touch": {
		"title": "腐蚀之触", "summary": "对僵尸防具造成三倍伤害。", "plant_type": 14, "tier": 3,
		"effects": [{"kind": "scaredy_armor_damage", "multiplier": 3.0}]},
	"promotion_scaredy_solar_conversion": {
		"title": "光能转化", "summary": "每击杀一只僵尸掉落8阳光；每持有10阳光，伤害提高1%，最高提高1000%。", "plant_type": 14, "tier": 4,
		"effects": [{"kind": "scaredy_solar"}]},
	"promotion_scaredy_humus_symbiosis": {
		"title": "腐殖共生", "summary": "将自己已学的一至三转词条共享给周围一圈的其他蘑菇；相同词条不叠加，胆小菇除外。", "plant_type": 14, "tier": 4,
		"effects": [{"kind": "scaredy_symbiosis"}]},
}
