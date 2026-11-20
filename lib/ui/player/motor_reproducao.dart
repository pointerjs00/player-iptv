import 'package:material_ui/material_ui.dart';

/// Uma faixa de vídeo, áudio ou legendas de um canal, como o painel a mostra. `id` é o do motor
/// (no mpv o `aid`/`sid`/`vid`; `auto` e `no` são as escolhas automática e nenhuma).
@immutable
class FaixaMotor {
  const FaixaMotor(this.id, {this.titulo, this.lingua, this.codec, this.altura});

  /// A escolha automática do motor.
  static const auto = FaixaMotor('auto');

  /// Nenhuma faixa (legendas desligadas).
  static const nenhuma = FaixaMotor('no');

  final String id;
  final String? titulo;

  /// O código da língua, como vem do stream (`por`, `eng`).
  final String? lingua;
  final String? codec;

  /// As linhas da imagem (só nas faixas de vídeo).
  final int? altura;

  @override
  bool operator ==(Object other) =>
      other is FaixaMotor &&
      other.id == id &&
      other.titulo == titulo &&
      other.lingua == lingua &&
      other.codec == codec &&
      other.altura == altura;

  @override
  int get hashCode => Object.hash(id, titulo, lingua, codec, altura);

  @override
  String toString() => 'FaixaMotor($id)';
}

/// As faixas que o canal tem.
@immutable
class FaixasMotor {
  const FaixasMotor({this.video = const [], this.audio = const [], this.legendas = const []});

  final List<FaixaMotor> video;
  final List<FaixaMotor> audio;
  final List<FaixaMotor> legendas;
}

/// As faixas escolhidas agora.
@immutable
class FaixaAtual {
  const FaixaAtual({this.video = FaixaMotor.auto, this.audio = FaixaMotor.auto, this.legenda = FaixaMotor.auto});

  final FaixaMotor video;
  final FaixaMotor audio;
  final FaixaMotor legenda;
}

/// Um retrato do motor para as estatísticas (null no que o motor não sabe).
@immutable
class EstatisticasMotor {
  const EstatisticasMotor({
    this.resolucao,
    this.fps,
    this.codec,
    this.perdidas,
    this.renderizadas,
    this.bitrate,
    this.buffer,
  });

  final Size? resolucao;

  /// Imagens por segundo do canal.
  final double? fps;
  final String? codec;

  /// Imagens perdidas (descodificador + saída) desde que o canal abriu.
  final int? perdidas;
  final int? renderizadas;

  /// Bits por segundo do vídeo.
  final double? bitrate;

  /// Quanto há no buffer à frente da posição.
  final Duration? buffer;
}

/// Um erro do motor. `mensagem` pode trazer o link (quem a mostra tira os segredos); `formato`: o
/// motor não consegue descodificar este canal (formato ou descodificador não suportado), ao contrário
/// de um erro de rede.
@immutable
class ErroMotor {
  const ErroMotor(this.mensagem, {this.formato = false, this.rede = false});

  final String mensagem;
  final bool formato;

  /// Uma falha de rede (ligação, tempo esgotado, código HTTP), que pode passar ao reabrir.
  final bool rede;

  @override
  String toString() => 'ErroMotor($mensagem, formato: $formato, rede: $rede)';
}

/// O que reproduz o vídeo de um canal. O ecrã do player ([PlayerCanais]) fala só com isto: o mpv
/// (media_kit, em `motor_mpv.dart`) e, no Android, o ExoPlayer ficam por trás.
///
/// Cada motor serve um player: depois de [descartar] não se usa mais.
abstract interface class MotorReproducao {
  /// `mpv` ou `exoplayer`.
  String get nome;

  /// Se o desentrelaçamento da app (filtros do mpv, shader do Flutter) se aplica a este motor.
  bool get suportaDesentrelacamento;

  /// Os erros do motor ([ErroMotor]).
  Stream<ErroMotor> get erros;

  /// Parado à espera de dados.
  Stream<bool> get aCarregar;

  /// 0–100 de quanto já chegou numa paragem à espera de dados.
  Stream<double> get percentagemCarga;

  /// O tamanho da imagem (null sem imagem, ex.: depois de parar).
  Stream<Size?> get tamanhoVideo;
  Stream<Duration> get posicao;

  /// O stream acabou (num direto: o servidor fechou a ligação e o buffer chegou ao fim).
  Stream<void> get fim;
  Stream<FaixasMotor> get faixas;
  Stream<FaixaAtual> get faixaAtual;

  /// As imagens por segundo que o motor mediu no vídeo deste canal, quando o formato não as diz
  /// (TS e HLS no ExoPlayer). O mpv não manda nada aqui: o ecrã lê as propriedades dele.
  Stream<double> get fps;

  /// Se o canal aberto é um direto (sem fim conhecido), segundo o motor; null se não sabe (o mpv:
  /// o ecrã lê as propriedades dele).
  bool? get direto;

  /// Abre o canal (`inicio`: num ficheiro, onde começar).
  Future<void> abrir(String url, Map<String, String> cabecalhos, {Duration? inicio});
  Future<void> play();
  Future<void> pausar();
  Future<void> parar();
  Future<void> escolherAudio(FaixaMotor faixa);

  /// null: sem legendas.
  Future<void> escolherLegenda(FaixaMotor? faixa);
  Future<void> velocidade(double v);

  /// 0–100.
  Future<void> volume(double v);
  Future<EstatisticasMotor> estatisticas();

  /// O vídeo, com o ajuste à caixa e, se dada, uma proporção forçada.
  Widget video({required BoxFit ajuste, double? proporcao});

  /// Pára e larga o motor (nunca toca por trás depois disto).
  Future<void> descartar();
}
