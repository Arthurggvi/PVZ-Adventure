# 黑将军美术提交检查点

- 已验收：一、二阶段站姿及 Idle；二阶段猩红眼；躯干锚定黑烟；血骷髅大令旗。
- 策划要求 6 类动作，拆为 7 段：idle、run（换行跑步）、raise（举旗）、windup（冲锋蓄力）、charge（冲锋）、teleport_in、teleport_out。
- 保留的 7 个 Animation 资源除 idle 外均为待重做的参考轨道，不能视为验收完成的动作。
- 无需 walk（独立行走）、plant（独立插旗）、eat（啃咬）、die（独立死亡）动画；死亡统一执行传送退场。
- 插旗、号令和领军统一复用举旗；换行跑步参考 Football walk，冲锋参考 All-Star run/tackle。
- 原版 Football 是分件关节来源，不得将 All-Star 的节点路径直接复制进黑将军。
- 黑烟节点 Zombie_football_upperbody/BlackSmokeBack 仅二阶段启用，不得恢复废弃的浮动石块状火焰。
- 当前仅是美术资源与独立视觉适配场景，未连接游戏实际 Boss 行为、伤害、召唤与音效。
