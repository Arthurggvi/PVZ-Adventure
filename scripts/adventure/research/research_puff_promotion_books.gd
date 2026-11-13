## 小喷菇四阶转职书；展示文字与执行参数在此统一定义。
extends RefCounted

## 植物编号沿用正式注册表的小喷菇类型9；每阶只允许选择一条路线。
const BOOKS: Dictionary = {
	"promotion_puff_day_patience": {
		"title": "白昼耐心", "summary": "白天也能保持清醒，正常攻击。", "plant_type": 9, "tier": 1,
		"effects": [{"kind": "puff_day_awake"}]},
	"promotion_puff_rapid_growth": {
		"title": "速生菌群", "summary": "种植冷却缩短一半。", "plant_type": 9, "tier": 1,
		"effects": [{"kind": "stat", "stat": "cooldown", "percent": -0.5}]},
	"promotion_puff_nozzle": {
		"title": "喷口改装", "summary": "孢子射程延伸至前方整行。", "plant_type": 9, "tier": 2,
		"effects": [{"kind": "puff_full_row"}]},
	"promotion_puff_gift": {
		"title": "礼物", "summary": "死亡时向四周散射8～12颗孢子。", "plant_type": 9, "tier": 2,
		"effects": [{"kind": "puff_death_burst", "count_min": 8, "count_max": 12}]},
	"promotion_puff_infection": {
		"title": "真菌感染", "summary": "击杀僵尸后，在其脚下的可种植空格长出一株同源小喷菇。", "plant_type": 9, "tier": 3,
		"effects": [{"kind": "puff_infection"}]},
	"promotion_puff_spore_surge": {
		"title": "孢涌", "summary": "每次喷出3～4颗霰弹孢子。贴脸伤害翻倍，一格内正常，超过一格减半。", "plant_type": 9, "tier": 3,
		"effects": [{"kind": "puff_shotgun", "count_min": 3, "count_max": 4,
			"spread_degrees": 18.0, "point_blank_cells": 0.5,
			"point_blank_factor": 2.0, "near_factor": 1.0, "far_factor": 0.5}]},
	"promotion_puff_collective": {
		"title": "集体意识", "summary": "种植时，同时在上下左右相邻的可种植空格长出小喷菇。", "plant_type": 9, "tier": 4,
		"effects": [{"kind": "puff_collective"}]},
	"promotion_puff_corpse": {
		"title": "尸变", "summary": "命中时有60%概率附加一种异常：中毒5秒、劣化5%、减速、眩晕半秒或魅惑。劣化可叠加，魅惑较少出现。", "plant_type": 9, "tier": 4,
		"effects": [{"kind": "puff_corpse", "chance": 0.6, "poison_seconds": 5.0,
			"degradation": 0.05, "slow_seconds": 5.0, "stun_seconds": 0.5,
			"weights": [2, 2, 2, 2, 1]}]},
}
