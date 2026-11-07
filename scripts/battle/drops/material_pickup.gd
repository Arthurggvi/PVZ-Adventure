## 战场材料掉落物：外观复用冒险物品图标，拾取后直接进背包。
## 抛出、落地、超时与收集表现继承自 [BattlePickup]；本类额外提供星芒光晕、弹出缩放与拾取迸发。
extends BattlePickup
class_name MaterialPickup

const ItemArt = preload("res://scripts/adventure/ui/inventory_item_art.gd")

## 图标在战场上的显示边长（像素）。
const ICON_PIXELS := 48.0
## 星芒光晕在战场上的基准直径（像素）。
const SPARKLE_PIXELS := 150.0
## 星芒自转一圈所需时间（秒）。
const SPARKLE_SPIN_SECONDS := 9.0

@onready var icon: Sprite2D = $Body/Icon
@onready var sparkle: Sprite2D = $Body/Sparkle
@onready var burst: GPUParticles2D = $Burst

## 本次掉落的物品 id 与数量。
var item_id: StringName
var quantity := 1
## 待机浮动补间。
var _bob: Tween
## 星芒呼吸补间。
var _sparkle_tween: Tween
## 星芒自转补间。
var _spin_tween: Tween

func _ready() -> void:
	super._ready()
	_start_idle_motion()

## 设置掉落的物品与数量，并按图标原始尺寸缩放到战场显示大小。
func setup_item(id: StringName, amount := 1) -> void:
	item_id = id
	quantity = maxi(1, amount)
	var uri := ItemArt.icon_uri(str(id))
	if uri.is_empty() or icon == null:
		return
	var texture := load(uri) as Texture2D
	if texture == null:
		return
	icon.texture = texture
	var longest := float(maxi(texture.get_width(), texture.get_height()))
	if longest > 0.0:
		icon.scale = Vector2.ONE * (ICON_PIXELS / longest)

## 抛出瞬间做一次弹出缩放，让掉落更容易被注意到。
func launch(relative_target: Vector2) -> void:
	scale = Vector2(0.35, 0.35)
	var pop := create_tween()
	pop.tween_property(self, "scale", Vector2(1.08, 1.08), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(self, "scale", Vector2.ONE, 0.12)
	super.launch(relative_target)

## 地面待机：本体轻微上下浮动，星芒缓慢自转并明暗呼吸。
func _start_idle_motion() -> void:
	var body := get_node_or_null("Body") as Node2D
	if body != null:
		var base_y := body.position.y
		_bob = create_tween().set_loops()
		_bob.tween_property(body, "position:y", base_y - 4.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_bob.tween_property(body, "position:y", base_y, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_start_sparkle()

## 星芒：按贴图尺寸缩放到战场大小，自转一圈的同时做缩放与透明度呼吸。
func _start_sparkle() -> void:
	if sparkle == null or sparkle.texture == null:
		return
	var longest := float(maxi(sparkle.texture.get_width(), sparkle.texture.get_height()))
	if longest <= 0.0:
		return
	var base_scale := SPARKLE_PIXELS / longest
	sparkle.scale = Vector2.ONE * base_scale
	sparkle.modulate.a = 0.55
	_sparkle_tween = create_tween().set_loops()
	_sparkle_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sparkle_tween.tween_property(sparkle, "scale", Vector2.ONE * base_scale * 1.22, 0.8)
	_sparkle_tween.parallel().tween_property(sparkle, "modulate:a", 1.0, 0.8)
	_sparkle_tween.tween_property(sparkle, "scale", Vector2.ONE * base_scale, 0.8)
	_sparkle_tween.parallel().tween_property(sparkle, "modulate:a", 0.55, 0.8)
	_spin_tween = create_tween().set_loops()
	_spin_tween.tween_property(sparkle, "rotation", TAU, SPARKLE_SPIN_SECONDS).as_relative()

func _on_collect_start() -> void:
	_stop_idle_motion()
	_emit_burst()

## 停止待机补间并隐藏星芒，避免它们跟着收集飞行一起被带走。
func _stop_idle_motion() -> void:
	if _bob != null:
		_bob.kill()
		_bob = null
	if _sparkle_tween != null:
		_sparkle_tween.kill()
		_sparkle_tween = null
	if _spin_tween != null:
		_spin_tween.kill()
		_spin_tween = null
	if sparkle != null:
		sparkle.visible = false

## 拾取迸发：把礼盒的星形粒子挪到父节点上原地炸开，本体继续飞向金币栏。
func _emit_burst() -> void:
	if burst == null:
		return
	var host := get_parent()
	if host == null:
		return
	burst.reparent(host, true)
	burst.emitting = true
	burst.finished.connect(burst.queue_free)

## 拾取后把材料写进冒险背包；界面不弹任何文字提示。
func _grant() -> bool:
	if item_id.is_empty() or not Global.adventure_inventory.owns_state(_owner_state):
		return false
	return Global.adventure_inventory.add_item(String(item_id), quantity)
