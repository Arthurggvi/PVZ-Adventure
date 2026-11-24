## 技能资源白名单：仅在战斗绑定角色技能时按 ID 加载，不参与启动预载。
extends RefCounted
class_name CharacterSkillCatalog

## 已实现技能的稳定 ID 与资源路径；未注册的 ID 不绑定技能。
const DEFINITION_PATHS: Dictionary = {
	&"default_farmer_refresh": "res://resources/adventure/skills/default_farmer_refresh.tres",
	&"eve_aurora_starfall": "res://resources/adventure/skills/eve_aurora_starfall.tres",
	&"deepseek_whale_freeze": "res://resources/adventure/skills/deepseek_whale_freeze.tres",
	&"sunflower_girl_sun_rain": "res://resources/adventure/skills/sunflower_girl_sun_rain.tres",
	&"spring_cattail_barrage": "res://resources/adventure/skills/spring_cattail_barrage.tres",
	&"rainy_postman_airmail": "res://resources/adventure/skills/rainy_postman_airmail.tres",
	&"glass_sea_diver_tidal_shock": "res://resources/adventure/skills/glass_sea_diver_tidal_shock.tres",
	&"midnight_clockmaker_slow": "res://resources/adventure/skills/midnight_clockmaker_slow.tres",
	&"unemployed_reaper_slash": "res://resources/adventure/skills/unemployed_reaper_slash.tres",
	&"tiramisu_flower_guard": "res://resources/adventure/skills/tiramisu_flower_guard.tres",
	&"don_quixote_charge": "res://resources/adventure/skills/don_quixote_charge.tres",
}

## 取 [param skill_id] 的有效定义副本；未知、未完成或资源不一致返回 null。
static func definition(skill_id: StringName) -> CharacterSkillDefinition:
	if skill_id.is_empty() or not DEFINITION_PATHS.has(skill_id):
		return null
	var path: String = str(DEFINITION_PATHS[skill_id]) # 只允许白名单路径，不接收存档中的任意文件路径。
	var source: CharacterSkillDefinition = load(path) as CharacterSkillDefinition # Godot 缓存重复加载的资源。
	if source == null or source.id != skill_id or not source.is_valid():
		return null
	return source.duplicate(true) as CharacterSkillDefinition
