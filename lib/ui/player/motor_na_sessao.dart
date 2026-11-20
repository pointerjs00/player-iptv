import 'package:flutter/foundation.dart';

import '../../dados/preferencias.dart';
import 'configuracao_mpv.dart';

/// O motor que abre um canal.
enum TipoMotor { mpv, exoplayer }

/// Os canais que, nesta sessão da app, abrem logo no mpv: o ExoPlayer não os conseguiu tocar (erro
/// de formato ou de descodificador) ou o utilizador pediu "Abrir em modo compatível". Só em
/// memória: a preferência não muda e os outros canais continuam no ExoPlayer.
class MotorNaSessao {
  static final instancia = MotorNaSessao();

  final _noMpv = <String>{};

  /// O motor com que o canal [chave] abre: no Android o das preferências (o mpv se o canal já
  /// passou para lá nesta sessão); nas outras plataformas sempre o mpv.
  TipoMotor para(String chave, {required PlataformaVideo plataforma, required MotorAndroid preferido}) =>
      plataforma == PlataformaVideo.android && preferido == MotorAndroid.exoplayer && !_noMpv.contains(chave)
          ? TipoMotor.exoplayer
          : TipoMotor.mpv;

  /// O canal passa a abrir no mpv; true se é a primeira vez.
  bool passarAoMpv(String chave) => _noMpv.add(chave);

  /// Esquece todos os canais (só nos testes: a sessão é a vida da app).
  @visibleForTesting
  void esquecer() => _noMpv.clear();
}
