class_name PaletteLookup
extends RefCounted
## Balanced RGB search tree: exact nearest color without a 1024-color scan per fragment.
var nodes: Array[Dictionary] = []
var memo: Dictionary = {}

func _init(palette: PackedColorArray = PackedColorArray()) -> void:
	var entries: Array[Vector4] = []
	for i in palette.size():
		var c := palette[i]
		entries.append(Vector4(c.r,c.g,c.b,i))
	_branch(entries, 0, nodes)

static func build(palette: PackedColorArray) -> Image:
	return PaletteLookup.new(palette).to_image()

func to_image() -> Image:
	var image := Image.create(maxi(1,nodes.size()),2,false,Image.FORMAT_RGBAF)
	for i in nodes.size():
		var node := nodes[i]
		var color: Vector4 = node.color
		image.set_pixel(i,0,Color(color.x,color.y,color.z,color.w))
		image.set_pixel(i,1,Color(node.left,node.right,node.axis,0))
	return image

func nearest(point: Vector3) -> Vector3:
	if memo.has(point): return memo[point]
	var best := INF
	var best_index := 2048
	var color := point
	var stack: Array[int] = [0]
	var bounds: Array[float] = [0.0]
	while not stack.is_empty():
		var index: int = stack.pop_back()
		var bound: float = bounds.pop_back()
		if bound > best + 0.0000001: continue
		var node := nodes[index]
		var value: Vector4 = node.color
		var candidate := Vector3(value.x,value.y,value.z)
		var delta := point - candidate
		var distance := delta.length_squared()
		if distance < best - 0.0000001 or (absf(distance - best) <= 0.0000001 and int(value.w) < best_index):
			best = distance
			best_index = int(value.w)
			color = candidate
		var plane: float = delta[node.axis]
		var near_node: int = node.left if plane <= 0 else node.right
		var far_node: int = node.right if plane <= 0 else node.left
		if far_node >= 0 and plane * plane <= best + 0.0000001:
			stack.append(far_node); bounds.append(plane * plane)
		if near_node >= 0:
			stack.append(near_node); bounds.append(0.0)
	# Bound memory independently of atlas resolution; repeated flat colors are common.
	if memo.size() >= 16384: memo.clear()
	memo[point] = color
	return color

static func _branch(entries: Array[Vector4], depth: int, tree_nodes: Array[Dictionary]) -> int:
	if entries.is_empty():
		return -1
	var axis := depth % 3
	entries.sort_custom(func(a: Vector4,b: Vector4) -> bool: return a[axis] < b[axis] if a[axis] != b[axis] else a.w < b.w)
	var middle := entries.size() >> 1
	var index := tree_nodes.size()
	tree_nodes.append({"color":entries[middle],"axis":axis,"left":-1,"right":-1})
	tree_nodes[index].left = _branch(entries.slice(0,middle),depth+1,tree_nodes)
	tree_nodes[index].right = _branch(entries.slice(middle+1),depth+1,tree_nodes)
	return index
