## 红焰与狱焰保留原生火豆的攻击、解冻、溅射和火把点燃规则。
extends Bullet006PeaFire
class_name RepeaterFireProjectile

## 本颗火豆的冻结战场与植物来源。
var shot: RepeaterShotContext
## 红焰追加灼烧；狱焰命中生成独立限时漩涡。
var kind: StringName = &"ember"

## 继承原生火焰动画，再为原素材添加变种材质与尾焰。
func _ready() -> void:
	super()
	if shot == null or not shot.is_active():
		queue_free()
		return
	is_can_up = false
	unique_target_hits = true
	impact_resolved.connect(_on_impact)
	RepeaterProjectileVisual.attach(self, kind)

## [param target] 已结算原生直击及溅射；[param position] 为世界命中点。
func _on_impact(target: Character000Base, position: Vector2) -> void:
	if shot == null or not shot.is_same_battle():
		return
	RepeaterImpactVisual.spawn(shot.game.bullets, kind, position, direction)
	if not shot.is_active():
		return
	RepeaterProjectileEffects.impact(kind, target, position, shot)
