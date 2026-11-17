import 'package:flutter/foundation.dart';

import 'configuracao_mpv.dart';
import 'relogio_direto.dart';

/// Recuar/avançar 10 s e "Voltar ao direto" num canal em direto, com o cache do mpv (seek
/// relativo: o mpv não sai do que tem no cache). O [RelogioDireto] fica com o atraso que o mpv
/// fez de facto (lido do `time-pos`). Nunca lança: devolve um aviso para mostrar, ou null.
class SaltosDireto {
  SaltosDireto(this.mpv, this.relogio, {this.esperar = const Duration(milliseconds: 400)});

  final MotorMpv mpv;
  final RelogioDireto relogio;

  /// Quanto se espera pelo seek antes de ler a posição nova.
  final Duration esperar;
  static const salto = Duration(seconds: 10);

  /// Depois de um salto o cache ainda se está a ajustar: não se acerta o atraso por ele.
  static const _calma = Duration(seconds: 2);
  DateTime? _ultimoSalto;

  Future<double?> _posicao() async => double.tryParse(await mpv.getProperty('time-pos'));

  Future<void> _seek(String segundos) async {
    _ultimoSalto = relogio.agora;
    await mpv.command(['seek', segundos, 'relative']);
  }

  static String _s(Duration d) => (d.inMicroseconds / 1e6).toStringAsFixed(3);

  Future<String?> recuar() async {
    try {
      final antes = await _posicao();
      await _seek('-${salto.inSeconds}');
      if (esperar > Duration.zero) await Future<void>.delayed(esperar);
      final depois = await _posicao();
      var recuou = salto;
      if (antes != null && depois != null) {
        // o que tocou durante a espera também conta
        final tocou = relogio.pausado ? 0.0 : esperar.inMicroseconds / 1e6 * relogio.velocidade;
        final s = (antes + tocou - depois).clamp(0.0, salto.inSeconds + 1.0);
        recuou = Duration(milliseconds: (s * 1000).round());
      }
      if (recuou < const Duration(seconds: 1)) return 'Não há mais para recuar';
      relogio.recuou(recuou);
    } catch (e) {
      debugPrint('mpv: recuar falhou ($e)');
    }
    return null;
  }

  Future<String?> avancar() async {
    final d = relogio.avancoPossivel(salto);
    if (d < const Duration(milliseconds: 500)) return 'Já está em direto';
    try {
      await _seek(_s(d));
      relogio.avancou(d);
    } catch (e) {
      debugPrint('mpv: avançar falhou ($e)');
    }
    return null;
  }

  Future<void> voltarAoDireto() async {
    final d = relogio.atraso;
    if (d < const Duration(milliseconds: 500)) return;
    try {
      await _seek(_s(d));
      relogio.voltouAoDireto();
    } catch (e) {
      debugPrint('mpv: voltar ao direto falhou ($e)');
    }
  }

  /// O atraso não passa do que há no buffer à frente (depois de a rede parar, por exemplo).
  Future<void> acertarPeloBuffer() async {
    final ultimo = _ultimoSalto;
    if (ultimo != null && relogio.agora.difference(ultimo) < _calma) return;
    try {
      final s = double.tryParse(await mpv.getProperty('demuxer-cache-duration'));
      if (s == null || s <= 0.5) return; // a abrir/sem dados: não diz nada
      relogio.limitar(Duration(milliseconds: (s * 1000).round()));
    } catch (_) {
      // o player fechou entretanto
    }
  }
}
