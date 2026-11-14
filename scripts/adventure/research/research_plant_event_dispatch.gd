## 将冻结转职事件挂接到实际植物，数值成长和生产结算仍由出生修饰器处理。
extends RefCounted
class_name AdventureResearchPlantEventDispatch

## 将 [param record] 的 [param events] 安装到入树前的 [param plant]；类型不符时拒绝出生。
static func apply_events(plant: Plant000Base, record: PlantCardInstance, events: Array[Dictionary]) -> bool:
	var wallnut_events: Array[Dictionary] = [] # 坚果的防御与亡语事件按来源单株安装。
	var potato_events: Array[Dictionary] = [] # 地雷的引信与爆炸规则交给原生植物。
	var cherry_events: Array[Dictionary] = [] # 交给樱桃炸弹本身冻结，等原版引信结算。
	var puff_events: Array[Dictionary] = [] # 孢子的射击与命中能力按单株冻结。
	var sunshroom_events: Array[Dictionary] = [] # 阳光菇的成长、光环与储蓄按实际植株执行。
	var scaredy_events: Array[Dictionary] = [] # 攻击专用词条和共享来源按单株冻结。
	var fume_events: Array[Dictionary] = [] # 大喷的范围、持续喷涌和命中规则按攻击冻结。
	var lily_events: Array[Dictionary] = [] # 睡莲仅维护真实承托植物的周期效果。
	var bloomerang_events: Array[Dictionary] = [] # 回旋镖由原株单时钟发射，弹体各自保存飞行规则。
	var repeater_events: Array[Dictionary] = [] # 双发只追加本轮总发数，每颗独立抽取一种变种。
	var snow_pea_events: Array[Dictionary] = [] # 寒冰射手事件交给原生发射上的转职控制器。
	var electric_pea_events: Array[Dictionary] = [] # 电能豌豆参数由原株在入树前冻结。
	var jalapeno_events: Array[Dictionary] = [] # 辣椒规则入树前冻结，仍用原生引信。
	var ice_shroom_events: Array[Dictionary] = [] # 寒冰菇转职由原生冰冻引爆入口结算。
	for event: Dictionary in events: # 每本书的事件只进入对应机制，不复制运行时状态。
		match str(event.get("kind", "")):
			"negative_effect_immunity":
				plant.battle_negative_effect_immune = true
			"puff_day_awake", "sunshroom_day_awake", "fume_day_awake":
				# 出生修饰发生在入树前，耐日技能从一开始就不进入睡眠状态。
				plant.is_sleep_in_day = false
			"wallnut_hit_cap":
				var hp: HpComponentPlant = plant.get_node_or_null("HpComponent") as HpComponentPlant # 单次受击上限由同一生命入口维护。
				if hp == null:
					push_error("单次受伤上限需要植物专用生命组件")
					return false
				hp.max_single_hit_fraction = float(event.get("fraction", 0.0))
			_:
				var kind: String = str(event.get("kind", "")) # 事件前缀声明所属植物机制。
				if kind.begins_with("wallnut_"):
					wallnut_events.append(event)
				elif kind.begins_with("potato_"):
					potato_events.append(event)
				elif kind.begins_with("cherry_"):
					cherry_events.append(event)
				elif kind.begins_with("puff_"):
					puff_events.append(event)
				elif kind.begins_with("sunshroom_"):
					sunshroom_events.append(event)
				elif kind.begins_with("scaredy_"):
					scaredy_events.append(event)
				elif kind.begins_with("fume_"):
					fume_events.append(event)
				elif kind.begins_with("lily_"):
					lily_events.append(event)
				elif kind.begins_with("bloomerang_"):
					bloomerang_events.append(event)
				elif kind.begins_with("repeater_"):
					repeater_events.append(event)
				elif kind.begins_with("snow_pea_"):
					snow_pea_events.append(event)
				elif kind.begins_with("electric_pea_"):
					electric_pea_events.append(event)
				elif kind.begins_with("jalapeno_"):
					jalapeno_events.append(event)
				elif kind.begins_with("ice_shroom_"):
					ice_shroom_events.append(event)
	if not ice_shroom_events.is_empty():
		if not plant is Plant015IceShroom:
			push_error("寒冰菇转职事件只能挂载于寒冰菇")
			return false
		(plant as Plant015IceShroom).configure_promotions(record.uid, ice_shroom_events)
	if not jalapeno_events.is_empty():
		if not plant is Plant021Jalapeno:
			push_error("火爆辣椒转职事件需要对应的战斗植物")
			return false
		(plant as Plant021Jalapeno).configure_promotions(record.uid, jalapeno_events)
	if not electric_pea_events.is_empty():
		if not plant is Plant052ElectricPeashooter:
			push_error("电能豌豆转职事件需要对应的战斗植物")
			return false
		(plant as Plant052ElectricPeashooter).configure_promotions(electric_pea_events)
	if not snow_pea_events.is_empty():
		if not plant is Plant006SnowPea:
			push_error("寒冰射手转职事件需要对应的战斗植物")
			return false
		var snow_pea := AdventureSnowPeaPromotion.new() # 先冻结选择，入树后只连接原生攻击信号。
		snow_pea.configure(plant as Plant006SnowPea, snow_pea_events)
		plant.add_child(snow_pea)
	if not repeater_events.is_empty():
		if not plant is Plant008PeaShooterDouble:
			push_error("双发射手转职事件需要对应的战斗植物")
			return false
		var repeater_controller := AdventureRepeaterPromotionEffects.new() # 入树前冻结书目，原株就绪后连接原攻击链。
		repeater_controller.configure(plant as Plant008PeaShooterDouble, repeater_events)
		plant.add_child(repeater_controller)
	if not bloomerang_events.is_empty():
		if not plant is Plant051Bloomerang:
			push_error("回旋镖转职事件需要对应的战斗植物")
			return false
		(plant as Plant051Bloomerang).configure_promotions(bloomerang_events)
	if not lily_events.is_empty():
		if not plant is Plant000DownBase:
			push_error("睡莲转职事件需要实际承托植物")
			return false
		var lily_controller := AdventureLilyPromotionEffects.new() # 承托关系由正常种植层提供。
		lily_controller.configure(plant as Plant000DownBase, lily_events)
		plant.add_child(lily_controller)
	if not fume_events.is_empty():
		if not plant is Plant011FumeShroom:
			push_error("大喷菇转职事件需要对应的战斗植物")
			return false
		var fume_controller := AdventureFumePromotionEffects.new() # 只扩展原生喷射与攻击门禁。
		fume_controller.configure(plant as Plant011FumeShroom, fume_events)
		plant.add_child(fume_controller)
	if not scaredy_events.is_empty() and not AdventureScaredyTraits.install(plant, scaredy_events):
		return false
	if not sunshroom_events.is_empty():
		if not plant is Plant010SunShroom:
			push_error("阳光菇转职事件需要对应的战斗植物")
			return false
		var sunshroom_controller := AdventureSunShroomPromotionEffects.new() # 成长事件与实际生产共用单株生命周期。
		sunshroom_controller.configure(plant as Plant010SunShroom, sunshroom_events)
		plant.add_child(sunshroom_controller)
	if not puff_events.is_empty():
		if not plant is Plant009Puff:
			push_error("小喷菇转职事件需要对应的战斗植物")
			return false
		var puff_controller := AdventurePuffPromotionEffects.new() # 随植株管理发射，弹体单独保存命中规则。
		puff_controller.configure(plant, puff_events)
		plant.add_child(puff_controller)
	if not cherry_events.is_empty():
		var cherry: Plant003CherryBomb = plant as Plant003CherryBomb # 仅真实樱桃可接管原版爆炸。
		if cherry == null:
			push_error("樱桃炸弹转职事件需要对应的战斗植物")
			return false
		cherry.configure_promotions(record.uid, cherry_events)
	if not potato_events.is_empty():
		var mine: Plant005PotatoMine = plant as Plant005PotatoMine # 拒绝把地雷配置挂到其他物种。
		if mine == null:
			push_error("土豆地雷转职事件只能挂在原版地雷植物上")
			return false
		var potato_controller := AdventurePotatoPromotionEffects.new() # 原版地雷仍拥有自身引信与存活状态。
		potato_controller.configure(mine, potato_events)
		mine.add_child(potato_controller)
	if not wallnut_events.is_empty():
		var controller := AdventureWallnutPromotionEffects.new() # 防御输出跟随本株生命周期撤销。
		controller.configure(plant, wallnut_events)
		plant.add_child(controller)
	return true
