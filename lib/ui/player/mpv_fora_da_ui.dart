import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'configuracao_mpv.dart';

/// As chamadas diretas ao libmpv (`mpv_set_property_string`, `mpv_get_property_string`,
/// `mpv_command`) esperam pelo mpv. Com o mpv ocupado (ex.: a abrir um canal que não responde,
/// ao fazer zapping rápido) podem ficar presas segundos. No Android a UI corre na thread
/// principal (Flutter ≥ 3.29): presa mais de 5 s, o sistema mata a app (ANR). Por isso estas
/// chamadas correm aqui, num isolate à parte; a UI nunca espera pelo mpv.
abstract interface class ExecutorMpv {
  Future<void> setProperty(int handle, String propriedade, String valor);
  Future<String> getProperty(int handle, String propriedade);
  Future<void> command(int handle, List<String> comando);

  /// Várias propriedades de uma vez (na ordem pedida; "" quando o mpv não sabe).
  Future<List<String>> getProperties(int handle, List<String> propriedades);
}

/// O [MotorMpv] do player: as propriedades e os comandos pelo [ExecutorMpv] (fora da UI); a
/// velocidade e o volume pelos métodos do media_kit (que já são assíncronos).
class MotorForaDaUi implements MotorMpv {
  MotorForaDaUi({
    required this._handle,
    required this._executor,
    required this._setRate,
    required this._setVolume,
    this.limite = const Duration(seconds: 10),
  });

  /// O motor de um `Player` do media_kit (sem mpv nativo — web — não faz nada).
  factory MotorForaDaUi.doPlayer(Player player) => MotorForaDaUi(
        handle: () async {
          final mpv = player.platform;
          if (mpv is! NativePlayer) return null;
          // como o NativePlayer.setProperty: o vo do Android só fica certo com o controlador
          await mpv.waitForVideoControllerInitializationIfAttached;
          return mpv.handle;
        },
        executor: ExecutorIsolate.instancia,
        setRate: player.setRate,
        setVolume: player.setVolume,
      );

  final Future<int?> Function() _handle;
  final ExecutorMpv _executor;
  final Future<void> Function(double) _setRate;
  final Future<void> Function(double) _setVolume;

  /// Quanto quem chama espera por um pedido (o mpv ocupado ou o isolate perdido nunca prendem o
  /// player: a abertura do canal, o zapping, a saída).
  final Duration limite;

  /// Os pedidos que já estão no isolate/mpv (até acabarem de facto, mesmo depois do limite).
  final _emCurso = <Future<void>>{};
  bool _fechado = false;
  int? _handleConhecido;
  bool _semResposta = false;

  /// O mpv deste player deixou de responder (um pedido passou o [limite]): não se lhe pede mais
  /// nada (cada pedido novo ficava também preso, na fila atrás do que não voltou).
  bool get semResposta => _semResposta;

  /// O handle do mpv, se já se soube (para parar o player sem esperar por nada).
  int? get handleConhecido => _handleConhecido;

  Future<T> _correr<T>(T semMpv, Future<T> Function(int handle) f) async {
    if (_fechado || _semResposta) return semMpv;
    final int? h;
    try {
      h = await _handle().timeout(limite);
    } catch (e) {
      debugPrint('mpv: sem player pronto ($e)');
      return semMpv;
    }
    if (h == null || _fechado || _semResposta) return semMpv;
    _handleConhecido = h;
    final pedido = f(h);
    final acabou = pedido.then<void>((_) {}, onError: (_) {});
    _emCurso.add(acabou);
    unawaited(acabou.whenComplete(() => _emCurso.remove(acabou)));
    try {
      return await pedido.timeout(limite);
    } on TimeoutException catch (e) {
      _semResposta = true;
      debugPrint('mpv: pedido sem resposta; o player deixa de ser usado ($e)');
      return semMpv;
    } catch (e) {
      debugPrint('mpv: pedido falhou ($e)');
      return semMpv;
    }
  }

  @override
  Future<void> setProperty(String propriedade, String valor) =>
      _correr(null, (h) => _executor.setProperty(h, propriedade, valor));

  @override
  Future<String> getProperty(String propriedade) => _correr('', (h) => _executor.getProperty(h, propriedade));

  @override
  Future<void> command(List<String> comando) => _correr(null, (h) => _executor.command(h, comando));

  /// Várias propriedades num só pedido (um isolate em vez de um por propriedade); "" nas que o
  /// mpv não sabe, e em todas se o pedido falhar.
  Future<Map<String, String>> getProperties(List<String> propriedades) async {
    final vazio = {for (final p in propriedades) p: ''};
    final r = await _correr<List<String>?>(null, (h) => _executor.getProperties(h, propriedades));
    if (r == null || r.length != propriedades.length) return vazio;
    return {for (var i = 0; i < propriedades.length; i++) propriedades[i]: r[i]};
  }

  @override
  Future<void> setRate(double velocidade) => _fechado ? Future.value() : _setRate(velocidade);

  @override
  Future<void> setVolume(double volume) => _fechado ? Future.value() : _setVolume(volume);

  /// Os pedidos seguintes são ignorados; espera (no máximo [limite]) pelos que já estão no mpv.
  /// true se já não há nenhum (o mpv pode ser destruído).
  Future<bool> fechar() async {
    _fechado = true;
    try {
      await Future.wait(_emCurso.toList()).timeout(limite);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  /// Larga o player: pausa-o e tira-lhe o som pelo media_kit (pedidos assíncronos, não passam
  /// pelo isolate — um player que fique por destruir nunca continua a tocar) e depois
  /// [fecharEDestruir].
  Future<void> aposentar({
    required Future<void> Function() pausar,
    required Future<void> Function() silenciar,
    required Future<void> Function() destruir,
  }) async {
    _fechado = true;
    try {
      await Future.wait([pausar(), silenciar()]).timeout(limite);
    } catch (e) {
      debugPrint('mpv: não parou o player largado ($e)');
    }
    await fecharEDestruir(destruir);
  }

  /// Fecha e destrói o player (`destruir`) sem nunca prender quem chama mais do que [limite]:
  /// se um pedido ainda estiver dentro do mpv, a destruição fica para quando ele acabar (destruir
  /// antes seria usar memória já libertada; se nunca acabar, o player fica por destruir).
  Future<void> fecharEDestruir(Future<void> Function() destruir) async {
    if (await fechar()) {
      await destruir();
      return;
    }
    debugPrint('mpv: pedido ainda no mpv; o player é destruído quando ele acabar');
    unawaited(Future.wait(_emCurso.toList()).then((_) => destruir()));
  }
}

typedef _SetNativo = Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _Set = int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _GetNativo = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _Get = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _FreeNativo = Void Function(Pointer<Void>);
typedef _Free = void Function(Pointer<Void>);
typedef _CommandNativo = Int32 Function(Pointer<Void>, Pointer<Pointer<Utf8>>);
typedef _Command = int Function(Pointer<Void>, Pointer<Pointer<Utf8>>);

/// Uma chamada ao libmpv feita noutro isolate: `op` ('set', 'get', 'cmd'), o endereço do mpv e
/// os argumentos. Tem de ser uma função de topo (vai para o isolate).
typedef ChamadaNoIsolate = Object? Function(String op, int handle, List<String> args);

/// O [ExecutorMpv] verdadeiro: cada chamada ao libmpv (o mesmo que o media_kit carregou) corre
/// no seu próprio isolate (`Isolate.run`, como o `foraDaUi` do media_kit). Um mpv que deixe de
/// responder só prende o isolate dessa chamada: os pedidos dos outros players nunca ficam na fila
/// atrás dele (nem são marcados sem resposta, nem ficam por destruir por causa dele). As chamadas
/// do mesmo mpv correm uma de cada vez, pela ordem em que chegam (ex.: `mute` ligado e desligado
/// depressa); as de um mpv preso ficam atrás da presa, e o [MotorForaDaUi] desiste delas no limite.
class ExecutorIsolate implements ExecutorMpv {
  ExecutorIsolate._(this._chamada);
  static final instancia = ExecutorIsolate._(_executar);

  /// Com outra função no isolate (testes: uma chamada que faz o isolate sair, lança ou fica presa).
  @visibleForTesting
  factory ExecutorIsolate.paraTestes(ChamadaNoIsolate chamada) => ExecutorIsolate._(chamada);

  final ChamadaNoIsolate _chamada;

  /// A última chamada de cada mpv (a seguinte só começa quando ela acabar).
  final _ultima = <int, Future<void>>{};

  Future<Object?> _pedir(String op, int handle, List<String> args) {
    final anterior = _ultima[handle] ?? Future<void>.value();
    final pedido = anterior.then((_) => _noIsolate(_chamada, op, handle, args));
    final acabou = pedido.then<void>((_) {}, onError: (_) {});
    _ultima[handle] = acabou;
    unawaited(acabou.whenComplete(() {
      if (identical(_ultima[handle], acabou)) _ultima.remove(handle);
    }));
    return pedido;
  }

  @override
  Future<void> setProperty(int handle, String propriedade, String valor) =>
      _pedir('set', handle, [propriedade, valor]);

  @override
  Future<String> getProperty(int handle, String propriedade) async =>
      (await _pedir('get', handle, [propriedade])) as String? ?? '';

  @override
  Future<void> command(int handle, List<String> comando) => _pedir('cmd', handle, comando);

  @override
  Future<List<String>> getProperties(int handle, List<String> propriedades) async =>
      [for (final v in (await _pedir('getn', handle, propriedades)) as List? ?? const []) v as String? ?? ''];

  static DynamicLibrary _libmpv() {
    final nomes = Platform.isWindows ? const ['libmpv-2.dll', 'mpv-2.dll', 'mpv-1.dll'] : const ['libmpv.so'];
    Object? erro;
    for (final n in nomes) {
      try {
        return DynamicLibrary.open(n);
      } catch (e) {
        erro = e;
      }
    }
    throw StateError('libmpv não encontrado ($erro)');
  }

  /// No isolate: uma propriedade como texto (null se o mpv não a tem). As propriedades com
  /// estrutura (ex.: `demuxer-cache-state`) vêm em JSON.
  static String? _ler(DynamicLibrary lib, Pointer<Void> ctx, String propriedade, Arena arena) {
    final r = lib.lookupFunction<_GetNativo, _Get>('mpv_get_property_string')(
        ctx, propriedade.toNativeUtf8(allocator: arena));
    if (r == nullptr) return null;
    try {
      return r.toDartString();
    } finally {
      lib.lookupFunction<_FreeNativo, _Free>('mpv_free')(r.cast());
    }
  }

  /// No isolate: uma chamada ao libmpv.
  static Object? _executar(String op, int handle, List<String> args) {
    final lib = _libmpv();
    final ctx = Pointer<Void>.fromAddress(handle);
    return using((arena) {
      switch (op) {
        case 'set':
          lib.lookupFunction<_SetNativo, _Set>('mpv_set_property_string')(
              ctx, args[0].toNativeUtf8(allocator: arena), args[1].toNativeUtf8(allocator: arena));
          return null;
        case 'get':
          return _ler(lib, ctx, args[0], arena);
        case 'getn':
          return [for (final p in args) _ler(lib, ctx, p, arena)];
        case 'cmd':
          final arr = arena<Pointer<Utf8>>(args.length + 1);
          for (var i = 0; i < args.length; i++) {
            arr[i] = args[i].toNativeUtf8(allocator: arena);
          }
          arr[args.length] = nullptr;
          lib.lookupFunction<_CommandNativo, _Command>('mpv_command')(ctx, arr);
          return null;
        default:
          throw StateError('pedido desconhecido: $op');
      }
    });
  }
}

/// Corre `chamada` num isolate novo (função de topo: a closure só leva estes argumentos). Um
/// isolate que lança ou sai sem responder dá um [StateError].
Future<Object?> _noIsolate(ChamadaNoIsolate chamada, String op, int handle, List<String> args) async {
  try {
    return await Isolate.run(() => chamada(op, handle, args), debugName: 'mpv');
  } on StateError {
    rethrow;
  } catch (e) {
    throw StateError('o isolate do mpv falhou ($e)');
  }
}

typedef _SetAsyncNativo = Int32 Function(Pointer<Void>, Uint64, Pointer<Utf8>, Int32, Pointer<Void>);
typedef _SetAsync = int Function(Pointer<Void>, int, Pointer<Utf8>, int, Pointer<Void>);

_SetAsync? _setAsync;

/// Pára já um player que se vai largar: `pause=yes` e `mute=yes` pelas funções assíncronas do
/// libmpv, que só põem o pedido na fila do mpv e voltam logo (podem ser chamadas
/// na thread da UI, mesmo com o mpv ocupado ou o isolate preso). Assim um player que fique por
/// destruir não toca por trás. Sem `stop`: com uma abertura a meio, o `stop` ocupava o mpv e as
/// chamadas síncronas que o media_kit_video faz na thread da UI ao largar a superfície ficavam
/// presas (ANR visto no emulador). Nunca lança.
void pararSemEsperar(int handle) {
  try {
    if (_setAsync == null) {
      final lib = ExecutorIsolate._libmpv();
      _setAsync = lib.lookupFunction<_SetAsyncNativo, _SetAsync>('mpv_set_property_async');
    }
    final ctx = Pointer<Void>.fromAddress(handle);
    // longe dos números de pedido do media_kit (a resposta é ignorada)
    const resposta = 1 << 52;
    using((arena) {
      for (final (nome, valor) in const [('pause', 'yes'), ('mute', 'yes')]) {
        final dados = arena<Pointer<Utf8>>()..value = valor.toNativeUtf8(allocator: arena);
        _setAsync!(ctx, resposta, nome.toNativeUtf8(allocator: arena), 1 /* MPV_FORMAT_STRING */, dados.cast());
      }
    });
  } catch (e) {
    debugPrint('mpv: não parou o player ($e)');
  }
}

/// A vez do áudio entre players. A saída `audiotrack` do mpv guarda as referências JNI do
/// `AudioTrack` em variáveis globais e limpa-as quando um player fecha o áudio: se outro player
/// estiver a tocar nesse momento, a thread de áudio dele chama um método nulo e a app morre
/// ("JNI DETECTED ERROR: mid == null", visto no emulador ao sair e entrar no player). Por isso um
/// player novo só abre um canal depois de os players largados terem fechado o áudio (o `dispose`
/// do media_kit faz `stop`).
///
/// Cada player largado conta no máximo [limite] desde a primeira abertura que espera por ele (um
/// `dispose` lento que acabe depois continua a ser esperado: a ordem do áudio fica) e nunca mais
/// de [maximo] desde que foi largado. Um player preso (o `dispose` dele nunca acaba) atrasa uma
/// abertura uma vez, nunca as seguintes, e um largado há muito não atrasa ninguém.
class VezDoAudio {
  VezDoAudio({this.limite = const Duration(seconds: 4), this.maximo = const Duration(seconds: 15)});
  static final instancia = VezDoAudio();

  final Duration limite;
  final Duration maximo;
  final _largados = <_Largado>{};

  /// `fechado` acaba quando o player largado tiver fechado o áudio (destruído).
  void largar(Future<void> fechado) {
    final l = _Largado(fechado.then<void>((_) {}, onError: (_) {}), DateTime.now().add(maximo));
    _largados.add(l);
    l.esquecer = Timer(maximo, () => _largados.remove(l));
    unawaited(l.fechado.whenComplete(() {
      _largados.remove(l);
      l.esquecer?.cancel();
    }));
  }

  /// Espera que os players largados fechem o áudio (cada um no máximo [limite] desde a primeira
  /// espera por ele e [maximo] desde que foi largado).
  Future<void> esperar() async {
    if (_largados.isEmpty) return;
    final agora = DateTime.now();
    await Future.wait([
      for (final l in _largados.toList()) _esperarPor(l, agora),
    ]);
  }

  Future<void> _esperarPor(_Largado l, DateTime agora) {
    l.prazo ??= agora.add(limite);
    final fim = l.prazo!.isBefore(l.fimMaximo) ? l.prazo! : l.fimMaximo;
    final falta = fim.difference(agora);
    if (falta <= Duration.zero) {
      _largados.remove(l);
      return Future.value();
    }
    return l.fechado.timeout(falta, onTimeout: () {
      _largados.remove(l);
      l.esquecer?.cancel();
      debugPrint('mpv: um player largado não fechou o áudio a tempo; deixa de se esperar por ele');
    });
  }
}

class _Largado {
  _Largado(this.fechado, this.fimMaximo);
  final Future<void> fechado;
  final DateTime fimMaximo;

  /// O fim da espera por este player, contado da primeira abertura que esperou por ele.
  DateTime? prazo;
  Timer? esquecer;
}
