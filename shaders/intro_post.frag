// NEXORA Voyage: deep-space backdrop (fbm nebula + twinkling star field), port of the intro's nebula sphere.
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uTime;
uniform float uMix;   // 0 = blue earth space, 1 = violet NEXORA space
uniform float uFade;  // global brightness
out vec4 fragColor;

float hash(vec3 p){p=fract(p*0.3183099+.1);p*=17.0;return fract(p.x*p.y*p.z*(p.x+p.y+p.z));}
float noise(vec3 x){vec3 i=floor(x);vec3 f=fract(x);f=f*f*(3.-2.*f);
 return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),
 mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);}
float fbm(vec3 p){float a=.5,s=0.;for(int i=0;i<4;i++){s+=a*noise(p);p=p*2.03+vec3(1.7,9.2,3.1);a*=.5;}return s;}
float h2(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}

void main(){
  vec2 uv=(FlutterFragCoord().xy-uSize*.5)/uSize.y;
  vec3 d=normalize(vec3(uv,1.2));
  float n=fbm(d*2.3+vec3(uTime*.02));float n2=fbm(d*5.+n*2.);
  vec3 A=mix(vec3(.008,.012,.05),vec3(.025,.0,.06),uMix);
  vec3 B=mix(vec3(.05,.09,.30),vec3(.32,.12,.55),uMix);
  vec3 C=mix(vec3(.04,.16,.36),vec3(.02,.30,.50),uMix);
  vec3 col=A+B*smoothstep(.38,.9,n)*.6+C*smoothstep(.5,.95,n2)*.38;
  // stars
  vec2 g=FlutterFragCoord().xy/2.5; vec2 id=floor(g); vec2 f=fract(g)-.5;
  float r=h2(id);
  if(r>.985){float tw=.6+.4*sin(uTime*(2.+r*6.)+r*40.);float s=smoothstep(.35,0.,length(f));col+=vec3(.8,.9,1.)*s*tw*(r-.985)*60.;}
  fragColor=vec4(col*uFade,1.);
}
