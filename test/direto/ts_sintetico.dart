/// Um MPEG-TS sintético para os testes da costura (nada de capturas reais).
///
/// O pacote `k` (188 bytes) é:
/// - `k % 100 == 0`: a PAT (programa 1 na PMT [pidPmtSintetico]);
/// - `k % 100 == 1`: a PMT (PCR e vídeo H.264 no PID [pidVideoSintetico]);
/// - os outros: vídeo, com PCR quando `k % 4 == 3` (o PCR vale `k × 10 ms`) e
///   `payload_unit_start_indicator` quando `k % 5 == 0`.
///
/// O conteúdo leva `k` e uma `variante` (0 por omissão): a mesma `k` com outra variante tem os
/// mesmos tempos e bytes diferentes (um servidor que voltou a multiplexar).
library;

import 'dart:typed_data';

const pidPmtSintetico = 0x1000;
const pidVideoSintetico = 0x100;

/// Quantos pacotes por segundo (o PCR anda 10 ms por pacote).
const pacotesPorSegundo = 100;

/// O PCR (27 MHz) do pacote `k`.
int pcrSintetico(int k) => k * 900 * 300;

bool temPcr(int k) => k % 100 > 1 && k % 4 == 3;
bool inicioPes(int k) => k % 100 > 1 && k % 5 == 0;

List<int> pacoteSintetico(int k, {int variante = 0, bool comPcr = true}) {
  final p = Uint8List(188)..fillRange(0, 188, 0xFF);
  p[0] = 0x47;
  final cc = k & 0x0F;
  if (k % 100 == 0) {
    p[1] = 0x40; // PUSI, PID 0
    p[2] = 0x00;
    p[3] = 0x10 | cc;
    const sec = [0x00, 0x00, 0xB0, 0x0D, 0x00, 0x01, 0xC1, 0x00, 0x00, 0x00, 0x01, 0xF0, 0x00, 1, 2, 3, 4];
    p.setRange(4, 4 + sec.length, sec);
    return p;
  }
  if (k % 100 == 1) {
    p[1] = 0x40 | (pidPmtSintetico >> 8);
    p[2] = pidPmtSintetico & 0xFF;
    p[3] = 0x10 | cc;
    const sec = [
      0x00, 0x02, 0xB0, 0x12, 0x00, 0x01, 0xC1, 0x00, 0x00, //
      0xE1, 0x00, 0xF0, 0x00, // PCR_PID 0x100, sem descritores
      0x1B, 0xE1, 0x00, 0xF0, 0x00, // H.264 no 0x100
      1, 2, 3, 4,
    ];
    p.setRange(4, 4 + sec.length, sec);
    return p;
  }
  p[1] = (inicioPes(k) ? 0x40 : 0) | (pidVideoSintetico >> 8);
  p[2] = pidVideoSintetico & 0xFF;
  var i = 4;
  if (comPcr && temPcr(k)) {
    p[3] = 0x30 | cc;
    p[4] = 7;
    p[5] = 0x10;
    final base = pcrSintetico(k) ~/ 300;
    p[6] = (base >> 25) & 0xFF;
    p[7] = (base >> 17) & 0xFF;
    p[8] = (base >> 9) & 0xFF;
    p[9] = (base >> 1) & 0xFF;
    p[10] = ((base & 1) << 7) | 0x7E;
    p[11] = 0;
    i = 12;
  } else {
    p[3] = 0x10 | cc;
  }
  // o conteúdo: k e a variante, a repetir (sem 0x47 para não enganar a sincronia)
  for (var j = i; j < 188; j++) {
    final v = switch ((j - i) % 4) { 0 => k >> 16, 1 => k >> 8, 2 => k, _ => variante + j };
    p[j] = (v & 0xFF) == 0x47 ? 0x48 : v & 0xFF;
  }
  return p;
}

/// Os pacotes `[de, ate)` seguidos.
Uint8List tsSintetico(int de, int ate, {int variante = 0, bool comPcr = true}) {
  final b = BytesBuilder(copy: false);
  for (var k = de; k < ate; k++) {
    b.add(pacoteSintetico(k, variante: variante, comPcr: comPcr));
  }
  return b.takeBytes();
}

/// Corta em pedaços de `tamanho` bytes (como chegam do socket).
List<List<int>> emPedacos(List<int> b, int tamanho) => [
      for (var i = 0; i < b.length; i += tamanho) b.sublist(i, i + tamanho > b.length ? b.length : i + tamanho),
    ];
