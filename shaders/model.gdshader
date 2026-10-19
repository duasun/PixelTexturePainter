shader_type spatial;
render_mode unshaded, cull_back;
#include "res://shaders/texture_common.gdshaderinc"
#include "res://shaders/shape_preview.gdshaderinc"
#include "res://shaders/selection_ants.gdshaderinc"
uniform bool shaded = false;
uniform bool pbr_enabled = false;
uniform bool pbr_albedo_live = true;
uniform sampler2D pbr_albedo : filter_nearest, repeat_disable;
uniform sampler2D pbr_roughness : filter_nearest, repeat_disable;
uniform sampler2D pbr_metallic : filter_nearest, repeat_disable;
uniform sampler2D pbr_normal : filter_nearest, repeat_disable;
uniform sampler2D pbr_ao : filter_nearest, repeat_disable;
uniform sampler2D pbr_emission : filter_nearest, repeat_disable;
uniform bool cursor_visible = false;
uniform vec2 cursor_pixel = vec2(0.0);
uniform float cursor_size = 4.0;
uniform bool cursor_round = false;
uniform bool cursor_mirror = false;
uniform float cursor_island = -1.0;
uniform bool spray_preview_enabled = false;
uniform sampler2D spray_preview : filter_nearest, repeat_disable;
uniform bool spray_mirror_enabled = false;
uniform sampler2D spray_mirror : filter_nearest, repeat_disable;
uniform bool stamp_preview_enabled = false;
uniform sampler2D stamp_preview_source : filter_nearest, repeat_disable;
uniform float stamp_source_size = 1.0;
uniform float stamp_angle = 0.0;
uniform float shape_preview_island = -1.0;

float footprint(vec2 p, vec2 center, float diameter, bool rounded) {
	vec2 local = floor(p) - (center - floor(diameter * 0.5));
	if (any(lessThan(local, vec2(0.0))) || any(greaterThanEqual(local, vec2(diameter)))) { return 0.0; }
	if (rounded && length(local + vec2(0.5) - vec2(diameter * 0.5)) > diameter * 0.5) { return 0.0; }
	return 1.0;
}

vec3 cursor_overlay(vec3 c, vec2 p, vec2 center, vec2 fw) {
	float inside = footprint(p, center, cursor_size, cursor_round);
	float edge = 0.0;
	float halo = 0.0;
	for (int axis = 0; axis < 2; axis++) {
		vec2 step_uv = axis == 0 ? vec2(fw.x, 0.0) : vec2(0.0, fw.y);
		edge = max(edge, abs(inside - footprint(p + step_uv, center, cursor_size, cursor_round)));
		edge = max(edge, abs(inside - footprint(p - step_uv, center, cursor_size, cursor_round)));
		halo = max(halo, abs(inside - footprint(p + step_uv * 2.5, center, cursor_size, cursor_round)));
		halo = max(halo, abs(inside - footprint(p - step_uv * 2.5, center, cursor_size, cursor_round)));
	}
	c = mix(c, vec3(0.2, 0.9, 0.85), inside * 0.12);
	c = mix(c, vec3(0.015), halo);
	return mix(c, vec3(0.9, 1.0, 1.0), edge);
}
vec4 stamp_texel(vec2 local) {
	vec2 d = local - vec2((cursor_size - 1.0) * 0.5);
	float ca = cos(stamp_angle);
	float sa = sin(stamp_angle);
	vec2 source = vec2(ca * d.x + sa * d.y, -sa * d.x + ca * d.y) + vec2((stamp_source_size - 1.0) * 0.5);
	vec2 pixel = floor(source + vec2(0.5));
	if (any(lessThan(pixel, vec2(0.0))) || any(greaterThanEqual(pixel,vec2(stamp_source_size)))) return vec4(0.0);
	return texture(stamp_preview_source,(pixel+vec2(0.5))/stamp_source_size);
}
void fragment() {
	vec4 col = painted(UV);
	if (pbr_enabled && !pbr_albedo_live) { col = texture(pbr_albedo,UV); }
	float checker = mod(floor(UV.x * texture_size.x / 8.0) + floor(UV.y * texture_size.y / 8.0), 2.0);
	vec3 c = mix(vec3(0.16 + checker * 0.04), col.rgb, col.a);
	if (pbr_enabled) {
		vec3 n = normalize(NORMAL);
		vec3 map_n = texture(pbr_normal,UV).rgb * 2.0 - 1.0;
		vec3 dp_x = dFdx(VERTEX);
		vec3 dp_y = dFdy(VERTEX);
		vec2 duv_x = dFdx(UV);
		vec2 duv_y = dFdy(UV);
		float det = duv_x.x*duv_y.y-duv_x.y*duv_y.x;
		if (abs(det)>0.000001) {
			vec3 tangent = normalize((dp_x*duv_y.y-dp_y*duv_x.y)/det);
			vec3 bitangent = normalize(cross(n,tangent)) * sign(det);
			n = normalize(tangent*map_n.x+bitangent*map_n.y+n*map_n.z);
		}
		vec3 l = normalize(vec3(-0.45,0.7,0.65));
		vec3 v = normalize(VIEW);
		vec3 h = normalize(l+v);
		float ndl = max(dot(n,l),0.0);
		float ndv = max(dot(n,v),0.001);
		float ndh = max(dot(n,h),0.001);
		float vdh = max(dot(v,h),0.0);
		float rough = clamp(texture(pbr_roughness,UV).r,0.04,1.0);
		float metal = clamp(texture(pbr_metallic,UV).r,0.0,1.0);
		float alpha = rough*rough;
		float a2 = alpha*alpha;
		float denom = ndh*ndh*(a2-1.0)+1.0;
		float d = a2/max(3.141593*denom*denom,0.0001);
		float k = (rough+1.0)*(rough+1.0)/8.0;
		float g = ndv/(ndv*(1.0-k)+k) * ndl/(ndl*(1.0-k)+k);
		vec3 f0 = mix(vec3(0.04),c,metal);
		vec3 fresnel = f0+(vec3(1.0)-f0)*pow(1.0-vdh,5.0);
		vec3 specular = d*g*fresnel/max(4.0*ndv*ndl,0.001);
		float ao = texture(pbr_ao,UV).r;
		vec3 diffuse = (vec3(1.0)-fresnel)*(1.0-metal)*c/3.141593;
		c = clamp(c*0.24*ao + (diffuse+specular)*ndl*2.6 + texture(pbr_emission,UV).rgb,vec3(0.0),vec3(1.0));
	} else if (shaded) { c *= 0.55 + 0.45 * max(dot(normalize(NORMAL), normalize(vec3(-0.4,0.7,0.6))), 0.0); }
	if (shape_preview_mode > 0 && (shape_preview_island < 0.0 || abs(UV2.x-shape_preview_island) < 0.25)) {
		c = shape_preview_color(c,UV*texture_size,fwidth(UV*texture_size));
	}
	c = selection_ants(c,UV);
	if (cursor_visible) {
		vec2 p = UV * texture_size;
		vec2 fw = max(fwidth(p) * 0.7, vec2(0.0001));
		if (cursor_island < 0.0 || abs(UV2.x - cursor_island) < 0.25) { c = cursor_overlay(c, p, cursor_pixel, fw); }
		if (spray_preview_enabled && (cursor_island < 0.0 || abs(UV2.x - cursor_island) < 0.25)) {
			vec2 local = floor(p) - (cursor_pixel - floor(cursor_size*0.5));
			if (all(greaterThanEqual(local,vec2(0.0))) && all(lessThan(local,vec2(cursor_size)))) {
				vec4 dots = texture(spray_preview,(local+vec2(0.5))/cursor_size);
				c = mix(c,dots.rgb,dots.a);
			}
		}
		if (stamp_preview_enabled && (cursor_island < 0.0 || abs(UV2.x - cursor_island) < 0.25)) {
			vec2 local = floor(p) - (cursor_pixel - floor(cursor_size*0.5));
			if (all(greaterThanEqual(local,vec2(0.0))) && all(lessThan(local,vec2(cursor_size)))) {
				vec4 ink = stamp_texel(local);
				c = mix(c,ink.rgb,ink.a);
			}
		}
		if (cursor_mirror) { c = cursor_overlay(c, p, vec2(texture_size.x - cursor_pixel.x - 1.0, cursor_pixel.y), fw); }
		if (cursor_mirror && spray_mirror_enabled) {
			vec2 center = vec2(texture_size.x-cursor_pixel.x-1.0,cursor_pixel.y);
			vec2 local = floor(p)-(center-floor(cursor_size*0.5));
			if (all(greaterThanEqual(local,vec2(0.0))) && all(lessThan(local,vec2(cursor_size)))) {
				vec4 dots = texture(spray_mirror,(local+vec2(0.5))/cursor_size);
				c = mix(c,dots.rgb,dots.a);
			}
		}
		if (cursor_mirror && stamp_preview_enabled) {
			vec2 center = vec2(texture_size.x-cursor_pixel.x-1.0,cursor_pixel.y);
			vec2 local = floor(p)-(center-floor(cursor_size*0.5));
			if (all(greaterThanEqual(local,vec2(0.0))) && all(lessThan(local,vec2(cursor_size)))) {
				vec4 ink = stamp_texel(local);
				c = mix(c,ink.rgb,ink.a);
			}
		}
		if (all(equal(floor(p), cursor_pixel))) { c = mix(c, vec3(1.0, 0.72, 0.25), 0.65); }
	}
	if (!OUTPUT_IS_SRGB) { c = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), greaterThan(c, vec3(0.04045))); }
	ALBEDO = c;
}
