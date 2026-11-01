shader_type spatial;
// The sea, coloured by its depth from the coast texture: green is the depth
// against the map's deepest, red is land (shallow, under the land plane).

uniform sampler2D coast : filter_linear, repeat_disable;
// The site's size in world units, so a world point maps onto the texture.
uniform vec2 site;
uniform vec3 shallow : source_color = vec3(0.25, 0.53, 0.6);
uniform vec3 deep : source_color = vec3(0.06, 0.19, 0.31);

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world.xz / site;
	// Past the site's edges the sea is open and deep.
	float depth = (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) ? 1.0 : texture(coast, uv).g;
	float ripple = sin(world.x * 3.1 + TIME * 1.3) * sin(world.z * 2.7 - TIME * 1.1);
	ALBEDO = mix(shallow, deep, depth) + ripple * 0.015;
	ROUGHNESS = 0.15;
	SPECULAR = 0.6;
}
