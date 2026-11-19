import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'configuracao_mpv.dart';
import 'motor_reproducao.dart';
import 'mpv_fora_da_ui.dart';

/// O [MotorReproducao] do mpv: um `Player` do media_kit com a [ConfiguracaoMpv] do direto.
///
/// (O plano chamava-lhe `MotorMpv`, mas esse nome já é a interface das propriedades do mpv em
/// `configuracao_mpv.dart`: essa é a que fica em [mpv].)
///
/// O que só existe no mpv (desentrelaçamento, modo Compatível, estatísticas e taxa do ecrã pelas
/// propriedades, seek no cache) usa [mpv]; o resto passa pela interface.
class MotorMediaKit implements MotorReproducao {
  /// Cria o player e configura o mpv (o controlador de vídeo antes de configurar: as propriedades
  /// esperam por ele).
  MotorMediaKit(this.config) : player = Player(configuration: config.configuracaoPlayer) {
    mpv = MotorForaDaUi.doPlayer(player);
    _video = VideoController(player, configuration: config.configuracaoVideo);
    configurado = aplicarConfiguracao(mpv, config);
    void tamanho(_) => _tamanho.add(tamanhoAtual);
    _subs
      ..add(player.stream.width.listen(tamanho))
      ..add(player.stream.height.listen(tamanho));
  }

  final ConfiguracaoMpv config;
  final Player player;

  /// As propriedades e os comandos do mpv, fora da thread da UI.
  late final MotorForaDaUi mpv;

  /// A configuração do mpv posta ([aplicarConfiguracao]): espera-se por ela antes de abrir.
  late final Future<void> configurado;
  late final VideoController _video;
  final _tamanho = StreamController<Size?>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];

  /// O tamanho da imagem agora (null sem imagem).
  Size? get tamanhoAtual {
    final w = player.state.width;
    return w == null ? null : Size(w.toDouble(), (player.state.height ?? 0).toDouble());
  }

  /// A duração do ficheiro (zero num direto).
  Duration get duracao => player.state.duration;

  @override
  String get nome => 'mpv';

  @override
  bool get suportaDesentrelacamento => true;

  @override
  Stream<String> get erros => player.stream.error;

  @override
  Stream<bool> get aCarregar => player.stream.buffering;

  @override
  Stream<double> get percentagemCarga => player.stream.bufferingPercentage;

  @override
  Stream<Size?> get tamanhoVideo => _tamanho.stream;

  @override
  Stream<Duration> get posicao => player.stream.position;

  @override
  Stream<void> get fim => player.stream.completed.where((c) => c).map<void>((_) {});

  @override
  Stream<FaixasMotor> get faixas => player.stream.tracks.map((t) => FaixasMotor(
        video: [for (final v in t.video) _deVideo(v)],
        audio: [for (final a in t.audio) _deAudio(a)],
        legendas: [for (final s in t.subtitle) _deLegenda(s)],
      ));

  @override
  Stream<FaixaAtual> get faixaAtual => player.stream.track.map((t) => FaixaAtual(
        video: _deVideo(t.video),
        audio: _deAudio(t.audio),
        legenda: _deLegenda(t.subtitle),
      ));

  static FaixaMotor _deVideo(VideoTrack v) => FaixaMotor(v.id, titulo: v.title, lingua: v.language, codec: v.codec, altura: v.h);
  static FaixaMotor _deAudio(AudioTrack a) => FaixaMotor(a.id, titulo: a.title, lingua: a.language, codec: a.codec);
  static FaixaMotor _deLegenda(SubtitleTrack s) => FaixaMotor(s.id, titulo: s.title, lingua: s.language, codec: s.codec);

  @override
  Future<void> abrir(String url, Map<String, String> cabecalhos, {Duration? inicio}) =>
      player.open(Media(url, httpHeaders: cabecalhos, start: inicio));

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pausar() => player.pause();

  @override
  Future<void> parar() => player.stop();

  /// A faixa do media_kit com este id (a que o mpv deu, com tudo o que traz).
  @override
  Future<void> escolherAudio(FaixaMotor faixa) => player.setAudioTrack(switch (faixa.id) {
        'auto' => AudioTrack.auto(),
        'no' => AudioTrack.no(),
        final id => player.state.tracks.audio.where((a) => a.id == id).firstOrNull ??
            AudioTrack(id, faixa.titulo, faixa.lingua),
      });

  @override
  Future<void> escolherLegenda(FaixaMotor? faixa) => player.setSubtitleTrack(switch (faixa?.id) {
        null || 'no' => SubtitleTrack.no(),
        'auto' => SubtitleTrack.auto(),
        final id => player.state.tracks.subtitle.where((s) => s.id == id).firstOrNull ??
            SubtitleTrack(id, faixa?.titulo, faixa?.lingua),
      });

  /// "Qualidade / faixa de vídeo" (só o mpv a escolhe).
  Future<void> escolherVideo(FaixaMotor faixa) => player.setVideoTrack(switch (faixa.id) {
        'auto' => VideoTrack.auto(),
        'no' => VideoTrack.no(),
        final id => player.state.tracks.video.where((v) => v.id == id).firstOrNull ??
            VideoTrack(id, faixa.titulo, faixa.lingua),
      });

  @override
  Future<void> velocidade(double v) => mpv.setRate(v);

  @override
  Future<void> volume(double v) => mpv.setVolume(v);

  @override
  Future<EstatisticasMotor> estatisticas() async {
    final m = await mpv.getProperties(const [
      'width',
      'height',
      'container-fps',
      'estimated-vf-fps',
      'video-codec',
      'frame-drop-count',
      'decoder-frame-drop-count',
      'video-bitrate',
      'demuxer-cache-duration',
    ]);
    double? n(String k) => double.tryParse(m[k]?.trim() ?? '');
    final w = n('width'), h = n('height');
    final fps = n('container-fps');
    final perdidasVo = n('frame-drop-count'), perdidasDec = n('decoder-frame-drop-count');
    final cache = n('demuxer-cache-duration');
    final codec = m['video-codec']?.trim() ?? '';
    return EstatisticasMotor(
      resolucao: w != null && h != null && w > 0 && h > 0 ? Size(w, h) : null,
      fps: fps != null && fps > 0 ? fps : n('estimated-vf-fps'),
      codec: codec.isEmpty ? null : codec,
      perdidas: perdidasVo == null && perdidasDec == null ? null : ((perdidasVo ?? 0) + (perdidasDec ?? 0)).round(),
      bitrate: n('video-bitrate'),
      buffer: cache == null ? null : Duration(microseconds: (cache * 1e6).round()),
    );
  }

  @override
  Widget video({required BoxFit ajuste, double? proporcao}) => videoMpv(ajuste: ajuste, proporcao: proporcao);

  /// O vídeo, com `envolverTextura` à volta da textura (o shader de desentrelaçamento do Android).
  Widget videoMpv({required BoxFit ajuste, double? proporcao, Widget Function(Widget textura)? envolverTextura}) =>
      Video(
        key: ObjectKey(_video),
        controller: _video,
        controls: NoVideoControls,
        fill: Colors.black,
        fit: ajuste,
        aspectRatio: proporcao,
        envolverTextura: envolverTextura,
      );

  /// Larga o player: pausa e volume 0 pelo media_kit já (se o mpv estiver preso e o player ficar
  /// por destruir, nunca toca por trás), depois destrói-o quando for seguro.
  @override
  Future<void> descartar() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    unawaited(_tamanho.close());
    // o próximo player só abre um canal depois de este fechar o áudio (ver VezDoAudio)
    final audioFechado = Completer<void>();
    VezDoAudio.instancia.largar(audioFechado.future);
    final motor = mpv;
    return motor.aposentar(
      // pelas funções assíncronas do libmpv (pause, mute): o pause()/setVolume() do
      // media_kit esperam pelo controlador de vídeo e pelo lock dele e, ao sair a meio de uma
      // abertura, nunca chegavam a parar nada (visto no emulador)
      pausar: () async {
        var h = motor.handleConhecido;
        final p = player.platform;
        if (h == null && p is NativePlayer) h = await p.handle.timeout(const Duration(seconds: 2));
        if (h != null) pararSemEsperar(h);
      },
      silenciar: () async {}, // o mute=yes vai com o pause
      destruir: () => player.dispose().whenComplete(audioFechado.complete),
    );
  }
}
