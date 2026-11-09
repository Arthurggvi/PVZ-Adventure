## 角色装备槽位到底图的映射，只供表现层使用。
extends RefCounted

## 通用装备底图所在的资源目录。
const ROOT := "res://assets/adventure/ui/player/backings/"
## 槽位到对应底图文件。
const BACKINGS: Dictionary = {
	0: "outfit_backing.png",
	1: "experience_card_backing.png",
	2: "item_card_backing.png",
	3: "item_card_backing.png", # 徽章共用道具卡底图。
	4: "collector_backing.png",
	5: "collector_backing.png",
}
## 四张原图共用的实底区，避开外缘透明像素和顶部装饰。
const BACKING_REGION := Rect2(71, 76, 126, 144)

## 返回 [param slot] 的底图实底区；没有映射或素材缺失时沿用默认槽底。
static func backing_texture(slot: int) -> Texture2D:
	var filename: String = str(BACKINGS.get(slot, "")) # 未知槽位不查找资源。
	if filename.is_empty() or not ResourceLoader.exists(ROOT + filename):
		return null
	var backing := AtlasTexture.new() # 从原图采样，保留源素材。
	backing.atlas = load(ROOT + filename) as Texture2D
	backing.region = BACKING_REGION
	backing.filter_clip = true
	return backing
