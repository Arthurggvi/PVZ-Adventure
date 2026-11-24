## 西瓜投手的转职书目由库存、研究室和出战快照共用。
extends RefCounted

## 四阶各有两个选择，数值成长与投掷词条分别交给统一的出战入口。
const BOOKS := {
	"promotion_melon_scatter": {"title": "散射", "plant_type": 40, "tier": 1,
		"summary": "向本行和相邻行各投掷1个西瓜，各行自动索敌。",
		"effects": [{"kind": "melon_scatter"}]},
	"promotion_melon_heavy": {"title": "重磅出击", "plant_type": 40, "tier": 1,
		"summary": "每轮攻击有50%概率改为在主目标周围3×3范围内投掷6个西瓜。",
		"effects": [{"kind": "melon_heavy"}]},
	"promotion_melon_shatter": {"title": "爆碎西瓜", "plant_type": 40, "tier": 2,
		"summary": "伤害+30%。西瓜的溅射伤害提高至直击伤害的100%。",
		"effects": [{"kind": "stat", "stat": "damage", "percent": 0.30}, {"kind": "melon_shatter"}]},
	"promotion_melon_knockback": {"title": "脱线一击", "plant_type": 40, "tier": 2,
		"summary": "攻速+20%。西瓜命中时轻微击退目标。",
		"effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.20}, {"kind": "melon_knockback"}]},
	"promotion_melon_burst": {"title": "爆射", "plant_type": 40, "tier": 3,
		"summary": "攻速-20%。西瓜伤害翻倍。",
		"effects": [{"kind": "stat", "stat": "attack_rate", "percent": -0.20}, {"kind": "melon_burst"}]},
	"promotion_melon_stun": {"title": "震撼", "plant_type": 40, "tier": 3,
		"summary": "攻速+20%。每次命中叠加1秒眩晕，剩余眩晕时间最长3秒。",
		"effects": [{"kind": "stat", "stat": "attack_rate", "percent": 0.20}, {"kind": "melon_stun"}]},
	"promotion_melon_kratos": {"title": "克拉托斯", "plant_type": 40, "tier": 4,
		"summary": "蓄力1秒后投出幻影瓜，命中伤害再翻倍。",
		"effects": [{"kind": "melon_kratos"}]},
	"promotion_melon_formation": {"title": "列阵", "plant_type": 40, "tier": 4,
		"summary": "同列每有一株存活的西瓜投手（含自身），本轮就额外连投一次。",
		"effects": [{"kind": "melon_formation"}]},
}
