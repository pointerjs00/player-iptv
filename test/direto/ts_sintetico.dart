/// Um MPEG-TS sintético para os testes da costura (nada de capturas reais).
///
/// O pacote `k` (188 bytes) é:
/// - `k % 100 == 0`: a PAT (programa 1 na PMT [pidPmtSintetico]);
/// - `k % 100 == 1`: a PMT (vídeo H.264 no PID [pidVideoSintetico]; o PCR no mesmo PID, ou no
///   [pidPcrSintetico] com `pcrNoutroPid`);
/// - os outros: vídeo, com PCR quando `k % 4 == 3` (o PCR vale `k × 10 ms`) e um PES novo
///   (`payload_unit_start_indicator`, PTS = DTS = `k × 10 ms`) quando `k % 5 == 0`. Com
///   `pcrNoutroPid`, os pacotes do PCR são só adaptation field no [pidPcrSintetico].
///
/// O conteúdo leva `k` e uma `variante` (0 por omissão): a mesma `k` com outra variante tem os
/// mesmos tempos e bytes diferentes (um servidor que voltou a multiplexar). O `deslocamento` (em
/// 90 kHz) soma-se aos tempos, com a volta dos 33 bits; o `passo` (em 90 kHz, 900 = 10 ms) é o tempo
/// de cada pacote.
library;

import 'dart:typed_data';

const pidPmtSintetico = 0x1000;
const pidVideoSintetico = 0x100;
const pidPcrSintetico = 0x101;

/// Quantos pacotes por segundo (o PCR anda 10 ms por pacote).
const pacotesPorSegundo = 100;

const _volta = 1 << 33;

/// O tempo (90 kHz) do pacote `k`.
int tempoSintetico(int k, {int deslocamento = 0, int passo = 900}) => (k * passo + deslocamento) % _volta;

/// O PCR (27 MHz) do pacote `k`.
int pcrSintetico(int k, {int deslocamento = 0, int passo = 900}) =>
    tempoSintetico(k, deslocamento: deslocamento, passo: passo) * 300;

bool temPcr(int k) => k % 100 > 1 && k % 4 == 3;
bool inicioPes(int k, {bool pcrNoutroPid = false}) =>
    k % 100 > 1 && k % 5 == 0 && !(pcrNoutroPid && temPcr(k));

void _tempo(Uint8List p, int o, int prefixo, int t) {
  p[o] = prefixo << 4 | (t >> 30 & 7) << 1 | 1;
  p[o + 1] = t >> 22 & 0xFF;
  p[o + 2] = (t >> 15 & 0x7F) << 1 | 1;
  p[o + 3] = t >> 7 & 0xFF;
  p[o + 4] = (t & 0x7F) << 1 | 1;
}

void _pcr(Uint8List p, int pcr) {
  final base = pcr ~/ 300;
  p[6] = (base >> 25) & 0xFF;
  p[7] = (base >> 17) & 0xFF;
  p[8] = (base >> 9) & 0xFF;
  p[9] = (base >> 1) & 0xFF;
  p[10] = ((base & 1) << 7) | 0x7E;
  p[11] = 0;
}

List<int> pacoteSintetico(int k,
    {int variante = 0, bool comPcr = true, int deslocamento = 0, bool pcrNoutroPid = false, int passo = 900}) {
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
    final pcrPid = pcrNoutroPid ? pidPcrSintetico : pidVideoSintetico;
    final sec = [
      0x00, 0x02, 0xB0, 0x12, 0x00, 0x01, 0xC1, 0x00, 0x00, //
      0xE0 | pcrPid >> 8, pcrPid & 0xFF, 0xF0, 0x00, // PCR_PID, sem descritores
      0x1B, 0xE1, 0x00, 0xF0, 0x00, // H.264 no 0x100
      1, 2, 3, 4,
    ];
    p.setRange(4, 4 + sec.length, sec);
    return p;
  }
  final pcr = comPcr && temPcr(k);
  if (pcr && pcrNoutroPid) {
    // só o PCR, noutro PID
    p[1] = pidPcrSintetico >> 8;
    p[2] = pidPcrSintetico & 0xFF;
    p[3] = 0x20 | cc;
    p[4] = 183;
    p[5] = 0x10;
    _pcr(p, pcrSintetico(k, deslocamento: deslocamento, passo: passo));
    return p;
  }
  final pes = inicioPes(k);
  p[1] = (pes ? 0x40 : 0) | (pidVideoSintetico >> 8);
  p[2] = pidVideoSintetico & 0xFF;
  var i = 4;
  if (pcr) {
    p[3] = 0x30 | cc;
    p[4] = 7;
    p[5] = 0x10;
    _pcr(p, pcrSintetico(k, deslocamento: deslocamento, passo: passo));
    i = 12;
  } else {
    p[3] = 0x10 | cc;
  }
  if (pes) {
    final t = tempoSintetico(k, deslocamento: deslocamento, passo: passo);
    p.setRange(i, i + 9, const [0, 0, 1, 0xE0, 0, 0, 0x80, 0xC0, 10]);
    _tempo(p, i + 9, 3, t);
    _tempo(p, i + 14, 1, t);
    i += 19;
  }
  // o conteúdo: k e a variante, a repetir (sem 0x47 para não enganar a sincronia)
  for (var j = i; j < 188; j++) {
    final v = switch ((j - i) % 4) { 0 => k >> 16, 1 => k >> 8, 2 => k, _ => variante + j };
    p[j] = (v & 0xFF) == 0x47 ? 0x48 : v & 0xFF;
  }
  return p;
}

/// Os pacotes `[de, ate)` seguidos.
Uint8List tsSintetico(int de, int ate,
    {int variante = 0, bool comPcr = true, int deslocamento = 0, bool pcrNoutroPid = false, int passo = 900}) {
  final b = BytesBuilder(copy: false);
  for (var k = de; k < ate; k++) {
    b.add(pacoteSintetico(k,
        variante: variante, comPcr: comPcr, deslocamento: deslocamento, pcrNoutroPid: pcrNoutroPid, passo: passo));
  }
  return b.takeBytes();
}

/// Um pacote nulo (PID 0x1FFF), sempre igual.
List<int> pacoteNulo() => Uint8List(188)
  ..fillRange(0, 188, 0xFF)
  ..setRange(0, 4, const [0x47, 0x1F, 0xFF, 0x10]);

/// `n` pacotes nulos seguidos.
List<int> nulos(int n) => [for (var i = 0; i < n; i++) ...pacoteNulo()];

/// Corta em pedaços de `tamanho` bytes (como chegam do socket).
List<List<int>> emPedacos(List<int> b, int tamanho) => [
      for (var i = 0; i < b.length; i += tamanho) b.sublist(i, i + tamanho > b.length ? b.length : i + tamanho),
    ];
