## 致幻洋流沿用主战斗实现，只声明普通、噩梦及噩梦末波 Boss 的动态资源依赖。
extends MainGameManager

## 统一 SceneTransition 在入场时后台准备，资源强引用由目标场景持有。
## 不实例化角色，不建立新的 Loader 或全局缓存。
static func get_initial_resource_paths() -> PackedStringArray:
	var paths := PackedStringArray() # 当前关卡的全部阶段共享一份有限清单。
	var stage: StageDefinition = AdventureStageRegistry.resolve(AdventureStageRegistry.PSYCHEDELIC_CURRENT) # 复用入口已解析的私有模板。
	if stage == null:
		return paths
	for phase: StagePhaseDefinition in stage.phases: # 后续阶段敌人也须避免出场帧同步读盘。
		for species: int in AdventureStageRoster.zombie_types(phase): # 从阶段权威提取实际物种。
			var path: String = Global.character_registry.ZombieInfo[species][CharacterRegistry.ZombieInfoAttribute.ZombieScenes] # 注册表中的惰性场景路径。
			if not paths.has(path):
				paths.append(path)
		for encounter: BossEncounterDefinition in phase.boss_encounters: # 同阶段末波遭遇使用的 Boss。
			var path: String = Global.character_registry.ZombieBossInfo[encounter.boss_type][CharacterRegistry.ZombieBossInfoAttribute.BossScenes] # 与 Boss 工厂读取同一注册项。
			if not paths.has(path):
				paths.append(path)
	return paths
