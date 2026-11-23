extends RefCounted
## CPU twin of the fish shader math fixed in ADR 0013 rule 5 and the technical plan of #34
## (section 1). Headless Godot compiles no shaders, so the contract is tested through this twin;
## test_fish_shader.gd pins the constant lines of game/shaders/fish_common.gdshaderinc against the
## constants below, so the twin cannot drift from the include unnoticed.
##
## GLSL semantics: smoothstep is the Hermite curve on the clamped fraction, round() rounds half
## away from zero, mix(a, b, t) = a * (1 - t) + b * t. Colours are linear RGB (Godot converts a
## `source_color` or instance Color to linear before the shader reads it), never converted again.

const SWIM_BEND_START := 0.2
const SWIM_BEND_FULL := 1.2
const SWIM_REST_AMPLITUDE := 0.15
const SWIM_REST_FREQUENCY := 0.4
const SWIM_WAVE_K := 4.0
const TINT_LUMA_REF := 0.35
const EYE_GLINT_ROUGHNESS := 0.1
const EYE_DOT_EMISSION := 0.3
const EYE_GLINT_SPECULAR := 1.0

## The eight constants by their name in the include.
const CONSTANTS: Dictionary[String, float] = {
	"SWIM_BEND_START": SWIM_BEND_START,
	"SWIM_BEND_FULL": SWIM_BEND_FULL,
	"SWIM_REST_AMPLITUDE": SWIM_REST_AMPLITUDE,
	"SWIM_REST_FREQUENCY": SWIM_REST_FREQUENCY,
	"SWIM_WAVE_K": SWIM_WAVE_K,
	"TINT_LUMA_REF": TINT_LUMA_REF,
	"EYE_GLINT_ROUGHNESS": EYE_GLINT_ROUGHNESS,
	"EYE_DOT_EMISSION": EYE_DOT_EMISSION,
}


static func smoothstep_glsl(edge0: float, edge1: float, x: float) -> float:
	var t: float = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func mix_f(a: float, b: float, t: float) -> float:
	return a * (1.0 - t) + b * t


static func mix_c(a: Color, b: Color, t: float) -> Color:
	return Color(mix_f(a.r, b.r, t), mix_f(a.g, b.g, t), mix_f(a.b, b.b, t), 1.0)


static func luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## s = 0.5 - VERTEX.z: 0 at the snout, 1 at the tail base, above 1 on the tail fin.
static func s_of(vertex_z: float) -> float:
	return 0.5 - vertex_z


static func speed_of(swim_speed: float, speed_scale: float) -> float:
	return clampf(swim_speed * speed_scale, 0.0, 1.0)


static func weight(vertex_z: float) -> float:
	return smoothstep_glsl(SWIM_BEND_START, SWIM_BEND_FULL, s_of(vertex_z))


static func amplitude(swim_amplitude: float, swim_speed: float, speed_scale: float) -> float:
	return swim_amplitude * mix_f(SWIM_REST_AMPLITUDE, 1.0, speed_of(swim_speed, speed_scale))


static func frequency(swim_frequency: float, swim_speed: float, speed_scale: float) -> float:
	return swim_frequency * mix_f(SWIM_REST_FREQUENCY, 1.0, speed_of(swim_speed, speed_scale))


## The lateral displacement (VERTEX.x offset) of a vertex at model-space z (ADR 0013 Amendment 1,
## #35): `swim_phase` is the current tail phase in radians, advanced on the CPU, so the shader
## reads no TIME. Matches `fish_bend_x(vertex_z, swim_phase, swim_speed, swim_amplitude,
## swim_speed_scale)` of the include.
static func bend_x(
	vertex_z: float, swim_phase: float, swim_speed: float, swim_amplitude: float, speed_scale: float
) -> float:
	var a: float = amplitude(swim_amplitude, swim_speed, speed_scale)
	var wave: float = sin(swim_phase - SWIM_WAVE_K * s_of(vertex_z))
	return a * weight(vertex_z) * wave


## The #34 form of the bend (TIME driven), kept as the reference of "no visible change" (#35): at a
## constant speed bend_x(z, phase0 + TAU * f * t, ...) equals legacy_bend_x(z, t, phase0, ...).
static func legacy_bend_x(
	vertex_z: float,
	time: float,
	swim_phase: float,
	swim_speed: float,
	swim_amplitude: float,
	swim_frequency: float,
	speed_scale: float
) -> float:
	var a: float = amplitude(swim_amplitude, swim_speed, speed_scale)
	var f: float = frequency(swim_frequency, swim_speed, speed_scale)
	var wave: float = sin(TAU * f * time + swim_phase - SWIM_WAVE_K * s_of(vertex_z))
	return a * weight(vertex_z) * wave


## The largest displacement the vertex ever has: a * w(s).
static func peak(
	vertex_z: float, swim_speed: float, swim_amplitude: float, speed_scale: float
) -> float:
	return amplitude(swim_amplitude, swim_speed, speed_scale) * weight(vertex_z)


## band = int(round(b * 3.0)) on the 0..1 value of the B channel read with texelFetch.
static func eye_band(blue: float) -> int:
	return int(roundf(blue * 3.0))


## The variant tint (replace style). `body` = m.a * (1 - eye) * (1 - COLOR.a).
static func tint(
	c: Color,
	mask_a: float,
	eye_mask: float,
	vertex_alpha: float,
	tint_colour: Color,
	strength: float,
	keep: float
) -> Color:
	var body: float = mask_a * (1.0 - eye_mask) * (1.0 - vertex_alpha)
	var k: float = mix_f(1.0, clampf(luma(c) / TINT_LUMA_REF, 0.0, 2.0), keep)
	var target: Color = Color(tint_colour.r * k, tint_colour.g * k, tint_colour.b * k, 1.0)
	return mix_c(c, target, clampf(strength, 0.0, 1.0) * body)


## The angle-dependent stripe shimmer. `normal_dot_view` is dot(NORMAL, VIEW).
static func shimmer(
	c: Color,
	normal_dot_view: float,
	power: float,
	colour_a: Color,
	colour_b: Color,
	strength: float,
	mask_r: float,
	eye_mask: float
) -> Color:
	var g: float = pow(1.0 - clampf(normal_dot_view, 0.0, 1.0), power)
	var stripe: Color = mix_c(colour_a, colour_b, g)
	return mix_c(c, stripe, clampf(strength, 0.0, 1.0) * mask_r * (1.0 - eye_mask))


## The eye of one fragment. `material` holds eye_colour, eye_iris_colour, eye_highlight_colour,
## eye_highlight_strength, eye_glint_strength, roughness and specular_amount. Returns
## {"colour", "emission", "roughness", "specular"}; band 0 leaves the colour unchanged.
static func eye_look(band: int, base: Color, material: Dictionary) -> Dictionary:
	var pupil: Color = material["eye_colour"]
	var iris: Color = material["eye_iris_colour"]
	var highlight: Color = material["eye_highlight_colour"]
	var dot_strength: float = material["eye_highlight_strength"]
	var glint: float = material["eye_glint_strength"]
	var colour: Color = base
	var emission: Color = Color(0.0, 0.0, 0.0, 1.0)
	if band == 1:
		colour = pupil
	elif band == 2:
		colour = iris
	elif band == 3:
		colour = mix_c(pupil, highlight, dot_strength)
		emission = Color(
			highlight.r * dot_strength * EYE_DOT_EMISSION,
			highlight.g * dot_strength * EYE_DOT_EMISSION,
			highlight.b * dot_strength * EYE_DOT_EMISSION,
			1.0
		)
	var eye_flag: float = 1.0 if band > 0 else 0.0
	return {
		"colour": colour,
		"emission": emission,
		"roughness": mix_f(float(material["roughness"]), EYE_GLINT_ROUGHNESS, eye_flag * glint),
		"specular": mix_f(float(material["specular_amount"]), EYE_GLINT_SPECULAR, eye_flag * glint),
	}


static func distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
