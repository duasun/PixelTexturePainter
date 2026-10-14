uniform sampler2DArray pages : filter_nearest, repeat_disable;
uniform vec2 texture_size = vec2(128.0);
uniform int page_columns = 1;
uniform int fx_steps = 0;
uniform float fx_dither = 0.0;
uniform float fx_brightness = 0.0;
uniform float fx_contrast = 1.0;
uniform float fx_saturation = 1.0;
uniform float fx_noise = 0.0;
uniform bool fx_palette = false;
uniform vec4 palette_colors[32];
uniform int palette_count = 16;
uniform sampler2D palette_tree : filter_nearest, repeat_disable;

vec3 nearest_palette(vec3 sample_color) {
	float best = 1000.0;
	float best_index = 2048.0;
	vec3 nearest = sample_color;
	if (palette_count <= 32) {
		for (int i = 0; i < 32; i++) {
			if (i >= palette_count) { break; }
			vec3 delta = sample_color - palette_colors[i].rgb;
			float dist = dot(delta, delta);
			if (dist < best - 0.0000001) { best = dist; nearest = palette_colors[i].rgb; }
		}
	} else {
		int stack[32];
		float bounds[32];
		stack[0] = 0;
		bounds[0] = 0.0;
		int count = 1;
		for (int step = 0; step < 1024; step++) {
			if (count <= 0) { break; }
			count--;
			int node = stack[count];
			if (bounds[count] > best + 0.0000001) { continue; }
			vec4 candidate = texelFetch(palette_tree, ivec2(node,0), 0);
			vec4 links = texelFetch(palette_tree, ivec2(node,1), 0);
			vec3 delta = sample_color - candidate.rgb;
			float dist = dot(delta, delta);
			if (dist < best - 0.0000001 || (abs(dist - best) <= 0.0000001 && candidate.a < best_index)) {
				best = dist; best_index = candidate.a; nearest = candidate.rgb;
			}
			float plane = delta[int(links.b)];
			int near_node = int(plane <= 0.0 ? links.r : links.g);
			int far_node = int(plane <= 0.0 ? links.g : links.r);
			if (far_node >= 0 && plane*plane <= best + 0.0000001 && count < 31) {
				stack[count] = far_node; bounds[count] = plane*plane; count++;
			}
			if (near_node >= 0 && count < 32) {
				stack[count] = near_node; bounds[count] = 0.0; count++;
			}
		}
	}
	return nearest;
}

vec4 painted(vec2 uv) {
	vec2 px = clamp(floor(uv * texture_size), vec2(0.0), texture_size - vec2(1.0));
	ivec2 page = ivec2(floor(px / 256.0));
	vec2 within = (mod(px, 256.0) + vec2(0.5)) / 256.0;
	vec4 col = texture(pages, vec3(within, float(page.y * page_columns + page.x)));
	vec3 c = (col.rgb - vec3(0.5)) * fx_contrast + vec3(0.5 + fx_brightness);
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(lum), c, fx_saturation);
	float noise = mod(px.x * 13.0 + px.y * 57.0, 17.0) / 16.0 - 0.5;
	c += noise * fx_noise;
	int bayer[16] = int[16](0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5);
	int index = int(mod(px.y, 4.0)) * 4 + int(mod(px.x, 4.0));
	float d = (float(bayer[index]) / 16.0 - 0.46875) * fx_dither;
	if (fx_steps > 1) {
		float levels = float(fx_steps - 1);
		c = floor(clamp(c + vec3(d / levels), vec3(0.0), vec3(1.0)) * levels + vec3(0.5)) / levels;
	}
	if (fx_palette) {
		c = nearest_palette(c + vec3(d / 8.0));
	}
	return vec4(clamp(c, vec3(0.0), vec3(1.0)), col.a);
}
