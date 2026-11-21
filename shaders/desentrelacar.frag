#version 460 core
// Desentrelaçamento do player no Android, por cima da textura do vídeo (ImageFilter.shader).
// O mesmo que o shader do mpv do Windows (lib/ui/player/desentrelacamento.dart): as linhas pares
// são de um campo, as ímpares do outro (outro instante). Onde uma linha ímpar não bate com as
// pares à volta mas bate com as ímpares (riscas de movimento), é trocada por uma interpolação das
// pares (seguindo a direção da aresta); onde não há riscas fica como está.
// As linhas contam-se na imagem do vídeo (uImagem), não no ecrã: serve também quando o vídeo é
// escalado (576 linhas num ecrã 1080).
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uTamanho;  // posto pelo motor: o tamanho da entrada
uniform vec2 uImagem;   // colunas e linhas do vídeo
uniform sampler2D uEntrada;

out vec4 fragColor;

float luz(vec4 c) { return dot(c.rgb, vec3(0.299, 0.587, 0.114)); }

vec4 linha(float x, float l) {
  return texture(uEntrada, vec2(x, (l + 0.5) / uImagem.y));
}

void main() {
  // (sem inverter o y no OpenGL ES, ao contrário do que diz a documentação do ImageFilter.shader:
  // no Impeller OpenGLES do emulador a imagem ficava de pernas para o ar)
  vec2 uv = FlutterFragCoord().xy / uTamanho;
  vec4 original = texture(uEntrada, uv);
  float l = floor(uv.y * uImagem.y);
  if (mod(l, 2.0) < 0.5) {
    fragColor = original;
    return;
  }
  float dx = 1.0 / uImagem.x;
  vec4 c = linha(uv.x, l);
  vec4 a = linha(uv.x, l - 1.0);
  vec4 b = linha(uv.x, l + 1.0);
  float lc = luz(c), la = luz(a), lb = luz(b);
  float la2 = luz(linha(uv.x, l - 2.0));
  float lb2 = luz(linha(uv.x, l + 2.0));
  float fora = abs(lc - 0.5 * (la + lb)) - 0.5 * abs(la - lb);
  float proprio = abs(lc - 0.5 * (la2 + lb2));
  float riscas = smoothstep(0.012, 0.04, fora - 0.5 * proprio);
  if (riscas <= 0.0) {
    fragColor = original;
    return;
  }
  vec4 al = linha(uv.x - dx, l - 1.0), ar = linha(uv.x + dx, l - 1.0);
  vec4 bl = linha(uv.x - dx, l + 1.0), br = linha(uv.x + dx, l + 1.0);
  float d0 = abs(la - lb), d1 = abs(luz(al) - luz(br)), d2 = abs(luz(ar) - luz(bl));
  vec4 m = 0.5 * (a + b);
  if (d1 < d0 && d1 <= d2) {
    m = 0.5 * (al + br);
  } else if (d2 < d0) {
    m = 0.5 * (ar + bl);
  }
  m = clamp(m, min(a, b), max(a, b));
  fragColor = mix(original, m, riscas);
}
