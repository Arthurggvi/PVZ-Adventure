## 已有植物的转职书定义；数值与ID原样保留，由统一目录汇总。
extends RefCounted

## 各阶二选一的技能配置，不持有玩家状态。
const BOOKS: Dictionary = {
	"promotion_cherry_bomb_spark": {
		"title": "火花", "summary": "每炸死一名僵尸，本卡剩余冷却−1秒", "plant_type": 3, "tier": 1,
		"effects": [{"kind": "cherry_spark", "cooldown_per_kill": 1.0}]},
	"promotion_cherry_bomb_combustion": {
		"title": "爆燃", "summary": "爆炸后留下2秒地火，每0.5秒造成30基础灼伤，受星级加成", "plant_type": 3, "tier": 1,
		"effects": [{"kind": "cherry_combustion", "damage": 30, "interval": 0.5, "duration": 2.0}]},
	"promotion_cherry_bomb_red_core": {
		"title": "赤核", "summary": "每炸死一名僵尸，下次种植本卡的费用−25，最低为0", "plant_type": 3, "tier": 2,
		"effects": [{"kind": "cherry_red_core", "discount_per_kill": 25}]},
	"promotion_cherry_bomb_shock_blast": {
		"title": "震爆", "summary": "将爆炸范围外扩一格内的僵尸抛高并向后震飞两格，落地眩晕0.5秒", "plant_type": 3, "tier": 2,
		"effects": [{"kind": "cherry_shock_blast", "extra_range": 1, "cells": 2,
			"flight": 0.45, "height": 100.0, "stun": 0.5}]},
	"promotion_cherry_bomb_double_blast": {
		"title": "子母雷", "summary": "首次引爆后在原地追加一次爆炸", "plant_type": 3, "tier": 3,
		"effects": [{"kind": "cherry_double_blast", "delay": 0.55}]},
	"promotion_cherry_bomb_fusion": {
		"title": "聚变", "summary": "爆炸范围扩大至5×5格", "plant_type": 3, "tier": 3,
		"effects": [{"kind": "cherry_fusion", "radius": 2}]},
	"promotion_cherry_bomb_fruit_of_fear": {
		"title": "恐惧之果", "summary": "爆炸伤害×2", "plant_type": 3, "tier": 4,
		"effects": [{"kind": "cherry_fruit_of_fear", "multiplier": 2.0}]},
	"promotion_cherry_bomb_bad_fruit": {
		"title": "恶果", "summary": "每名炸死的僵尸引爆一次周围一格，伤害为本株爆炸伤害的50%", "plant_type": 3, "tier": 4,
		"effects": [{"kind": "cherry_bad_fruit", "damage_fraction": 0.5}]},
	"promotion_potato_harmony": {
		"title": "调和", "summary": "阳光费用−25，冷却时间−25%", "plant_type": 5, "tier": 1,
		"effects": [{"kind": "stat", "stat": "sun_cost", "flat": -25.0},
			{"kind": "stat", "stat": "cooldown", "percent": -0.25}]},
	"promotion_potato_charge": {
		"title": "蓄势", "summary": "出土后每秒爆炸伤害+5%，最多+300%", "plant_type": 5, "tier": 1,
		"effects": [{"kind": "potato_charge", "step": 0.05, "cap": 3.0}]},
	"promotion_potato_instant": {
		"title": "休眠停止", "summary": "种植后立即完成出土并可以触雷", "plant_type": 5, "tier": 2,
		"effects": [{"kind": "potato_instant"}]},
	"promotion_potato_regrow": {
		"title": "萌发", "summary": "爆炸后保留地雷并重新进入埋伏状态", "plant_type": 5, "tier": 2,
		"effects": [{"kind": "potato_regrow"}]},
	"promotion_potato_spread": {
		"title": "扩散", "summary": "爆炸范围扩大为自身周围3×3格", "plant_type": 5, "tier": 3,
		"effects": [{"kind": "potato_spread", "range": 1}]},
	"promotion_potato_frenzy": {
		"title": "狂化", "summary": "爆炸伤害翻倍，每炸死一名僵尸使本卡剩余冷却−1秒", "plant_type": 5, "tier": 3,
		"effects": [{"kind": "potato_frenzy", "damage": 2.0, "cooldown_per_kill": 1.0}]},
	"promotion_potato_energy": {
		"title": "能量转化", "summary": "每炸死一名僵尸掉落50阳光", "plant_type": 5, "tier": 4,
		"effects": [{"kind": "potato_energy", "sun_per_kill": 50}]},
	"promotion_potato_coupling": {
		"title": "耦合", "summary": "每次爆炸抛射3枚土豆子弹，落地引爆并继承爆炸伤害、范围与击杀效果", "plant_type": 5, "tier": 4,
		"effects": [{"kind": "potato_coupling", "projectiles": 3}]},
	"promotion_wallnut_rolling": {
		"title": "翻滚坚果", "summary": "以任何形式死亡时化为坚果保龄球", "plant_type": 4, "tier": 1,
		"effects": [{"kind": "wallnut_bowling_on_death"}]},
	"promotion_wallnut_tenacity": {
		"title": "不屈", "summary": "未受伤害时，每秒恢复最大生命值的5%", "plant_type": 4, "tier": 1,
		"effects": [{"kind": "wallnut_regen", "per_second": 0.05}]},
	"promotion_wallnut_fortress": {
		"title": "坚不可摧", "summary": "最大生命值翻倍", "plant_type": 4, "tier": 2,
		"effects": [{"kind": "stat", "stat": "max_health", "percent": 1.0}]},
	"promotion_wallnut_veteran": {
		"title": "百战", "summary": "卡片冷却时间减少50%", "plant_type": 4, "tier": 2,
		"effects": [{"kind": "stat", "stat": "cooldown", "percent": -0.5}]},
	"promotion_wallnut_armor_growth": {
		"title": "积甲", "summary": "未被攻击时，每秒获得100护甲，最多1000护甲", "plant_type": 4, "tier": 3,
		"effects": [{"kind": "wallnut_armor_growth", "per_second": 100, "cap": 1000}]},
	"promotion_wallnut_breakthrough": {
		"title": "摧锋", "summary": "免疫劣化、无效化等负面状态效果", "plant_type": 4, "tier": 3,
		"effects": [{"kind": "negative_effect_immunity"}]},
	"promotion_wallnut_guardian": {
		"title": "守护", "summary": "每损失20点生命，给予同排前后两格内的植物20点护甲", "plant_type": 4, "tier": 4,
		"effects": [{"kind": "wallnut_guard", "health_per_trigger": 20, "armor_per_trigger": 20, "range": 2}]},
	"promotion_wallnut_last_stand": {
		"title": "不屈", "summary": "单次承受的实际伤害不超过最大生命值的2%", "plant_type": 4, "tier": 4,
		"effects": [{"kind": "wallnut_hit_cap", "fraction": 0.02}]},
	"promotion_peashooter_tempering": {
		"title": "淬火", "summary": "50%概率发射可击退火豆，伤害150%；攻速+20%", "plant_type": 1, "tier": 1,
		"effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.2},
			{"kind": "pea_fire", "chance": 0.5, "damage": 1.5, "knockback": 24.0}]},
	"promotion_peashooter_photosynthesis": {
		"title": "光合作用", "summary": "攻速+50%，阳光费用−25", "plant_type": 1, "tier": 1,
		"effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.5},
			{"kind": "stat", "stat": "sun_cost", "flat": -25.0}]},
	"promotion_peashooter_piercing": {
		"title": "贯穿", "summary": "子弹连续穿透两次；三段伤害分别为200%、100%、50%", "plant_type": 1, "tier": 2,
		"effects": [{"kind": "pea_pierce", "hit_factors": [2.0, 1.0, 0.5]}]},
	"promotion_peashooter_synergy": {
		"title": "协同", "summary": "每株同种植物使本卡冷却−10%(最多50%)、费用−10(最多50)；3×3相邻同种植物彼此攻击+10%", "plant_type": 1, "tier": 2,
		"effects": [{"kind": "pea_synergy", "cooldown_per_plant": 0.1, "cost_per_plant": 10,
			"maximum": 5, "adjacent_damage": 0.1}]},
	"promotion_peashooter_hot_blood": {
		"title": "热血", "summary": "每次射击使下次伤害+20%，最多累加至+300%；失去射击目标后重置", "plant_type": 1, "tier": 3,
		"effects": [{"kind": "pea_hot_blood", "step": 0.2, "cap": 3.0}]},
	"promotion_peashooter_multishot": {
		"title": "连发", "summary": "每次发射后50%概率追加一发，每发可独立继续触发", "plant_type": 1, "tier": 3,
		"effects": [{"kind": "pea_multishot", "chance": 0.5}]},
	"promotion_peashooter_splash": {
		"title": "溅射", "summary": "豌豆命中时对周围僵尸造成本次命中伤害的50%", "plant_type": 1, "tier": 4,
		"effects": [{"kind": "pea_splash", "damage": 0.5, "radius": 96.0}]},
	"promotion_peashooter_shock": {
		"title": "震撼", "summary": "子弹轻微击退不带二类防具的僵尸；攻速+50%", "plant_type": 1, "tier": 4,
		"effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.5},
			{"kind": "pea_shock", "knockback": 12.0}]},
	"promotion_sunflower_light_conversion": {
		"title": "光能转化", "summary": "阳光费用−25，生命+50%", "plant_type": 2, "tier": 1,
		"effects": [
			{"kind": "stat", "stat": "sun_cost", "flat": -25.0},
			{"kind": "stat", "stat": "max_health", "percent": 0.5}
		]},
	"promotion_sunflower_photosynthesis": {
		"title": "光合作用", "summary": "每次额外生产1–2个小阳光", "plant_type": 2, "tier": 1,
		"effects": [{"kind": "sun_production", "extra_small_sun_min": 1,
			"extra_small_sun_max": 2}]},
	"promotion_sunflower_radiance": {
		"title": "辉光", "summary": "自身生产的阳光价值+100%", "plant_type": 2, "tier": 2,
		"effects": [{"kind": "stat", "stat": "sun_value", "percent": 1.0}]},
	"promotion_sunflower_synergy": {
		"title": "协同", "summary": "冷却−30%；生命+300%；死亡时掉落50阳光", "plant_type": 2, "tier": 2,
		"effects": [
			{"kind": "stat", "stat": "cooldown", "percent": -0.3},
			{"kind": "stat", "stat": "max_health", "percent": 3.0},
			{"kind": "on_death", "drop_sun": 50}
		]},
	"promotion_sunflower_stellar": {
		"title": "恒星", "summary": "每次产阳光后，下次额外产量+15，累计最多+100", "plant_type": 2, "tier": 3,
		"effects": [{"kind": "sun_growth", "step": 15, "cap": 100}]},
	"promotion_sunflower_resonance": {
		"title": "共鸣", "summary": "付费种植后立刻恢复本卡冷却、下次种植免费；免费种植不再触发", "plant_type": 2, "tier": 3,
		"effects": [{"kind": "card_resonance"}]},
	"promotion_sunflower_holy_war": {
		"title": "圣战", "summary": "自身同排前后相邻一格的植物伤害+100%、受到伤害−50%", "plant_type": 2, "tier": 4,
		"effects": [{"kind": "adjacent_aura", "damage_bonus": 1.0, "damage_reduction": 0.5}]},
	"promotion_sunflower_flower_field": {
		"title": "花田", "summary": "每次种植本向日葵，使其他植物卡费用−25（可叠加，最低0）；使用各卡后重置该卡折扣", "plant_type": 2, "tier": 4,
		"effects": [{"kind": "deck_cost_discount", "step": 25}]},
	"promotion_lightning_reed_quick_burst": {
		"title": "闪电神经", "summary": "每次攻击快速放电两次", "plant_type": 50, "tier": 1,
		"effects": [{"kind": "reed_quick_burst", "delay": 0.12}]},
	"promotion_lightning_reed_overload": {
		"title": "感电过载", "summary": "同一道闪电每折射一次，伤害额外+50%，累计最多+200%", "plant_type": 50, "tier": 1,
		"effects": [{"kind": "reed_overload", "step": 0.5, "cap": 2.0}]},
	"promotion_lightning_reed_splash": {
		"title": "激荡", "summary": "击中僵尸时，对周围其他敌人造成本次命中伤害的30%", "plant_type": 50, "tier": 2,
		"effects": [{"kind": "reed_splash", "fraction": 0.3, "radius": 96.0}]},
	"promotion_lightning_reed_paralysis": {
		"title": "麻痹", "summary": "每次击中使可受控的僵尸停止行动0.2秒", "plant_type": 50, "tier": 2,
		"effects": [{"kind": "reed_paralysis", "seconds": 0.2}]},
	"promotion_lightning_reed_dual_strike": {
		"title": "电压击穿", "summary": "每次放电可同时直击两个不同敌人", "plant_type": 50, "tier": 3,
		"effects": [{"kind": "reed_dual_strike", "targets": 2}]},
	"promotion_lightning_reed_warp": {
		"title": "跃迁", "summary": "首击索敌覆盖全屏（含身后），且闪电可以命中空中单位", "plant_type": 50, "tier": 3,
		"effects": [{"kind": "reed_warp"}]},
	"promotion_lightning_reed_split": {
		"title": "弧光震荡", "summary": "每次折射可分裂出两道闪电，分别攻击附近的敌人", "plant_type": 50, "tier": 4,
		"effects": [{"kind": "reed_split", "branches": 2}]},
	"promotion_lightning_reed_ion_refraction": {
		"title": "电离折射", "summary": "闪电的折射次数+5", "plant_type": 50, "tier": 4,
		"effects": [{"kind": "reed_ion_refraction", "extra_bounces": 5}]},
}
