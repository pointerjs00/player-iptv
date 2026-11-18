import 'package:flutter/foundation.dart';

import 'configuracao_mpv.dart';
import 'progresso.dart' show fimProcuravel;
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

  /// Quanto se pode avançar daqui: até ao fim do intervalo do cache em que se está (o mais recente
  /// recebido; `seekable-ranges` do `demuxer-cache-state`), menos [margemFim]. Um seek exatamente
  /// até esse fim fica no cache (visto no libmpv da app), mas o seek é relativo à posição de quando
  /// chega ao mpv: a imagem anda entre a leitura e o seek, e no emulador o 3.º → seguido passou o
  /// fim ("Cannot seek in this stream"). O `demuxer-cache-duration` passava o fim até ~1,6 s
  /// ("Cached seek not possible"), por isso só serve sem o cache-state, com
  /// [margemSemCacheState]. null: não se sabe.
  Future<double?> _aFrente() async {
    final pos = await _posicao();
    if (pos == null) return null;
    final fim = fimProcuravel(await mpv.getProperty('demuxer-cache-state'), pos);
    if (fim != null) {
      final m = fim - pos - margemFim.inMicroseconds / 1e6;
      return m < 0 ? 0 : m;
    }
    final d = double.tryParse(await mpv.getProperty('demuxer-cache-duration'));
    if (d == null) return null;
    final m = d - margemSemCacheState.inMicroseconds / 1e6;
    return m < 0 ? 0 : m;
  }

  /// Quanto fica antes do fim do buffer (o que a imagem anda entre ler o fim e o seek chegar ao mpv).
  static const margemFim = Duration(milliseconds: 500);

  /// Sem o `demuxer-cache-state`, quanto fica antes do fim pela duração à frente.
  static const margemSemCacheState = Duration(seconds: 1);

  /// Abaixo disto à frente já se está no fim do buffer.
  static const _minimo = Duration(milliseconds: 500);

  static Duration _duracao(double s) => Duration(microseconds: (s * 1e6).round());

  Future<void> _seek(String segundos) async {
    await mpv.command(['seek', segundos, 'relative']);
  }

  static String _s(Duration d) => (d.inMicroseconds / 1e6).toStringAsFixed(3);

  Future<String?> recuar() => _recuar(salto, '-${salto.inSeconds}');

  Future<String?> avancar() => _avancar(salto);

  /// Vai para `alvo` (segundos do `time-pos`; a barra de progresso). Sempre pelo seek relativo
  /// destes saltos: dentro do cache, sem reabrir o canal, e o [relogio] conta o que o mpv andou de
  /// facto. Menos de 1 s (ou sem posição) não faz nada: abaixo disso o recuar diria "Não há mais
  /// para recuar".
  Future<String?> irPara(double alvo) async {
    final double? agora;
    try {
      agora = await _posicao();
    } catch (e) {
      debugPrint('mpv: ir para $alvo falhou ($e)');
      return null;
    }
    if (agora == null) return null;
    final d = Duration(microseconds: ((alvo - agora) * 1e6).round());
    if (d.abs() < const Duration(seconds: 1)) return null;
    return d.isNegative ? _recuar(-d, '-${_s(-d)}') : _avancar(d);
  }

  Future<String?> _recuar(Duration pedido, String segundos) async {
    try {
      final antes = await _posicao();
      await _seek(segundos);
      if (esperar > Duration.zero) await Future<void>.delayed(esperar);
      final depois = await _posicao();
      var recuou = pedido;
      if (antes != null && depois != null) {
        // o que tocou durante a espera também conta
        final tocou = relogio.pausado ? 0.0 : esperar.inMicroseconds / 1e6 * relogio.velocidade;
        final s = (antes + tocou - depois).clamp(0.0, pedido.inMicroseconds / 1e6 + 1.0);
        recuou = Duration(milliseconds: (s * 1000).round());
      }
      if (recuou < const Duration(seconds: 1)) return 'Não há mais para recuar';
      relogio.recuou(recuou);
    } catch (e) {
      debugPrint('mpv: recuar falhou ($e)');
    }
    return null;
  }

  /// Avança até `pedido`, nunca para lá do fim do buffer (o mais recente recebido). O relógio já
  /// não limita: o servidor pode ter mandado mais à frente do que o "direto" que o relógio conta
  /// (um portal mandou 28 s de uma vez), e o utilizador pode querer ir para o mais recente. Quando
  /// a imagem chega ao fim do buffer o mpv espera por dados (o indicador de buffering).
  Future<String?> _avancar(Duration pedido) async {
    final double? aFrente;
    try {
      aFrente = await _aFrente();
    } catch (e) {
      debugPrint('mpv: avançar falhou ($e)');
      return null;
    }
    final d = aFrente == null ? pedido : (pedido < _duracao(aFrente) ? pedido : _duracao(aFrente));
    if (d < _minimo) return 'Já está no fim do buffer';
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
      if (avancou < _minimo) return 'Já está no fim do buffer';
    } catch (e) {
      debugPrint('mpv: avançar falhou ($e)');
    }
    return null;
  }

  /// Volta ao direto: até ao fim do buffer (o mais recente recebido, que pode estar à frente do
  /// direto que o relógio conta). Pelo seek só se o atraso todo estiver no buffer à frente; senão
  /// (pausa longa: o buffer encheu, o mpv deixou de ler e o canal ficou mesmo para trás; ou o
  /// buffer não se sabe) devolve [VoltaAoDireto.reabrir]: quem chama reabre o canal (link novo), a
  /// única forma de chegar ao direto verdadeiro.
  /// `aindaValido`: falso se entretanto se mudou de canal (não se faz nada no canal novo).
  Future<VoltaAoDireto> voltarAoDireto({bool Function()? aindaValido}) async {
    final d = relogio.atraso;
    try {
      final aFrente = await _aFrente();
      if (aindaValido != null && !aindaValido()) return VoltaAoDireto.cancelado;
      final noFim = aFrente != null && _duracao(aFrente) < _minimo;
      if (d < _minimo && (noFim || aFrente == null)) return VoltaAoDireto.jaEmDireto;
      if (aFrente == null || d.inMicroseconds / 1e6 - aFrente > margemReabrir.inSeconds) {
        return VoltaAoDireto.reabrir;
      }
      if (!noFim) await _seek(aFrente.toStringAsFixed(3));
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

enum VoltaAoDireto { jaEmDireto, porSeek, reabrir, cancelado }
