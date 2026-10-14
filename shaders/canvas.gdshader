shader_type canvas_item;
#include "res://shaders/texture_common.gdshaderinc"
#include "res://shaders/shape_preview.gdshaderinc"
void fragment() {
	vec4 col = painted(UV);
	float checker = mod(floor(UV.x * texture_size.x / 8.0) + floor(UV.y * texture_size.y / 8.0), 2.0);
	vec3 color = mix(vec3(0.12 + checker * 0.03), col.rgb, col.a);
	color = shape_preview_color(color,UV*texture_size,fwidth(UV*texture_size));
	COLOR = vec4(color, 1.0);
}
