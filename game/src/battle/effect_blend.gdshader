shader_type canvas_item;
// The blends of the effect players (0x402cb5), per pixel of a non-transparent image pixel, with L the pixel's
// brightness (r + g + b) / 3 in 4-bit steps and the weights in 1/256:
//   mode 0 (0x43030e -> 0x42fd5a): u = p2 * (256 - L * p3) / 16   (p2 = 0: the plain picture)
//   mode 1 (0x430369 -> 0x4300c8): A = the alpha map's byte; A = 0 and p3 = 0: the background;
//                                  A = 255: the plain picture; else u = (256 - A) * (256 - L * p3) / 256
//   colour = min((bg * u + picture * (256 - u * (16 - p3) / 16)) / 256, 1)
// The original works on 4-bit channels and maps the result back to the palette (RGB444 LUT 0x4b1b28).

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D alpha_tex : filter_nearest;
uniform int mode = 0;
uniform float p2 = 0.0;
uniform float p3 = 16.0;

void fragment() {
	vec4 img = texture(TEXTURE, UV);
	if (img.a < 0.5) {
		discard;
	}
	vec3 bg = texture(screen_tex, SCREEN_UV).rgb;
	float l = floor((floor(img.r * 15.0 + 0.5) + floor(img.g * 15.0 + 0.5) + floor(img.b * 15.0 + 0.5)) / 3.0);
	float u;
	if (mode == 0) {
		u = floor(p2 * (256.0 - l * p3) / 16.0);
	} else {
		float a = floor(texture(alpha_tex, UV).r * 255.0 + 0.5);
		if (a == 0.0 && p3 == 0.0) {
			discard;
		}
		u = a >= 255.0 ? 0.0 : floor((256.0 - a) * (256.0 - l * p3) / 256.0);
	}
	vec3 c = img.rgb;
	if (u > 0.0) {
		c = min((bg * u + img.rgb * (256.0 - floor(u * (16.0 - p3) / 16.0))) / 256.0, vec3(1.0));
	}
	COLOR = vec4(c, 1.0);
}
