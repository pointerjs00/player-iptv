import 'dart:convert';
import 'dart:io';

import '../ui/player/configuracao_mpv.dart';

/// As preferências do player que afetam a fluidez (guardadas em `preferencias_player.json`).
/// A Task 5 mostra-as nas definições do player; até lá valem os valores por omissão.
class PreferenciasPlayer {
  PreferenciasPlayer({this.modoAndroid = ModoDescodificacao.direto, this.ajustarTaxaEcra = false, this.pasta});

  /// As preferências em uso (carregadas no arranque, em `main`).
  static PreferenciasPlayer atual = PreferenciasPlayer();

  static const _nome = 'preferencias_player.json';

  /// Descodificação no Android: direta (por omissão) ou "Compatível".
  ModoDescodificacao modoAndroid;

  /// "Ajustar a taxa do ecrã ao canal" (ligada por omissão na TV).
  bool ajustarTaxaEcra;

  final Directory? pasta;

  static Future<PreferenciasPlayer> carregar(Directory pasta, {required bool tv}) async {
    Map<String, Object?> j = const {};
    try {
      final f = _ficheiro(pasta);
      if (await f.exists()) {
        final lido = jsonDecode(await f.readAsString());
        if (lido is Map<String, Object?>) j = lido;
      }
    } catch (_) {
      // estragado: valores por omissão
    }
    final taxa = j['ajustarTaxaEcra'];
    return PreferenciasPlayer(
      modoAndroid: ModoDescodificacao.deNome(j['modoAndroid'] as String?),
      ajustarTaxaEcra: taxa is bool ? taxa : tv,
      pasta: pasta,
    );
  }

  Future<void> guardar() async {
    final p = pasta;
    if (p == null) return;
    final f = _ficheiro(p);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode({'modoAndroid': modoAndroid.nome, 'ajustarTaxaEcra': ajustarTaxaEcra}));
    await tmp.rename(f.path);
  }

  static File _ficheiro(Directory pasta) => File('${pasta.path}${Platform.pathSeparator}$_nome');
}
