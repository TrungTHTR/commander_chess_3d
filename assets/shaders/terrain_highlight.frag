#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform vec4 uBaseColor;
uniform vec4 uAccentColor;

out vec4 fragColor;

void main() {
  vec2 safeSize = max(uSize, vec2(1.0));
  vec2 uv = FlutterFragCoord().xy / safeSize;

  // Subtle animated tactical water caustics and grid shimmer.
  float waveA = sin(uv.x * 26.0 + uTime * 1.9 + sin(uv.y * 14.0 - uTime * 1.2));
  float waveB = cos(uv.y * 22.0 - uTime * 1.5 + uv.x * 8.0);
  float caustic = smoothstep(0.35, 0.95, 0.5 + 0.25 * waveA + 0.25 * waveB);

  // Fine tactical scan/grid modulation.
  float gridX = smoothstep(0.92, 1.0, abs(sin(uv.x * 34.5575)));
  float gridY = smoothstep(0.92, 1.0, abs(sin(uv.y * 37.6991)));
  float gridLine = max(gridX, gridY) * 0.18;

  // Selection pulse breathing factor.
  float pulse = 0.72 + 0.28 * sin(uTime * 3.1);

  float blend = clamp(caustic * 0.42 * pulse + gridLine, 0.0, 1.0);
  vec3 rgb = mix(uBaseColor.rgb, uAccentColor.rgb, blend);
  float alpha = clamp(mix(uBaseColor.a, uAccentColor.a, blend * 0.65), 0.0, 1.0);

  // Premultiplied alpha output required by Flutter/Impeller runtime effects.
  fragColor = vec4(rgb * alpha, alpha);
}
