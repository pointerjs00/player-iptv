/// Coser uma religação do direto à anterior.
///
/// Há servidores que fecham a ligação a cada poucos segundos e, na ligação nova, voltam a mandar
/// 10–30 s que já tinham mandado (bytes iguais). Para o gravado não repetir nem andar para trás:
///
/// 1. **Pelos bytes** ([pontoDeCostura]): guardam-se os últimos [tamanhoCauda] bytes gravados (20
///    pacotes TS) e procuram-se nos primeiros [limiteProcura] bytes da ligação nova; grava-se só o
///    que vem depois deles. O gravado fica contínuo byte a byte (até o pacote cortado no fim da
///    anterior se completa).
/// 2. **Pelo PCR** ([costuraPorPcr]), se a cauda não aparecer: descartam-se os pacotes até o PCR
///    passar o último gravado e começa-se no primeiro início de PES do vídeo a partir daí (ou no
///    pacote com o PCR maior, sem PID de vídeo conhecido). Se o primeiro PCR da ligação nova já é
///    maior, o servidor saltou à frente: grava-se a ligação inteira.
/// 3. Sem PCR legível (ou muito para trás: o canal recomeçou), grava-se a ligação inteira, como
///    antes.
///
/// [ProcuraCostura] faz isto à medida que os bytes chegam; as duas funções são o mesmo de uma vez.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// O tamanho de um pacote MPEG-TS.
const pacoteTs = 188;

/// Quanto do fim do gravado se procura na ligação nova (20 pacotes).
const tamanhoCauda = 20 * pacoteTs;

/// Até onde se procura a cauda na ligação nova (depois disso, só o PCR).
const limiteProcura = 8 << 20;

/// O relógio do PCR (27 MHz).
const relogioPcr = 27000000;

/// Um PCR mais para trás do que isto não é uma repetição: o canal recomeçou (não se compara).
const recuoMaximoPcr = 120 * relogioPcr;

/// Depois do ponto do PCR, até onde se espera por um início de PES do vídeo.
const _limitePes = 1 << 20;

/// O PCR dá a volta aos 33 bits da base (× 300 da extensão).
const _voltaPcr = (1 << 33) * 300;

/// Tipos de stream de vídeo na PMT (MPEG-1/2, MPEG-4, H.264, H.265, AVS, VC-1 e afins).
const _tiposVideo = {0x01, 0x02, 0x10, 0x1B, 0x24, 0x42, 0xD1, 0xEA};

/// `a − b` em PCR, com a volta do relógio: positivo se `a` vem depois de `b`.
int diferencaPcr(int a, int b) {
  var d = (a - b) % _voltaPcr;
  if (d >= _voltaPcr ~/ 2) d -= _voltaPcr;
  return d;
}

/// Um pacote lido: a `posicao` (desde o começo do que se deu ao [LeitorTs]), o PID, se começa uma
/// unidade (`payload_unit_start_indicator`) e o PCR (só no PID do PCR).
typedef PacoteTs = ({int posicao, int pid, bool inicioUnidade, int? pcr});

/// Lê um MPEG-TS aos pedaços: sincroniza num `0x47` que se repete 188 bytes depois, acha a PMT pela
/// PAT, o PID do PCR e do vídeo pela PMT (ou o PID do PCR no primeiro pacote que o leve) e guarda o
/// último PCR. Só as secções que cabem num pacote (o normal na PAT e na PMT).
class LeitorTs {
  LeitorTs({this.pidPmt, this.pidPcr, this.pidVideo});

  int? pidPmt;
  int? pidPcr;
  int? pidVideo;

  /// O último PCR lido no [pidPcr].
  int? ultimoPcr;

  /// A posição do primeiro pacote lido (null: ainda não sincronizou).
  int? primeiroPacote;

  /// Pacotes lidos.
  int pacotes = 0;

  /// A posição a seguir ao último byte dado.
  int _posicao = 0;

  /// O começo de um pacote (ou de um candidato a sincronia) que ainda não chegou todo.
  Uint8List _resto = Uint8List(0);
  bool _aSincronizar = true;
  bool _pidPcrDaPmt = false;

  /// A posição do próximo pacote por ler (o que vem antes já foi lido ou não é TS).
  int get lidoAte => _posicao - _resto.length;

  /// Uma ligação nova (que não continua os bytes da anterior): larga o pacote a meio e volta a
  /// procurar a sincronia. Os PIDs e o último PCR ficam.
  void novaLigacao() {
    _resto = Uint8List(0);
    _aSincronizar = true;
  }

  /// Lê mais bytes. Se `aoPacote` devolver true, pára (o resto destes bytes fica por ler).
  void ler(List<int> dados, [bool Function(PacoteTs)? aoPacote]) {
    final List<int> b;
    if (_resto.isEmpty) {
      b = dados;
    } else {
      b = Uint8List(_resto.length + dados.length)
        ..setRange(0, _resto.length, _resto)
        ..setRange(_resto.length, _resto.length + dados.length, dados);
    }
    final desde = _posicao - _resto.length; // a posição de b[0]
    _posicao += dados.length;
    var i = 0;
    while (true) {
      if (_aSincronizar) {
        while (i < b.length) {
          if (b[i] == 0x47) {
            if (i + pacoteTs >= b.length) break; // falta ver o pacote seguinte
            if (b[i + pacoteTs] == 0x47) break;
          }
          i++;
        }
        if (i + pacoteTs >= b.length) {
          _guardarResto(b, i);
          return;
        }
        _aSincronizar = false;
      }
      if (i + pacoteTs > b.length) {
        _guardarResto(b, i);
        return;
      }
      if (b[i] != 0x47) {
        _aSincronizar = true; // perdeu a sincronia
        continue;
      }
      final p = _pacote(b, i, desde + i);
      i += pacoteTs;
      if (aoPacote != null && aoPacote(p)) {
        _resto = Uint8List(0);
        return;
      }
    }
  }

  void _guardarResto(List<int> b, int i) {
    _resto = i >= b.length ? Uint8List(0) : Uint8List.fromList(b.sublist(i));
  }

  PacoteTs _pacote(List<int> b, int i, int posicao) {
    pacotes++;
    primeiroPacote ??= posicao;
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
    if (inicio && controlo & 1 != 0 && carga < i + pacoteTs) {
      if (pid == 0) {
        _pat(b, carga, i + pacoteTs);
      } else if (pid == pidPmt) {
        _pmt(b, carga, i + pacoteTs);
      }
    }
    return (posicao: posicao, pid: pid, inicioUnidade: inicio, pcr: pcr);
  }

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
    if (pcr != 0x1FFF && (pidPcr == null || !_pidPcrDaPmt)) {
      pidPcr = pcr;
      _pidPcrDaPmt = true;
    }
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

  /// Pelo PCR: o que tinha PCR até ao último gravado ficou de fora.
  pcr,

  /// O primeiro PCR da ligação nova já passava o último gravado: grava-se inteira.
  salto,

  /// Não se conseguiu coser (sem PCR legível, não é TS, o canal recomeçou): grava-se inteira.
  inteira,
}

class DecisaoCostura {
  const DecisaoCostura(this.modo, this.desde, {this.sincronia, this.motivo});

  final ModoCostura modo;

  /// Grava-se a partir desta posição da ligação nova.
  final int desde;

  /// O primeiro pacote da ligação nova (null: não se achou), para o alinhamento.
  final int? sincronia;

  /// Porque não se coseu ([ModoCostura.inteira]), para o registo (sem dados da ligação).
  final String? motivo;

  @override
  String toString() => 'DecisaoCostura($modo, $desde)';
}

/// Procura a costura à medida que a ligação nova chega. Até haver [decisao] não se grava nada; quem
/// a usa guarda os bytes recebidos a partir de [descartavelAte] (no máximo cerca de [limite] bytes,
/// mais um pedaço).
class ProcuraCostura {
  ProcuraCostura({
    required List<int> cauda,
    this.ultimoPcr,
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
  final int limite;

  final Uint8List _cauda;
  late final Int32List _falhas;
  final LeitorTs _leitor;
  late bool _procurarBytes;

  /// Quantos bytes da cauda coincidem agora (Knuth–Morris–Pratt).
  int _coincide = 0;

  /// Já passou um PCR (de qualquer valor) na ligação nova.
  bool _viuPcr = false;

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
      final ate = math.min(dados.length, limite - ini);
      for (var k = 0; k < ate; k++) {
        final c = dados[k];
        var j = _coincide;
        while (j > 0 && _cauda[j] != c) {
          j = _falhas[j - 1];
        }
        if (_cauda[j] == c) j++;
        if (j == _cauda.length) {
          return _decidir(DecisaoCostura(ModoCostura.bytes, ini + k + 1));
        }
        _coincide = j;
      }
      if (recebidos >= limite) _procurarBytes = false;
    }
    _leitor.ler(dados, _aoPacote);
    if (decisao != null) return decisao;
    if (_leitor.primeiroPacote == null && recebidos >= 4 * pacoteTs) {
      return _decidir(const DecisaoCostura(ModoCostura.inteira, 0, motivo: 'não parece MPEG-TS'));
    }
    if (recebidos >= limite && (ultimoPcr == null || !_viuPcr)) {
      // sem a cauda até ao limite e sem PCR com que comparar
      return _decidir(DecisaoCostura(ModoCostura.inteira, 0,
          sincronia: _leitor.primeiroPacote,
          motivo: ultimoPcr == null ? 'sem PCR no que estava gravado' : 'PCR ilegível na ligação nova'));
    }
    if (!_procurarBytes && _viuPcr) {
      // a cauda já não aparece e tudo o que veio até aqui tinha PCR até ao último gravado: é velho
      descartavelAte = _ponto ?? _leitor.lidoAte;
    }
    return null;
  }

  /// A ligação nova acabou sem decisão: decide-se com o que veio.
  DecisaoCostura terminar() {
    final d = decisao;
    if (d != null) return d;
    final ponto = _ponto;
    if (ponto != null) return _decidir(DecisaoCostura(ModoCostura.pcr, ponto));
    if (_leitor.primeiroPacote == null) {
      return _decidir(DecisaoCostura(ModoCostura.inteira, 0, motivo: recebidos == 0 ? null : 'não parece MPEG-TS'));
    }
    if (ultimoPcr != null && _viuPcr) {
      return _decidir(DecisaoCostura(ModoCostura.pcr, recebidos)); // tudo velho: nada a gravar
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
    final pcr = p.pcr, ultimo = ultimoPcr;
    if (pcr != null && ultimo != null) {
      final d = diferencaPcr(pcr, ultimo);
      if (d < -recuoMaximoPcr) {
        _decidir(DecisaoCostura(ModoCostura.inteira, 0,
            sincronia: _leitor.primeiroPacote, motivo: 'PCR muito para trás (o canal recomeçou)'));
        return true;
      }
      if (_ponto == null && d > 0) {
        if (!_viuPcr) {
          _decidir(DecisaoCostura(ModoCostura.salto, 0, sincronia: _leitor.primeiroPacote));
          return true;
        }
        _ponto = p.posicao;
        _procurarBytes = false; // a cauda já não aparece: vinha antes deste PCR
      }
    }
    if (pcr != null) _viuPcr = true;
    final ponto = _ponto;
    if (ponto == null) return false;
    final video = _leitor.pidVideo;
    if (video == null || p.posicao - ponto >= math.min(limite, _limitePes)) {
      _decidir(DecisaoCostura(ModoCostura.pcr, ponto));
      return true;
    }
    if (p.pid == video && p.inicioUnidade) {
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

/// Onde começar a gravar `novo` depois de um gravado cujo último PCR é `ultimoPcr`: o primeiro
/// início de PES do vídeo a partir do primeiro pacote com PCR maior (ou esse pacote, sem PID de
/// vídeo); 0 se a ligação começa já à frente; `novo.length` se é toda velha; null se o PCR não se
/// lê (ou recuou demais).
int? costuraPorPcr(int ultimoPcr, List<int> novo, {int? pidPcr, int? pidVideo}) {
  final p = ProcuraCostura(cauda: const [], ultimoPcr: ultimoPcr, pidPcr: pidPcr, pidVideo: pidVideo);
  final d = p.receber(novo) ?? p.terminar();
  return d.modo == ModoCostura.inteira ? null : d.desde;
}
