class_name PaintFloodFill
extends RefCounted
## Four-connected fill, matching the visible composite. Uniform tiles take a native fast path.
class Tile extends RefCounted:
	var pixels := PackedInt32Array()
	var allowed := PackedByteArray()
	var seen := BitMap.new()
	var full := false
	var done := false

var source: PaintDocument
var document: PaintDocument
var island := -1
var target := 0
var color: Color
var cache: Dictionary = {}
var before: Dictionary = {}
var after: Dictionary = {}
var pending: Array[Vector2i] = []
var use_effects := false
var tolerance := 0.0

static func run(progress: BackgroundJob.JobProgress, doc: PaintDocument, seed: Vector2i, limit_island: int, fill_color: Color, match_tolerance := 0.0, contiguous := true) -> Dictionary:
	var job := PaintFloodFill.new()
	job.document = doc
	job.source = doc.read_copy()
	job.island = limit_island
	job.color = fill_color
	job.tolerance = clampf(match_tolerance,0.0,1.0)
	job.use_effects = doc.current_channel() == "albedo" and doc.effects != PaintDocument.new().effects and not doc.editing_mask
	seed = seed.clamp(Vector2i.ZERO, Vector2i(doc.width - 1, doc.height - 1))
	var first := job._source_tile(seed / 64)
	job.target = first.get_data().to_int32_array()[(seed.y % 64) * 64 + seed.x % 64]
	if not contiguous:
		return job._fill_matching(progress)
	job.pending.append(seed)
	var iterations := 0
	while not job.pending.is_empty():
		if iterations % 32 == 0 and progress.report(minf(0.95, job.after.size() / float(doc.tile_extent().x * doc.tile_extent().y)), "Filling connected color region…"):
			return {"cancelled": true}
		iterations += 1
		job._visit(job.pending.pop_back())
	return PaintOperations._command(doc.selected_layer(), doc.editing_mask, job.before, job.after, "Flood fill")

static func similar(a: int, b: int, threshold: int) -> bool:
	if threshold <= 0: return a == b
	for shift in [0,8,16,24]:
		if absi(((a >> shift) & 255) - ((b >> shift) & 255)) > threshold: return false
	return true

func _fill_matching(progress: BackgroundJob.JobProgress) -> Dictionary:
	var keys := document.all_keys()
	var paint := Image.create(1,1,false,Image.FORMAT_RGBA8)
	paint.set_pixel(0,0,color)
	var paint_bytes := paint.get_data()
	for i in keys.size():
		if i % 4 == 0 and progress.report(float(i)/maxi(1,keys.size()),"Replacing matching color…"):
			return {"cancelled":true}
		var key: Vector2i = keys[i]
		var source_bytes := _source_tile(key).get_data()
		var mask: Image = document.geometry.island_tile_mask(island,key,Vector2i(document.width,document.height)) if island >= 0 else null
		if island >= 0 and mask == null: continue
		var mask_bytes := mask.get_data() if mask != null else PackedByteArray()
		var changed := false
		var out := document.selected_layer().tile_at(key,document.editing_mask,false).get_data()
		for y in mini(64,document.height-key.y*64):
			for x in mini(64,document.width-key.x*64):
				var p := y*64+x
				if not mask_bytes.is_empty() and mask_bytes[p*4+3] == 0: continue
				var sample := source_bytes.decode_u32(p*4)
				if not similar(sample,target,roundi(tolerance*255.0)): continue
				for c in 4: out[p*4+c] = paint_bytes[c]
				changed = true
		if changed:
			PaintOperations._capture(document,key,before,after)
			after[key] = Image.create_from_data(64,64,false,Image.FORMAT_RGBA8,out)
	return PaintOperations._command(document.selected_layer(),document.editing_mask,before,after,"Replace matching color")

func _source_tile(key: Vector2i) -> Image:
	var image := source.selected_layer().tile_at(key, true, false) if document.editing_mask else source.compose_tile(key)
	return ProjectIO.apply_effects(image, key * 64, source) if use_effects else image

func _tile(key: Vector2i) -> Tile:
	if cache.has(key): return cache[key]
	var tile := Tile.new()
	tile.seen.create(Vector2i(64, 64))
	tile.pixels = _source_tile(key).get_data().to_int32_array()
	var entire := true
	if island >= 0:
		var mask := document.geometry.island_tile_mask(island, key, Vector2i(document.width, document.height))
		if mask == null:
			tile.done = true
		else:
			tile.allowed = mask.get_data()
			entire = tile.allowed.count(255) == tile.allowed.size()
	tile.full = entire and tolerance <= 0.0 and tile.pixels.count(target) == 4096
	if tile.full: tile.pixels.clear()
	cache[key] = tile
	return tile

func _matches(p: Vector2i) -> bool:
	if p.x < 0 or p.y < 0 or p.x >= document.width or p.y >= document.height: return false
	var tile := _tile(p / 64)
	if tile.done: return false
	if tile.full: return true
	var local := Vector2i(p.x % 64, p.y % 64)
	var index := local.y * 64 + local.x
	return not tile.seen.get_bitv(local) and similar(tile.pixels[index],target,roundi(tolerance*255.0)) and (tile.allowed.is_empty() or tile.allowed[index * 4 + 3] > 0)

func _visit(p: Vector2i) -> void:
	if not _matches(p): return
	var key := p / 64
	var tile := _tile(key)
	var origin := key * 64
	var extent := Vector2i(mini(64, document.width - origin.x), mini(64, document.height - origin.y))
	PaintOperations._capture(document, key, before, after)
	if tile.full:
		tile.done = true
		after[key].fill_rect(Rect2i(Vector2i.ZERO, extent), color)
		_edge(origin + Vector2i(0, -1), Vector2i.RIGHT, extent.x)
		_edge(origin + Vector2i(0, extent.y), Vector2i.RIGHT, extent.x)
		_edge(origin + Vector2i(-1, 0), Vector2i.DOWN, extent.y)
		_edge(origin + Vector2i(extent.x, 0), Vector2i.DOWN, extent.y)
		return
	var left := p.x
	var right := p.x
	while left > origin.x and _matches(Vector2i(left - 1, p.y)): left -= 1
	while right + 1 < origin.x + extent.x and _matches(Vector2i(right + 1, p.y)): right += 1
	tile.seen.set_bit_rect(Rect2i(left - origin.x, p.y - origin.y, right - left + 1, 1), true)
	after[key].fill_rect(Rect2i(left - origin.x, p.y - origin.y, right - left + 1, 1), color)
	_edge(Vector2i(left, p.y - 1), Vector2i.RIGHT, right - left + 1)
	_edge(Vector2i(left, p.y + 1), Vector2i.RIGHT, right - left + 1)
	if left == origin.x: _edge(Vector2i(left - 1, p.y), Vector2i.RIGHT, 1)
	if right + 1 == origin.x + extent.x: _edge(Vector2i(right + 1, p.y), Vector2i.RIGHT, 1)

func _edge(start: Vector2i, direction: Vector2i, length: int) -> void:
	# Every range lies inside one adjacent tile. One seed suffices for a uniform tile.
	if _matches(start) and _tile(start / 64).full:
		pending.append(start)
		return
	var in_run := false
	for i in length:
		var p := start + direction * i
		var eligible := _matches(p)
		if eligible and not in_run: pending.append(p)
		in_run = eligible
