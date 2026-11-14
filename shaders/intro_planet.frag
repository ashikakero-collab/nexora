// NEXORA Voyage: analytic sphere planet (port of the intro PLANET_FS): fbm terrain, clouds, terminator,
// city lights on the night side, fresnel atmosphere glow. Transparent outside the halo.
#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uCenter;
uniform float uRadius;
uniform float uTime;
uniform float uSeed;
uniform vec3 uCa;
uniform vec3 uCb;
uniform vec3 uCc;
uniform vec3 uAtmo;
uniform float uClouds;
uniform float uCity;
uniform float uSpin;
out vec4 fragColor;

float hash(vec3 p){p=fract(p*0.3183099+.1);p*=17.0;return fract(p.x*p.y*p.z*(p.x+p.y+p.z));}
float noise(vec3 x){vec3 i=floor(x);vec3 f=fract(x);f=f*f*(3.-2.*f);
 return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),
 mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);}
float fbm(vec3 p){float a=.5,s=0.;for(int i=0;i<5;i++){s+=a*noise(p);p=p*2.03+vec3(1.7,9.2,3.1);a*=.5;}return s;}

void main(){
  vec2 q=(FlutterFragCoord().xy-uCenter)/uRadius;
  float d=length(q);
  vec3 L=normalize(vec3(-.6,-.35,.7));
  if(d>1.){
    float halo=exp(-(d-1.)*7.)*.8;
    vec3 c=uAtmo*halo;
    fragColor=vec4(c,halo);
    return;
  }
  float z=sqrt(1.-d*d);
  vec3 N=vec3(q.x,q.y,z);
  float cs=cos(uSpin),sn=sin(uSpin);
  vec3 P=vec3(cs*N.x+sn*N.z,N.y,-sn*N.x+cs*N.z);
  vec3 p=P*2.2+uSeed;float h=fbm(p);float h2=fbm(p*2.7+h*1.5);
  vec3 col=mix(uCa,uCb,smoothstep(.35,.62,h));col=mix(col,uCc,smoothstep(.55,.8,h2));
  float c=fbm(P*4.+vec3(uTime*.03,0.,uTime*.02)+uSeed*2.);c=smoothstep(.5,.8,c)*uClouds;
  col=mix(col,vec3(1.),c*.75);
  float dl=dot(N,L);float dif=smoothstep(-.1,.6,dl);float night=1.-smoothstep(-.15,.1,dl);
  float cityN=smoothstep(.62,.7,fbm(P*9.+uSeed))*(1.-c)*uCity;
  vec3 lit=col*(vec3(1.,.93,.82)*dif*1.15+vec3(.012,.025,.07)*(1.-dif)+.02);
  lit+=uAtmo*cityN*night*1.8;
  float fres=pow(1.-z,3.);lit+=uAtmo*fres*(.25+dif*.8);
  float aa=smoothstep(1.,.985,d);
  fragColor=vec4(lit*aa,aa);
}
