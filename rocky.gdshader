shader_type spatial;

// ---------- USER-TWEAKABLE UNIFORMS ----------
uniform float noise_scale				: hint_range(0.1, 10.0) = 1.2;
uniform float voronoi_scale				: hint_range(0.1, 5.0) = 1.5;
uniform float rock_detail				: hint_range(0.0, 2.0) = 0.8;
uniform float bump_strength				: hint_range(0.0, 2.0) = 0.5;
uniform vec3 base_color					: source_color = vec3(0.6, 0.45, 0.35);  // Darker tan
uniform vec3 dark_color					: source_color = vec3(0.3, 0.2, 0.15);   // Darker brown
uniform vec3 highlight_color			: source_color = vec3(0.8, 0.65, 0.5);   // Muted highlight
uniform float color_variation			: hint_range(0.0, 1.0) = 0.4;
uniform float cartoon_contrast			: hint_range(1.0, 8.0) = 4.0;
uniform float style_sharpness			: hint_range(0.1, 1.0) = 0.3;

// ---------- VARYINGS ----------
varying vec3 v_model_pos;
varying vec3 v_model_norm;

// ---------- UTILITY / HASH / NOISE ----------
vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

vec3 hash33(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)),
			 dot(p, vec3(269.5, 183.3, 246.1)),
			 dot(p, vec3(113.5, 271.9, 124.6)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

// Improved 3D noise function
float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);

	return mix(
		mix(
			mix(dot(hash33(i + vec3(0.0, 0.0, 0.0)), f - vec3(0.0, 0.0, 0.0)),
				dot(hash33(i + vec3(1.0, 0.0, 0.0)), f - vec3(1.0, 0.0, 0.0)), u.x),
			mix(dot(hash33(i + vec3(0.0, 1.0, 0.0)), f - vec3(0.0, 1.0, 0.0)),
				dot(hash33(i + vec3(1.0, 1.0, 0.0)), f - vec3(1.0, 1.0, 0.0)), u.x), u.y),
		mix(
			mix(dot(hash33(i + vec3(0.0, 0.0, 1.0)), f - vec3(0.0, 0.0, 1.0)),
				dot(hash33(i + vec3(1.0, 0.0, 1.0)), f - vec3(1.0, 0.0, 1.0)), u.x),
			mix(dot(hash33(i + vec3(0.0, 1.0, 1.0)), f - vec3(0.0, 1.0, 1.0)),
				dot(hash33(i + vec3(1.0, 1.0, 1.0)), f - vec3(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

// 2D Voronoi function
float voronoi2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	
	float min_dist = 1.0;
	
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = hash22(i + neighbor);
			point = 0.5 + 0.5 * sin(6.2831 * point);
			vec2 diff = neighbor + point - f;
			float dist = length(diff);
			min_dist = min(min_dist, dist);
		}
	}
	
	return min_dist;
}

// Fractal Brownian Motion
float fbm(vec3 p, int octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	
	for (int i = 0; i < octaves; i++) {
		value += amplitude * noise3d(p * frequency);
		amplitude *= 0.5;
		frequency *= 2.0;
	}
	
	return value;
}

// ---------- TRIPLANAR SAMPLING ----------
float sample_triplanar_noise(vec3 p, vec3 n) {
	vec3 w = abs(n);
	w = pow(w, vec3(3.0));
	w /= (w.x + w.y + w.z);

	float nx = fbm(vec3(p.y, p.z, 0.0), 4);
	float ny = fbm(vec3(p.x, p.z, 0.0), 4);
	float nz = fbm(vec3(p.x, p.y, 0.0), 4);

	return nx * w.x + ny * w.y + nz * w.z;
}

float sample_triplanar_voronoi(vec3 p, vec3 n) {
	vec3 w = abs(n);
	w = pow(w, vec3(3.0));
	w /= (w.x + w.y + w.z);

	float vx = voronoi2d(p.yz);
	float vy = voronoi2d(p.xz);
	float vz = voronoi2d(p.xy);

	return vx * w.x + vy * w.y + vz * w.z;
}

// ---------- NORMAL CALCULATION ----------
vec3 calculate_normal(vec3 p, vec3 n) {
	const float eps = 0.0001;
	
	// Sample noise and voronoi separately for better control
	float noise_h = sample_triplanar_noise(p, n);
	float voronoi_h = sample_triplanar_voronoi(p, n);
	
	// Smooth the voronoi to reduce harsh edges
	voronoi_h = smoothstep(0.1, 0.9, voronoi_h);
	
	// Combine with reduced voronoi influence for normals
	float h = noise_h + voronoi_h * 0.3;
	
	// Calculate gradients with the same pattern
	float noise_hx = sample_triplanar_noise(p + vec3(eps, 0.0, 0.0), n);
	float voronoi_hx = smoothstep(0.1, 0.9, sample_triplanar_voronoi(p + vec3(eps, 0.0, 0.0), n));
	float hx = noise_hx + voronoi_hx * 0.3;
	
	float noise_hy = sample_triplanar_noise(p + vec3(0.0, eps, 0.0), n);
	float voronoi_hy = smoothstep(0.1, 0.9, sample_triplanar_voronoi(p + vec3(0.0, eps, 0.0), n));
	float hy = noise_hy + voronoi_hy * 0.3;
	
	float noise_hz = sample_triplanar_noise(p + vec3(0.0, 0.0, eps), n);
	float voronoi_hz = smoothstep(0.1, 0.9, sample_triplanar_voronoi(p + vec3(0.0, 0.0, eps), n));
	float hz = noise_hz + voronoi_hz * 0.3;

	vec3 gradient = vec3(hx - h, hy - h, hz - h) / eps;
	
	// Clamp gradient to prevent extreme values
	gradient = clamp(gradient, vec3(-2.0), vec3(2.0));
	
	return normalize(n - gradient * bump_strength);
}

// ---------- VERTEX ----------
void vertex() {
	v_model_pos = VERTEX;
	v_model_norm = normalize(NORMAL);
}

// ---------- FRAGMENT ----------
void fragment() {
	vec3 p_noise = v_model_pos * noise_scale;
	vec3 p_voronoi = v_model_pos * voronoi_scale;
	vec3 n = normalize(v_model_norm);

	// Sample noise and voronoi patterns
	float noise_val = sample_triplanar_noise(p_noise, n);
	float voronoi_val = sample_triplanar_voronoi(p_voronoi, n);
	
	// Combine patterns for rock detail
	float rock_pattern = mix(noise_val, voronoi_val, 0.7);
	rock_pattern = rock_pattern * 0.5 + 0.5; // Normalize to 0-1
	
	// Add fine detail with higher frequency for crispness
	float detail = fbm(p_noise * 3.0, 3) * rock_detail;
	rock_pattern += detail * 0.25;
	
	// Apply aggressive cartoon-style contrast enhancement
	rock_pattern = pow(rock_pattern, 1.0 / cartoon_contrast);
	rock_pattern = smoothstep(0.1, 0.9, rock_pattern);
	
	// Create sharp, distinct color zones with minimal blending
	float shadow_threshold = 0.3;
	float highlight_threshold = 0.7;
	
	float shadow_mask = smoothstep(shadow_threshold - style_sharpness, shadow_threshold + style_sharpness, rock_pattern);
	float highlight_mask = smoothstep(highlight_threshold - style_sharpness, highlight_threshold + style_sharpness, rock_pattern);
	
	// Quantize the pattern for more distinct zones but with higher resolution
	float quantized_pattern = floor(rock_pattern * 8.0) / 8.0;
	
	// Build color in sharp layers for strong cartoon effect
	vec3 rock_color = dark_color;
	rock_color = mix(rock_color, base_color, shadow_mask);
	rock_color = mix(rock_color, highlight_color, highlight_mask);
	
	// Add high-contrast stylized banding
	float color_bands = sin(quantized_pattern * 6.28 * 3.0) * 0.5 + 0.5;
	color_bands = step(0.5, color_bands); // Hard step for sharp bands
	float color_accent = color_bands * color_variation;
	
	// Apply color accent more dramatically
	rock_color += vec3(color_accent * 0.15, color_accent * 0.08, color_accent * 0.05);
	
	// Enhance contrast further by pushing colors to extremes
	rock_color = pow(rock_color, vec3(0.8)); // Gamma adjustment for more pop
	
	// Simplified roughness for cartoon style
	float roughness = mix(1.0, 0.7, highlight_mask);
	roughness = clamp(roughness, 0.0, 1.0);

	ALBEDO = clamp(rock_color, vec3(0.0), vec3(1.0));
	ROUGHNESS = roughness;
	NORMAL = normalize(VIEW_MATRIX * vec4(calculate_normal(p_noise, n), 0.0)).xyz;
}
