/// Instalar a versão nova no Android: o instalador do sistema abre com o APK descarregado (o
/// utilizador confirma). Precisa da autorização «instalar apps desconhecidas» para a TVIntel.
library;

import 'dart:io';

import 'package:flutter/services.dart';

class InstaladorAndroid {
  const InstaladorAndroid([this._canal = const MethodChannel('player_iptv/atualizar')]);
  final MethodChannel _canal;

  /// Os processadores do aparelho, o preferido primeiro (Build.SUPPORTED_ABIS).
  Future<List<String>> abis() async => ((await _canal.invokeListMethod<String>('abis')) ?? const <String>[]).toList();

  /// A TVIntel já pode instalar pacotes?
  Future<bool> podeInstalar() async => (await _canal.invokeMethod<bool>('podeInstalar')) ?? false;

  /// Abre o ecrã do Android onde se autoriza; false se esse ecrã não existir neste aparelho.
  Future<bool> pedirAutorizacao() async => (await _canal.invokeMethod<bool>('pedirAutorizacao')) ?? false;

  /// Abre o instalador do sistema com `apk` (tem de estar na pasta `atualizar` da cache).
  Future<void> instalar(File apk) => _canal.invokeMethod<void>('instalar', {'caminho': apk.path});
}
