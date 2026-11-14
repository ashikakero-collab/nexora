// NEXORA Voyage: hyperspace warp: radial star streaks + rotating energy tunnel + nebula tint.
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uTime;
uniform float uSpeed;  // 0..1 warp intensity
uniform float uFade;
out vec4 fragColor;

float h1(float n){return fract(sin(n)*43758.5453);}

void main(){
  vec2 uv=(FlutterFragCoord().xy-uSize*.5)/uSize.y;
  float r=length(uv); float a=atan(uv.y,uv.x);
  vec3 col=vec3(.01,.015,.05);
  // tunnel rings
  float z=.25/(r+.02)+uTime*(2.+uSpeed*10.);
  float ring=pow(.5+.5*sin(z*6.),8.)*smoothstep(.0,.5,r);
  float spokes=pow(.5+.5*sin(a*12.+z*.6),6.);
  col+=vec3(.25,.35,1.)*ring*.35*uSpeed + vec3(.6,.3,1.)*spokes*ring*.25*uSpeed;
  // streaks
  for(int i=0;i<3;i++){
    float k=float(i);
    float seg=floor((a+3.14159)/(6.28318)*180.+k*37.);
    float rnd=h1(seg*1.7+k*13.1);
    float sp=.6+rnd*1.4;
    float pos=fract(rnd*7.3+uTime*sp*(.25+uSpeed*1.6));
    float len=.04+uSpeed*.35;
    float rr=pos*1.4;
    float s=smoothstep(rr-len,rr,r)*(1.-smoothstep(rr,rr+.01,r));
    float w=1.-smoothstep(0.,.5,abs(fract((a+3.14159)/(6.28318)*180.+k*37.)-.5)*2.);
    vec3 c=mix(vec3(.5,.7,1.),vec3(.8,.6,1.),rnd);
    col+=c*s*w*(.5+uSpeed)*(rnd>.35?1.:0.);
  }
  // core flash
  col+=vec3(.55,.75,1.)*exp(-r*10.)*(.4+uSpeed*1.4);
  col*=1.-smoothstep(.75,1.25,r)*.6;
  fragColor=vec4(col*uFade,1.);
}
