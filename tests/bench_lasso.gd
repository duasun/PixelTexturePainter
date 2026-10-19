extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	var start := Time.get_ticks_msec()
	var mask := LassoSelection.uv_mask(PackedVector2Array([Vector2(32,32),Vector2(4064,32),Vector2(4064,4064),Vector2(32,4064)]),Vector2i(4096,4096))
	var mask_ms := Time.get_ticks_msec()-start
	start = Time.get_ticks_msec()
	var border := LassoSelection.boundary(mask,Vector2i(4096,4096))
	var border_ms := Time.get_ticks_msec()-start
	print("4K LASSO: mask %d ms, boundary %d ms, tiles %d, border %s" % [mask_ms,border_ms,mask.size(),str(border.get_size())])
	quit(0)
