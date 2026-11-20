extends Node2D
## 启动时把敌人/豆子等小图形画进一张图集，运行时只贴图（省绘制调用）。
var fn: Callable

func _draw() -> void:
	fn.call(self)
