/// Gravar um direto no armazenamento, para se poder recuar nele.
///
/// O stream (MPEG-TS por HTTP) é escrito em blocos de [GravadorDireto.tamanhoBloco] bytes numa
/// pasta da sessão. No máximo `reserva ÷ tamanhoBloco` blocos: antes de abrir um bloco novo fecha-se
/// o que estava em escrita e apaga-se o mais antigo, por isso o espaço em disco **nunca** passa da
/// reserva, contando o bloco em escrita. As posições são absolutas (bytes desde o início da sessão):
/// o bloco `n` guarda `[n × tamanhoBloco, (n + 1) × tamanhoBloco)`.
///
/// Quando a ligação à origem cai, volta a ligar e continua no mesmo ponto (o `fim` não salta), com a
/// regra de desistência do [ContinuarDireto]. [GravadorDireto.parar] apaga a pasta.
///
/// Nunca se regista o URL nem os cabeçalhos (levam utilizador, password, MAC ou token).
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../protocolos/protocolo.dart' show uaListas;
import '../rede/http.dart';
import '../ui/player/continuar_direto.dart';

/// Um problema do gravador, para o player. A mensagem já é para o utilizador e não tem o URL.
class ErroGravador {
  const ErroGravador({required this.desistiu, required this.mensagem});

  /// O gravador deixou de tentar: o canal acabou para o player.
  final bool desistiu;
  final String mensagem;

  @override
  String toString() => mensagem;
}

/// Um erro ao escrever no armazenamento (disco cheio, pasta apagada): não adianta voltar a ligar.
class _ErroEscrita implements Exception {
  _ErroEscrita(this.causa);
  final Object causa;
}

/// Um ponto do índice de tempo: o byte em `posicao` chegou em `instante`.
typedef _Marca = ({DateTime instante, int posicao});

class GravadorDireto {
  GravadorDireto({
    required this.origem,
    required this.cabecalhos,
    required this.pasta,
    required this.reservaBytes,
    this.tamanhoBloco = 16 << 20,
    DateTime Function()? agora,
    Future<Stream<List<int>>> Function(Uri, Map<String, String>)? abrir,
    Future<void> Function(Duration)? esperar,
  })  : maximoBlocos = tamanhoBloco > 0 ? reservaBytes ~/ tamanhoBloco : 0,
        _agora = agora ?? DateTime.now,
        _esperar = esperar ?? Future<void>.delayed {
    if (tamanhoBloco <= 0 || maximoBlocos < 1) {
      throw ArgumentError('a reserva tem de levar pelo menos um bloco');
    }
    _abrir = abrir ?? _abrirHttp;
  }

  final Uri origem;
  final Map<String, String> cabecalhos;
  final Directory pasta;
  final int reservaBytes;
  final int tamanhoBloco;

  /// Quantos blocos cabem na reserva (contando o que está em escrita).
  final int maximoBlocos;

  final DateTime Function() _agora;
  final Future<void> Function(Duration) _esperar;
  late final Future<Stream<List<int>>> Function(Uri, Map<String, String>) _abrir;

  /// O tamanho de um pacote MPEG-TS: as posições do índice ficam numa fronteira de pacote.
  static const pacote = 188;

  /// De quanto em quanto tempo se marca o índice dentro de um bloco.
  static const passoIndice = Duration(seconds: 1);

  final _crescimento = StreamController<int>.broadcast();
  final _erros = StreamController<ErroGravador>.broadcast();

  /// Os números dos blocos que estão no disco, do mais antigo ao que está em escrita.
  final _blocos = <int>[];
  RandomAccessFile? _aberto;
  int _noBloco = 0;
  int _fim = 0;

  /// O índice de tempo, por ordem; fica uma marca antes do [inicio] (para interpolar).
  final _indice = <_Marca>[];

  /// Onde começou cada ligação: os pacotes TS de uma ligação nova não ficam alinhados com os da
  /// anterior, por isso o alinhamento a 188 conta a partir do início da ligação.
  final _ligacoes = <int>[];

  bool _iniciado = false;
  bool _parado = false;
  HttpClient? _cliente;
  StreamSubscription<List<int>>? _leitura;
  Completer<void>? _ligacao;
  Future<void> _escrita = Future<void>.value();

  /// Exclusão entre rodar blocos (apagar o mais antigo) e ler: nunca se apaga um bloco a meio de
  /// uma leitura dele.
  Future<void> _vez = Future<void>.value();

  /// A primeira posição que ainda está no disco.
  int get inicio => _blocos.isEmpty ? _fim : _blocos.first * tamanhoBloco;

  /// A posição a seguir ao último byte gravado (o direto).
  int get fim => _fim;

  /// O novo [fim] depois de cada escrita.
  Stream<int> get crescimento => _crescimento.stream;

  Stream<ErroGravador> get erros => _erros.stream;

  /// Começa a gravar (a ligação corre em fundo; os problemas chegam por [erros]).
  Future<void> iniciar() async {
    if (_iniciado) throw StateError('o gravador já foi iniciado');
    _iniciado = true;
    await pasta.create(recursive: true);
    unawaited(_correr());
  }

  /// Pára de gravar e fecha a ligação; com `apagar` (o normal) apaga a pasta da sessão.
  Future<void> parar({bool apagar = true}) async {
    _parado = true;
    final ligacao = _ligacao;
    if (ligacao != null && !ligacao.isCompleted) ligacao.complete();
    final leitura = _leitura;
    _leitura = null;
    try {
      await leitura?.cancel();
    } catch (_) {}
    _cliente?.close(force: true);
    _cliente = null;
    try {
      await _escrita;
    } catch (_) {}
    await _exclusivo(() async {
      final f = _aberto;
      _aberto = null;
      try {
        await f?.close();
      } catch (_) {}
      if (apagar) {
        _blocos.clear();
        _indice.clear();
        try {
          if (await pasta.exists()) await pasta.delete(recursive: true);
        } on FileSystemException {
          // num Windows com o ficheiro ainda aberto por outro: tenta outra vez a seguir
          await Future<void>.delayed(const Duration(milliseconds: 100));
          if (await pasta.exists()) await pasta.delete(recursive: true);
        }
      }
    });
    if (!_crescimento.isClosed) await _crescimento.close();
    if (!_erros.isClosed) await _erros.close();
  }

  /// Até `max` bytes a partir de `desde`. Null se `desde` já foi apagado (ou o gravador parou);
  /// vazio se ainda não chegou.
  Future<List<int>?> ler(int desde, int max) => _exclusivo(() async {
        if (desde < inicio || _blocos.isEmpty) return desde >= _fim && !_parado ? const <int>[] : null;
        final int ate = math.min(_fim, desde + (max < 0 ? 0 : max));
        final saida = <int>[];
        var p = desde;
        while (p < ate) {
          final n = p ~/ tamanhoBloco;
          final noBloco = p - n * tamanhoBloco;
          final quanto = math.min(ate - p, tamanhoBloco - noBloco);
          final f = await _ficheiro(n).open();
          try {
            await f.setPosition(noBloco);
            final lido = await f.read(quanto);
            if (lido.isEmpty) break;
            saida.addAll(lido);
            p += lido.length;
          } finally {
            await f.close();
          }
        }
        return saida;
      });

  /// A posição (numa fronteira de pacote) de há `recuo`, limitada ao [inicio]: a marca do índice
  /// mais recente que já tinha chegado nesse instante.
  int posicaoHa(Duration recuo) {
    final alvo = _agora().subtract(recuo);
    var p = inicio;
    for (var i = _indice.length - 1; i >= 0; i--) {
      if (!_indice[i].instante.isAfter(alvo)) {
        p = math.max(_indice[i].posicao, inicio);
        break;
      }
    }
    return _alinhar(p);
  }

  /// Há quanto tempo chegou o byte em `posicao` (o inverso de [posicaoHa], para a barra).
  Duration recuoDe(int posicao) {
    if (posicao >= _fim || _indice.isEmpty) return Duration.zero;
    final chegou = _instanteDe(math.max(posicao, inicio));
    final r = _agora().difference(chegou);
    return r.isNegative ? Duration.zero : r;
  }

  /// O tempo gravado que está disponível (do [inicio] ao direto).
  Duration get janela => _fim > inicio ? recuoDe(inicio) : Duration.zero;

  // ---- ligação ----

  Future<void> _correr() async {
    var semProveito = 0;
    while (!_parado) {
      final comecou = _agora();
      DateTime? ultimaChegada;
      Object? falha;
      try {
        final stream = await _abrir(origem, cabecalhos);
        if (_parado) {
          unawaited(stream.listen(null).cancel().catchError((_) {}));
          break;
        }
        if (_ligacoes.isEmpty || _ligacoes.last != _fim) _ligacoes.add(_fim);
        await _consumir(stream, () => ultimaChegada = _agora());
      } catch (e) {
        falha = e;
      }
      if (_parado) break;
      if (falha is _ErroEscrita) {
        _avisar(const ErroGravador(desistiu: true, mensagem: 'não foi possível gravar no armazenamento'));
        break;
      }
      // o proveito é o tempo em que chegaram dados (uma ligação parada até ao limite não conta)
      final chegada = ultimaChegada;
      final deu = chegada == null ? Duration.zero : chegada.difference(comecou);
      semProveito = deu >= ContinuarDireto.proveito ? 0 : semProveito + 1;
      if (semProveito >= ContinuarDireto.maximoSemProveito) {
        _avisar(const ErroGravador(desistiu: true, mensagem: ContinuarDireto.desistencia));
        break;
      }
      _avisar(ErroGravador(
          desistiu: false,
          mensagem: falha == null ? 'o servidor fechou a ligação' : descreverErro(falha)));
      if (semProveito > 0) {
        final esperas = ContinuarDireto.esperas;
        await _esperar(esperas[math.min(semProveito - 1, esperas.length - 1)]);
      }
    }
  }

  void _avisar(ErroGravador e) {
    if (!_parado && !_erros.isClosed) _erros.add(e);
  }

  /// Lê a ligação até ao fim (ou erro), uma escrita de cada vez: a ligação fica em pausa enquanto
  /// se escreve, por isso nunca há mais do que um pedaço em memória.
  Future<void> _consumir(Stream<List<int>> stream, void Function() chegou) {
    final feito = Completer<void>();
    _ligacao = feito;
    void acabar([Object? erro]) {
      if (feito.isCompleted) return;
      if (erro == null) {
        feito.complete();
      } else {
        feito.completeError(erro);
      }
    }

    late final StreamSubscription<List<int>> leitura;
    leitura = stream.timeout(ContinuarDireto.limiteSemDados).listen((dados) {
      if (_parado) return;
      chegou();
      leitura.pause();
      _escrita = _escrever(dados).then((_) {
        if (!_parado) leitura.resume();
      }, onError: (Object e) {
        unawaited(leitura.cancel().catchError((_) {}));
        acabar(_ErroEscrita(e));
      });
    }, onError: (Object e) {
      unawaited(leitura.cancel().catchError((_) {}));
      acabar(e);
    }, onDone: acabar, cancelOnError: true);
    _leitura = leitura;
    return feito.future.whenComplete(() {
      if (identical(_leitura, leitura)) _leitura = null;
    });
  }

  Future<Stream<List<int>>> _abrirHttp(Uri uri, Map<String, String> cab) async {
    final cliente = _cliente ??= HttpClient()
      ..userAgent = null
      ..connectionTimeout = const Duration(seconds: 15);
    final p = await cliente.getUrl(uri).timeout(ContinuarDireto.limiteSemDados);
    p.followRedirects = true;
    p.maxRedirects = 5;
    cab.forEach((k, v) {
      if (k.toLowerCase() != 'accept-encoding') p.headers.set(k, v, preserveHeaderCase: true);
    });
    if (!cab.keys.any((k) => k.toLowerCase() == 'user-agent')) p.headers.set('User-Agent', uaListas());
    final r = await p.close().timeout(ContinuarDireto.limiteSemDados);
    if (r.statusCode >= 400) {
      unawaited(r.drain<void>().catchError((_) {}));
      throw ErroHttp(r.statusCode); // sem o URL
    }
    return r;
  }

  // ---- escrita ----

  File _ficheiro(int n) => File('${pasta.path}${Platform.pathSeparator}bloco_$n.ts');

  Future<void> _escrever(List<int> dados) async {
    final instante = _agora();
    var marcou = false;
    var i = 0;
    while (i < dados.length && !_parado) {
      if (_aberto == null || _noBloco >= tamanhoBloco) {
        await _novoBloco();
        if (_parado) return;
        _marcar(instante, _fim); // a cada bloco
        marcou = true;
      }
      if (!marcou) {
        if (_indice.isEmpty || instante.difference(_indice.last.instante) >= passoIndice) {
          _marcar(instante, _fim);
        }
        marcou = true;
      }
      final cabe = math.min(tamanhoBloco - _noBloco, dados.length - i);
      await _aberto!.writeFrom(dados, i, i + cabe);
      i += cabe;
      _noBloco += cabe;
      _fim += cabe;
    }
    if (!_parado && !_crescimento.isClosed) _crescimento.add(_fim);
  }

  void _marcar(DateTime instante, int posicao) {
    if (_indice.isNotEmpty && _indice.last.posicao == posicao) return;
    _indice.add((instante: instante, posicao: posicao));
  }

  /// Fecha o bloco em escrita, apaga os mais antigos até haver lugar e só então abre o novo:
  /// em nenhum momento há mais de [maximoBlocos] blocos no disco.
  Future<void> _novoBloco() => _exclusivo(() async {
        final anterior = _aberto;
        _aberto = null;
        await anterior?.close();
        if (_parado) return;
        while (_blocos.length >= maximoBlocos) {
          final n = _blocos.removeAt(0); // o início avança antes de o ficheiro desaparecer
          final f = _ficheiro(n);
          if (await f.exists()) await f.delete();
        }
        _podarIndice();
        final n = _fim ~/ tamanhoBloco;
        _aberto = await _ficheiro(n).open(mode: FileMode.writeOnly);
        _blocos.add(n);
        _noBloco = _fim - n * tamanhoBloco;
      });

  /// Tira do índice e das ligações o que ficou antes do [inicio], menos a última marca (precisa-se
  /// dela para saber quando chegou o próprio início).
  void _podarIndice() {
    final ini = inicio;
    var corte = 0;
    while (corte + 1 < _indice.length && _indice[corte + 1].posicao <= ini) {
      corte++;
    }
    if (corte > 0) _indice.removeRange(0, corte);
    var c = 0;
    while (c + 1 < _ligacoes.length && _ligacoes[c + 1] <= ini) {
      c++;
    }
    if (c > 0) _ligacoes.removeRange(0, c);
  }

  Future<T> _exclusivo<T>(Future<T> Function() f) {
    final anterior = _vez;
    final minha = Completer<void>();
    _vez = minha.future;
    return anterior.then((_) => f()).whenComplete(minha.complete);
  }

  // ---- índice ----

  /// A primeira fronteira de pacote em `p` ou depois, contada a partir do início da ligação a que
  /// `p` pertence (sem passar para a ligação seguinte nem do [fim]).
  int _alinhar(int p) {
    var base = 0;
    int? seguinte;
    for (var i = _ligacoes.length - 1; i >= 0; i--) {
      if (_ligacoes[i] <= p) {
        base = _ligacoes[i];
        if (i + 1 < _ligacoes.length) seguinte = _ligacoes[i + 1];
        break;
      }
    }
    final resto = (p - base) % pacote;
    final alinhado = resto == 0 ? p : p + pacote - resto;
    return math.min(alinhado, seguinte ?? _fim);
  }

  /// Quando chegou o byte em `posicao`, interpolando entre as marcas do índice.
  DateTime _instanteDe(int posicao) {
    var i = _indice.length - 1;
    while (i > 0 && _indice[i].posicao > posicao) {
      i--;
    }
    final a = _indice[i];
    if (i + 1 >= _indice.length || posicao <= a.posicao) return a.instante;
    final b = _indice[i + 1];
    final fracao = (posicao - a.posicao) / (b.posicao - a.posicao);
    final us = b.instante.difference(a.instante).inMicroseconds;
    return a.instante.add(Duration(microseconds: (us * fracao).round()));
  }
}
