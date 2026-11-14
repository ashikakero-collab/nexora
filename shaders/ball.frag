// 3D rolling ball: port of BALL_SKSL in src/game/render.ts. The ball texture is wrapped on a sphere whose
// orientation is the engine's rotation matrix R (rows passed as c0/c1/c2), lit from the top-left.
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uCenter;   // ball centre in physical pixels
uniform float uRadius;  // ball radius in physical pixels
uniform vec3 c0;
uniform vec3 c1;
uniform vec3 c2;
uniform float aa;       // edge anti-aliasing width (fraction of the radius)
uniform sampler2D img;

out vec4 fragColor;

void main() {
  vec2 p = (FlutterFragCoord().xy - uCenter) / uRadius;
  float d = length(p);
  if (d > 1.0) { fragColor = vec4(0.0); return; }
  float z = sqrt(max(0.0, 1.0 - d * d));
  vec3 n = vec3(p.x, p.y, z);
  vec3 q = vec3(dot(c0, n), dot(c1, n), dot(c2, n));
  vec2 uv = q.xy;
  if (q.z < 0.0) uv.x = -uv.x;
  vec4 c = texture(img, uv * 0.93 * 0.5 + 0.5);
  vec3 L = normalize(vec3(-0.42, -0.55, 0.72));
  float dif = 0.62 + 0.5 * max(dot(n, L), 0.0);
  vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
  float sp = pow(max(dot(n, H), 0.0), 36.0) * 0.55;
  float rim = pow(1.0 - z, 2.5);
  vec3 col = c.rgb * dif * (1.0 - 0.45 * rim) + vec3(sp) + vec3(0.35, 0.6, 1.0) * rim * 0.18;
  float a = smoothstep(1.0, 1.0 - aa, d);
  fragColor = vec4(col * a, a);
}
