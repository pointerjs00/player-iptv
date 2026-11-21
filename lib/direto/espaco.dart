/// O espaço livre do aparelho, para o direto gravado não encher o armazenamento.
///
/// Android: o método `espacoLivre` do canal `player_iptv/ficheiros` (`StatFs.availableBytes`);
/// Windows: `GetDiskFreeSpaceExW` (FFI); outros sistemas: null («não se sabe»: usa-se a reserva sem
/// margem). Nunca lança.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart';

/// O espaço livre (bytes) no disco de uma pasta; null se não se sabe. Injetável nos testes.
typedef EspacoLivre = Future<int?> Function(Directory pasta);

/// O que fica sempre livre no aparelho, além do gravado: 1 GB.
const margemEspaco = 1 << 30;

/// Com menos do que isto não se grava (o recuo fica em memória): 256 MiB.
const reservaMinima = 256 << 20;

/// A reserva a usar com `livre` bytes livres: a toda se couber com a [margemEspaco]; senão o que
/// couber (em blocos inteiros), no mínimo [reservaMinima]; null se nem isso couber. Sem saber o
/// espaço (null), a reserva toda.
int? reservaPara(int reserva, int? livre, {int tamanhoBloco = 16 << 20}) {
  if (livre == null || livre >= reserva + margemEspaco) return reserva;
  final cabe = (livre - margemEspaco) ~/ tamanhoBloco * tamanhoBloco;
  return cabe < reservaMinima ? null : cabe;
}

/// Em que sistema se mede (os testes escolhem).
@visibleForTesting
enum PlataformaEspaco { android, windows, outro }

PlataformaEspaco get _plataformaAtual => Platform.isAndroid
    ? PlataformaEspaco.android
    : Platform.isWindows
        ? PlataformaEspaco.windows
        : PlataformaEspaco.outro;

const _canal = MethodChannel('player_iptv/ficheiros');

/// O espaço livre (bytes, o que esta app pode usar) no disco de `pasta`, medido na primeira pasta
/// que existe a partir dela; null se não se sabe.
Future<int?> espacoLivre(Directory pasta, {@visibleForTesting PlataformaEspaco? plataforma}) async {
  try {
    final p = plataforma ?? _plataformaAtual;
    if (p == PlataformaEspaco.outro) return null;
    final existe = await _existente(pasta);
    switch (p) {
      case PlataformaEspaco.android:
        return await _canal.invokeMethod<int>('espacoLivre', {'pasta': existe.path});
      case PlataformaEspaco.windows:
        return _livreWindows(existe.path);
      case PlataformaEspaco.outro:
        return null;
    }
  } catch (e) {
    debugPrint('espaço livre: não se sabe (${e.runtimeType})');
    return null;
  }
}

/// A primeira pasta que existe, de `pasta` para cima.
Future<Directory> _existente(Directory pasta) async {
  var d = pasta.absolute;
  while (!await d.exists()) {
    final pai = d.parent;
    if (pai.path == d.path) break;
    d = pai;
  }
  return d;
}

typedef _GetDiskFreeSpaceExC = Int32 Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _GetDiskFreeSpaceExDart = int Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);

_GetDiskFreeSpaceExDart? _getDiskFreeSpaceEx;

/// `GetDiskFreeSpaceExW`: os bytes livres para este utilizador (conta com as quotas).
int? _livreWindows(String caminho) {
  final f = _getDiskFreeSpaceEx ??= DynamicLibrary.open('kernel32.dll')
      .lookupFunction<_GetDiskFreeSpaceExC, _GetDiskFreeSpaceExDart>('GetDiskFreeSpaceExW');
  return using((arena) {
    final livre = arena<Uint64>();
    final ok = f(caminho.toNativeUtf16(allocator: arena), livre, nullptr, nullptr);
    return ok == 0 ? null : livre.value;
  });
}
