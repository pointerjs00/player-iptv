/// Continuar um direto quando o servidor fecha a ligação.
///
/// Muitos servidores IPTV fecham a ligação ao fim de uns segundos (visto em portais Stalker a
/// cada 6–35 s) e respondem a uma ligação nova com um bloco do que já passou. Com a reconexão do
/// ffmpeg dentro do mesmo stream, esse bloco entrava a seguir ao que já se tinha visto, com os
/// tempos a recomeçar ("Invalid audio PTS: 33.0 -> 10.0", "Reset playback due to audio timestamp
/// reset"): o vídeo voltava atrás 10–25 s. Por isso o mpv não reconecta
/// (`configuracao_mpv.dart`): toca o buffer até ao fim e, só aí, o player pede o canal de novo
/// (link novo; no Stalker o link antigo já não serve) com "A carregar…" no ecrã. Nunca volta
/// atrás; salta para a frente só o tempo que demorou a reabrir.
class ContinuarDireto {
  /// Quantas vezes seguidas se continua dentro da [janela]; mais do que isso é um canal que cai
  /// sempre (o player mostra o erro em vez de pedir ao servidor sem parar).
  static const maximo = 5;
  static const janela = Duration(seconds: 60);

  final _cortes = <DateTime>[];

  /// O fim do buffer de um canal que estava a tocar: continua-se. A abrir quem decide é o vigia;
  /// com erro ou em pausa não se faz nada.
  static bool deve({required bool fimDoBuffer, required bool aAbrir, required bool erro, required bool aTocar}) =>
      fimDoBuffer && !aAbrir && !erro && aTocar;

  /// Regista um corte; falso se já houve [maximo] na [janela] (não continuar).
  bool permitir(DateTime agora) {
    _cortes.removeWhere((t) => agora.difference(t) > janela);
    if (_cortes.length >= maximo) return false;
    _cortes.add(agora);
    return true;
  }

  /// Canal novo (escolhido pelo utilizador): a contagem recomeça.
  void reiniciar() => _cortes.clear();
}
