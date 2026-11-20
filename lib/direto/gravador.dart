/// Gravar um direto no armazenamento, para se poder recuar nele.
///
/// O stream (MPEG-TS por HTTP) é escrito em blocos de [GravadorDireto.tamanhoBloco] bytes numa
/// pasta da sessão ([ArmazemDisco]) ou em memória ([ArmazemMemoria], o recuo em Memória). No máximo `reserva ÷ tamanhoBloco` blocos: antes de abrir um bloco novo fecha-se
/// o que estava em escrita e apaga-se o mais antigo, por isso o espaço em disco **nunca** passa da
/// reserva, contando o bloco em escrita. As posições são absolutas (bytes desde o início da sessão):
/// o bloco `n` guarda `[n × tamanhoBloco, (n + 1) × tamanhoBloco)`.
///
/// Quando a ligação à origem cai, volta a ligar e continua no mesmo ponto (o `fim` não salta), com a
/// regra de desistência do [ContinuarDireto]. [GravadorDireto.parar] apaga a pasta.
///
/// Com [GravadorDireto.espacoLivre] (só no disco), antes de cada bloco novo vê-se o espaço livre do
/// aparelho: sem [margemEspaco] mais um bloco, apagam-se os blocos mais antigos (medindo outra vez
/// depois de cada um) até chegar (ou até restar um); se nem assim chegar, deixa de gravar e larga a
/// origem ([ErroGravador.semEspaco]).
///
/// Cada religação cose-se à anterior ([ProcuraCostura], em `costura.dart`): há servidores que, em
/// cada ligação nova, voltam a mandar 10–30 s que já tinham mandado. Enquanto se procura o ponto
/// da costura não se grava nada; os bytes recebidos entretanto ficam em memória (no máximo
/// [limiteCostura] mais um pedaço, cerca de 8 MiB) e não contam para a reserva, porque não estão no
/// armazém. Grava-se logo que se decide.
///
/// Nunca se regista o URL nem os cabeçalhos (levam utilizador, password, MAC ou token).
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import '../protocolos/protocolo.dart' show uaListas;
import '../rede/http.dart';
import '../ui/player/continuar_direto.dart';
import '../verificar/video.dart' show syncTs;
import 'armazem.dart';
import 'costura.dart';
import 'espaco.dart' show margemEspaco;

/// Um problema do gravador, para o player. A mensagem já é para o utilizador e não tem o URL.
class ErroGravador {
  const ErroGravador({required this.desistiu, required this.mensagem, this.semEspaco = false});

  /// O gravador deixou de tentar: o canal acabou para o player.
  final bool desistiu;
  final String mensagem;

  /// Deixou de gravar por falta de espaço no aparelho, ou por outro erro do armazenamento (com
  /// [desistiu]): a origem está boa, o canal pode continuar sem o gravado (no anel em RAM).
  final bool semEspaco;

  @override
  String toString() => mensagem;
}

/// Um erro ao escrever no armazenamento (disco cheio, pasta apagada): não adianta voltar a ligar.
class _ErroEscrita implements Exception {
  _ErroEscrita(this.causa);
  final Object causa;
}

/// O aparelho ficou sem a margem de espaço livre, mesmo depois de apagar os blocos antigos.
class _SemEspaco implements Exception {}

/// Um ponto do índice de tempo: o byte em `posicao` chegou em `instante`.
typedef _Marca = ({DateTime instante, int posicao});

class GravadorDireto {
  GravadorDireto({
    required this.origem,
    required this.cabecalhos,
    this.obterOrigem,
    Directory? pasta,
    ArmazemBlocos? armazem,
    required this.reservaBytes,
    this.tamanhoBloco = 16 << 20,
    DateTime Function()? agora,
    Future<Stream<List<int>>> Function(Uri, Map<String, String>)? abrir,
    Future<void> Function(Duration)? esperar,
    this.espacoLivre,
    this.limiteCostura = limiteProcura,
  })  : maximoBlocos = tamanhoBloco > 0 ? reservaBytes ~/ tamanhoBloco : 0,
        _agora = agora ?? DateTime.now,
        _esperar = esperar ?? Future<void>.delayed,
        armazem = armazem ?? ArmazemDisco(pasta ?? (throw ArgumentError('falta a pasta ou o armazém'))) {
    if (tamanhoBloco <= 0 || maximoBlocos < 1) {
      throw ArgumentError('a reserva tem de levar pelo menos um bloco');
    }
    _abrir = abrir ?? _abrirHttp;
  }

  final Uri origem;
  final Map<String, String> cabecalhos;

  /// Se dado, a origem de cada ligação (a primeira e cada religação) vem daqui, em vez de
  /// [origem] e [cabecalhos]: os links do Stalker só servem uma vez. Uma falha conta como uma
  /// ligação falhada.
  final Future<(Uri, Map<String, String>)> Function()? obterOrigem;

  /// Onde ficam os blocos (a pasta da sessão, por omissão).
  final ArmazemBlocos armazem;
  final int reservaBytes;
  final int tamanhoBloco;

  /// Quantos blocos cabem na reserva (contando o que está em escrita).
  final int maximoBlocos;

  /// O espaço livre do aparelho (null: não se sabe), visto a cada bloco novo; sem ele, só a reserva.
  final Future<int?> Function()? espacoLivre;

  /// Até onde se procura, no começo de uma religação, o fim do que já está gravado (depois disso,
  /// só pelo PCR). É também, mais ou menos, o máximo que fica em memória enquanto se procura.
  final int limiteCostura;

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
  /// Há um bloco em escrita no [armazem].
  bool _aberto = false;
  int _noBloco = 0;
  int _fim = 0;

  /// O índice de tempo, por ordem; fica uma marca antes do [inicio] (para interpolar).
  final _indice = <_Marca>[];

  /// Onde começou cada ligação: os pacotes TS de uma ligação nova não ficam alinhados com os da
  /// anterior, por isso o alinhamento a 188 conta a partir do primeiro pacote da ligação (`base`,
  /// o primeiro `0x47` que se repete 188 bytes depois; `inicio` enquanto não se encontra).
  final _ligacoes = <({int inicio, int base})>[];

  /// O começo da ligação atual, enquanto se procura o primeiro pacote (null: já se sabe).
  BytesBuilder? _aSincronizar;

  /// O próximo pedaço é o primeiro de uma ligação: marca-se no índice.
  bool _novaLigacao = false;

  /// Até onde se procura o primeiro pacote de uma ligação.
  static const _limiteSincronizar = 4 * pacote;

  /// O que já está gravado, lido como TS: o PID do PCR e do vídeo e o último PCR, para a costura.
  final _gravado = LeitorTs();

  /// Os últimos [tamanhoCauda] bytes gravados (a procurar na ligação seguinte).
  Uint8List _cauda = Uint8List(0);

  /// A procura da costura na ligação atual (null: não há, ou já se decidiu).
  ProcuraCostura? _procura;

  /// O que chegou da ligação atual enquanto se procura (fora do armazém), a partir de
  /// [_pendenteDesde] (uma posição na ligação).
  final _pendente = <List<int>>[];
  int _pendenteDesde = 0;

  /// A regra de desistência do player ([ContinuarDireto.permitir]).
  final _regra = ContinuarDireto();

  bool _iniciado = false;
  bool _parado = false;

  /// A preparação do armazém (a pasta) em [iniciar]: o [parar] espera por ela antes de apagar.
  Future<void> _criacao = Future<void>.value();
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
    if (_parado) return; // parado antes de começar: nem se cria a pasta
    final criacao = armazem.preparar();
    _criacao = criacao.then((_) {}, onError: (_) {});
    await criacao;
    if (_parado) return; // o parar() espera pela criação e apaga a pasta
    unawaited(_correr());
  }

  /// Pára de gravar e fecha a ligação; com `apagar` (o normal) apaga a pasta da sessão.
  Future<void> parar({bool apagar = true}) async {
    _parado = true;
    _procura = null;
    _pendente.clear();
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
    await _criacao; // um iniciar() a meio: a pasta pode ainda estar a ser criada
    try {
      await _exclusivo(() async {
        _aberto = false;
        if (apagar) {
          _blocos.clear();
          _indice.clear();
        }
        await armazem.fechar(apagar: apagar);
      });
    } finally {
      if (!_crescimento.isClosed) await _crescimento.close();
      if (!_erros.isClosed) await _erros.close();
    }
  }

  /// Até `max` bytes a partir de `desde` (nunca mais do que isso, nem em memória). Null se `desde`
  /// já foi apagado (ou o gravador parou e apagou); vazio se ainda não chegou.
  Future<List<int>?> ler(int desde, int max) => _exclusivo(() async {
        if (desde < inicio || _blocos.isEmpty) return desde >= _fim && !_parado ? Uint8List(0) : null;
        final int ate = math.min(_fim, desde + (max < 0 ? 0 : max));
        final saida = BytesBuilder(copy: false);
        var p = desde;
        while (p < ate) {
          final n = p ~/ tamanhoBloco;
          final noBloco = p - n * tamanhoBloco;
          final quanto = math.min(ate - p, tamanhoBloco - noBloco);
          final lido = await armazem.ler(n, noBloco, quanto);
          if (lido.isEmpty) break;
          saida.add(lido);
          p += lido.length;
        }
        return saida.takeBytes();
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

  /// A primeira fronteira de pacote TS em `p` ou depois, contada a partir do primeiro pacote da
  /// ligação que contém `p` (nunca passa do [fim]). Para começar a enviar num pacote inteiro.
  int alinhar(int p) => _alinhar(p);

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
    var semProveito = 0; // só para escolher a espera; quem decide desistir é o [_regra]
    while (!_parado) {
      DateTime? primeiraChegada, ultimaChegada;
      Object? falha;
      try {
        final obter = obterOrigem;
        final (uri, cab) = obter == null ? (origem, cabecalhos) : await obter();
        if (_parado) break;
        final stream = await _abrir(uri, cab);
        if (_parado) {
          unawaited(stream.listen(null).cancel().catchError((_) {}));
          break;
        }
        _novaLigacao = true;
        final ultimoPcr = _gravado.ultimoPcr;
        if (_gravado.pacotes > 0 && (_cauda.length == tamanhoCauda || ultimoPcr != null)) {
          // há um TS gravado: cose-se a ligação nova ao fim dele
          _procura = ProcuraCostura(
              cauda: _cauda,
              ultimoPcr: ultimoPcr,
              pidPcr: _gravado.pidPcr,
              pidVideo: _gravado.pidVideo,
              pidPmt: _gravado.pidPmt,
              limite: limiteCostura);
          _pendente.clear();
          _pendenteDesde = 0;
        } else {
          _novaLigacaoNoAlinhamento(0);
          _aSincronizar = BytesBuilder();
        }
        await _consumir(stream, () {
          ultimaChegada = _agora();
          primeiraChegada ??= ultimaChegada;
        });
      } catch (e) {
        falha = e;
      }
      _aSincronizar = null;
      if (!_parado && falha is! _ErroEscrita) {
        // a ligação acabou a meio da procura: decide-se com o que veio
        try {
          await _terminarProcura();
        } catch (e) {
          falha = _ErroEscrita(e);
        }
      }
      _procura = null;
      _pendente.clear();
      if (_parado) break;
      if (falha is _ErroEscrita) {
        // qualquer erro do armazenamento (sem espaço, a pasta apagada pelo sistema) conta como sem
        // espaço: a origem está boa e o player passa ao anel em RAM
        final semEspaco = falha.causa is _SemEspaco;
        if (!semEspaco) {
          debugPrint('gravador do direto: erro a escrever (${falha.causa.runtimeType}); o recuo passa à memória');
        }
        _avisar(ErroGravador(
            desistiu: true,
            semEspaco: true,
            mensagem: semEspaco
                ? 'não há espaço no armazenamento para continuar a gravar'
                : 'não foi possível gravar no armazenamento'));
        break;
      }
      final primeira = primeiraChegada, ultima = ultimaChegada;
      // o fim desta ligação no índice: o corte até à próxima não se espalha pelos bytes dela
      if (ultima != null) _marcar(ultima, _fim);
      // o proveito é o tempo em que chegaram dados (nem a espera pela resposta nem uma ligação
      // parada até ao limite contam)
      final deu = primeira == null || ultima == null ? Duration.zero : ultima.difference(primeira);
      semProveito = deu >= ContinuarDireto.proveito ? 0 : semProveito + 1;
      if (!_regra.permitir(tocou: deu)) {
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
      _escrita = _receber(dados).then((_) {
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

  // ---- costura ----

  /// Um pedaço da ligação: com a procura da costura em curso, guarda-o até ela decidir.
  Future<void> _receber(List<int> dados) async {
    final procura = _procura;
    if (procura == null) return _escrever(dados);
    _pendente.add(dados);
    final d = procura.receber(dados);
    if (d != null) return _decidir(d);
    // o que já se sabe que não se grava sai da memória
    while (_pendente.isNotEmpty && _pendenteDesde + _pendente.first.length <= procura.descartavelAte) {
      _pendenteDesde += _pendente.removeAt(0).length;
    }
  }

  Future<void> _terminarProcura() async {
    final procura = _procura;
    if (procura == null) return;
    try {
      await _escrita; // o último pedaço já passou pela procura
    } catch (_) {}
    if (_parado || !identical(_procura, procura)) return;
    await _decidir(procura.terminar());
  }

  /// Grava o que vem depois do ponto da costura.
  Future<void> _decidir(DecisaoCostura d) async {
    _procura = null;
    final pendente = List.of(_pendente);
    var pos = _pendenteDesde;
    _pendente.clear();
    final recebidos = pendente.fold<int>(pos, (s, p) => s + p.length);
    switch (d.modo) {
      case ModoCostura.bytes:
        break; // os bytes continuam os da ligação anterior: o alinhamento também
      case ModoCostura.pcr when d.desde >= recebidos:
        break; // toda velha: não se grava nada, e a seguinte ainda pode continuar a anterior
      case ModoCostura.pcr:
        _novaLigacaoNoAlinhamento(0); // começa num pacote
      case ModoCostura.salto || ModoCostura.inteira:
        _novaLigacaoNoAlinhamento(d.sincronia ?? 0);
    }
    if (d.motivo != null) {
      debugPrint('gravador do direto: religação sem costura (${d.motivo}); grava-se inteira');
    }
    for (final p in pendente) {
      final de = math.max(0, d.desde - pos);
      pos += p.length;
      if (de >= p.length) continue;
      if (_parado) return;
      await _escrever(de == 0 ? p : p.sublist(de));
    }
  }

  /// A ligação atual começa no [fim] (o primeiro pacote `sincronia` bytes depois): os pacotes dela
  /// não continuam os da anterior.
  void _novaLigacaoNoAlinhamento(int sincronia) {
    if (_ligacoes.isNotEmpty && _ligacoes.last.inicio == _fim) _ligacoes.removeLast();
    _ligacoes.add((inicio: _fim, base: _fim + sincronia));
    _gravado.novaLigacao();
  }

  // ---- escrita ----

  Future<void> _escrever(List<int> dados) async {
    final instante = _agora();
    _sincronizar(dados);
    // a cada ligação nova marca-se logo, mesmo dentro do segundo da marca anterior
    var marcou = false;
    if (_novaLigacao) {
      _novaLigacao = false;
      _marcar(instante, _fim);
      marcou = true;
    }
    var i = 0;
    while (i < dados.length && !_parado) {
      if (!_aberto || _noBloco >= tamanhoBloco) {
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
      await armazem.escrever(dados, i, i + cabe);
      i += cabe;
      _noBloco += cabe;
      _fim += cabe;
    }
    if (_parado) return;
    _gravado.ler(dados);
    _guardarCauda(dados);
    if (!_crescimento.isClosed) _crescimento.add(_fim);
  }

  void _guardarCauda(List<int> dados) {
    if (dados.length >= tamanhoCauda) {
      _cauda = Uint8List.fromList(dados.sublist(dados.length - tamanhoCauda));
      return;
    }
    final fica = math.min(_cauda.length, tamanhoCauda - dados.length);
    _cauda = Uint8List(fica + dados.length)
      ..setRange(0, fica, _cauda, _cauda.length - fica)
      ..setRange(fica, fica + dados.length, dados);
  }

  /// Duas marcas na mesma posição só quando a segunda é mais tarde: o fim de uma ligação e o
  /// começo da seguinte (o byte nessa posição chegou com a ligação nova). O tempo nunca anda para
  /// trás (o que se grava depois de uma procura chegou antes de ser gravado).
  void _marcar(DateTime instante, int posicao) {
    if (_indice.isNotEmpty) {
      final ultima = _indice.last;
      if (instante.isBefore(ultima.instante)) instante = ultima.instante;
      if (ultima.posicao == posicao && !instante.isAfter(ultima.instante)) return;
    }
    _indice.add((instante: instante, posicao: posicao));
  }

  /// Procura, no começo da ligação atual, o primeiro `0x47` que se repete 188 bytes depois (o
  /// servidor pode começar a meio de um pacote) e passa a contar o alinhamento daí.
  void _sincronizar(List<int> dados) {
    final b = _aSincronizar;
    if (b == null || _ligacoes.isEmpty) return;
    final falta = _limiteSincronizar - b.length;
    b.add(dados.length <= falta ? dados : dados.sublist(0, falta));
    final visto = b.toBytes();
    final i = syncTs(visto);
    if (i != null) {
      final l = _ligacoes.removeLast();
      _ligacoes.add((inicio: l.inicio, base: l.inicio + i));
      _aSincronizar = null;
    } else if (visto.length >= _limiteSincronizar) {
      _aSincronizar = null; // não parece TS: fica o começo da ligação
    }
  }

  /// Fecha o bloco em escrita, apaga os mais antigos até haver lugar e só então abre o novo:
  /// em nenhum momento há mais de [maximoBlocos] blocos no disco. Com pouco espaço livre no
  /// aparelho apaga mais ([_guardarMargem]); lança [_SemEspaco] se nem assim chegar.
  Future<void> _novoBloco() => _exclusivo(() async {
        final havia = _aberto;
        _aberto = false;
        if (havia) await armazem.fecharAberto();
        if (_parado) return;
        while (_blocos.length >= maximoBlocos) {
          await _apagarMaisAntigo();
        }
        try {
          await _guardarMargem();
        } finally {
          _podarIndice();
        }
        final n = _fim ~/ tamanhoBloco;
        await armazem.abrir(n);
        _aberto = true;
        _blocos.add(n);
        _noBloco = _fim - n * tamanhoBloco;
      });

  /// Apaga o bloco mais antigo (o início avança antes de ele desaparecer).
  Future<void> _apagarMaisAntigo() => armazem.apagar(_blocos.removeAt(0));

  /// Antes de abrir um bloco: o aparelho tem de ficar com [margemEspaco] livres mesmo depois de o
  /// bloco novo encher, ou seja `margem + tamanhoBloco`. Se não tiver, apagam-se os blocos mais
  /// antigos, um de cada vez e medindo outra vez depois de cada um (nada de estimar), até chegar ou
  /// até restar um (o que está antes do direto); se nem assim, lança [_SemEspaco]. Nenhum bloco
  /// está aberto por um leitor ao apagar: o servidor lê por [ler], que abre e fecha o ficheiro e
  /// exclui a rotação, por isso apagar liberta logo o espaço. Sem saber o espaço, não faz nada.
  Future<void> _guardarMargem() async {
    final medir = espacoLivre;
    if (medir == null) return;
    final precisa = margemEspaco + tamanhoBloco;
    Future<int?> medida() async {
      try {
        return await medir();
      } catch (e) {
        debugPrint('gravador do direto: o espaço livre não se soube (${e.runtimeType})');
        return null;
      }
    }

    var livre = await medida();
    while (livre != null && livre < precisa && _blocos.length > 1) {
      await _apagarMaisAntigo();
      livre = await medida();
    }
    if (livre != null && livre < precisa) {
      debugPrint('gravador do direto: sem espaço no armazenamento; deixa de gravar');
      throw _SemEspaco();
    }
  }

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
    while (c + 1 < _ligacoes.length && _ligacoes[c + 1].inicio <= ini) {
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

  /// A primeira fronteira de pacote em `p` ou depois, contada a partir do primeiro pacote da
  /// ligação a que `p` pertence. Os bytes antes dele (um pacote cortado no começo da ligação) dão
  /// o primeiro pacote; um pacote cortado no fim de uma ligação dá o primeiro da seguinte. Nunca
  /// passa do [fim].
  int _alinhar(int p) {
    var i = _ligacoes.length - 1;
    while (i > 0 && _ligacoes[i].inicio > p) {
      i--;
    }
    if (i < 0) return math.min(p, _fim);
    final l = _ligacoes[i];
    final seguinte = i + 1 < _ligacoes.length ? _ligacoes[i + 1] : null;
    if (p <= l.base) return math.min(l.base, _fim);
    final resto = (p - l.base) % pacote;
    final alinhado = resto == 0 ? p : p + pacote - resto;
    if (seguinte != null && alinhado >= seguinte.inicio) return math.min(seguinte.base, _fim);
    return math.min(alinhado, _fim);
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
