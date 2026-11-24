## 飞艇甲板在稀疏棋盘上的固定身份与草皮范围；位移、暂停和存档由 BoardSurface 管理。
extends BoardSurfaceDefinition

## 初始逻辑区域，X 为列、Y 为行；平台跨行移动时仍保留这些地址。
@export var grid_rect := Rect2i(0, 0, 2, 2)
## 平台局部像素中的可种草皮，不含栏杆、花饰和悬空处。
@export var turf_rect := Rect2(13.8, 6.0, 126.0, 150.0)
