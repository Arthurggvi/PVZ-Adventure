## 腐殖共生只传播本株已学的一至三转规则；共享结果与其他光环不能再次传播。
extends AdventureMushroomAura
class_name AdventureScaredySymbiosis

## [param plant] 为本株共生来源；[param rules] 是自身冻结转职规则，不接受目标合成后的倍率。
## 静态接收回调绑定白名单规则深副本，来源节点释放后仍可撤销其全部贡献。
func configure(plant: Plant000Base, rules: Dictionary) -> void:
	var shared: Dictionary = AdventureScaredyTraitRules.shareable(rules) # 来源与目标合成使用同一白名单，返回冻结深副本。
	configure_aura(plant, AdventureScaredySymbiosis._accept_other_mushroom,
		AdventureScaredySymbiosis._set_shared_source.bind(shared))

## [param target] 已通过公共蘑菇身份校验；原始物种为胆小菇时始终排除，含来源自身。
static func _accept_other_mushroom(target: Plant000Base) -> bool:
	return target.spawn_species_id() != CharacterRegistry.PlantType.P014ScaredyShroom

## [param target] 是实际受益植株；[param source_id] 标记唯一共生来源；[param enabled] 控制授予或撤销。
## [param rules] 是绑定的白名单冻结规则；撤销只查找已有控制器，不能因清理重新创建节点。
static func _set_shared_source(target: Plant000Base, source_id: int, enabled: bool, rules: Dictionary) -> void:
	if enabled:
		if rules.is_empty():
			return
		var traits: AdventureScaredyTraits = AdventureScaredyTraits.ensure(target) # 每个目标只有一个合成入口。
		if is_instance_valid(traits):
			traits.set_source(source_id, rules)
	else:
		var traits: AdventureScaredyTraits = target.get_node_or_null(^"AdventureScaredyTraits") \
			as AdventureScaredyTraits # 来源撤离时不安装新的目标节点。
		if is_instance_valid(traits):
			traits.remove_source(source_id)
