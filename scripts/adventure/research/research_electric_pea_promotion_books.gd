## 电能豌豆四阶二选一书目，战斗参数由实际出战植株冻结。
extends RefCounted

## 稳定书目ID、玩家说明及战斗效果参数。
const BOOKS := {
	"promotion_electric_pea_charge_pull": {
		"title": "电荷牵引", "summary": "电球飞行速度降低50%，能在战场上停留更久。", "plant_type": 52, "tier": 1,
		"effects": [{"kind": "electric_pea_charge_pull", "speed_multiplier": 0.5}]},
	"promotion_electric_pea_static_cling": {
		"title": "静电附着", "summary": "每轮放电最多可击中4名敌人。", "plant_type": 52, "tier": 1,
		"effects": [{"kind": "electric_pea_static_cling", "targets": 4}]},
	"promotion_electric_pea_arc_jump": {
		"title": "电弧跳跃", "summary": "每道电弧命中后，可向附近另一名敌人跳跃一次。", "plant_type": 52, "tier": 2,
		"effects": [{"kind": "electric_pea_arc_jump", "cells": 1.0}]},
	"promotion_electric_pea_spread": {
		"title": "扩散射击", "summary": "每次向前方扇形同时射出3枚电球。", "plant_type": 52, "tier": 2,
		"effects": [{"kind": "electric_pea_spread", "spread_cells": 2.0}]},
	"promotion_electric_pea_overload": {
		"title": "电力过载", "summary": "电球直击或电弧命中时，使僵尸眩晕0.1秒。", "plant_type": 52, "tier": 3,
		"effects": [{"kind": "electric_pea_overload", "seconds": 0.1}]},
	"promotion_electric_pea_pulse_split": {
		"title": "脉冲分裂", "summary": "电球首次撞伤敌人就分裂成3枚可穿透的小电球，并使受伤的僵尸眩晕0.2秒。小电球造成60%的伤害。", "plant_type": 52, "tier": 3,
		"effects": [{"kind": "electric_pea_pulse_split", "seconds": 0.2, "count": 3, "damage_multiplier": 0.6, "size_multiplier": 0.6}]},
	"promotion_electric_pea_matrix": {
		"title": "超导矩阵", "summary": "同一株射出的电球彼此连接，电弧持续伤害穿过它的僵尸，每秒造成600点基础伤害。", "plant_type": 52, "tier": 4,
		"effects": [{"kind": "electric_pea_matrix", "damage": 10}]},
	"promotion_electric_pea_symbiosis": {
		"title": "电磁共生", "summary": "周围3×3格内每有一株其他雷电植物，本株的伤害增加40%。", "plant_type": 52, "tier": 4,
		"effects": [{"kind": "electric_pea_symbiosis", "bonus": 0.4}]},
}
