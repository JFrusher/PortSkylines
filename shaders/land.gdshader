shader_type spatial;
// The site's land: a plane cut away wherever the coast texture is water, so
// the coast follows the map's curves. Land tiles the port doesn't own are
// shaded darker.

uniform sampler2D coast : filter_linear, repeat_disable;
uniform sampler2D owned : filter_nearest, repeat_disable;
// The site's size in world units (set for the shared coast texture).
uniform vec2 site;
uniform vec3 colour : source_color;

void fragment() {
	vec2 uv = UV;
	if (texture(coast, uv).r < 0.5) {
		discard;
	}
	ALBEDO = colour * (texture(owned, uv).r > 0.5 ? 1.0 : 0.7);
	ROUGHNESS = 1.0;
}
