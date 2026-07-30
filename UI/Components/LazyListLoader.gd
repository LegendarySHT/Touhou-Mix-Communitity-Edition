## 懒加载列表构建器
## 提供增量让帧 + 生成计数器取消机制，供 DelView / AlbumView 等列表视图共用。
## 节点生命周期由调用方管理（创建 + add_child + 释放），本模块只负责编排构建循环。
class_name LazyListLoader extends RefCounted

## 首个非空组完成时触发（用于停止 Loading 动画 + fade-in 等早期 UX 反馈）
signal first_step_completed()

## 每处理 N 组让出一帧（>=1）
var _yield_interval: int = 1
## build 开始前是否先让一帧（让 queue_free 的旧节点先释放）
var _initial_frame_yield: bool = true

## 单调递增的生成计数器（每次 build 或 cancel +1）
var _generation: int = 0
## 当前正在构建的 generation（0 = 无构建）
var _building_generation: int = 0


func _init(yield_interval: int = 1, initial_frame_yield: bool = true) -> void:
	_yield_interval = max(1, yield_interval)
	_initial_frame_yield = initial_frame_yield


## 异步构建：对 i in range(group_count) 调用 factory(i)。
## factory(i) 应返回 Array（本组创建的节点，已 add_child；可为空数组）；
## 返回 null 表示请求中止构建。
## 调用本方法会自动取消上一轮 in-flight build。
## 返回 true=正常完成，false=被取消或中止。
func build(group_count: int, factory: Callable) -> bool:
	_generation += 1
	var my_gen := _generation
	_building_generation = my_gen

	if _initial_frame_yield:
		await _process_frame()
		if _generation != my_gen:
			_cleanup_build(my_gen)
			return false

	var first_done := false
	var i := 0
	while i < group_count:
		if _generation != my_gen:
			_cleanup_build(my_gen)
			return false

		var created: Variant = factory.call(i)
		if created == null:
			# 工厂请求中止
			_generation += 1
			_cleanup_build(my_gen)
			return false

		if not first_done and created is Array:
			var arr := created as Array
			if not arr.is_empty():
				first_done = true
				first_step_completed.emit()

		i += 1
		if i % _yield_interval == 0 and i < group_count:
			await _process_frame()
			if _generation != my_gen:
				_cleanup_build(my_gen)
				return false

	_cleanup_build(my_gen)
	return true


## 让出一帧（RefCounted 无 get_tree()，通过 Engine 获取 SceneTree）
func _process_frame() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		await tree.process_frame


## 清理构建状态：只有当前 building generation 才重置（防止旧协程清理新协程状态）
func _cleanup_build(gen: int) -> void:
	if _building_generation == gen:
		_building_generation = 0


## 取消当前 in-flight build（不释放任何节点）
func cancel() -> void:
	_generation += 1


## 是否正在构建中
func is_building() -> bool:
	return _building_generation != 0
