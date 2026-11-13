## 双发弹体工厂按需加载原生继承场景，避免全局类与子弹注册表发生静态加载环。
extends RefCounted
class_name RepeaterProjectileFactory

## 原生豌豆派生场景，支持冻弹、震撼、引爆、晨星、辉夜和冥弹。
const PEA_PATH: String = "res://scenes/bullet/bullet_repeater_pea.tscn"
## 保留原生火豆动画、直击与溅射的派生场景。
const FIRE_PATH: String = "res://scenes/bullet/bullet_repeater_fire.tscn"
## 原生阳桃弹体的有限代分裂场景。
const STAR_PATH: String = "res://scenes/bullet/bullet_repeater_star.tscn"

## [param kind] 为单一变种；[param shot] 为冻结来源；返回尚未初始化和入树的弹体。
## [param scaled_damage] 非负时已经包含卡片倍率，调用方必须用一倍初始化；负一保留原生攻值。
## [param generation] 是分裂代数；[param color_index] 只影响同代配色，不影响伤害。
static func create(kind: StringName, shot: RepeaterShotContext, scaled_damage: int = -1,
		generation: int = 0, color_index: int = 0) -> Bullet000NormBase:
	var scene: PackedScene # 按能力选择场景，不改变全局子弹注册表。
	if kind == &"":
		scene = Global.bullet_registry.get_bullet_scenes(BulletRegistry.BulletType.Bullet001Pea)
	else:
		var path: String = FIRE_PATH if kind in [&"ember", &"hell"] else (
			STAR_PATH if kind in [&"star_dark", &"star_light"] else PEA_PATH) # 原生素材继承保持一致。
		scene = load(path) as PackedScene
	if scene == null:
		push_error("双发转职弹体场景缺失")
		return null
	var bullet: Bullet000NormBase = scene.instantiate() as Bullet000NormBase # 原命中管线继续负责护甲与死亡事件。
	if bullet == null:
		push_error("双发转职弹体不支持原生伤害接口")
		return null
	bullet.attack_validity = _source_is_active.bind(shot)
	if scaled_damage >= 0:
		bullet.attack_value = scaled_damage
	if kind != &"":
		bullet.set("shot", shot)
		bullet.set("kind", kind)
		bullet.is_can_up = false
	if generation > 0:
		bullet.set("generation", generation)
		bullet.set("color_index", color_index)
	return bullet

## [param shot] 由绑定参数强持有；普通豌豆被火炬换形后仍保留原战场门禁。
static func _source_is_active(shot: RepeaterShotContext) -> bool:
	return shot != null and shot.is_active()
