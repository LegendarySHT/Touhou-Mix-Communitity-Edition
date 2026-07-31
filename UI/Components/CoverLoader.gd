## 封面纹理异步加载器
## 共享线程池 + 任务队列模式，避免主线程 Image.load_from_file 同步阻塞
##
## 使用方式（主线程调用）：
##   CoverLoader.request_load(item_id, path, callback)
##   callback 签名: func(path: String, image: Image, version: int) -> void
##   CoverLoader.cancel(item_id)  # 取消在途任务（版本号失效）
##
## 线程安全：
##   - _task_queue / _result_queue 仅通过 _mutex 访问
##   - _pending_callbacks / _item_versions 仅主线程访问
##   - 后台线程只读 LoadTask 字段，只写 LoadResult.image，不访问任何 Node/Resource/Singleton
##   - Image.load_from_file 在 Godot 4.x 线程安全
extends Node

class_name CoverLoaderClass

## 后台线程数（Android 8 核够用，2 个即可消费封面加载任务）
const THREAD_COUNT := 2

## 默认封面路径（res:// 走 ResourceLoader，由调用方处理同步加载分支）
const DEFAULT_COVER_PATH := "res://Resources/song_cover/1.jpg"


## 加载任务
class LoadTask:
	var path: String
	var item_id: String
	var version: int


## 加载结果
class LoadResult:
	var path: String
	var item_id: String
	var version: int
	var image: Image  # 失败时为 null


## 后台线程
var _threads: Array[Thread] = []
## 任务队列（Mutex 保护）
var _task_queue: Array[LoadTask] = []
## 结果队列（Mutex 保护）
var _result_queue: Array[LoadResult] = []
var _mutex: Mutex = Mutex.new()
var _semaphore: Semaphore = Semaphore.new()
## 线程运行标志（shutdown 时置 false）
var _running: bool = true

## item_id → 最新版本号（主线程访问，用于取消）
## 每次 request_load / cancel 递增，使在途任务结果作废
var _item_versions: Dictionary = {}
## item_id → 回调 Callable（主线程访问）
var _pending_callbacks: Dictionary = {}


func _ready() -> void:
	# 启动后台线程
	for i in THREAD_COUNT:
		var t := Thread.new()
		var err := t.start(_thread_loop)
		if err != OK:
			GLogger.error("CoverLoader: Failed to start thread %d (err=%d)" % [i, err], "CoverLoader")
		else:
			_threads.append(t)
	set_process(true)


## 请求加载封面（主线程调用）
## item_id: 列表项标识（用于回调校验和取消）
## path: 封面文件绝对路径（主线程已预算好）
## callback: 签名 func(path: String, image: Image, version: int) -> void
func request_load(item_id: String, path: String, callback: Callable) -> void:
	# 递增版本号，使在途任务结果作废
	var version: int = int(_item_versions.get(item_id, 0)) + 1
	_item_versions[item_id] = version
	_pending_callbacks[item_id] = callback

	var task := LoadTask.new()
	task.path = path
	task.item_id = item_id
	task.version = version

	_mutex.lock()
	_task_queue.append(task)
	_mutex.unlock()

	_semaphore.post()


## 取消在途任务（主线程调用）
## 递增版本号使在途任务结果作废，并清理回调引用避免内存泄漏
## 注：不主动从 _task_queue 移除任务（后台线程会自然消费并丢弃）
func cancel(item_id: String) -> void:
	if not _item_versions.has(item_id):
		return
	_item_versions.erase(item_id)
	_pending_callbacks.erase(item_id)


## 主线程每帧消费结果队列，触发回调
func _process(_delta: float) -> void:
	# 全程持锁访问 _result_queue，避免与后台线程 append 的数据竞争
	# （Array.is_empty() / append() 均非线程安全，无锁读取在 Godot 4.x 可能崩溃或读到中间态）
	_mutex.lock()
	if _result_queue.is_empty():
		_mutex.unlock()
		return

	# 一次性取出所有结果（减少锁竞争）
	var results := _result_queue.duplicate()
	_result_queue.clear()
	_mutex.unlock()

	for result in results:
		var r: LoadResult = result
		# 校验版本号（cancel / 新 request_load 后版本号会变）
		var latest_version: int = int(_item_versions.get(r.item_id, -1))
		if r.version != latest_version:
			continue  # 旧任务结果，丢弃

		# 取回调（可能已被新 request_load 覆盖，覆盖了也无所谓——版本号校验已通过）
		var cb: Variant = _pending_callbacks.get(r.item_id, null)
		if cb == null or not (cb is Callable):
			continue
		var callback: Callable = cb
		# 先清理条目,再调用回调
		# 1. 防止内存泄漏:_pending_callbacks / _item_versions 不再无限增长
		# 2. 回调内部可能触发新的 request_load(如复用项切换封面),
		#    先 erase 确保新 request_load 添加的条目不被误删
		# 3. 旧任务结果已被版本号校验过滤,此处只剩"最新版本"的结果,可安全清理
		_pending_callbacks.erase(r.item_id)
		_item_versions.erase(r.item_id)
		# 校验回调绑定对象是否仍有效（节点可能已被 queue_free）
		# callback.call 对已 freed 的 Object 会报错并跳过函数体，导致缓存不写入
		if not callback.is_valid():
			continue
		# 调用回调（回调内部会再校验节点有效性 + _loading_path 一致性）
		callback.call(r.path, r.image, r.version)


## 后台线程主循环
func _thread_loop() -> void:
	while _running:
		_semaphore.wait()
		if not _running:
			return

		# 取任务
		_mutex.lock()
		var task: LoadTask = null
		if not _task_queue.is_empty():
			task = _task_queue.pop_front()
		_mutex.unlock()

		if task == null:
			continue  # 虚假唤醒，继续等

		# 执行磁盘 I/O（线程安全）
		var image: Image = _load_image(task.path)

		# 入结果队列
		var result := LoadResult.new()
		result.path = task.path
		result.item_id = task.item_id
		result.version = task.version
		result.image = image

		_mutex.lock()
		_result_queue.append(result)
		_mutex.unlock()


## 子线程读 Image(纯 I/O,无 Node/Resource 访问)
## 仅处理 user:// 路径(res:// 已在主线程同步加载)
## 失败返回 null
## 注:子线程不直接调 GLogger(非线程安全),错误信息通过 call_deferred 推到主线程
func _load_image(path: String) -> Image:
	if path.is_empty():
		return null

	# res:// 路径不应到达此处(主线程已处理),防御性返回 null
	if path.begins_with("res://"):
		return null

	if not FileAccess.file_exists(path):
		call_deferred("_log_warning", "CoverLoader: Cover file not found: %s" % path)
		return null
	var img := Image.load_from_file(path)
	if img == null:
		call_deferred("_log_warning", "CoverLoader: Failed to load cover image: %s" % path)
	return img


## 主线程日志(GLogger 非线程安全,子线程通过 call_deferred 调用此方法)
func _log_warning(msg: String) -> void:
	GLogger.warning(msg, "CoverLoader")


## 关闭线程池（Main 退出时调用）
## 幂等：重复调用安全（_threads.clear() 后循环不执行）
func shutdown() -> void:
	if _threads.is_empty() and not _running:
		return  # 已关闭,避免重复执行
	_running = false
	set_process(false)  # 停止 _process,避免空跑锁
	# 唤醒所有线程使其退出循环
	for i in _threads.size():
		_semaphore.post()
	# 等待所有线程退出
	for t in _threads:
		if t.is_alive():
			t.wait_to_finish()
	_threads.clear()
	# 清空队列与字典,释放 Callable 引用(可能绑定到已 freed 的节点)
	_mutex.lock()
	_task_queue.clear()
	_result_queue.clear()
	_mutex.unlock()
	_pending_callbacks.clear()
	_item_versions.clear()


## _exit_tree 兜底：Main 未捕获的退出场景(编辑器停止运行、Android 强杀等)
## 确保 Thread 被 wait_to_finish,避免 Godot "Thread was never freed" 告警
func _exit_tree() -> void:
	shutdown()
