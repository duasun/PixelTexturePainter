shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;
uniform int overlay_mode = 0;
varying vec3 barycentric;
void vertex() {
	barycentric = COLOR.rgb;
}
void fragment() {
	vec3 width = max(fwidth(barycentric), vec3(0.00001));
	vec3 distance = barycentric / width;
	float edge = min(distance.x, min(distance.y, distance.z));
	vec3 c = vec3(1.0, 0.61, 0.08);
	float alpha = 0.24;
	if (edge < 3.3) { c = vec3(0.025); alpha = 0.95; }
	if (edge < 1.5) { c = vec3(1.0, 0.91, 0.24); alpha = 1.0; }
	if (overlay_mode == 1) {
		c = vec3(0.04); alpha = edge < 2.0 ? 0.9 : 0.0;
		if (edge < 0.8) { c = vec3(0.48,0.9,0.94); alpha = 0.85; }
	} else if (overlay_mode == 2) {
		c = vec3(0.15,0.9,1.0); alpha = 0.16;
		if (edge < 1.8) { alpha = 0.9; }
	}
	if (!OUTPUT_IS_SRGB) { c = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), greaterThan(c, vec3(0.04045))); }
	ALBEDO = c;
	ALPHA = alpha;
}
