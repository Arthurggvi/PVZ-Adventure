## 雪山植株的抖雪源。只选真实美术部件，避开发光层、弹体和爆炸效果。
extends RefCounted
class_name SnowPlantProfiles

## 复用角色登记中的稳定物种编号。
const Plant: Dictionary = CharacterRegistry.PlantType
## 各豌豆类共有的近地叶片，从真实基部精灵取样。
const PEA_BASE: Array[StringName] = [&"Frontleaf", &"Backleaf"]


## 返回 [param species] 可作为扬雪位置的真实节点名；没有适合的部件时返回空数组。
static func for_species(species: int) -> Array[StringName]:
	match species:
		Plant.P001PeaShooterSingle, Plant.P008PeaShooterDouble, Plant.P049PeaShooterDoubleReverse:
			return _pea_sources([&"Anim_face"])
		Plant.P006SnowPea:
			return _pea_sources([&"Anim_face", &"SnowPea_crystals1"])
		Plant.P019ThreePeater:
			return _pea_sources([&"Anim_face1", &"Anim_face2", &"Anim_face3"])
		Plant.P029SplitPea:
			return _pea_sources([&"Anim_face", &"SplitPea_head"])
		Plant.P041GatlingPea:
			return _pea_sources([&"GatlingPea_helmet", &"Anim_face"])
		Plant.P002SunFlower:
			return _pea_sources([&"SunFlower_toppetals"])
		Plant.P039MariGold:
			return _pea_sources([&"Marigold_petals"])
		Plant.P042TwinSunFlower:
			return _pea_sources([&"Sunflower_double_petals1", &"Sunflower_double_petals2"])
		Plant.P004WallNut:
			return [&"Anim_face"]
		Plant.P024TallNut:
			return [&"Anim_idle"]
		Plant.P031Pumpkin:
			return [&"Pumpkin_back", &"Pumpkin_front"]
		Plant.P037Garlic:
			return [&"Anim_face", &"Garlic_stem1"]
		Plant.P007Chomper:
			return [&"Chomper_topjaw", &"Chomper_Headleaf1", &"Chomper_groundleaf1", &"Chomper_groundleaf2"]
		Plant.P012GraveBuster:
			return [&"Gravebuster_head", &"Gravebuster_leaf1"]
		Plant.P018Squash:
			return [&"Squash_body", &"Squash_stem"]
		Plant.P027Cactus:
			return [&"Cactus_flower", &"Cactus_arm1_1", &"Cactus_arm2_1"]
		Plant.P026Plantern:
			return [&"Plantern_leaf1", &"Plantern_leaf2", &"Plantern_leaf3"]
		Plant.P038UmbrellaLeaf:
			return [&"Umbrellaleaf_leaf1", &"Umbrellaleaf_leaf2", &"Umbrellaleaf_leaf3", &"Umbrellaleaf_leaf4"]
		Plant.P030StarFruit:
			return [&"Anim_face", &"Starfruit_leaf"]
		Plant.P009PuffShroom:
			return [&"PuffShroom_head", &"PuffShroom_tip", &"PuffShroom_stem"]
		Plant.P010SunShroom:
			return [&"SunShroom_head", &"Anim_face"]
		Plant.P011FumeShroom:
			return [&"DoomShroom_head", &"Anim_face"]
		Plant.P013HypnoShroom:
			return [&"Layer 2", &"Layer 1"]
		Plant.P014ScaredyShroom:
			return [&"ScaredyShroom_head", &"ScaredyShroom_head2"]
		Plant.P015IceShroom:
			return [&"IceShroom_head", &"IceShroom_base"]
		Plant.P016DoomShroom:
			return [&"DoomShroom_head1", &"DoomShroom_head2", &"DoomShroom_sleepinghead", &"DoomShroom_body"]
		Plant.P032MagnetShroom:
			return [&"Magnetshroom_stemcap", &"Magnetshroom_stemcap_overlay"]
		Plant.P043GloomShroom:
			return [&"GloomShroom_face", &"GloomShroom_shooter4", &"GloomShroom_base"]
		Plant.P046GoldMagnet:
			return [&"GoldMagnet_leaf1", &"GoldMagnet_leaf4", &"GoldMagnet_leaf5", &"GoldMagnet_stem"]
		Plant.P033CabbagePult:
			return [&"Cabbagepult_basket", &"Cabbagepult_leaf", &"Frontleaf", &"Cabbagepult_backleaf1"]
		Plant.P035CornPult:
			return [&"Cabbagepult_basket", &"Cabbagepult_basket2", &"Cornpult_husk1", &"Cornpult_husk2"]
		Plant.P040MelonPult, Plant.P045WinterMelon:
			return [&"Cabbagepult_basket", &"Anim_face", &"Frontleaf"]
		Plant.P048CobCannon:
			return [&"CobCannon_husk4", &"CobCannon_husk3", &"CobCannon_cob", &"CobCannon_log1"]
		Plant.P005PotatoMine:
			return [&"PotatoMine_rock1", &"PotatoMine_rock2", &"PotatoMine_rock41", &"PotatoMine_rock3"]
		Plant.P022Caltrop:
			return [&"Anim_face", &"Caltrop_horn1", &"Caltrop_horn2", &"Caltrop_horn3"]
		Plant.P047SpikeRock:
			return [&"Anim_face", &"Bigspike1", &"Bigspike2", &"Bigspike3"]
		Plant.P034FlowerPot:
			return [&"Pot_top", &"Pot_leaf1", &"Pot_bottom"]
		Plant.P017LilyPad:
			return [&"Anim_idle"]
		Plant.P044Cattail:
			return [&"Cattail_hat", &"Cattail_tail", &"Cattail_paw1"]
		Plant.P050LightningReed:
			# 图集 Rig 的顶叶与两片近地叶，排除细电光、根部阴影与特效场景。
			return [&"Layer02", &"Layer10", &"Layer11"]
		Plant.P051Bloomerang:
			# 使用横九帧图集的当前帧。
			return [&"Art"]
		Plant.P052ElectricPeashooter:
			# 图集 Rig 中顶叶、头部和根叶；放电特效不在选定范围。
			return [&"Layer01", &"Layer08", &"Layer03", &"Layer04"]
		Plant.P1000Sprout:
			return [&"Sprout", &"Sprout_petal"]
		_:
			# 常燃、浸水和一次性效果没有稳定的扬雪源。
			return []


## 把 [param heads] 的主部件与各豌豆类共有的底叶合并。
static func _pea_sources(heads: Array[StringName]) -> Array[StringName]:
	var sources: Array[StringName] = heads.duplicate() # 当前物种的完整候选节点名。
	sources.append_array(PEA_BASE)
	return sources
