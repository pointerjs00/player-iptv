/// Coser uma religação do direto à anterior.
///
/// Há servidores que fecham a ligação a cada poucos segundos e, na ligação nova, voltam a mandar
/// 10–30 s que já tinham mandado (bytes iguais). Para o gravado não repetir nem andar para trás:
///
/// 1. **Pelos bytes** ([pontoDeCostura]): guardam-se os últimos [tamanhoCauda] bytes gravados (20
///    pacotes TS) e procuram-se na ligação nova; grava-se só o que vem depois deles. O gravado fica
///    contínuo byte a byte (até o pacote cortado no fim da anterior se completa). A procura é uma
///    janela deslizante (Knuth–Morris–Pratt): não precisa dos bytes já vistos, por isso continua
///    enquanto o PCR da ligação nova não passar o último gravado, por muito longa que seja a
///    repetição. Um encontro só vale se o PCR seguinte passar o último gravado (uma cauda ambígua,
///    por exemplo 20 pacotes nulos, casa noutros sítios).
/// 2. **Pelo tempo** ([costuraPorPcr]), se a cauda não aparecer antes do primeiro PCR maior do que
///    o último gravado: começa-se no primeiro PES de vídeo com DTS (ou PTS) maior do que o do
///    último PES de vídeo gravado (não se perde a imagem seguinte); sem esse DTS, no primeiro início
///    de PES do vídeo a partir do PCR maior (ou nesse pacote, sem PID de vídeo conhecido). Se o
///    primeiro PCR da ligação nova já é maior, o servidor saltou à frente: grava-se inteira.
/// 3. Sem PCR com que comparar (até [limiteProcura]), sem PCR legível ou com o PCR muito para trás
///    (o canal recomeçou), grava-se a ligação inteira, como antes.
///
/// [ProcuraCostura] faz isto à medida que os bytes chegam; as duas funções são o mesmo de uma vez.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// O tamanho de um pacote MPEG-TS.
const pacoteTs = 188;

/// Quanto do fim do gravado se procura na ligação nova (20 pacotes).
const tamanhoCauda = 20 * pacoteTs;

/// Quanto se guarda da ligação nova à espera de decidir (sem PCR com que comparar, é também até
/// onde se procura a cauda).
const limiteProcura = 8 << 20;

/// O relógio do PCR (27 MHz).
const relogioPcr = 27000000;

/// Um PCR mais para trás do que isto não é uma repetição: o canal recomeçou (não se compara).
const recuoMaximoPcr = 120 * relogioPcr;

/// Depois do ponto do PCR, até onde se espera por um início de PES do vídeo.
const _limitePes = 1 << 20;

/// O PCR dá a volta aos 33 bits da base (× 300 da extensão).
const _voltaPcr = (1 << 33) * 300;

/// O PTS e o DTS (90 kHz) dão a volta aos 33 bits.
const _voltaPts = 1 << 33;

/// Tipos de stream de vídeo na PMT (MPEG-1/2, MPEG-4, H.264, H.265, AVS, VC-1 e afins).
const _tiposVideo = {0x01, 0x02, 0x10, 0x1B, 0x24, 0x42, 0xD1, 0xEA};

int _diferenca(int a, int b, int volta) {
  var d = (a - b) % volta;
  if (d >= volta ~/ 2) d -= volta;
  return d;
}

/// `a − b` em PCR, com a volta do relógio: positivo se `a` vem depois de `b`.
int diferencaPcr(int a, int b) => _diferenca(a, b, _voltaPcr);

/// `a − b` em PTS/DTS (90 kHz), com a volta dos 33 bits.
int diferencaPts(int a, int b) => _diferenca(a, b, _voltaPts);

/// Um pacote lido: a `posicao` (desde o começo do que se deu ao [LeitorTs]), o PID, se começa uma
/// unidade (`payload_unit_start_indicator`), o PCR (só no PID do PCR) e o DTS (ou PTS) de um PES
/// de vídeo que comece nele.
typedef PacoteTs = ({int posicao, int pid, bool inicioUnidade, int? pcr, int? dts});

/// Lê um MPEG-TS aos pedaços: sincroniza num `0x47` que se repete 188 bytes depois, acha a PMT pela
/// PAT, o PID do PCR e do vídeo pela PMT (ou o PID do PCR no primeiro pacote que o leve) e guarda o
/// último PCR e o DTS do último PES de vídeo. Só as secções que cabem num pacote (o normal na PAT e
/// na PMT). Não copia os pedaços (só o pacote que ficou a meio entre dois).
class LeitorTs {
  LeitorTs({this.pidPmt, this.pidPcr, this.pidVideo});

  int? pidPmt;
  int? pidPcr;
  int? pidVideo;

  /// O último PCR lido no [pidPcr].
  int? ultimoPcr;

  /// O DTS (ou o PTS, sem DTS) do último PES de vídeo lido.
  int? ultimoDts;

  /// A posição do primeiro pacote lido (null: ainda não sincronizou).
  int? primeiroPacote;

  /// Pacotes lidos.
  int pacotes = 0;

  /// A posição a seguir ao último byte dado.
  int _posicao = 0;

  /// O começo de um pacote (ou de um candidato a sincronia) que ainda não chegou todo.
  Uint8List _resto = Uint8List(0);
  bool _aSincronizar = true;

  /// A posição do próximo pacote por ler (o que vem antes já foi lido ou não é TS).
  int get lidoAte => _posicao - _resto.length;

  /// Uma ligação nova (que não continua os bytes da anterior): larga o pacote a meio e volta a
  /// procurar a sincronia. Os PIDs, o último PCR e o último DTS ficam.
  void novaLigacao() {
    _resto = Uint8List(0);
    _aSincronizar = true;
  }

  /// Lê mais bytes. Se `aoPacote` devolver true, pára (o resto destes bytes fica por ler).
  void ler(List<int> dados, [bool Function(PacoteTs)? aoPacote]) {
    final desde = _posicao - _resto.length; // a posição do 1.º byte do resto (ou de dados)
    _posicao += dados.length;
    final r = _resto.length;
    if (r == 0) {
      _percorrer(dados, 0, desde, aoPacote, dados.length);
      return;
    }
    // o pacote a meio: junta-se só o resto com o começo de dados (2 pacotes chegam para o acabar e
    // ver a sincronia do seguinte); o resto de dados lê-se sem cópia
    final n = math.min(dados.length, 2 * pacoteTs);
    final b = Uint8List(r + n)
      ..setRange(0, r, _resto)
      ..setRange(r, r + n, dados);
    _resto = Uint8List(0);
    final i = _percorrer(b, 0, desde, aoPacote, r);
    if (i == null) return; // parou, ou guardou o resto (dados curtos: b tem-nos todos)
    _percorrer(dados, i - r, desde + r, aoPacote, dados.length);
  }

  /// Lê os pacotes de `b` que começam antes de `ate`; devolve onde ficou (null se parou a pedido
  /// ou se faltam bytes e guardou o resto).
  int? _percorrer(List<int> b, int i, int base, bool Function(PacoteTs)? aoPacote, int ate) {
    while (i < ate) {
      if (_aSincronizar) {
        while (i < ate) {
          if (b[i] == 0x47 && (i + pacoteTs >= b.length || b[i + pacoteTs] == 0x47)) break;
          i++;
        }
        if (i >= ate) return i;
        if (i + pacoteTs >= b.length) {
          _guardarResto(b, i); // falta ver o pacote seguinte
          return null;
        }
        _aSincronizar = false;
      }
      if (i + pacoteTs > b.length) {
        _guardarResto(b, i);
        return null;
      }
      if (b[i] != 0x47) {
        _aSincronizar = true; // perdeu a sincronia
        continue;
      }
      final p = _pacote(b, i, base + i);
      i += pacoteTs;
      if (aoPacote != null && aoPacote(p)) return null;
    }
    return i;
  }

  void _guardarResto(List<int> b, int i) {
    _resto = i >= b.length ? Uint8List(0) : Uint8List.fromList(b.sublist(i));
  }

  PacoteTs _pacote(List<int> b, int i, int posicao) {
    pacotes++;
    primeiroPacote ??= posicao;
    final fim = i + pacoteTs;
    final inicio = b[i + 1] & 0x40 != 0;
    final pid = (b[i + 1] & 0x1F) << 8 | b[i + 2];
    final controlo = (b[i + 3] >> 4) & 3;
    var carga = i + 4;
    int? pcr;
    if (controlo & 2 != 0) {
      final n = b[i + 4];
      if (n >= 7 && b[i + 5] & 0x10 != 0) {
        final base = b[i + 6] << 25 | b[i + 7] << 17 | b[i + 8] << 9 | b[i + 9] << 1 | b[i + 10] >> 7;
        pcr = base * 300 + ((b[i + 10] & 1) << 8 | b[i + 11]);
      }
      carga = i + 5 + n;
    }
    if (pcr != null) {
      pidPcr ??= pid;
      if (pid == pidPcr) {
        ultimoPcr = pcr;
      } else {
        pcr = null;
      }
    }
    int? dts;
    if (inicio && controlo & 1 != 0 && carga < fim) {
      if (pid == 0) {
        _pat(b, carga, fim);
      } else if (pid == pidPmt) {
        _pmt(b, carga, fim);
      } else if (pid == pidVideo) {
        dts = _dts(b, carga, fim);
        if (dts != null) ultimoDts = dts;
      }
    }
    return (posicao: posicao, pid: pid, inicioUnidade: inicio, pcr: pcr, dts: dts);
  }

  /// O DTS (ou o PTS) do cabeçalho do PES que começa em `c`.
  static int? _dts(List<int> b, int c, int fim) {
    if (c + 9 > fim || b[c] != 0 || b[c + 1] != 0 || b[c + 2] != 1) return null;
    final flags = b[c + 7] >> 6;
    if (flags == 3 && c + 19 <= fim) return _tempo(b, c + 14);
    if (flags >= 2 && c + 14 <= fim) return _tempo(b, c + 9);
    return null;
  }

  static int _tempo(List<int> b, int o) =>
      (b[o] >> 1 & 7) << 30 | b[o + 1] << 22 | (b[o + 2] >> 1) << 15 | b[o + 3] << 7 | b[o + 4] >> 1;

  /// O começo e o fim (sem o CRC) da secção que começa em `carga`, se for a tabela `tabela`.
  (int, int)? _seccao(List<int> b, int carga, int fimPacote, int tabela) {
    final s = carga + 1 + b[carga];
    if (s + 3 > fimPacote || b[s] != tabela) return null;
    final comprimento = (b[s + 1] & 0x0F) << 8 | b[s + 2];
    return (s, math.min(s + 3 + comprimento - 4, fimPacote));
  }

  void _pat(List<int> b, int carga, int fimPacote) {
    final sec = _seccao(b, carga, fimPacote, 0x00);
    if (sec == null) return;
    final (s, fim) = sec;
    for (var e = s + 8; e + 4 <= fim; e += 4) {
      final programa = b[e] << 8 | b[e + 1];
      if (programa != 0) {
        pidPmt = (b[e + 2] & 0x1F) << 8 | b[e + 3];
        return;
      }
    }
  }

  void _pmt(List<int> b, int carga, int fimPacote) {
    final sec = _seccao(b, carga, fimPacote, 0x02);
    if (sec == null) return;
    final (s, fim) = sec;
    if (s + 12 > fim) return;
    final pcr = (b[s + 8] & 0x1F) << 8 | b[s + 9];
    if (pcr != 0x1FFF) pidPcr = pcr; // a PMT manda (e pode mudar)
    var e = s + 12 + ((b[s + 10] & 0x0F) << 8 | b[s + 11]);
    while (e + 5 <= fim) {
      final tipo = b[e];
      final pid = (b[e + 1] & 0x1F) << 8 | b[e + 2];
      if (_tiposVideo.contains(tipo)) {
        pidVideo = pid;
        return;
      }
      e += 5 + ((b[e + 3] & 0x0F) << 8 | b[e + 4]);
    }
  }
}

/// Como se coseu a ligação nova.
enum ModoCostura {
  /// A cauda apareceu: escreve-se o que vem depois dela.
  bytes,

  /// Pelo tempo (PCR e DTS): o que já estava gravado ficou de fora.
  pcr,

  /// O primeiro PCR da ligação nova já passava o último gravado: grava-se inteira.
  salto,

  /// Não se conseguiu coser (sem PCR legível, não é TS, o canal recomeçou): grava-se a partir de
  /// [DecisaoCostura.desde] (o começo, ou o que ainda estava guardado).
  inteira,
}

class DecisaoCostura {
  const DecisaoCostura(this.modo, this.desde, {this.sincronia, this.motivo});

  final ModoCostura modo;

  /// Grava-se a partir desta posição da ligação nova.
  final int desde;

  /// O primeiro pacote a partir de [desde] (null: não se achou), para o alinhamento.
  final int? sincronia;

  /// Porque não se coseu ([ModoCostura.inteira]), para o registo (sem dados da ligação).
  final String? motivo;

  @override
  String toString() => 'DecisaoCostura($modo, $desde)';
}

/// Procura a costura à medida que a ligação nova chega. Até haver [decisao] não se grava nada; quem
/// a usa guarda os bytes recebidos a partir de [descartavelAte]: no máximo [limite] bytes mais o
/// último pedaço.
class ProcuraCostura {
  ProcuraCostura({
    required List<int> cauda,
    this.ultimoPcr,
    this.ultimoDts,
    int? pidPcr,
    int? pidVideo,
    int? pidPmt,
    this.limite = limiteProcura,
  })  : _cauda = Uint8List.fromList(cauda),
        _leitor = LeitorTs(pidPmt: pidPmt, pidPcr: pidPcr, pidVideo: pidVideo) {
    _falhas = _tabela(_cauda);
    _procurarBytes = _cauda.isNotEmpty;
  }

  /// O último PCR gravado (null: não se sabe).
  final int? ultimoPcr;

  /// O DTS do último PES de vídeo gravado (null: não se sabe).
  final int? ultimoDts;
  final int limite;

  final Uint8List _cauda;
  late final Int32List _falhas;
  final LeitorTs _leitor;
  late bool _procurarBytes;

  /// Quantos bytes da cauda coincidem agora (Knuth–Morris–Pratt).
  int _coincide = 0;

  /// Comparações de bytes feitas pela procura da cauda (para medir o custo).
  @visibleForTesting
  int comparacoes = 0;

  /// Os fins de encontros da cauda ainda por ver pelo leitor de pacotes (por ordem).
  final _encontros = <int>[];

  /// O primeiro encontro desde o último PCR: vale se o PCR seguinte passar o último gravado.
  int? _candidato;

  /// Já passou um PCR (de qualquer valor) na ligação nova.
  bool _viuPcr = false;

  /// O primeiro PES de vídeo com DTS maior do que o [ultimoDts].
  int? _pesNovo;

  /// O primeiro pacote com PCR maior do que o [ultimoPcr] (à espera de um início de PES do vídeo).
  int? _ponto;

  /// Bytes recebidos da ligação nova.
  int recebidos = 0;

  DecisaoCostura? decisao;

  /// O que vem antes desta posição já não se grava (pode largar-se da memória).
  int descartavelAte = 0;

  /// Mais bytes da ligação nova; a decisão, quando a houver (depois disso não faz nada).
  DecisaoCostura? receber(List<int> dados) {
    if (decisao != null) return decisao;
    final ini = recebidos;
    recebidos += dados.length;
    if (_procurarBytes) {
      // sem PCR com que confirmar ou com que continuar, só até ao limite
      final ate = ultimoPcr == null ? math.max(0, math.min(dados.length, limite - ini)) : dados.length;
      final m = _cauda.length;
      var j = _coincide;
      for (var k = 0; k < ate; k++) {
        final c = dados[k];
        comparacoes++;
        while (j > 0 && _cauda[j] != c) {
          j = _falhas[j - 1];
          comparacoes++;
        }
        if (_cauda[j] == c) j++;
        if (j == m) {
          if (ultimoPcr == null) return _decidir(DecisaoCostura(ModoCostura.bytes, ini + k + 1));
          _encontros.add(ini + k + 1);
          j = _falhas[m - 1];
        }
      }
      _coincide = j;
    }
    _leitor.ler(dados, _aoPacote);
    if (decisao != null) return decisao;
    if (_leitor.primeiroPacote == null && recebidos >= 4 * pacoteTs) {
      return _decidir(const DecisaoCostura(ModoCostura.inteira, 0, motivo: 'não parece MPEG-TS'));
    }
    final comPcr = ultimoPcr != null && _viuPcr;
    if (recebidos >= limite && !comPcr) {
      // sem a cauda até ao limite e sem PCR com que comparar
      return _decidir(DecisaoCostura(ModoCostura.inteira, 0,
          sincronia: _leitor.primeiroPacote,
          motivo: ultimoPcr == null ? 'sem PCR no que estava gravado' : 'PCR ilegível na ligação nova'));
    }
    if (comPcr) {
      // com PCR com que comparar, a ligação nunca se grava desde o começo: guarda-se só o que ainda
      // pode ser gravado, e nunca mais do que o limite (um encontro por confirmar aceita-se; um PES
      // novo sem PCR que o confirme larga-se)
      final c = _candidato ?? (_encontros.isNotEmpty ? _encontros.first : null);
      if (c != null && recebidos - c > limite) return _decidir(DecisaoCostura(ModoCostura.bytes, c));
      final pes = _pesNovo;
      if (pes != null && _ponto == null && recebidos - pes > limite) _pesNovo = null;
      // o que se guarda: a partir do pedaço atual (um encontro que acabe mais à frente só precisa do
      // que vem depois dele), de um encontro por confirmar, do PES novo ou do ponto do PCR
      var guarda = _procurarBytes ? ini : recebidos;
      for (final p in [_candidato, if (_encontros.isNotEmpty) _encontros.first, _pesNovo, _ponto]) {
        if (p != null && p < guarda) guarda = p;
      }
      descartavelAte = math.max(descartavelAte, guarda);
    }
    return null;
  }

  /// A ligação nova acabou sem decisão: decide-se com o que veio.
  DecisaoCostura terminar() {
    final d = decisao;
    if (d != null) return d;
    final c = _candidato ?? (_encontros.isNotEmpty ? _encontros.first : null);
    if (c != null) return _decidir(DecisaoCostura(ModoCostura.bytes, c)); // sem PCR depois: aceita-se
    final ponto = _ponto;
    if (ponto != null) return _decidir(DecisaoCostura(ModoCostura.pcr, _pesNovo ?? ponto));
    if (_leitor.primeiroPacote == null) {
      // uns bytes soltos (a ligação fechou logo, ex.: 20 bytes): não chegam a um pacote que se possa
      // ver; vêm de uma ligação que recomeça atrás, por isso não se grava nada
      if (recebidos < 4 * pacoteTs) return _decidir(DecisaoCostura(ModoCostura.pcr, recebidos));
      return _decidir(const DecisaoCostura(ModoCostura.inteira, 0, motivo: 'não parece MPEG-TS'));
    }
    if (ultimoPcr != null && _viuPcr) {
      final pes = _pesNovo;
      // tudo velho (nada a gravar), ou desde a primeira imagem nova
      return _decidir(DecisaoCostura(ModoCostura.pcr, pes ?? recebidos));
    }
    return _decidir(DecisaoCostura(ModoCostura.inteira, 0,
        sincronia: _leitor.primeiroPacote,
        motivo: ultimoPcr == null ? 'sem PCR no que estava gravado' : 'PCR ilegível na ligação nova'));
  }

  DecisaoCostura _decidir(DecisaoCostura d) {
    decisao = d;
    descartavelAte = d.desde;
    return d;
  }

  bool _aoPacote(PacoteTs p) {
    while (_encontros.isNotEmpty && _encontros.first <= p.posicao) {
      final e = _encontros.removeAt(0);
      _candidato ??= e;
    }
    final video = _leitor.pidVideo;
    final dts = p.dts, ultimoD = ultimoDts;
    if (_pesNovo == null && dts != null && ultimoD != null && p.pid == video && diferencaPts(dts, ultimoD) > 0) {
      _pesNovo = p.posicao;
    }
    // um encontro que acaba dentro deste pacote: é o último pacote gravado (cortado), e o PCR dele
    // não chegou ao último gravado; não conta para decidir
    final cortado = _encontros.isNotEmpty && _encontros.first <= p.posicao + pacoteTs;
    final pcr = cortado ? null : p.pcr, ultimo = ultimoPcr;
    if (pcr != null && ultimo != null) {
      final d = diferencaPcr(pcr, ultimo);
      if (d < -recuoMaximoPcr) {
        // o canal recomeçou: grava-se a partir do que ainda está guardado (deste pacote, se já se
        // largou o começo da ligação)
        final desde = descartavelAte > 0 ? p.posicao : 0;
        _decidir(DecisaoCostura(ModoCostura.inteira, desde,
            sincronia: desde > 0 ? p.posicao : _leitor.primeiroPacote,
            motivo: 'PCR muito para trás (o canal recomeçou)'));
        return true;
      }
      if (d <= 0) {
        _candidato = null; // depois do encontro, o PCR não passou o último: não era o sítio
      } else if (_ponto == null) {
        final c = _candidato;
        if (c != null) {
          _decidir(DecisaoCostura(ModoCostura.bytes, c));
          return true;
        }
        if (!_viuPcr) {
          _decidir(DecisaoCostura(ModoCostura.salto, 0, sincronia: _leitor.primeiroPacote));
          return true;
        }
        _ponto = p.posicao;
        _procurarBytes = false; // a cauda já não aparece: vinha antes deste PCR
        _encontros.clear();
      }
    }
    if (p.pcr != null) _viuPcr = true;
    final ponto = _ponto;
    if (ponto == null) return false;
    final pes = _pesNovo;
    if (pes != null) {
      _decidir(DecisaoCostura(ModoCostura.pcr, pes)); // a primeira imagem que não estava gravada
      return true;
    }
    if (video == null || p.posicao - ponto >= math.min(limite, _limitePes)) {
      _decidir(DecisaoCostura(ModoCostura.pcr, ponto));
      return true;
    }
    if (p.pid == video && p.inicioUnidade && (ultimoD == null || p.dts == null)) {
      _decidir(DecisaoCostura(ModoCostura.pcr, p.posicao));
      return true;
    }
    return false;
  }

  static Int32List _tabela(Uint8List c) {
    final t = Int32List(c.length);
    var j = 0;
    for (var i = 1; i < c.length; i++) {
      while (j > 0 && c[i] != c[j]) {
        j = t[j - 1];
      }
      if (c[i] == c[j]) j++;
      t[i] = j;
    }
    return t;
  }
}

/// A posição em `novo` logo a seguir à `cauda` (procurada nos primeiros `limite` bytes); null se
/// não estiver lá.
int? pontoDeCostura(List<int> cauda, List<int> novo, {int limite = limiteProcura}) {
  if (cauda.isEmpty) return null;
  final d = ProcuraCostura(cauda: cauda, limite: limite).receber(novo);
  return d?.modo == ModoCostura.bytes ? d!.desde : null;
}

/// Onde começar a gravar `novo` depois de um gravado cujo último PCR é `ultimoPcr` (e o DTS do
/// último PES de vídeo, `ultimoDts`): o primeiro PES de vídeo com DTS maior; sem DTS, o primeiro
/// início de PES do vídeo a partir do primeiro pacote com PCR maior (ou esse pacote, sem PID de
/// vídeo); 0 se a ligação começa já à frente; `novo.length` se é toda velha; null se o PCR não se
/// lê (ou recuou demais).
int? costuraPorPcr(int ultimoPcr, List<int> novo, {int? ultimoDts, int? pidPcr, int? pidVideo}) {
  final p = ProcuraCostura(
      cauda: const [], ultimoPcr: ultimoPcr, ultimoDts: ultimoDts, pidPcr: pidPcr, pidVideo: pidVideo);
  final d = p.receber(novo) ?? p.terminar();
  return d.modo == ModoCostura.inteira ? null : d.desde;
}
