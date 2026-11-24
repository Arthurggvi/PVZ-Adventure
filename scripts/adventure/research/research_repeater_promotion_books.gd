## 双发射手四阶转职书；每阶二选一，所有弹种与额外发数由同一冻结选择解析。
extends RefCounted

## 每本书增加一发，并独占四分之一弹种抽签区间；四转后每轮共六发。
const BOOKS: Dictionary = {
	"promotion_repeater_deep_blue": {
		"title": "深蓝之星", "summary": "每轮多射1发；25%的豌豆化为深蓝冻结弹，命中附加减速与1点冻结值。", "plant_type": 8, "tier": 1,
		"effects": [{"kind": "repeater_variant", "variant": "frost", "extra_shots": 1, "chance": 0.25}]},
	"promotion_repeater_deep_red": {
		"title": "深红之星", "summary": "每轮多射1发；25%的豌豆化为红焰焚烧弹，保留火豆溅射，命中附加1秒灼烧。", "plant_type": 8, "tier": 1,
		"effects": [{"kind": "repeater_variant", "variant": "ember", "extra_shots": 1, "chance": 0.25}]},
	"promotion_repeater_pride": {
		"title": "傲慢之眼", "summary": "每轮多射1发；25%的豌豆化为震撼弹，命中眩晕0.2秒，并击退无二类防具的非载具僵尸。", "plant_type": 8, "tier": 2,
		"effects": [{"kind": "repeater_variant", "variant": "shock", "extra_shots": 1, "chance": 0.25}]},
	"promotion_repeater_wrath": {
		"title": "暴怒之眼", "summary": "每轮多射1发；25%的豌豆化为引爆弹，命中叠加10%劣化，最多50%，并积累1点引爆值；满10点引爆，造成一格1800点伤害。", "plant_type": 8, "tier": 2,
		"effects": [{"kind": "repeater_variant", "variant": "detonation", "extra_shots": 1, "chance": 0.25}]},
	"promotion_repeater_poor_star": {
		"title": "穷星之触", "summary": "每轮多射1发；25%的豌豆化为晨星弹。命中散出5颗同伤深色星，每颗再分裂3颗半伤浅色星。", "plant_type": 8, "tier": 3,
		"effects": [{"kind": "repeater_variant", "variant": "morning", "extra_shots": 1, "chance": 0.25}]},
	"promotion_repeater_abyss": {
		"title": "奈落之触", "summary": "每轮多射1发；25%的豌豆化为地狱弹。命中留下后移5秒的黑色漩涡，每秒吸取周围3×3敌人最大生命的5%，等量治疗本株。", "plant_type": 8, "tier": 3,
		"effects": [{"kind": "repeater_variant", "variant": "hell", "extra_shots": 1, "chance": 0.25}]},
	"promotion_repeater_nyx": {
		"title": "倪克斯", "summary": "每轮多射1发；25%的豌豆化为辉夜弹。命中绽开彩色星屑，停留3秒，接触敌人每秒结算60次、每次10点伤害；重叠星屑不重复结算。", "plant_type": 8, "tier": 4,
		"effects": [{"kind": "repeater_variant", "variant": "kaguya", "extra_shots": 1, "chance": 0.25}]},
	"promotion_repeater_hades": {
		"title": "哈迪斯", "summary": "每轮多射1发；25%的豌豆化为冥弹，穿透并处决有效生命低于30%的普通僵尸；否则为周围3×3敌人附加缠怨，每秒流失最大生命的2%，直至死亡。", "plant_type": 8, "tier": 4,
		"effects": [{"kind": "repeater_variant", "variant": "hades", "extra_shots": 1, "chance": 0.25}]},
}
