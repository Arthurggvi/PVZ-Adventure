## Central art resolver for adventure star badges. No gameplay or save-state dependency.
extends RefCounted

const ROOT := "res://assets/adventure/ui/star_badges/"
const FX_SHADER := preload("res://shaders/adventure/star_badge_fx.gdshader")

static func body(rank: int) -> Texture2D:
	if rank < 1 or rank > 10:
		return null
	var uri := ROOT + "static/256/star_%02d.png" % rank
	return load(uri) as Texture2D if ResourceLoader.exists(uri) else null

static func mask(rank: int, suffix: String) -> Texture2D:
	if rank < 5 or rank > 10:
		return null
	var uri := ROOT + "masks/star_%02d_%s.png" % [rank, suffix]
	return load(uri) as Texture2D if ResourceLoader.exists(uri) else null

static func sparkle() -> Texture2D:
	return load(ROOT + "fx/sparkle_shared.png") as Texture2D

static func halo() -> Texture2D:
	return load(ROOT + "fx/star_10_halo.png") as Texture2D
