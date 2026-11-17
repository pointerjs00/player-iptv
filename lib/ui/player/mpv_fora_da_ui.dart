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
  /// nada (cada pedido novo ficava também preso e enchia a fila do isolate).
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

/// O [ExecutorMpv] verdadeiro: um isolate que chama o libmpv (o mesmo que o media_kit carregou),
/// um pedido de cada vez, pela ordem em que chegam.
class ExecutorIsolate implements ExecutorMpv {
  ExecutorIsolate._(this._entrada, this.limiteAbandono);
  static final instancia = ExecutorIsolate._(_principal, const Duration(seconds: 30));

  /// Com outra função no isolate (testes: um isolate que morre, lança ou fica preso).
  @visibleForTesting
  factory ExecutorIsolate.paraTestes(void Function(SendPort) entrada,
          {Duration limiteAbandono = const Duration(seconds: 30)}) =>
      ExecutorIsolate._(entrada, limiteAbandono);

  final void Function(SendPort) _entrada;

  /// Um pedido sem resposta há tanto tempo prendeu o isolate (uma chamada nativa que não volta
  /// não o faz morrer): esse isolate é abandonado e os pedidos seguintes vão para um novo, para
  /// os players seguintes não ficarem na fila atrás dele. Os pedidos dele continuam à espera
  /// (o player deles só é destruído se acabarem).
  final Duration limiteAbandono;

  Future<SendPort>? _porta;
  int _geracao = 0;
  int _proximo = 0;
  final _pendentes = <int, (int, Completer<Object?>)>{};

  void _abandonar(int geracao) {
    if (geracao != _geracao) return;
    _geracao++;
    _porta = null;
  }

  Future<SendPort> _iniciar() async {
    final geracao = _geracao;
    final respostas = ReceivePort('mpv-respostas');
    final pronto = Completer<SendPort>();
    void morreu(Object motivo) {
      // os pedidos que lá estavam nunca terão resposta: falham já; o próximo arranca outro
      _abandonar(geracao);
      respostas.close();
      final ids = [for (final e in _pendentes.entries) if (e.value.$1 == geracao) e.key];
      for (final id in ids) {
        _pendentes.remove(id)!.$2.completeError(StateError('o isolate do mpv parou ($motivo)'));
      }
      if (!pronto.isCompleted) pronto.completeError(StateError('o isolate do mpv não arrancou ($motivo)'));
    }

    respostas.listen((m) {
      if (m is SendPort) {
        if (!pronto.isCompleted) pronto.complete(m);
      } else if (m is (int, Object?, String?)) {
        final (id, valor, erro) = m;
        final c = _pendentes.remove(id)?.$2;
        if (c == null) return;
        erro == null ? c.complete(valor) : c.completeError(StateError(erro));
      } else if (m is List) {
        morreu(m.isEmpty ? 'erro' : m.first); // onError: [erro, pilha]
      } else if (m == null) {
        morreu('saiu'); // onExit
      }
    });
    try {
      await Isolate.spawn(_entrada, respostas.sendPort,
          debugName: 'mpv', onError: respostas.sendPort, onExit: respostas.sendPort);
    } catch (e) {
      morreu(e);
    }
    return pronto.future;
  }

  Future<Object?> _pedir(String op, int handle, List<String> args) async {
    final iniciar = _porta ??= _iniciar();
    final SendPort porta;
    try {
      porta = await iniciar;
    } catch (_) {
      if (identical(_porta, iniciar)) _porta = null;
      rethrow;
    }
    final id = _proximo++;
    final c = Completer<Object?>();
    final geracao = _geracao;
    _pendentes[id] = (geracao, c);
    porta.send((id, op, handle, args));
    final vigia = Timer(limiteAbandono, () {
      if (!c.isCompleted) _abandonar(geracao);
    });
    return c.future.whenComplete(vigia.cancel);
  }

  @override
  Future<void> setProperty(int handle, String propriedade, String valor) =>
      _pedir('set', handle, [propriedade, valor]);

  @override
  Future<String> getProperty(int handle, String propriedade) async =>
      (await _pedir('get', handle, [propriedade])) as String? ?? '';

  @override
  Future<void> command(int handle, List<String> comando) => _pedir('cmd', handle, comando);

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

  /// O isolate: abre o libmpv e responde a cada pedido (id, op, handle, args).
  static void _principal(SendPort respostas) {
    final pedidos = ReceivePort('mpv-pedidos');
    respostas.send(pedidos.sendPort);
    DynamicLibrary? lib;
    late _Set set;
    late _Get get;
    late _Free free;
    late _Command command;
    pedidos.listen((m) {
      int? id;
      try {
        final (int i, String op, int handle, List<String> args) = m as (int, String, int, List<String>);
        id = i;
        if (lib == null) {
          lib = _libmpv();
          set = lib!.lookupFunction<_SetNativo, _Set>('mpv_set_property_string');
          get = lib!.lookupFunction<_GetNativo, _Get>('mpv_get_property_string');
          free = lib!.lookupFunction<_FreeNativo, _Free>('mpv_free');
          command = lib!.lookupFunction<_CommandNativo, _Command>('mpv_command');
        }
        final ctx = Pointer<Void>.fromAddress(handle);
        Object? valor;
        using((arena) {
          switch (op) {
            case 'set':
              set(ctx, args[0].toNativeUtf8(allocator: arena), args[1].toNativeUtf8(allocator: arena));
            case 'get':
              final r = get(ctx, args[0].toNativeUtf8(allocator: arena));
              if (r != nullptr) {
                try {
                  valor = r.toDartString();
                } finally {
                  free(r.cast());
                }
              }
            case 'cmd':
              final arr = arena<Pointer<Utf8>>(args.length + 1);
              for (var i = 0; i < args.length; i++) {
                arr[i] = args[i].toNativeUtf8(allocator: arena);
              }
              arr[args.length] = nullptr;
              command(ctx, arr);
          }
        });
        respostas.send((id, valor, null));
      } catch (e) {
        if (id != null) respostas.send((id, null, '$e'));
      }
    });
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
/// do media_kit faz `stop`). Cada player largado conta no máximo [limite] desde que foi largado:
/// um player preso (o `dispose` dele nunca acaba) atrasa uma abertura uma vez, nunca as seguintes.
class VezDoAudio {
  VezDoAudio({this.limite = const Duration(seconds: 4)});
  static final instancia = VezDoAudio();

  final Duration limite;
  final _largados = <Future<void>>{};

  /// `fechado` acaba quando o player largado tiver fechado o áudio (destruído).
  void largar(Future<void> fechado) {
    late final Future<void> f;
    f = fechado.then<void>((_) {}, onError: (_) {}).timeout(limite, onTimeout: () {
      debugPrint('mpv: um player largado não fechou o áudio em ${limite.inMilliseconds} ms; deixa de se esperar por ele');
    }).whenComplete(() => _largados.remove(f));
    _largados.add(f);
  }

  /// Espera que os players largados fechem o áudio (cada um no máximo [limite] desde que foi largado).
  Future<void> esperar() async {
    if (_largados.isEmpty) return;
    await Future.wait(_largados.toList());
  }
}
