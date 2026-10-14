class_name BackgroundJob
extends Node
signal completed(kind: String, result: Variant)
var thread: Thread
var kind := ""
var progress := JobProgress.new()

class JobProgress extends RefCounted:
	var mutex := Mutex.new()
	var value := 0.0
	var message := ""
	var cancelled := false
	func report(fraction: float, text: String) -> bool:
		mutex.lock()
		value = fraction
		message = text
		var stop := cancelled
		mutex.unlock()
		return stop
	func read() -> Dictionary:
		mutex.lock()
		var result := {"value": value, "message": message, "cancelled": cancelled}
		mutex.unlock()
		return result
	func cancel() -> void:
		mutex.lock()
		cancelled = true
		mutex.unlock()
	func is_cancelled() -> bool:
		mutex.lock()
		var result := cancelled
		mutex.unlock()
		return result

func busy() -> bool:
	return thread != null

func start(task_kind: String, task: Callable) -> bool:
	if busy():
		return false
	kind = task_kind
	progress = JobProgress.new()
	thread = Thread.new()
	var error := thread.start(task.bind(progress))
	if error != OK:
		thread = null
		completed.emit(kind, {"error": "Could not start background job."})
		return false
	return true

func _process(_delta: float) -> void:
	if thread != null and not thread.is_alive():
		var result: Variant = thread.wait_to_finish()
		thread = null
		if progress.is_cancelled() and kind in ["new", "open", "recover", "import", "unwrap", "selection", "geometry_edit", "edges", "operation", "palette", "normal", "layer_blur_preview", "resize", "replace_color", "pattern_render", "pbr_preview", "geometry_mask"]:
			result = {"cancelled": true}
		completed.emit(kind, result)

func _exit_tree() -> void:
	if thread != null:
		progress.cancel()
		thread.wait_to_finish()
