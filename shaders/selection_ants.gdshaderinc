uniform bool selection_ants_enabled = false;
uniform sampler2D selection_border : filter_nearest, repeat_disable;

vec3 selection_ants(vec3 base, vec2 uv) {
	if (!selection_ants_enabled) return base;
	if (texture(selection_border, uv).r < 0.5) return base;
	vec2 pixel = floor(uv * texture_size);
	float stripe = mod(floor((pixel.x + pixel.y) * 0.5 + TIME * 6.0), 2.0);
	return mix(vec3(0.01), vec3(1.0, 0.82, 0.35), stripe);
}
