## 只负责初始卡牌的展示和原生奖励拾取星屑，不创建物品奖励或改写任何存档。
extends Control

## 使用原有两种植物身份和卡牌模板，展示不触发战斗或选卡逻辑。
const PLANTS: Array[CharacterRegistry.PlantType] = [CharacterRegistry.PlantType.P002SunFlower, CharacterRegistry.PlantType.P001PeaShooterSingle]
## 卡牌自身放大倍率，原模板尺寸为50×70。
const CARD_SCALE := 3.2
## 两张牌的视觉中心，粒子发射也严格使用同一局部坐标。
const CENTERS := [Vector2(110, 160), Vector2(330, 160)]
## 原生粒子以1066逻辑坐标制作，换算到1920设计画布。
const NATIVE_FX_SCALE := 1.8
## 本地展示卡，不修改AllCards中的源模板。
var cards: Array[Card] = []
## 只保留一条入场补间，收取或卸载时不会遗留回调。
var entrance: Tween
## 每次对话只展示一次，重复句通知不会重复生成奖励。
var revealed := false
## 是否仍有可见卡牌；收取后重复调用不会重播音效。
var cards_visible := false

## 原卡牌仅作静态展示，所有子控件忽略输入，点击仍交给戴夫。
func _ready() -> void:
	size = Vector2(440, 320)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for plant: CharacterRegistry.PlantType in PLANTS: # 只复制已注册的卡牌美术。
		var reference := ResourceCardReference.create(ResourceCardReference.CardType.Plant, plant) # 原有卡牌身份。
		var card := AllCards.create_card(reference) # Catalog用途不参与选卡和种植。
		add_child(card)
		card.pivot_offset = card.size / 2.0
		card.button.disabled = true
		_ignore_input(card)
		card.hide()
		cards.append(card)

## [param node] 的展示子控件统一忽略鼠标，不改变原模板的输入设置。
func _ignore_input(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children(): # 同时处理卡牌费用和缩略图的子节点。
		_ignore_input(child)

## 卡片从中心缩放、轻抬并淡入，保持两张牌的视觉中心对齐。
func reveal() -> void:
	if revealed:
		return
	revealed = true
	cards_visible = true
	entrance = create_tween().set_parallel(true)
	for index: int in range(cards.size()): # 仅两张固定卡，入场错开90毫秒。
		var card := cards[index] # 当前本地实例。
		var destination: Vector2 = CENTERS[index] - card.pivot_offset # 缩放围绕pivot，位置不按放大后的尺寸重复偏移。
		card.position = destination + Vector2(0, 28)
		card.scale = Vector2.ONE * CARD_SCALE * 0.6
		card.modulate.a = 0.0
		card.show()
		entrance.tween_property(card, "position", destination, 0.38).set_delay(index * 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		entrance.tween_property(card, "scale", Vector2.ONE * CARD_SCALE, 0.38).set_delay(index * 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		entrance.tween_property(card, "modulate:a", 1.0, 0.25).set_delay(index * 0.09)

## 下一句立即隐藏卡牌，在实际牌中心复用原礼盒彩色Star40拾取粒子，并仅播放一次prize。
func collect() -> void:
	if not cards_visible:
		return
	cards_visible = false
	if entrance != null:
		entrance.kill()
	# 原礼盒不入树，因此不会触发自动收集、花园奖励、音效或SaveService；只复制原粒子节点。
	var source := SceneRegistry.PRESENT.instantiate() # 保留原生粒子材质、数量、轨迹和纹理。
	for card: Card in cards: # 各自沿视觉中心发射，随同一画布缩放。
		var burst := source.get_node("GPUParticles2D").duplicate() as GPUParticles2D # 不运行Present脚本。
		burst.position = card.position + card.pivot_offset
		burst.scale = Vector2.ONE * NATIVE_FX_SCALE
		card.hide()
		add_child(burst)
		burst.finished.connect(burst.queue_free)
		burst.restart()
		burst.emitting = true
	source.free()
	SoundManager.play_other_SFX("prize")

## 主动结束对话时，所有补间和粒子都由本组件回收。
func _exit_tree() -> void:
	if entrance != null:
		entrance.kill()
