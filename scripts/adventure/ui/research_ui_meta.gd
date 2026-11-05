## Research UI labels only. No fabricated player or gameplay data.
extends RefCounted
const MODES := ["craft", "upgrade", "promotion"]
const TITLES := {"craft": "合成", "upgrade": "强化", "promotion": "转职"}
static func title(mode: String) -> String:
	return str(TITLES.get(mode, ""))
