extends BulletLinear000Base
class_name Bullet006PeaFire

## 火豌豆自身的循环表现动画。
@onready var anim_lib: AnimationPlayer = $Body/AnimLib
## 命中或撞地后结算周围目标的溅射组件。
@onready var spatter_component: SpatterComponent = $SpatterComponent
## 冒险转职火豆禁用原版固定溅射；原版火豆保持默认效果。
var enable_base_splash: bool = true

func _ready() -> void:
	super()
	anim_lib.play(&"ALL_ANIMS")

## [param enemy] 基类确认的命中目标；为空时仍允许撞地溅射，但不会尝试解冻。[br]
## 解冻先于扣血，防止解冻回调覆盖致死伤害启动的死亡动画速度。
func _attack_enemy(enemy:Character000Base):
	if _can_attack_character(enemy):
		enemy.cancel_ice()
	super(enemy)
	if enable_base_splash:
		spatter_component.spatter_all_area_zombie(enemy)


## [param zombie] 直击的僵尸；探险家只有实际受到火焰伤害时才会重燃。
func _attack_zombie(zombie: Zombie000Base) -> void:
	# 减伤或免疫可能使一次火豌豆命中没有造成伤害。
	var hp_before: int = zombie.hp_component.get_all_hp()
	super(zombie)
	if is_instance_valid(zombie) and zombie is Zombie027Explorer \
		and zombie.hp_component.get_all_hp() < hp_before:
		zombie.relight_from_fire()

## [param zombie]、[param mode]、[param armor] 与 [param bonus] 沿用原生直击参数。
## 火豆只为本次实际伤害携带火焰死因；红焰、狱焰继承此入口，代伤保持同一来源。
func _apply_zombie_impact(zombie: Zombie000Base, mode: BulletRegistry.AttackMode,
		armor: float, bonus: Vector2i) -> Zombie000Base:
	return (zombie.hp_component as HpComponentZombie).apply_hit(attack_value, mode, true,
		trigger_be_attack_sfx, true, armor, bonus.x, bonus.y, _impact_receipt(),
		CombatHitScope.for_cause(CombatHitScope.DeathCause.FIRE))
