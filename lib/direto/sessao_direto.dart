/// Uma sessão do direto gravado: um [GravadorDireto] e um [ServidorDireto] para um canal.
///
/// O player abre o canal pela sessão ([SessaoDireto.abrir]) e o motor toca o URL local; recuar e
/// avançar são reaberturas do motor noutro `desde=`. Ao mudar de canal, sair ou dar erro, o player
/// chama [SessaoDireto.fechar]: pára o gravador, apaga a pasta e fecha o servidor. Nunca há duas
/// sessões ao mesmo tempo, nem entre dois players seguidos: a fila do processo
/// ([SessaoGravada.abrir] espera que a anterior feche).
///
/// Nunca se regista o URL de origem, os cabeçalhos, nem o código do servidor local.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:path_provider/path_provider.dart';

import '../dados/preferencias.dart';
import '../modelo/canal.dart';
import '../rede/http.dart';
import '../verificar/video.dart' show syncTs;
import 'armazem.dart';
import 'espaco.dart';
import 'gravador.dart';
import 'servidor.dart';

/// Cria a sessão de um canal (uma por canal aberto). null no player: sem gravação. `memoria`: o
/// recuo em Memória (ou o armazenamento acabou neste canal): grava num anel de blocos em RAM.
typedef CriarSessaoDireto = SessaoDireto Function({required bool memoria});

/// O gravador desistiu antes de o canal começar: a mensagem é para o utilizador e não tem o URL.
class ErroSessaoDireto implements Exception, ErroLegivel {
  const ErroSessaoDireto(this.mensagem);
  @override
  final String mensagem;
  @override
  String toString() => mensagem;
}

/// O que o player usa de uma sessão (os testes dão uma falsa).
abstract interface class SessaoDireto {
  /// Começa a gravar `fonte` e devolve o URL local do direto; null se o stream não é um MPEG-TS
  /// (uma playlist HLS, um ficheiro) ou a gravação não pôde começar: o player abre a origem. Lança
  /// [ErroSessaoDireto] se o gravador desistir antes de haver dados. `renovar`: o link para cada
  /// religação do gravador (no Stalker um link novo; sem ele, o mesmo `fonte`).
  Future<Uri?> abrir(FonteVideo fonte, {Future<FonteVideo> Function()? renovar});

  /// Depois do [abrir], o aviso do espaço para o utilizador: a reserva baixou («Pouco espaço: o
  /// recuo fica com N MB»), ou não há espaço para o disco e grava-se em memória ([avisoMemoria]).
  String? get aviso;

  /// O [abrir] chegou a ligar à origem. Falso quando deu null sem ligar (a sessão não começou):
  /// o link ainda está por usar.
  bool get ligouOrigem;

  /// O URL para ver a partir de `posicao` (bytes desde o início da sessão).
  Uri urlDesde(int posicao);

  /// O URL do direto (a [posicaoDireto]).
  Uri get urlDireto;

  /// A posição onde o [urlDireto] começa ([atrasoDireto] antes do fim).
  int get posicaoDireto;

  /// A posição de há `recuo` (limitada ao início do gravado).
  int posicaoHa(Duration recuo);

  /// Há quanto tempo chegou o byte em `posicao`.
  Duration recuoDe(int posicao);

  /// O tempo gravado disponível (do mais antigo ao direto).
  Duration get janela;

  Stream<ErroGravador> get erros;

  /// O novo fim a cada escrita do gravador.
  Stream<int> get crescimento;

  /// Pára o gravador, apaga a pasta e fecha o servidor (pode chamar-se mais de uma vez).
  Future<void> fechar();
}

/// Quanto atrás do fim começa o direto local.
const atrasoDireto = ServidorDireto.atrasoDireto;

/// O aviso quando o armazenamento não chega (no começo ou a meio) e o recuo passa à memória.
const avisoMemoria = 'Pouco espaço: o recuo fica em memória (cerca de 2 min em HD)';

/// A memória do recurso quando o armazenamento não chega: 128 MiB.
const reservaMemoriaRecurso = 128 << 20;

/// O recuo em Memória (a opção das Definições): 128 MiB no Android (TV e telemóvel), 256 MiB no
/// Windows.
int get reservaMemoriaPlataforma => Platform.isWindows ? 256 << 20 : 128 << 20;

/// Os blocos em memória: mais pequenos do que no disco (a janela roda em passos de 8 MiB).
const blocoMemoria = 8 << 20;

/// Só os diretos progressivos passam pelo gravador: nem HLS (`.m3u8`, `extension=m3u8`), nem
/// filmes e séries (Xtream `/movie/`, `/series/`, extensões de ficheiro).
bool gravavel(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || (u.scheme != 'http' && u.scheme != 'https') || u.host.isEmpty) return false;
  final caminho = u.path.toLowerCase();
  if (caminho.endsWith('.m3u8') || caminho.endsWith('.m3u') || caminho.endsWith('.mpd')) return false;
  const ficheiros = [
    '.mp4', '.mkv', '.avi', '.mov', '.m4v', '.webm', '.flv', '.wmv', '.mpg', '.mpeg', '.mp3', '.aac', '.m4a', '.ogg',
  ];
  if (ficheiros.any(caminho.endsWith)) return false;
  // filmes, séries e o timeshift do Xtream (também com um prefixo no caminho)
  final seg = u.pathSegments.map((s) => s.toLowerCase()).toList();
  if (seg.any((s) => s == 'movie' || s == 'series' || s == 'timeshift')) return false;
  for (final v in u.queryParameters.entries) {
    final k = v.key.toLowerCase(), valor = v.value.toLowerCase();
    if ((k == 'extension' || k == 'output' || k == 'type') && (valor == 'm3u8' || valor == 'hls')) return false;
  }
  return true;
}

/// A pasta de todas as sessões: `direto/` na cache da app (o Android também a pode limpar e
/// apaga-a ao desinstalar).
Future<Directory> pastaDireto({Directory? cache}) async =>
    Directory('${(cache ?? await getApplicationCacheDirectory()).path}${Platform.pathSeparator}direto');

/// No arranque: apaga o que ficou em `direto/` de um fecho à força. Salta as pastas de sessões
/// vivas (o ficheiro [ArmazemDisco.nomeBloqueio] bloqueado por outro processo: a janela do player
/// do Windows pode arrancar com outra ainda a gravar). Nunca lança.
Future<void> limparDireto({Directory? cache}) async {
  try {
    final d = await pastaDireto(cache: cache);
    if (!await d.exists()) return;
    await for (final e in d.list(followLinks: false)) {
      try {
        if (e is Directory && await _sessaoViva(e)) continue;
        await e.delete(recursive: true);
      } on FileSystemException catch (x) {
        debugPrint('direto gravado: uma sobra não foi apagada (código ${x.osError?.errorCode ?? '?'})');
      }
    }
    try {
      await d.delete(); // vazia: sai também (com uma sessão viva fica)
    } on FileSystemException {
      // ainda tem a sessão viva
    }
  } catch (e) {
    debugPrint('direto gravado: a pasta não foi limpa no arranque (${e.runtimeType})');
  }
}

/// A pasta é de uma sessão a gravar noutro processo: o bloqueio dela não se consegue.
Future<bool> _sessaoViva(Directory pasta) async {
  final f = File('${pasta.path}${Platform.pathSeparator}${ArmazemDisco.nomeBloqueio}');
  if (!await f.exists()) return false;
  RandomAccessFile? raf;
  try {
    raf = await f.open(mode: FileMode.append);
    await raf.lock(FileLock.exclusive);
    await raf.unlock();
    return false;
  } on FileSystemException {
    return true;
  } finally {
    await raf?.close();
  }
}

/// Fecha as sessões abertas do processo (a fila de [SessaoGravada]): o gravado apaga-se e a origem
/// fica livre. Para a janela do player do Windows antes do `exit` (a janela principal fechou).
/// Nunca lança.
Future<void> fecharSessoesDireto() async {
  try {
    await SessaoGravada._fecharTodas();
  } catch (e) {
    debugPrint('direto gravado: as sessões não fecharam bem (${e.runtimeType})');
  }
}

/// A sessão de produção. Em disco: `direto/<sessão>` na cache, com a reserva das Definições
/// ([Preferencias.reservaDiretoGb]) ajustada ao espaço livre do aparelho. Em `memoria`: um anel em
/// RAM de [reservaMemoriaPlataforma].
SessaoDireto criarSessaoDireto({required bool memoria}) => SessaoGravada(
      pastaBase: pastaDireto,
      reservaBytes: memoria ? reservaMemoriaPlataforma : Preferencias.atual.reservaDiretoGb << 30,
      memoria: memoria,
      espacoLivre: espacoLivre,
    );

class SessaoGravada implements SessaoDireto {
  SessaoGravada({
    required this.pastaBase,
    required this.reservaBytes,
    this.tamanhoBloco = 16 << 20,
    this.memoria = false,
    this.tamanhoBlocoMemoria = blocoMemoria,
    this.reservaMemoria = reservaMemoriaRecurso,
    this.agora,
    this.espacoLivre,
    @visibleForTesting this.abrirOrigem,
    @visibleForTesting this.esperar,
  });

  final Future<Directory> Function() pastaBase;

  /// A reserva pedida (a das Definições, ou a da memória com [memoria]); a usada é
  /// [reservaEfetiva].
  final int reservaBytes;
  final int tamanhoBloco;

  /// Grava em memória desde o começo (o recuo em Memória): nem pasta nem espaço livre.
  final bool memoria;

  /// O tamanho dos blocos em memória.
  final int tamanhoBlocoMemoria;

  /// A memória do recurso quando o armazenamento não chega.
  final int reservaMemoria;

  /// O espaço livre do aparelho: ajusta a reserva ao começar ([reservaPara]) e protege a margem a
  /// cada bloco. null: não se mede (a reserva toda).
  final EspacoLivre? espacoLivre;
  /// O relógio do índice de tempo (por omissão o de parede).
  final DateTime Function()? agora;

  /// Só para os testes: a origem falsa e as esperas entre ligações.
  final Future<Stream<List<int>>> Function(Uri, Map<String, String>)? abrirOrigem;
  final Future<void> Function(Duration)? esperar;

  /// Quanto a sessão nova espera que a anterior feche antes de a fechar ela.
  @visibleForTesting
  static Duration esperaAnterior = const Duration(seconds: 10);

  /// A última sessão que começou a abrir, de qualquer player do processo. As sessões fazem uma
  /// fila: cada uma só cria a pasta e liga à origem depois de a anterior ter fechado (um player que
  /// sai fecha a sua depois de largar o motor, e o seguinte já pode estar a abrir). Nunca há duas
  /// sessões nem duas ligações à origem.
  static SessaoGravada? _ultima;

  /// A sessão antes desta na fila (null depois de ela fechar).
  SessaoGravada? _anterior;
  bool _naFila = false;

  /// Esta sessão e as anteriores na fila fecharam.
  final _fechadaToda = Completer<void>();

  /// Fecha todas as sessões da fila e espera por elas.
  static Future<void> _fecharTodas() async {
    final u = _ultima;
    if (u == null) return;
    for (SessaoGravada? s = u; s != null; s = s._anterior) {
      unawaited(s.fechar());
    }
    await u._fechadaToda.future;
  }

  /// Espera que esta sessão (e as anteriores) feche; passado [esperaAnterior], fecha-as.
  Future<void> _esperarFecho() async {
    try {
      await _fechadaToda.future.timeout(esperaAnterior);
    } on TimeoutException {
      debugPrint('direto gravado: a sessão anterior não fechou a tempo; fecha-se agora');
      for (SessaoGravada? s = this; s != null; s = s._anterior) {
        unawaited(s.fechar());
      }
      await _fechadaToda.future;
    }
  }

  GravadorDireto? _g;
  ServidorDireto? _s;
  bool _fechada = false;
  String? _aviso;
  bool _ligou = false;
  int? _reserva;

  @override
  String? get aviso => _aviso;

  @override
  bool get ligouOrigem => _ligou;

  /// A reserva que o gravador usa (a pedida, ou menos por falta de espaço).
  @visibleForTesting
  int? get reservaEfetiva => _reserva;

  /// O gravador escreve em memória (pedido, ou por falta de espaço).
  @visibleForTesting
  bool get emMemoria => _emMemoria;
  bool _emMemoria = false;

  /// O armazém do gravador (para os testes verem a memória usada).
  @visibleForTesting
  ArmazemBlocos? get armazem => _g?.armazem;
  Future<void>? _fecho;
  final _erros = StreamController<ErroGravador>.broadcast();
  final _crescimento = StreamController<int>.broadcast();
  final _subs = <StreamSubscription>[];

  /// Quantos bytes se juntam para ver se é um MPEG-TS.
  static const _amostra = 4 * GravadorDireto.pacote;

  GravadorDireto get _gravador => _g ?? (throw StateError('a sessão não está aberta'));

  static String _nomeSessao() {
    final r = math.Random.secure();
    return 's${DateTime.now().microsecondsSinceEpoch}_${r.nextInt(1 << 32).toRadixString(16)}';
  }

  @override
  Future<Uri?> abrir(FonteVideo fonte, {Future<FonteVideo> Function()? renovar}) async {
    if (_g != null || _naFila) throw StateError('a sessão já foi aberta');
    if (_fechada) return null;
    // a fila do processo: a anterior (de outro player, também) fecha antes de esta começar
    _naFila = true;
    final anterior = _anterior = _ultima;
    _ultima = this;
    if (anterior != null) {
      await anterior._esperarFecho();
      if (_fechada) return null;
    }
    final GravadorDireto g;
    try {
      // em disco: a reserva conforme o espaço livre; sem espaço nem para o mínimo, a memória
      var emMemoria = memoria;
      var reserva = reservaBytes;
      Directory? pasta;
      EspacoLivre? medir;
      if (!emMemoria) {
        final base = await pastaBase();
        if (_fechada) return null;
        medir = espacoLivre;
        if (medir != null) {
          final r = reservaPara(reservaBytes, await medir(base), tamanhoBloco: tamanhoBloco);
          if (_fechada) return null;
          if (r == null) {
            debugPrint('direto gravado: sem espaço para a reserva mínima; o recuo fica em memória');
            _aviso = avisoMemoria;
            emMemoria = true;
            reserva = reservaMemoria;
          } else {
            if (r < reservaBytes) _aviso = 'Pouco espaço: o recuo fica com ${r >> 20} MB';
            reserva = r;
          }
        }
        if (!emMemoria) pasta = Directory('${base.path}${Platform.pathSeparator}${_nomeSessao()}');
      }
      _reserva = reserva;
      _emMemoria = emMemoria;
      final noDisco = pasta;
      final medirDisco = medir;
      var primeira = true;
      g = GravadorDireto(
        origem: Uri.parse(fonte.url),
        cabecalhos: fonte.headers,
        // a primeira ligação usa o link já pedido; cada religação pede outro
        obterOrigem: () async {
          final f = primeira || renovar == null ? fonte : await renovar();
          primeira = false;
          return (Uri.parse(f.url), f.headers);
        },
        armazem: noDisco == null ? ArmazemMemoria(tamanhoBlocoMemoria) : ArmazemDisco(noDisco),
        reservaBytes: reserva,
        tamanhoBloco: noDisco == null ? tamanhoBlocoMemoria : tamanhoBloco,
        agora: agora,
        abrir: abrirOrigem,
        esperar: esperar,
        espacoLivre: noDisco == null || medirDisco == null ? null : () => medirDisco(noDisco),
      );
    } catch (e) {
      debugPrint('direto gravado: a sessão não começou (${e.runtimeType}); toca a origem');
      await fechar(); // a seguinte na fila não fica à espera desta
      return null;
    }
    _g = g;
    // é TS? decide-se com os primeiros bytes (ou com o que veio, se a ligação acabou antes)
    final decisao = Completer<bool?>();
    void decidir() {
      if (decisao.isCompleted) return;
      g.ler(0, _amostra).then((b) {
        if (!decisao.isCompleted) decisao.complete(b != null && syncTs(b) != null);
      }, onError: (Object _) {
        if (!decisao.isCompleted) decisao.complete(false);
      });
    }

    _subs.add(g.crescimento.listen((fim) {
      if (!_crescimento.isClosed) _crescimento.add(fim);
      if (fim >= _amostra) decidir();
    }, onDone: () {
      if (!decisao.isCompleted) decisao.complete(null);
    }));
    _subs.add(g.erros.listen((e) {
      if (!_erros.isClosed) _erros.add(e);
      if (e.semEspaco && !decisao.isCompleted) {
        // o espaço acabou logo no primeiro bloco: a origem está boa, o player toca-a
        debugPrint('direto gravado: sem espaço logo no começo; toca a origem');
        decisao.complete(null);
      } else if (e.desistiu && !decisao.isCompleted) {
        decisao.completeError(ErroSessaoDireto(semSegredos(e.mensagem)));
      } else if (!e.desistiu && g.fim > 0) {
        decidir(); // a ligação acabou com menos do que a amostra (uma playlist é pequena)
      }
    }));
    _ligou = true;
    try {
      await g.iniciar();
    } catch (e) {
      debugPrint('direto gravado: o gravador não começou (${e.runtimeType}); toca a origem');
      await fechar();
      return null;
    }
    final bool? ts;
    try {
      ts = await decisao.future;
    } on ErroSessaoDireto {
      await fechar();
      rethrow;
    }
    if (_fechada) return null;
    if (ts != true) {
      if (ts == false) debugPrint('direto gravado: não é MPEG-TS; toca a origem');
      await fechar();
      return null;
    }
    try {
      final s = await ServidorDireto.iniciar(g);
      if (_fechada) {
        await s.fechar();
        return null;
      }
      _s = s;
      return s.urlDireto;
    } catch (e) {
      debugPrint('direto gravado: o servidor local não começou (${e.runtimeType}); toca a origem');
      await fechar();
      return null;
    }
  }

  ServidorDireto get _servidor => _s ?? (throw StateError('a sessão não está aberta'));

  @override
  Uri urlDesde(int posicao) => _servidor.urlDesde(posicao);

  @override
  Uri get urlDireto => _servidor.urlDesde(posicaoDireto);

  @override
  int get posicaoDireto => _gravador.posicaoHa(atrasoDireto);

  @override
  int posicaoHa(Duration recuo) => _gravador.posicaoHa(recuo);

  @override
  Duration recuoDe(int posicao) => _gravador.recuoDe(posicao);

  @override
  Duration get janela => _g?.janela ?? Duration.zero;

  /// O fim do gravado (bytes).
  int get fim => _g?.fim ?? 0;

  @override
  Stream<ErroGravador> get erros => _erros.stream;

  @override
  Stream<int> get crescimento => _crescimento.stream;

  @override
  Future<void> fechar() => _fecho ??= _fechar();

  Future<void> _fechar() async {
    _fechada = true;
    try {
      await _s?.fechar();
    } catch (_) {}
    try {
      await _g?.parar();
    } catch (e) {
      debugPrint('direto gravado: o gravador não parou bem (${e.runtimeType})');
    }
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    await _erros.close();
    await _crescimento.close();
    // fechada só quando as anteriores na fila também fecharam
    final anterior = _anterior;
    if (anterior != null) await anterior._esperarFecho();
    _anterior = null;
    if (identical(_ultima, this)) _ultima = null;
    _fechadaToda.complete();
  }
}
