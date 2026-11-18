import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Onde o player corre (decide a saída de vídeo e a descodificação).
enum PlataformaVideo {
  android,
  windows,
  outra;

  static PlataformaVideo get atual =>
      Platform.isAndroid ? android : (Platform.isWindows ? windows : outra);
}

/// Como o Android descodifica o vídeo (preferência do utilizador; a Task 5 mostra-a nas
/// definições do player).
enum ModoDescodificacao {
  /// `vo=mediacodec_embed` + `hwdec=mediacodec`: o descodificador de hardware desenha
  /// diretamente na superfície do vídeo, sem cópias (o mais leve num Fire TV Stick).
  direto('direto', 'Direta (recomendada)'),

  /// `vo=gpu` + `hwdec=mediacodec-copy`: as imagens voltam à memória e passam pelo mpv
  /// (permite filtros como o desentrelaçamento do mpv; mais pesado). Para aparelhos onde o
  /// direto mostra ecrã preto ou cores erradas.
  compativel('compativel', 'Compatível');

  const ModoDescodificacao(this.nome, this.rotulo);

  /// O nome guardado nas preferências.
  final String nome;

  /// O texto mostrado ao utilizador.
  final String rotulo;

  static ModoDescodificacao deNome(String? n) =>
      values.firstWhere((m) => m.nome == n, orElse: () => direto);
}

/// A configuração do mpv para o player de canais em direto, por plataforma e modo.
/// Não toca em nenhum player: só diz o que pôr (para se poder testar).
class ConfiguracaoMpv {
  const ConfiguracaoMpv._({
    required this.vo,
    required this.hwdec,
    required this.propriedades,
    required this.reamostraRitmo,
  });

  /// 64 MiB para a frente e 64 MiB para trás. Para trás é o que se pode recuar num direto:
  /// cerca de 1½–2 min num canal HD a 5 Mb/s, uns 4 min num SD a 2 Mb/s. Valor escolhido como
  /// meio-termo com a memória de um Fire TV Stick (1 GB): no máximo 128 MiB por player.
  static const bufferBytes = 64 * 1024 * 1024;

  /// Quanto o mpv continua a ler à frente (limitado pelos 64 MiB). Num direto só há à frente o
  /// que já chegou, por isso a tocar normalmente não muda nada; depois de recuar ou pausar, o
  /// mpv continua a receber o canal (até aos 64 MiB) e "Voltar ao direto" chega lá com um seek.
  /// Numa pausa mais longa do que os 64 MiB (~1–2 min em HD) o mpv deixa de ler; aí "Voltar ao
  /// direto" reabre o canal (`SaltosDireto.voltarAoDireto`).
  /// Com os 20 s de antes, ao recuar mais de ~20 s o mpv deixava de ler e o canal ficava para trás.
  static const segundosAFrente = 300;

  /// A saída de vídeo e a descodificação (vão no `VideoControllerConfiguration`).
  final String vo;
  final String hwdec;

  /// Propriedades do mpv a pôr antes do primeiro `open()`.
  final Map<String, String> propriedades;

  /// Pede-se `video-sync=display-resample` (o mpv acerta o ritmo do vídeo ao do ecrã). Só tem
  /// efeito se o mpv souber os Hz do ecrã; o diagnóstico verifica-o em tempo real
  /// ([AmostraMpv.reamostraAtiva]) em vez de confiar neste pedido.
  final bool reamostraRitmo;

  PlayerConfiguration get configuracaoPlayer => const PlayerConfiguration(bufferSize: bufferBytes);

  VideoControllerConfiguration get configuracaoVideo => VideoControllerConfiguration(vo: vo, hwdec: hwdec);

  /// Com `mediacodec_embed` as imagens nunca passam pelo mpv: o filtro de desentrelaçamento
  /// não se aplica (o descodificador de hardware do aparelho é que trata das imagens
  /// entrelaçadas). Nos outros casos aplica-se (o desentrelaçamento é posto a cada canal, em
  /// `aplicar_preferencias.dart`).
  static bool desentrelacamentoTemEfeito(PlataformaVideo p, ModoDescodificacao modo, {bool hardware = true}) =>
      !(p == PlataformaVideo.android && modo == ModoDescodificacao.direto && hardware);

  /// `hardware: false`: descodificação por software (preferência para aparelhos com problemas;
  /// no Android passa a `vo=gpu`, como o "Compatível").
  factory ConfiguracaoMpv.para(
    PlataformaVideo p, {
    ModoDescodificacao modo = ModoDescodificacao.direto,
    bool hardware = true,
  }) {
    final String vo;
    final String hwdec;
    switch (p) {
      case PlataformaVideo.android:
        // (também no emulador: o media_kit forçaria lá software com vo=gpu, mas o emulador da
        // Android TV não cria o contexto GLES do mpv — "Video: no video" — e o descodificador
        // goldfish do emulador funciona com o mediacodec_embed)
        if (!hardware) {
          vo = 'gpu';
          hwdec = 'no';
        } else if (modo == ModoDescodificacao.direto) {
          vo = 'mediacodec_embed';
          hwdec = 'mediacodec';
        } else {
          vo = 'gpu';
          hwdec = 'mediacodec-copy';
        }
      case PlataformaVideo.windows:
      case PlataformaVideo.outra:
        // no Windows o media_kit desenha numa textura do Flutter pela API de render do mpv:
        // a única saída que fica dentro da janela é a "libmpv" (com "gpu" o mpv abria uma
        // janela sua por cima). A libmpv usa o mesmo renderizador que a "gpu".
        vo = 'libmpv';
        hwdec = hardware ? 'auto-safe' : 'no';
    }
    final reamostra = p != PlataformaVideo.android;
    return ConfiguracaoMpv._(
      vo: vo,
      hwdec: hwdec,
      reamostraRitmo: reamostra,
      propriedades: {
        // buffer para direto: com cache=yes o mpv junta até cache-secs à frente (ver
        // segundosAFrente; limitado pelos demuxer-max-bytes); o demuxer-readahead-secs só conta
        // se o cache estiver desligado
        'cache': 'yes',
        'demuxer-readahead-secs': '10',
        'cache-secs': '$segundosAFrente',
        'demuxer-max-bytes': '$bufferBytes',
        'demuxer-max-back-bytes': '$bufferBytes',
        // junta 2 s antes de começar: evita engasgos logo no arranque
        'cache-pause-initial': 'yes',
        'cache-pause-wait': '2',
        'network-timeout': '15',
        // sem reconexão dentro do mesmo stream (o mpv liga-a por omissão no http): o servidor
        // responde a uma ligação nova com um bloco do que já passou, os tempos recomeçam e o
        // vídeo voltava atrás dezenas de segundos; no Stalker o link nem serve duas vezes (HTTP
        // 462). O buffer toca até ao fim e o player pede o canal de novo (ContinuarDireto).
        'stream-lavf-o': 'reconnect=0,reconnect_streamed=0',
        'framedrop': 'vo',
        if (p == PlataformaVideo.android) 'ao': 'audiotrack,opensles',
        if (reamostra) 'video-sync': 'display-resample',
      },
    );
  }
}

/// Põe as propriedades no mpv (antes do primeiro `open()`).
Future<void> aplicarConfiguracao(MotorMpv mpv, ConfiguracaoMpv c) async {
  try {
    for (final e in c.propriedades.entries) {
      await mpv.setProperty(e.key, e.value);
    }
  } catch (e) {
    // o player fechou entretanto; uma configuração a menos nunca impede o canal de abrir
    debugPrint('mpv: configuração não aplicada ($e)');
  }
}

/// O que o player usa do mpv. O verdadeiro é o `MotorForaDaUi` (as chamadas ao libmpv fora da
/// thread da UI); os testes usam um falso que regista as chamadas.
abstract interface class MotorMpv {
  Future<void> setProperty(String propriedade, String valor);
  Future<String> getProperty(String propriedade);
  Future<void> setRate(double velocidade);
  Future<void> setVolume(double volume);

  /// Um comando do mpv (ex.: `['seek', '-10', 'relative']`).
  Future<void> command(List<String> comando);
}
