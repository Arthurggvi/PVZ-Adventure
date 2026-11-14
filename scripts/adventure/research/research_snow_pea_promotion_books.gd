## 寒冰射手四阶转职书；ID 用于背包物品和永久转职记录。
extends RefCounted

## 每阶两个互斥选项；技能的可调数值随出战选择一并冻结。
const BOOKS: Dictionary = {
	"promotion_snow_pea_cold_extract": {
		"title": "冷萃", "summary": "豌豆命中后对周围敌人溅射50%的伤害，并使它们减速。", "plant_type": 6, "tier": 1,
		"effects": [{"kind": "snow_pea_cold_extract", "damage_factor": 0.5, "width_cells": 1.6}]},
	"promotion_snow_pea_brittleness": {
		"title": "脆性", "summary": "命中已减速的敌人会使其多承受10%的伤害，最多叠加到100%。", "plant_type": 6, "tier": 1,
		"effects": [{"kind": "snow_pea_brittleness", "stacks": 10}]},
	"promotion_snow_pea_winter": {
		"title": "凛冬", "summary": "每次命中为敌人增加2点冻结值。", "plant_type": 6, "tier": 2,
		"effects": [{"kind": "snow_pea_winter", "points": 2}]},
	"promotion_snow_pea_corridor": {
		"title": "回廊", "summary": "豌豆可以穿透已经减速的敌人。", "plant_type": 6, "tier": 2,
		"effects": [{"kind": "snow_pea_corridor"}]},
	"promotion_snow_pea_deep_cold": {
		"title": "深寒", "summary": "深蓝豌豆可使敌人冻结0.2秒，新被冻结的敌人受到20点伤害。减速与冻结不会被火焰解除。", "plant_type": 6, "tier": 3,
		"effects": [{"kind": "snow_pea_deep_cold", "seconds": 0.2, "damage": 20}]},
	"promotion_snow_pea_torment": {
		"title": "酷刑", "summary": "每颗豌豆首次击中的僵尸会沿途留下持续5秒的冰痕，踩中冰痕的敌人会受到寒冷效果。", "plant_type": 6, "tier": 3,
		"effects": [{"kind": "snow_pea_torment", "seconds": 5.0}]},
	"promotion_snow_pea_skadi": {
		"title": "斯卡蒂", "summary": "被豌豆击杀的敌人会变成冰雕。冰雕再受攻击就会爆裂，射出16枚可穿透的冰锥，每枚增加5点冻结值。", "plant_type": 6, "tier": 4,
		"effects": [{"kind": "snow_pea_skadi", "prism_count": 16, "prism_points": 5}]},
	"promotion_snow_pea_chione": {
		"title": "喀俄涅", "summary": "每攻击5次，吹起暴雪将本行敌人击退2格，并追加5连射。", "plant_type": 6, "tier": 4,
		"effects": [{"kind": "snow_pea_chione", "period": 5, "cells": 2.0, "shots": 5, "spacing": 0.10}]},
}
