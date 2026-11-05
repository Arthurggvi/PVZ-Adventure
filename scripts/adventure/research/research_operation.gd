## Typed research command. The service recreates it from UI input for every execution.
## The transaction never interprets arbitrary dictionaries as write instructions.
extends RefCounted
class_name AdventureResearchOperation

enum Kind { CRAFT, ENHANCE, PROMOTE }
var kind: Kind
var recipe_id: String = ""
var card_uid: String = ""
var book_id: String = ""
var material_uids: Array = []
var use_pot: bool = false
var fertilizer_id: String = ""

static func from_choice(mode: String, choice: Dictionary) -> AdventureResearchOperation:
	var action := AdventureResearchOperation.new()
	match mode:
		"craft":
			action.kind = Kind.CRAFT
			action.recipe_id = str(choice.get("recipe_id", ""))
			if action.recipe_id.is_empty():
				return null
		"upgrade":
			action.kind = Kind.ENHANCE
			action.card_uid = str(choice.get("uid", ""))
			var raw: Variant = choice.get("materials", [])
			if not raw is Array:
				return null
			action.material_uids = raw.duplicate()
			action.use_pot = bool(choice.get("use_pot", false))
			action.fertilizer_id = str(choice.get("fertilizer", ""))
		"promotion":
			action.kind = Kind.PROMOTE
			action.card_uid = str(choice.get("uid", ""))
			action.book_id = str(choice.get("book_id", ""))
		_:
			return null
	return action

func mode() -> String:
	match kind:
		Kind.CRAFT: return "craft"
		Kind.ENHANCE: return "upgrade"
		Kind.PROMOTE: return "promotion"
	return ""

func choice() -> Dictionary:
	match kind:
		Kind.CRAFT:
			return {"recipe_id": recipe_id}
		Kind.ENHANCE:
			return {"uid": card_uid, "materials": material_uids.duplicate(),
				"use_pot": use_pot, "fertilizer": fertilizer_id}
		Kind.PROMOTE:
			return {"uid": card_uid, "book_id": book_id}
	return {}
