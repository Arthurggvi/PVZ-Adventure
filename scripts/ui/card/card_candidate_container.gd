## 备选卡的占位背景，卡片移走后保留相同内容与费用预览。
extends Control
class_name CardCandidateContainer

## 与本容器关联的可选卡实例；选择时可移到出战卡槽。
var card: Card
## 与真实卡片保持一致的占位背景。
@onready var card_bg: TextureRect = $CardBg
## 显示真实卡片当前费用的占位标签。
@onready var cost: Label = $CardBg/Cost
## 卡片首次移走后才生成的占位图；开局卡片覆盖背景时不复制第二棵静态图树。
var _placeholder_preview: Node2D

## 子卡已完成初始化，只同步背景与费用；占位图在真实卡片离开时再创建。
func _ready() -> void:
	cost.text = str(card.sun_cost)
	card_bg.texture = card.card_bg.texture
	child_exiting_tree.connect(_on_child_exiting)

## [param child] 为即将移走的节点；延迟到重挂完成后判断，避免离场时创建无用占位图。
func _on_child_exiting(child: Node) -> void:
	if child == card and not is_instance_valid(_placeholder_preview):
		_ensure_placeholder.call_deferred()

## 只在容器仍有效且真实卡已移走时装配占位图；同一容器最多复制一次。
func _ensure_placeholder() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or is_instance_valid(_placeholder_preview) \
			or not is_instance_valid(card) or card.get_parent() == self:
		return
	_placeholder_preview = AllCards.create_static_preview(card.card_reference, card.promotion_tier())
	if _placeholder_preview != null:
		card_bg.add_child(_placeholder_preview)

## 入树前绑定 [param curr_card] 并设置返回位置，然后挂载子卡；占位不拥有卡牌身份。
func init_card_in_seed_chooser(curr_card: Card) -> void:
	card = curr_card
	curr_card.card_candidate_container = self
	add_child(curr_card)
