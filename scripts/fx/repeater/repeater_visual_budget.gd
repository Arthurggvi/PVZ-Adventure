## 双发射手重特效的场景级视觉预算；仅控制绘制，禁止影响战斗时间与伤害查询。
extends RefCounted
class_name RepeaterVisualBudget

## 低负载的完整视觉层级。
const FULL: int = 0
## 中负载的简化视觉层级。
const MEDIUM: int = 1
## 密集战斗仅保留攻击识别元素。
const CHEAP: int = 2

## 当前仍在场景树里的辉夜场；退出场景树立即撤销。
static var _galaxies: int = 0
## 当前仍在场景树里的黑洞场。
static var _vortices: int = 0
## 正在绘制的冥弹、地狱、晨星与辉夜专属飞行尾迹。
static var _trails: int = 0
## 短命打击、爆发与吸收链数量。
static var _impacts: int = 0

## [param kind] 为四种视觉成本来源之一；每次入树恰好调用一次。
static func enter(kind: StringName) -> void:
	match kind:
		&"galaxy": _galaxies += 1
		&"vortex": _vortices += 1
		&"trail": _trails += 1
		&"impact": _impacts += 1

## [param kind] 必须与对应入树种类一致，计数永不为负。
static func leave(kind: StringName) -> void:
	match kind:
		&"galaxy": _galaxies = maxi(0, _galaxies - 1)
		&"vortex": _vortices = maxi(0, _vortices - 1)
		&"trail": _trails = maxi(0, _trails - 1)
		&"impact": _impacts = maxi(0, _impacts - 1)

## 辉夜最贵，涡旋次之；阈值不依赖帧率，负载上升会自动降级。
static func quality() -> int:
	var cost: int = _galaxies * 6 + _vortices * 3 + _trails + int(float(_impacts) * 0.5) # 粗略的GPU和CPU工作成本。
	if cost >= 96: # 十几处重型银河同时出现才切入最低画质。
		return CHEAP
	if cost >= 30: # 四个银河仍保留完整细节，五个开始温和降级。
		return MEDIUM
	return FULL

## 视觉时间采样间隔；不影响持续场精确的60Hz攻击时钟。
static func interval() -> float:
	match quality():
		MEDIUM: return 1.0 / 30.0
		CHEAP: return 1.0 / 24.0
	return 1.0 / 60.0

## 限制打击碎片与吸血链的同时存活数；冥弹保留额外的优先显示额度。
static func may_add_impact(priority: bool = false) -> bool:
	return _impacts < (64 if priority else 40)

## 用于压力验收的当前注册数量；正常玩法不读取调试数据。
static func counts() -> Vector4i:
	return Vector4i(_galaxies, _vortices, _trails, _impacts)
