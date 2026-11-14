shader_type canvas_item;
// Gentle wind sway for decorative plant sprites: the top of the sprite leans, the base stays planted.
// Phase comes from the sprite's world position, so neighbouring plants never move in lockstep.
uniform float amount = 4.0;   // px of lean at the top
uniform float speed = 1.3;

void vertex() {
	float phase = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).x * 0.013;
	float lean = sin(TIME * speed + phase) * 0.7 + sin(TIME * speed * 2.3 + phase * 1.7) * 0.3;
	VERTEX.x += lean * amount * (1.0 - UV.y);
}
