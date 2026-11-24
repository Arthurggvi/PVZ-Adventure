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
	var tanglekelp_events: Array[Dictionary] = [] # 缠绕海草在种植和拖拽时读取本株冻结的效果。
	var hypno_events: Array[Dictionary] = [] # 魅惑菇在原生种植、唤醒与死亡入口读取已选词条。
	var doom_events: Array[Dictionary] = [] # 毁灭菇的睡眠和灾害范围都在原生引爆前冻结。
	var squash_events: Array[Dictionary] = [] # 窝瓜先冻结种植与攻击规则，再由实际落地结算。
	var threepeater_events: Array[Dictionary] = [] # 三路弹道与叠种资格由原株在入树前冻结。
	var cactus_events: Array[Dictionary] = [] # 仙人掌攻速、弹道与命中状态由同一株冻结。
	var starfruit_events: Array[Dictionary] = [] # 杨桃的五向附弹、被动与命中规则。
	var cabbage_events: Array[Dictionary] = [] # 卷心菜的投掷和落点词条由本株冻结。
	var corn_events: Array[Dictionary] = [] # 玉米粒、投掷增益和黄油词条。
	var melon_events: Array[Dictionary] = [] # 西瓜的目标、连投和命中词条由本株冻结。
	for event: Dictionary in events: # 每本书的事件只进入对应机制，不复制运行时状态。
		match str(event.get("kind", "")):
			"negative_effect_immunity":
				plant.battle_negative_effect_immune = true
			"tallnut_armor_growth", "tallnut_guard_rear", "tallnut_thorns", "tallnut_crush_cap", "tallnut_absorb_blasts":
				var tall_nut := plant as Plant024TallNut # 植物入树前冻结自身防御配置。
				if tall_nut == null:
					return false
				tall_nut.configure_defense(event)
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
				elif kind.begins_with("tanglekelp_"):
					tanglekelp_events.append(event)
				elif kind.begins_with("hypno_"):
					hypno_events.append(event)
				elif kind.begins_with("doom_"):
					doom_events.append(event)
				elif kind.begins_with("squash_"):
					squash_events.append(event)
				elif kind.begins_with("threepeater_"):
					threepeater_events.append(event)
				elif kind.begins_with("cactus_"):
					cactus_events.append(event)
				elif kind.begins_with("starfruit_"):
					starfruit_events.append(event)
				elif kind.begins_with("cabbage_"):
					cabbage_events.append(event)
				elif kind.begins_with("corn_"):
					corn_events.append(event)
				elif kind.begins_with("melon_"):
					melon_events.append(event)
	if not melon_events.is_empty():
		var melon := plant as Plant040MelonPult # 只向普通西瓜投手安装投掷和命中词条。
		if melon == null:
			return false
		melon.configure_promotions(melon_events)
	if not corn_events.is_empty():
		var corn := plant as Plant035CornPult # 词条只应用于真实玉米投手。
		if corn == null:
			return false
		corn.configure_promotions(corn_events)
	if not cabbage_events.is_empty():
		var cabbage := plant as Plant033CabbagePult # 只为真实卷心菜投手安装这些词条。
		if cabbage == null:
			return false
		cabbage.configure_promotions(cabbage_events)
	if not starfruit_events.is_empty():
		var starfruit := plant as Plant030StarFruit # 只有真实杨桃能接收这组五向发射规则。
		if starfruit == null:
			return false
		starfruit.configure_promotions(starfruit_events)
	if not cactus_events.is_empty():
		var cactus := plant as Plant027Cactus # 只有仙人掌能安装这一组弹体规则。
		if cactus == null:
			return false
		cactus.configure_promotions(cactus_events)
	if not threepeater_events.is_empty():
		var threepeater := plant as Plant019ThreePeater # 只有三线射手使用这组发射及叠种规则。
		if threepeater == null:
			return false
		threepeater.configure_promotions(record.uid, threepeater_events)
	if not squash_events.is_empty():
		var squash := plant as Plant018Squash # 只有实际出战的窝瓜能接收它的放置与伤害规则。
		if squash == null:
			push_error("窝瓜转职事件需要对应的战斗植物")
			return false
		squash.configure_promotions(record.uid, squash_events)
	if not doom_events.is_empty():
		var doom := plant as Plant016DoomShroom # 仅对应的正式战斗植物能接收本物种词条。
		if doom == null:
			push_error("毁灭菇转职事件需要对应的战斗植物")
			return false
		doom.configure_promotions(doom_events)
	if not hypno_events.is_empty():
		var mushroom := plant as Plant013HypnoShroom # 只向同物种的真实战斗植物注入规则。
		if mushroom == null:
			push_error("魅惑菇转职事件需要对应的战斗植物")
			return false
		mushroom.configure_promotions(hypno_events)
	if not tanglekelp_events.is_empty():
		var kelp := plant as Plant020Tanglekelp # 只向本物种的实际战斗实例交付事件。
		if kelp == null:
			push_error("海草转职事件需要对应的战斗植物")
			return false
		kelp.configure_promotions(tanglekelp_events)
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
