import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
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
  final _emCurso = <Future<void>>{};
  bool _fechado = false;

  Future<T> _correr<T>(T semMpv, Future<T> Function(int handle) f) async {
    if (_fechado) return semMpv;
    final feito = Completer<void>();
    _emCurso.add(feito.future);
    try {
      final h = await _handle();
      if (h == null || _fechado) return semMpv;
      return await f(h);
    } finally {
      _emCurso.remove(feito.future);
      feito.complete();
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

  /// Antes de destruir o player: os pedidos seguintes são ignorados e espera-se pelos que já
  /// estão no mpv (nunca se usa um mpv destruído).
  Future<void> fechar() async {
    _fechado = true;
    await Future.wait(_emCurso.toList());
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
  ExecutorIsolate._();
  static final instancia = ExecutorIsolate._();

  Future<SendPort>? _porta;
  int _proximo = 0;
  final _pendentes = <int, Completer<Object?>>{};

  Future<SendPort> _iniciar() async {
    final respostas = ReceivePort('mpv-respostas');
    final pronto = Completer<SendPort>();
    respostas.listen((m) {
      if (m is SendPort) {
        pronto.complete(m);
        return;
      }
      final (int id, Object? valor, String? erro) = m as (int, Object?, String?);
      final c = _pendentes.remove(id);
      if (c == null) return;
      erro == null ? c.complete(valor) : c.completeError(StateError(erro));
    });
    await Isolate.spawn(_principal, respostas.sendPort, debugName: 'mpv');
    return pronto.future;
  }

  Future<Object?> _pedir(String op, int handle, List<String> args) async {
    final porta = await (_porta ??= _iniciar());
    final id = _proximo++;
    final c = _pendentes[id] = Completer<Object?>();
    porta.send((id, op, handle, args));
    return c.future;
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
      final (int id, String op, int handle, List<String> args) = m as (int, String, int, List<String>);
      try {
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
                valor = r.toDartString();
                free(r.cast());
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
        respostas.send((id, null, '$e'));
      }
    });
  }
}
