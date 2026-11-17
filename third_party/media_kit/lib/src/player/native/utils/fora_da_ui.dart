// player-iptv: ficheiro acrescentado à cópia local do media_kit (ver README.player-iptv.md).
//
// As funções síncronas do libmpv (mpv_set_property*, mpv_get_property*, mpv_hook_continue,
// mpv_initialize, mpv_terminate_destroy…) esperam pelo núcleo do mpv. Se ele deixar de responder,
// a thread que chamou fica presa. No Android a UI do Flutter corre na thread principal: presa mais
// de 5 s, o sistema mata a app (ANR). Por isso estas chamadas correm aqui, cada uma num isolate
// próprio (`Isolate.run`): um mpv preso só prende esse isolate, nunca a UI nem os outros players.
import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:media_kit/ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as generated;

/// Uma chamada ao libmpv: `lib` é o caminho do libmpv, `ctx` o endereço do `mpv_handle`.
typedef ChamadaMpv<R> = R Function(String lib, int ctx, List<String> args);

/// As chamadas de cada mpv (endereço) que estão a correr noutro isolate.
final _emCurso = <int, int>{};
final _livre = <int, List<Completer<void>>>{};

/// Corre `f(lib, ctx, args)` noutro isolate (nunca na thread que chama).
Future<R> foraDaUi<R>(ChamadaMpv<R> f, String lib, int ctx, List<String> args) async {
  _emCurso[ctx] = (_emCurso[ctx] ?? 0) + 1;
  try {
    return await _correr(f, lib, ctx, args);
  } finally {
    final n = _emCurso[ctx]! - 1;
    if (n == 0) {
      _emCurso.remove(ctx);
      for (final c in _livre.remove(ctx) ?? const <Completer<void>>[]) {
        c.complete();
      }
    } else {
      _emCurso[ctx] = n;
    }
  }
}

// num função de topo: a closure só leva estes argumentos para o outro isolate
Future<R> _correr<R>(ChamadaMpv<R> f, String lib, int ctx, List<String> args) =>
    Isolate.run(() => f(lib, ctx, args), debugName: 'mpv');

/// Destrói o mpv (`destruir`, normalmente [ffiTerminateDestroy]) só quando não houver chamadas
/// dele a correr: destruí-lo com uma chamada ainda no libmpv seria usar memória libertada (crash).
/// Se uma chamada nunca acabar (mpv preso), o mpv fica por destruir.
Future<R> destruirQuandoLivre<R>(ChamadaMpv<R> destruir, String lib, int ctx) async {
  if ((_emCurso[ctx] ?? 0) > 0) {
    final c = Completer<void>();
    (_livre[ctx] ??= []).add(c);
    await c.future;
  }
  return foraDaUi(destruir, lib, ctx, const []);
}

generated.MPV _mpv(String lib) => generated.MPV(DynamicLibrary.open(lib));

Pointer<generated.mpv_handle> _ctx(int ctx) => Pointer<generated.mpv_handle>.fromAddress(ctx);

/// [nome, valor] → código de erro do mpv.
int ffiSetPropertyString(String lib, int ctx, List<String> args) {
  final mpv = _mpv(lib);
  final name = args[0].toNativeUtf8();
  final value = args[1].toNativeUtf8();
  try {
    return mpv.mpv_set_property_string(_ctx(ctx), name.cast(), value.cast());
  } finally {
    calloc.free(name);
    calloc.free(value);
  }
}

/// [nome] → valor em texto ("" se não há).
String ffiGetPropertyString(String lib, int ctx, List<String> args) {
  final mpv = _mpv(lib);
  final name = args[0].toNativeUtf8();
  try {
    final value = mpv.mpv_get_property_string(_ctx(ctx), name.cast());
    if (value == nullptr) return '';
    try {
      return value.cast<Utf8>().toDartString();
    } finally {
      mpv.mpv_free(value.cast());
    }
  } finally {
    calloc.free(name);
  }
}

/// [nome] → valor inteiro (-1 se não há).
int ffiGetPropertyInt64(String lib, int ctx, List<String> args) {
  final mpv = _mpv(lib);
  final name = args[0].toNativeUtf8();
  final value = calloc<Int64>()..value = -1;
  try {
    mpv.mpv_get_property(_ctx(ctx), name.cast(), generated.mpv_format.MPV_FORMAT_INT64, value.cast());
    return value.value;
  } finally {
    calloc.free(name);
    calloc.free(value);
  }
}

/// `http-header-fields` = args (cada um "Nome: valor"); sem args, limpa.
int ffiSetHttpHeaders(String lib, int ctx, List<String> args) {
  final mpv = _mpv(lib);
  final property = 'http-header-fields'.toNativeUtf8();
  final value = calloc<generated.mpv_node>();
  final strings = <Pointer<Utf8>>[];
  try {
    if (args.isEmpty) {
      value.ref.format = generated.mpv_format.MPV_FORMAT_NONE;
    } else {
      value.ref.format = generated.mpv_format.MPV_FORMAT_NODE_ARRAY;
      value.ref.u.list = calloc<generated.mpv_node_list>();
      value.ref.u.list.ref.num = args.length;
      value.ref.u.list.ref.values = calloc<generated.mpv_node>(args.length);
      for (int i = 0; i < args.length; i++) {
        final data = args[i].toNativeUtf8();
        strings.add(data);
        value.ref.u.list.ref.values[i].format = generated.mpv_format.MPV_FORMAT_STRING;
        value.ref.u.list.ref.values[i].u.string = data.cast();
      }
    }
    return mpv.mpv_set_property(_ctx(ctx), property.cast(), generated.mpv_format.MPV_FORMAT_NODE, value.cast());
  } finally {
    for (final s in strings) {
      calloc.free(s);
    }
    if (args.isNotEmpty) {
      calloc.free(value.ref.u.list.ref.values);
      calloc.free(value.ref.u.list);
    }
    calloc.free(property);
    calloc.free(value);
  }
}

/// [id do hook] → continua o hook (`mpv_hook_continue`).
int ffiHookContinue(String lib, int ctx, List<String> args) =>
    _mpv(lib).mpv_hook_continue(_ctx(ctx), int.parse(args[0]));

/// `mpv_terminate_destroy`.
int ffiTerminateDestroy(String lib, int ctx, List<String> args) {
  _mpv(lib).mpv_terminate_destroy(_ctx(ctx));
  return 0;
}

/// Cria e inicializa um mpv com as opções (args: nome, valor, nome, valor…); devolve o endereço.
int ffiCreate(String lib, int ctx, List<String> args) {
  final mpv = _mpv(lib);
  final handle = mpv.mpv_create();
  for (int i = 0; i + 1 < args.length; i += 2) {
    final name = args[i].toNativeUtf8();
    final value = args[i + 1].toNativeUtf8();
    mpv.mpv_set_option_string(handle, name.cast(), value.cast());
    calloc.free(name);
    calloc.free(value);
  }
  mpv.mpv_initialize(handle);
  return handle.address;
}

/// [comando] → `mpv_command_string`.
int ffiCommandString(String lib, int ctx, List<String> args) {
  final cmd = args[0].toNativeUtf8();
  try {
    return _mpv(lib).mpv_command_string(_ctx(ctx), cmd.cast());
  } finally {
    calloc.free(cmd);
  }
}
