shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D main_texture : hint_albedo;
uniform sampler2D lm_texture;
uniform float use_lightmap;

void fragment() {
	vec4 diffuse = texture(main_texture, UV);
	
	if (use_lightmap > 0.5) {
		vec3 lm = texture(lm_texture, UV2).rgb * 0.5;
		ALBEDO = diffuse.rgb * lm;
	} else {
		ALBEDO = diffuse.rgb;
	}
}
