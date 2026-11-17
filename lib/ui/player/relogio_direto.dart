/// Quanto se está atrás do direto. O direto anda ao ritmo do relógio; o que se vê anda à
/// velocidade escolhida (parado na pausa). Recuar/avançar mudam o atraso pelo que o mpv
/// recuou/avançou de facto. O atraso nunca passa do buffer que há à frente (não se pode estar
/// mais atrás do que aquilo que já chegou) e nunca fica negativo (à frente do direto).
///
/// Recuar no direto usa o cache do mpv para trás (`demuxer-max-back-bytes`, 64 MiB: cerca de
/// 1 min num canal HD a 8 Mb/s, vários minutos num SD) — ver `configuracao_mpv.dart`.
class RelogioDireto {
  RelogioDireto({DateTime Function()? agora}) : _agora = agora ?? DateTime.now {
    _desde = _agora();
  }

  /// Até aqui ainda se diz "Em direto" (o buffer normal de um direto anda por aí).
  static const limiar = Duration(seconds: 2);

  final DateTime Function() _agora;
  late DateTime _desde;
  Duration _base = Duration.zero;
  bool _pausado = false;
  double _velocidade = 1;

  double get velocidade => _velocidade;
  bool get pausado => _pausado;

  /// O relógio usado (o dos testes, nos testes).
  DateTime get agora => _agora();

  /// O atraso agora.
  Duration get atraso {
    final taxa = _pausado ? 0.0 : _velocidade;
    final passou = _agora().difference(_desde);
    final a = _base + passou * (1 - taxa);
    return a.isNegative ? Duration.zero : a;
  }

  bool get emDireto => atraso < limiar;

  /// Fixa o atraso até agora e começa um novo troço.
  void _marcar() {
    _base = atraso;
    _desde = _agora();
  }

  void pausou() {
    _marcar();
    _pausado = true;
  }

  void retomou() {
    _marcar();
    _pausado = false;
  }

  void mudouVelocidade(double v) {
    _marcar();
    _velocidade = v;
  }

  void recuou(Duration d) {
    _marcar();
    _base += d;
  }

  void avancou(Duration d) {
    _marcar();
    _base -= d;
    if (_base.isNegative) _base = Duration.zero;
  }

  /// Quanto se pode avançar de `pedido` sem passar o direto.
  Duration avancoPossivel(Duration pedido) {
    final a = atraso;
    return pedido < a ? pedido : a;
  }

  /// O buffer que há à frente (o mpv): o atraso não passa dele.
  void limitar(Duration bufferAFrente) {
    _marcar();
    if (_base > bufferAFrente) _base = bufferAFrente;
  }

  void voltouAoDireto() {
    _marcar();
    _base = Duration.zero;
  }

  /// Canal novo: em direto, a tocar, a 1×.
  void reiniciar() {
    _base = Duration.zero;
    _desde = _agora();
    _pausado = false;
    _velocidade = 1;
  }
}

/// "−0:07", "−1:15", "−1:01:02".
String textoAtraso(Duration d) {
  String dois(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  return h > 0 ? '−$h:${dois(m)}:${dois(s)}' : '−$m:${dois(s)}';
}
