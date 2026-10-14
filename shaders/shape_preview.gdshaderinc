uniform int shape_preview_mode = 0;
uniform vec2 shape_preview_start = vec2(0.0);
uniform vec2 shape_preview_end = vec2(0.0);
uniform float shape_preview_size = 1.0;

float shape_segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	return length(p - (a + ab * clamp(dot(p - a, ab) / max(dot(ab, ab), 0.0001), 0.0, 1.0)));
}

float shape_preview_distance(vec2 p) {
	vec2 a = shape_preview_start + vec2(0.5);
	vec2 b = shape_preview_end + vec2(0.5);
	if (shape_preview_mode == 1) { return shape_segment_distance(p, a, b); }
	vec2 low = min(a, b);
	vec2 high = max(a, b);
	if (shape_preview_mode == 2) {
		float horizontal = (p.x >= low.x && p.x <= high.x) ? min(abs(p.y-low.y),abs(p.y-high.y)) : 100000.0;
		float vertical = (p.y >= low.y && p.y <= high.y) ? min(abs(p.x-low.x),abs(p.x-high.x)) : 100000.0;
		return min(min(horizontal,vertical),min(min(length(p-vec2(low.x,low.y)),length(p-vec2(high.x,high.y))),min(length(p-vec2(low.x,high.y)),length(p-vec2(high.x,low.y)))));
	}
	vec2 radius = (high-low)*0.5;
	if (radius.x < 0.5 || radius.y < 0.5) { return shape_segment_distance(p,low,high); }
	vec2 center = (low+high)*0.5;
	float normalized_radius = length((p-center)/radius);
	return abs(normalized_radius-1.0)*min(radius.x,radius.y);
}

vec3 shape_preview_color(vec3 color, vec2 texel, vec2 footprint) {
	if (shape_preview_mode == 0) { return color; }
	vec2 pixel = floor(texel)+vec2(0.5);
	float distance_to_shape = shape_preview_distance(pixel);
	float width = max(0.75,shape_preview_size*0.5);
	float edge = max(max(footprint.x,footprint.y),0.03);
	float halo = 1.0-smoothstep(width+edge,width+edge*2.0,distance_to_shape);
	float inside = 1.0-smoothstep(width-edge,width+edge,distance_to_shape);
	color = mix(color,vec3(0.015),halo*0.85);
	return mix(color,vec3(0.50,1.0,0.90),inside*0.65);
}
