shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_nearest;

// This gives you a slider in the inspector to fine-tune the transparency cutoff
uniform float line_threshold : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec4 tex_color = texture(albedo_texture, UV);
	
	// Calculate the luminance (perceived brightness) of the pixel accurately
	float brightness = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
	
	// If the pixel is brighter than our threshold, vaporize it
	if (brightness > line_threshold) {
		discard;
	}
	
	// Set the color and force it to be 100% visible
	ALBEDO = tex_color.rgb;
	ALPHA = 1.0;
}
