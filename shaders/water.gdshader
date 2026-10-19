shader_type spatial;
// The sea, shallow by the shore and deeper offshore. The berth pocket along
// the quay is the dredged channel: it darkens as the channel is dredged.

uniform float coast_x;
// 0 at the channel's starting depth, 1 at its deepest.
uniform float channel = 0.0;
uniform vec3 shallow : source_color = vec3(0.25, 0.53, 0.6);
uniform vec3 deep : source_color = vec3(0.06, 0.19, 0.31);

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float out_to_sea = coast_x - world.x;
	float offshore = clamp(out_to_sea / 12.0, 0.0, 1.0);
	float berth = 1.0 - smoothstep(2.0, 3.5, out_to_sea);
	float depth = mix(offshore, 0.45 + 0.55 * channel, berth * step(0.0, out_to_sea));
	float ripple = sin(world.x * 3.1 + TIME * 1.3) * sin(world.z * 2.7 - TIME * 1.1);
	ALBEDO = mix(shallow, deep, depth) + ripple * 0.015;
	ROUGHNESS = 0.15;
	SPECULAR = 0.6;
}
