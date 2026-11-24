## 冒险续战的场景演出接口。战斗输入和暂停由续战流程管理。
@abstract
extends CanvasLayer
class_name AdventurePhasePresentation

## 预检 [param phase] 的演出条件。返回 [code]false[/code] 时保留当前阶段。
@abstract func prepare_phase(phase: StagePhaseDefinition) -> bool

## 播放已提交的 [param phase] 的演出，完成后由续战控制器交接战斗。
@abstract func play_phase(phase: StagePhaseDefinition) -> void
