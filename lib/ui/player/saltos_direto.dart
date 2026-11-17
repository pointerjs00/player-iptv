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

  Future<double?> _posicao() async => double.tryParse(await mpv.getProperty('time-pos'));

  Future<void> _seek(String segundos) async {
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
      final antes = await _posicao();
      await _seek(_s(d));
      if (esperar > Duration.zero) await Future<void>.delayed(esperar);
      final depois = await _posicao();
      var avancou = d;
      if (antes != null && depois != null) {
        // o mpv não passa do fim do cache: conta só o que avançou de facto
        final tocou = relogio.pausado ? 0.0 : esperar.inMicroseconds / 1e6 * relogio.velocidade;
        final s = (depois - antes - tocou).clamp(0.0, d.inMicroseconds / 1e6);
        avancou = Duration(milliseconds: (s * 1000).round());
      }
      relogio.avancou(avancou);
      if (avancou < const Duration(milliseconds: 500)) return 'Para chegar ao direto use "Voltar ao direto"';
    } catch (e) {
      debugPrint('mpv: avançar falhou ($e)');
    }
    return null;
  }

  /// Volta ao direto. Pelo seek só se o atraso todo estiver no buffer à frente; senão (pausa
  /// longa: o buffer encheu, o mpv deixou de ler e o canal ficou mesmo para trás; ou o buffer não
  /// se sabe) devolve [VoltaAoDireto.reabrir]: quem chama reabre o canal (link novo), a única
  /// forma de chegar ao direto verdadeiro.
  Future<VoltaAoDireto> voltarAoDireto() async {
    final d = relogio.atraso;
    if (d < const Duration(milliseconds: 500)) return VoltaAoDireto.jaEmDireto;
    try {
      final aFrente = double.tryParse(await mpv.getProperty('demuxer-cache-duration'));
      if (aFrente == null || d.inMicroseconds / 1e6 - aFrente > margemReabrir.inSeconds) {
        return VoltaAoDireto.reabrir;
      }
      await _seek(_s(d));
      relogio.voltouAoDireto();
      return VoltaAoDireto.porSeek;
    } catch (e) {
      debugPrint('mpv: voltar ao direto falhou ($e)');
      return VoltaAoDireto.reabrir;
    }
  }

  /// Quanto do atraso pode faltar no buffer à frente e ainda se voltar pelo seek (o buffer
  /// normal de um direto).
  static const margemReabrir = Duration(seconds: 3);
}

enum VoltaAoDireto { jaEmDireto, porSeek, reabrir }
