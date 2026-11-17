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
    required this.desentrelacamentoAtivo,
    required this.reamostraRitmo,
  });

  /// 64 MiB para a frente e 64 MiB para trás (recuar no direto, Task 5).
  static const bufferBytes = 64 * 1024 * 1024;

  /// A saída de vídeo e a descodificação (vão no `VideoControllerConfiguration`).
  final String vo;
  final String hwdec;

  /// Propriedades do mpv a pôr antes do primeiro `open()`.
  final Map<String, String> propriedades;

  /// O desentrelaçamento do mpv está mesmo ligado (não se mostra "ligado" quando não teria
  /// efeito).
  final bool desentrelacamentoAtivo;

  /// Pede-se `video-sync=display-resample` (o mpv acerta o ritmo do vídeo ao do ecrã). Só tem
  /// efeito se o mpv souber os Hz do ecrã; o diagnóstico verifica-o em tempo real
  /// ([AmostraMpv.reamostraAtiva]) em vez de confiar neste pedido.
  final bool reamostraRitmo;

  PlayerConfiguration get configuracaoPlayer => const PlayerConfiguration(bufferSize: bufferBytes);

  VideoControllerConfiguration get configuracaoVideo => VideoControllerConfiguration(vo: vo, hwdec: hwdec);

  /// Com `mediacodec_embed` as imagens nunca passam pelo mpv: o filtro de desentrelaçamento
  /// não se aplica (o descodificador de hardware do aparelho é que trata das imagens
  /// entrelaçadas). Nos outros casos aplica-se.
  static bool desentrelacamentoTemEfeito(PlataformaVideo p, ModoDescodificacao modo) =>
      !(p == PlataformaVideo.android && modo == ModoDescodificacao.direto);

  factory ConfiguracaoMpv.para(
    PlataformaVideo p, {
    ModoDescodificacao modo = ModoDescodificacao.direto,
    bool desentrelacar = false,
  }) {
    final String vo;
    final String hwdec;
    switch (p) {
      case PlataformaVideo.android:
        // (também no emulador: o media_kit forçaria lá software com vo=gpu, mas o emulador da
        // Android TV não cria o contexto GLES do mpv — "Video: no video" — e o descodificador
        // goldfish do emulador funciona com o mediacodec_embed)
        if (modo == ModoDescodificacao.direto) {
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
        hwdec = 'auto-safe';
    }
    final reamostra = p != PlataformaVideo.android;
    final temEfeito = desentrelacamentoTemEfeito(p, modo);
    final desentrelaca = desentrelacar && temEfeito;
    return ConfiguracaoMpv._(
      vo: vo,
      hwdec: hwdec,
      desentrelacamentoAtivo: desentrelaca,
      reamostraRitmo: reamostra,
      propriedades: {
        // buffer para direto: com cache=yes o mpv junta até cache-secs (20 s) à frente; o
        // demuxer-readahead-secs só conta se o cache estiver desligado
        'cache': 'yes',
        'demuxer-readahead-secs': '10',
        'cache-secs': '20',
        'demuxer-max-bytes': '$bufferBytes',
        'demuxer-max-back-bytes': '$bufferBytes',
        // junta 2 s antes de começar: evita engasgos logo no arranque
        'cache-pause-initial': 'yes',
        'cache-pause-wait': '2',
        'network-timeout': '15',
        // cortes curtos na ligação não param o canal
        'stream-lavf-o': 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5',
        'framedrop': 'vo',
        if (p == PlataformaVideo.android) 'ao': 'audiotrack,opensles',
        if (reamostra) 'video-sync': 'display-resample',
        // "auto": só desentrelaça as imagens marcadas como entrelaçadas
        if (temEfeito) 'deinterlace': desentrelaca ? 'auto' : 'no',
      },
    );
  }
}

/// Põe as propriedades no mpv do `player` (antes do primeiro `open()`).
Future<void> aplicarConfiguracao(Player player, ConfiguracaoMpv c) async {
  final mpv = player.platform;
  if (mpv is! NativePlayer) return;
  try {
    for (final e in c.propriedades.entries) {
      await mpv.setProperty(e.key, e.value);
    }
    if (c.desentrelacamentoAtivo && await mpv.getProperty('deinterlace') != 'auto') {
      // libmpv antigo sem deinterlace=auto: o mesmo efeito com o filtro (só imagens entrelaçadas)
      await mpv.setProperty('vf', 'lavfi=[bwdif=deint=interlaced]');
      debugPrint('mpv: deinterlace=auto indisponível; a usar bwdif=deint=interlaced');
    }
  } catch (e) {
    // o player fechou entretanto; uma configuração a menos nunca impede o canal de abrir
    debugPrint('mpv: configuração não aplicada ($e)');
  }
}
