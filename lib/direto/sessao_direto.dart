/// Uma sessão do direto gravado: um [GravadorDireto] e um [ServidorDireto] para um canal.
///
/// O player abre o canal pela sessão ([SessaoDireto.abrir]) e o motor toca o URL local; recuar e
/// avançar são reaberturas do motor noutro `desde=`. Ao mudar de canal, sair ou dar erro, o player
/// chama [SessaoDireto.fechar]: pára o gravador, apaga a pasta e fecha o servidor. Nunca há duas
/// sessões ao mesmo tempo.
///
/// Nunca se regista o URL de origem, os cabeçalhos, nem o código do servidor local.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:path_provider/path_provider.dart';

import '../modelo/canal.dart';
import '../rede/http.dart';
import '../verificar/video.dart' show syncTs;
import 'gravador.dart';
import 'servidor.dart';

/// Cria a sessão de um canal (uma por canal aberto). null no player: sem gravação.
typedef CriarSessaoDireto = SessaoDireto Function();

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

/// A reserva por omissão (até a preferência existir): 2 GB.
const reservaPorOmissao = 2 << 30;

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

/// A sessão de produção: grava em `getApplicationCacheDirectory()/direto/<sessão>`, com a reserva
/// por omissão (a preferência e o espaço livre vêm depois).
SessaoDireto criarSessaoArmazenamento() => SessaoGravada(
      pastaBase: () async => Directory('${(await getApplicationCacheDirectory()).path}${Platform.pathSeparator}direto'),
      reservaBytes: reservaPorOmissao,
    );

class SessaoGravada implements SessaoDireto {
  SessaoGravada({
    required this.pastaBase,
    required this.reservaBytes,
    this.tamanhoBloco = 16 << 20,
    this.agora,
    @visibleForTesting this.abrirOrigem,
    @visibleForTesting this.esperar,
  });

  final Future<Directory> Function() pastaBase;
  final int reservaBytes;
  final int tamanhoBloco;
  /// O relógio do índice de tempo (por omissão o de parede).
  final DateTime Function()? agora;

  /// Só para os testes: a origem falsa e as esperas entre ligações.
  final Future<Stream<List<int>>> Function(Uri, Map<String, String>)? abrirOrigem;
  final Future<void> Function(Duration)? esperar;

  GravadorDireto? _g;
  ServidorDireto? _s;
  bool _fechada = false;
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
    if (_g != null) throw StateError('a sessão já foi aberta');
    if (_fechada) return null;
    final GravadorDireto g;
    try {
      final base = await pastaBase();
      if (_fechada) return null;
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
        pasta: Directory('${base.path}${Platform.pathSeparator}${_nomeSessao()}'),
        reservaBytes: reservaBytes,
        tamanhoBloco: tamanhoBloco,
        agora: agora,
        abrir: abrirOrigem,
        esperar: esperar,
      );
    } catch (e) {
      debugPrint('direto gravado: a sessão não começou (${e.runtimeType}); toca a origem');
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
      if (e.desistiu && !decisao.isCompleted) {
        decisao.completeError(ErroSessaoDireto(semSegredos(e.mensagem)));
      } else if (!e.desistiu && g.fim > 0) {
        decidir(); // a ligação acabou com menos do que a amostra (uma playlist é pequena)
      }
    }));
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
  }
}
