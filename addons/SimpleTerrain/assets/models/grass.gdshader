shader_type spatial;
render_mode cull_disabled;

uniform vec3 color : source_color;
uniform vec3 color2 : source_color;

void fragment() {
	ALBEDO = mix(color, color2, 1.0 - UV.y);
	if (!FRONT_FACING) {
		//NORMAL = -NORMAL;
	}
}