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

/// O filtro de recurso: bwdif só nas imagens marcadas como entrelaçadas (o mesmo que `auto`).
const filtroDesentrelacamento = 'lavfi=[bwdif=deint=interlaced]';

/// Liga/desliga o desentrelaçamento do mpv; devolve se ficou ligado.
///
/// Ligado = `deinterlace=auto` (só as imagens entrelaçadas; mpv ≥ 0.38). A libmpv incluída
/// (0.36) não conhece `auto` e ignora-o; aí:
/// - imagens na memória (Android Compatível — `mediacodec-copy` —, software): o filtro
///   [filtroDesentrelacamento], que só toca nas imagens entrelaçadas;
/// - imagens que podem estar na GPU (Windows com hardware, `d3d11va`/`nvdec`): `deinterlace=yes`.
///   O mpv escolhe o desentrelaçador certo para o tipo de imagem (`d3d11vpp`, `bwdif_cuda`,
///   `bwdif` em software) e, se não o conseguir pôr, segue sem ele. Um filtro lavfi de software
///   à força em imagens da GPU podia deixar o vídeo sem imagem (M6 da tarefa 9).
///
/// `temEfeito: false` (Android direto: o descodificador do aparelho trata das imagens
/// entrelaçadas) não mexe no mpv. Nunca lança.
Future<bool> aplicarDesentrelacamento(MotorMpv mpv,
    {required bool ligado, required bool temEfeito, required bool imagensNaGpu}) async {
  if (!temEfeito) return false;
  try {
    if (!ligado) {
      await mpv.setProperty('deinterlace', 'no');
      await mpv.setProperty('vf', '');
      return false;
    }
    await mpv.setProperty('vf', '');
    await mpv.setProperty('deinterlace', 'auto');
    if (await mpv.getProperty('deinterlace') == 'auto') return true;
    if (imagensNaGpu) {
      await mpv.setProperty('deinterlace', 'yes');
    } else {
      await mpv.setProperty('deinterlace', 'no');
      await mpv.setProperty('vf', filtroDesentrelacamento);
    }
    debugPrint('mpv: deinterlace=auto indisponível; a usar ${imagensNaGpu ? 'deinterlace=yes' : 'bwdif'}');
    return true;
  } catch (e) {
    debugPrint('mpv: desentrelaçamento não aplicado ($e)');
    return false;
  }
}

/// As imagens descodificadas podem ficar na GPU (o filtro lavfi de software não serve)?
bool imagensNaGpu(PlataformaVideo p, {required bool hardware}) => p != PlataformaVideo.android && hardware;

/// O hwdec a pôr em tempo real (Windows); no Android fixa-se ao criar o player.
String? hwdecEmTempoReal(PlataformaVideo p, {required bool hardware}) =>
    p == PlataformaVideo.android ? null : ConfiguracaoMpv.para(p, hardware: hardware).hwdec;

/// Aplica as preferências e o estado da sessão ao mpv antes de abrir cada canal: 1×, volume,
/// silêncio, atraso do áudio, descodificação por hardware (Windows) e desentrelaçamento. Nunca
/// lança (uma propriedade a menos não impede o canal de abrir). Devolve se o desentrelaçamento
/// do mpv ficou ligado.
Future<bool> aplicarAoAbrir(MotorMpv mpv, Preferencias p, SessaoPlayer s,
    {required PlataformaVideo plataforma, required ModoDescodificacao modo}) async {
  try {
    await mpv.setRate(1.0);
    await mpv.setVolume(p.volume);
    await mpv.setProperty('mute', s.silencio ? 'yes' : 'no');
    await mpv.setProperty('audio-delay', _segundos(s.atrasoAudio));
    final hwdec = hwdecEmTempoReal(plataforma, hardware: p.hardware);
    if (hwdec != null) await mpv.setProperty('hwdec', hwdec);
  } catch (e) {
    debugPrint('mpv: preferências não aplicadas ($e)');
  }
  return aplicarDesentrelacamento(mpv,
      ligado: p.desentrelacar,
      temEfeito: ConfiguracaoMpv.desentrelacamentoTemEfeito(plataforma, modo, hardware: p.hardware),
      imagensNaGpu: imagensNaGpu(plataforma, hardware: p.hardware));
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
