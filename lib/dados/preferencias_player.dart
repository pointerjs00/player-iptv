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

  /// Nunca lança: ficheiro em falta, estragado ou com valores de outro tipo dá os valores por
  /// omissão (um ficheiro estragado fica guardado como preferencias_player.json.bak).
  static Future<PreferenciasPlayer> carregar(Directory pasta, {required bool tv}) async {
    Object? modo;
    Object? taxa;
    final f = _ficheiro(pasta);
    try {
      if (await f.exists()) {
        var estragado = false;
        try {
          final lido = jsonDecode(await f.readAsString());
          if (lido is Map) {
            modo = lido['modoAndroid'];
            taxa = lido['ajustarTaxaEcra'];
            if ((modo != null && modo is! String) || (taxa != null && taxa is! bool)) estragado = true;
          } else {
            estragado = true;
          }
        } on FormatException {
          estragado = true;
        }
        if (estragado) await f.copy('${f.path}.bak');
      }
    } catch (_) {
      // não se lê/copia: fica-se pelos valores por omissão
    }
    return PreferenciasPlayer(
      modoAndroid: ModoDescodificacao.deNome(modo is String ? modo : null),
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
