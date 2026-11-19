import 'package:material_ui/material_ui.dart';

import '../../dados/preferencias.dart';
import 'configuracao_mpv.dart';

export 'configuracao_mpv.dart' show MotorMpv;

/// O que vale enquanto o player está aberto, para todos os canais, mas não se guarda.
class SessaoPlayer {
  bool silencio = false;

  /// `audio-delay` do mpv (−1 s…+1 s): positivo atrasa o som.
  Duration atrasoAudio = Duration.zero;
}

/// As velocidades da barra (a velocidade não é preferência: cada canal começa a 1×).
const velocidades = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// "0,75×", "1×".
String textoVelocidade(double v) {
  final t = v == v.roundToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', ',');
  return '$t×';
}

const limiteAtrasoAudio = Duration(seconds: 1);
const passoAtrasoAudioMs = 50;

/// Um passo (`direcao` ±1) de 50 ms, entre −1 s e +1 s.
Duration passoAtrasoAudio(Duration atual, int direcao) {
  final ms = (atual.inMilliseconds + direcao * passoAtrasoAudioMs)
      .clamp(-limiteAtrasoAudio.inMilliseconds, limiteAtrasoAudio.inMilliseconds);
  return Duration(milliseconds: ms);
}

/// "0 ms", "+150 ms", "−250 ms".
String textoAtrasoAudio(Duration d) {
  final ms = d.inMilliseconds;
  return ms == 0 ? '0 ms' : (ms > 0 ? '+$ms ms' : '−${-ms} ms');
}

String _segundos(Duration d) => (d.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(3);

/// O hwdec a pôr em tempo real (Windows); no Android fixa-se ao criar o player.
String? hwdecEmTempoReal(PlataformaVideo p, {required bool hardware}) =>
    p == PlataformaVideo.android ? null : ConfiguracaoMpv.para(p, hardware: hardware).hwdec;

/// Aplica as preferências e o estado da sessão ao mpv antes de abrir cada canal: 1×, volume,
/// silêncio, atraso do áudio e descodificação por hardware (Windows). Nunca lança (uma
/// propriedade a menos não impede o canal de abrir).
///
/// O desentrelaçamento decide-se depois, com a imagem (`controlo_desentrelacamento.dart`), nos três
/// modos (o Ligado também: o `deinterlace=yes` aqui pedia o yadif, que não existe no libmpv). Aqui o
/// Windows só fica com `deinterlace=no` (o filtro ou o d3d11vpp ligam-se depois) e, com
/// `limparFiltro`, sem o `vf` do canal anterior. `manterDesentrelacamento`: o mesmo canal reaberto
/// depois de um corte do servidor, no mesmo mpv: fica tudo como estava (nem um segundo com riscas
/// nem os filtros refeitos). `hardware`: em vez da preferência (Windows: um canal aberto "em modo
/// compatível" no cartão de erro fica por software).
Future<void> aplicarAoAbrir(MotorMpv mpv, Preferencias p, SessaoPlayer s,
    {required PlataformaVideo plataforma,
    required ModoDescodificacao modo,
    bool? hardware,
    bool limparFiltro = false,
    bool manterDesentrelacamento = false}) async {
  try {
    await mpv.setRate(1.0);
    await mpv.setVolume(p.volume);
    await mpv.setProperty('mute', s.silencio ? 'yes' : 'no');
    await mpv.setProperty('audio-delay', _segundos(s.atrasoAudio));
    final hwdec = hwdecEmTempoReal(plataforma, hardware: hardware ?? p.hardware);
    if (hwdec != null) await mpv.setProperty('hwdec', hwdec);
    if (manterDesentrelacamento) return;
    if (plataforma != PlataformaVideo.android) await mpv.setProperty('deinterlace', 'no');
    // o bwdif do canal anterior: o canal novo decide-se de novo com a imagem dele
    if (limparFiltro) await mpv.setProperty('vf', '');
  } catch (e) {
    debugPrint('mpv: preferências não aplicadas ($e)');
  }
}

/// Põe o atraso do áudio no mpv (passos do painel).
Future<void> aplicarAtrasoAudio(MotorMpv mpv, Duration d) => mpv.setProperty('audio-delay', _segundos(d));

/// Como o widget de vídeo mostra cada formato de imagem: o ajuste à caixa, um formato forçado
/// e um aumento (o "Zoom"). Feito no Flutter (e não no mpv) porque o media_kit desenha o vídeo
/// numa textura do tamanho da imagem: o `panscan`/`keepaspect` do mpv não mudavam nada.
({BoxFit fit, double? aspecto, double escala}) ajusteVideo(FormatoImagem f) => switch (f) {
      FormatoImagem.ajustar => (fit: BoxFit.contain, aspecto: null, escala: 1.0),
      FormatoImagem.preencher => (fit: BoxFit.cover, aspecto: null, escala: 1.0),
      FormatoImagem.esticar => (fit: BoxFit.fill, aspecto: null, escala: 1.0),
      FormatoImagem.r16x9 => (fit: BoxFit.contain, aspecto: 16 / 9, escala: 1.0),
      FormatoImagem.r4x3 => (fit: BoxFit.contain, aspecto: 4 / 3, escala: 1.0),
      FormatoImagem.zoom => (fit: BoxFit.contain, aspecto: null, escala: 1.25),
    };
