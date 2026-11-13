## 回旋镖射手四阶转职书；自然投掷与派生弹均从同一冻结选择取规则。
extends RefCounted

## 回旋镖射手沿用物种51，每阶两种选择互斥。
const BOOKS: Dictionary = {
	"promotion_bloomerang_wind_cut": {
		"title": "风切", "summary": "攻击时有50%概率改为三连投。", "plant_type": 51, "tier": 1,
		"effects": [{"kind": "bloomerang_wind_cut", "chance": 0.5, "shots": 3}]},
	"promotion_bloomerang_crescent": {
		"title": "回旋苍镰", "summary": "同一枚回旋镖每次命中后增加初始伤害的30%，最多增至3倍。", "plant_type": 51, "tier": 1,
		"effects": [{"kind": "bloomerang_crescent", "step": 0.3, "max_multiplier": 3.0}]},
	"promotion_bloomerang_sweep": {
		"title": "扫荡", "summary": "攻击时前后同时投掷；没有目标的一侧会在屏幕边缘折返。", "plant_type": 51, "tier": 2,
		"effects": [{"kind": "bloomerang_sweep"}]},
	"promotion_bloomerang_slice": {
		"title": "斩切", "summary": "每程可穿透的目标增加2个。", "plant_type": 51, "tier": 2,
		"effects": [{"kind": "bloomerang_slice", "extra_hits": 2}]},
	"promotion_bloomerang_hunt": {
		"title": "追猎", "summary": "每次命中追加目标已损生命9%的伤害；对Boss的附伤不超过其最大生命的0.2%。", "plant_type": 51, "tier": 3,
		"effects": [{"kind": "bloomerang_hunt", "missing_health_ratio": 0.09, "boss_cap_ratio": 0.002}]},
	"promotion_bloomerang_storm_blade": {
		"title": "岚刀", "summary": "攻速和回旋镖飞行速度均提高70%。", "plant_type": 51, "tier": 3,
		"effects": [{"kind": "bloomerang_storm_blade", "attack_rate_bonus": 0.7, "flight_speed_bonus": 0.7}]},
	"promotion_bloomerang_spiral": {
		"title": "螺旋", "summary": "每收回一枚回旋镖，立刻沿原方向补投一枚；补投不会再次触发此效果。", "plant_type": 51, "tier": 4,
		"effects": [{"kind": "bloomerang_spiral"}]},
	"promotion_bloomerang_rain": {
		"title": "暴雨", "summary": "每次命中都向反方向分出一枚基础伤害减半的弱镖。弱镖触及母株或飞出屏幕即消失，不再分裂。", "plant_type": 51, "tier": 4,
		"effects": [{"kind": "bloomerang_rain", "weak_base_multiplier": 0.5}]},
}
