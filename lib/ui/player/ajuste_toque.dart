import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';

/// O volume do sistema e o brilho da janela, pelo canal nativo `player_iptv/sistema`
/// (MainActivity). O volume muda sem a barra do Android (flags 0); o brilho é só o da janela
/// da app (`screenBrightness`), o do sistema não se toca.
class SistemaAudioBrilho {
  const SistemaAudioBrilho();

  static const _canal = MethodChannel('player_iptv/sistema');
  static const _eventosVolume = EventChannel('player_iptv/sistema_volume');

  /// (atual, máximo) do volume da música; null se o canal falhar.
  Future<(int, int)?> volume() async {
    try {
      final m = await _canal.invokeMapMethod<String, int>('volume');
      final atual = m?['atual'], max = m?['max'];
      if (atual == null || max == null || max <= 0) return null;
      return (atual, max);
    } on Exception {
      return null;
    }
  }

  Future<void> definirVolume(int indice) async {
    try {
      await _canal.invokeMethod('definirVolume', {'indice': indice});
    } on Exception {
      // sem permissão (não incomodar) ou sem canal: o volume fica como está
    }
  }

  /// O brilho da janela, 0–1 (se a app ainda não o mudou: o do sistema).
  Future<double?> brilho() async {
    try {
      return await _canal.invokeMethod<double>('brilho');
    } on Exception {
      return null;
    }
  }

  /// 0–1; null volta ao brilho do sistema.
  Future<void> definirBrilho(double? v) async {
    try {
      await _canal.invokeMethod('definirBrilho', {'valor': v ?? -1.0});
    } on Exception {
      // sem canal: nada
    }
  }

  /// (atual, máximo) sempre que o volume da música muda (teclas do aparelho, outra app, esta).
  /// Sem o canal (testes, Windows) não dá nada.
  Stream<(int, int)> mudancasVolume() => _eventosVolume
      .receiveBroadcastStream()
      .handleError((Object _) {})
      .where((e) => e is Map && e['atual'] is int && e['max'] is int && (e['max'] as int) > 0)
      .map((e) => ((e as Map)['atual'] as int, e['max'] as int));
}

/// O que um deslize vertical está a mudar.
enum ZonaAjuste { volume, brilho }

/// Os deslizes verticais nas laterais do vídeo (telemóvel Android): à direita o volume do
/// sistema, à esquerda o brilho da app. O meio fica para mudar de canal.
class AjusteToque extends ChangeNotifier {
  AjusteToque({this.sistema = const SistemaAudioBrilho()}) {
    unawaited(_lerVolume());
    unawaited(_lerBrilho());
    _mudancas = sistema.mudancasVolume().listen(_aoMudarSistema);
  }

  StreamSubscription<(int, int)>? _mudancas;

  final SistemaAudioBrilho sistema;

  /// O brilho escolhido nesta sessão da app: volta a aplicar-se no próximo canal aberto.
  static double? _brilhoSessao;

  /// Até onde vai cada zona lateral (fração da largura).
  static const lateral = 0.4;

  /// Um deslize de [_percurso] da altura vai do mínimo ao máximo.
  static const _percurso = 0.6;

  /// Quanto tempo a barra fica à vista depois de largar.
  static const _visivelApos = Duration(milliseconds: 900);

  ZonaAjuste? _zona;
  ZonaAjuste? _visivel;
  Timer? _esconder;
  double _volume = 0.5;
  int _maxVolume = 15;
  int _indiceVolume = -1;

  /// O volume antes do silêncio (para o repor ao ligar o som).
  int _antesSilencio = 0;
  double _brilho = 0.5;
  bool _brilhoMudado = false;
  bool _fechado = false;

  /// O deslize em curso já mexeu (uma leitura atrasada do volume não o desfaz).
  bool _movido = false;

  /// A barra que está à vista (null = nenhuma).
  ZonaAjuste? get visivel => _visivel;

  /// 0–1.
  double get nivelVolume => _volume;

  /// Quantos degraus tem o volume do sistema (o passo da barra do player é um degrau).
  int get maxVolume => _maxVolume;

  /// O volume do sistema está a zero.
  bool get silencio => _indiceVolume == 0;
  double get nivelBrilho => _brilho;

  Future<void> _lerVolume() async {
    final v = await sistema.volume();
    if (v == null || _fechado || (_zona == ZonaAjuste.volume && _movido)) return;
    _guardarSistema(v.$1, v.$2);
  }

  void _guardarSistema(int atual, int max) {
    if (atual == _indiceVolume && max == _maxVolume) return;
    _maxVolume = max;
    _indiceVolume = atual;
    _volume = atual / max;
    notifyListeners();
  }

  /// O sistema avisou que o volume mudou: a barra do player e a lateral acompanham-no (durante
  /// um deslize manda o dedo).
  void _aoMudarSistema((int, int) v) {
    if (_fechado || (_zona == ZonaAjuste.volume && _movido)) return;
    _guardarSistema(v.$1, v.$2);
  }

  /// A barra do volume do player (0–1): muda o volume do sistema, ao degrau.
  void definirVolume(double fracao) {
    final i = (fracao.clamp(0.0, 1.0) * _maxVolume).round();
    _volume = i / _maxVolume;
    if (i != _indiceVolume) {
      _indiceVolume = i;
      unawaited(sistema.definirVolume(i));
    }
    notifyListeners();
  }

  /// Um degrau para cima (+1) ou para baixo (-1).
  void passoVolume(int degraus) => definirVolume((_indiceVolume.clamp(0, _maxVolume) + degraus) / _maxVolume);

  /// O silêncio do player no telemóvel é o volume do sistema a zero; ligar o som repõe o de antes.
  void silenciar(bool sim) {
    if (sim == silencio) return;
    if (sim) {
      _antesSilencio = _indiceVolume;
      definirVolume(0);
    } else {
      final i = _antesSilencio > 0 ? _antesSilencio : (_maxVolume / 2).ceil();
      definirVolume(i / _maxVolume);
    }
  }

  Future<void> _lerBrilho() async {
    final guardado = _brilhoSessao;
    if (guardado != null) {
      _brilho = guardado;
      _brilhoMudado = true;
      await sistema.definirBrilho(guardado);
      return;
    }
    final b = await sistema.brilho();
    if (b != null && !_fechado && _zona != ZonaAjuste.brilho) _brilho = b.clamp(0.0, 1.0);
  }

  /// Começa um deslize em `x` (fração da largura). false = é no meio (não é um ajuste).
  bool comecar(double x) {
    _zona = x < lateral ? ZonaAjuste.brilho : (x > 1 - lateral ? ZonaAjuste.volume : null);
    if (_zona == null) return false;
    _movido = false;
    // o volume pode ter mudado com as teclas do aparelho
    if (_zona == ZonaAjuste.volume) unawaited(_lerVolume());
    _esconder?.cancel();
    _visivel = _zona;
    notifyListeners();
    return true;
  }

  /// `fracao`: o deslize em fração da altura (positivo = para cima).
  void mover(double fracao) {
    if (_zona != null) _movido = true;
    switch (_zona) {
      case ZonaAjuste.volume:
        _volume = (_volume + fracao / _percurso).clamp(0.0, 1.0);
        final i = (_volume * _maxVolume).round();
        if (i != _indiceVolume) {
          _indiceVolume = i;
          unawaited(sistema.definirVolume(i));
        }
      case ZonaAjuste.brilho:
        // nunca a zero: o ecrã ficava preto
        _brilho = (_brilho + fracao / _percurso).clamp(0.01, 1.0);
        _brilhoMudado = true;
        _brilhoSessao = _brilho;
        unawaited(sistema.definirBrilho(_brilho));
      case null:
        return;
    }
    notifyListeners();
  }

  /// Acaba o deslize; true se era um ajuste (não muda de canal).
  bool terminar() {
    final era = _zona != null;
    _zona = null;
    if (era) {
      _esconder?.cancel();
      _esconder = Timer(_visivelApos, () {
        _visivel = null;
        if (!_fechado) notifyListeners();
      });
    }
    return era;
  }

  /// Ao sair do player: o resto da app volta ao brilho do sistema.
  @override
  void dispose() {
    _fechado = true;
    _esconder?.cancel();
    unawaited(_mudancas?.cancel());
    if (_brilhoMudado) unawaited(sistema.definirBrilho(null));
    super.dispose();
  }
}

/// As barras verticais do ajuste: o volume à esquerda, o brilho à direita (do lado oposto ao
/// dedo, para se verem). Não apanham toques.
class IndicadoresAjuste extends StatelessWidget {
  const IndicadoresAjuste({super.key, required this.ajuste});

  final AjusteToque ajuste;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ListenableBuilder(
          listenable: ajuste,
          builder: (context, _) {
            final z = ajuste.visivel;
            return Stack(children: [
              _barra(
                key: const ValueKey('barra-volume'),
                visivel: z == ZonaAjuste.volume,
                alinhamento: Alignment.centerLeft,
                nivel: ajuste.nivelVolume,
                icone: ajuste.nivelVolume <= 0
                    ? Icons.volume_off_rounded
                    : (ajuste.nivelVolume < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
              ),
              _barra(
                key: const ValueKey('barra-brilho'),
                visivel: z == ZonaAjuste.brilho,
                alinhamento: Alignment.centerRight,
                nivel: ajuste.nivelBrilho,
                icone: ajuste.nivelBrilho < 0.35
                    ? Icons.brightness_low_rounded
                    : (ajuste.nivelBrilho < 0.7 ? Icons.brightness_medium_rounded : Icons.brightness_high_rounded),
              ),
            ]);
          },
        ),
      );

  Widget _barra({
    required Key key,
    required bool visivel,
    required Alignment alinhamento,
    required double nivel,
    required IconData icone,
  }) =>
      AnimatedOpacity(
        key: key,
        opacity: visivel ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Align(
          alignment: alinhamento,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.e32),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xCC0B0F17),
                borderRadius: BorderRadius.circular(Tokens.raioPilula),
                border: Border.all(color: Tokens.bordaVidro),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${(nivel * 100).round()}',
                      style: const TextStyle(color: Tokens.texto, fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: Tokens.e8),
                  SizedBox(
                    width: 6,
                    height: 150,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Stack(fit: StackFit.expand, children: [
                        const ColoredBox(color: Color(0x33FFFFFF)),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: nivel.clamp(0.0, 1.0),
                            widthFactor: 1,
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [Tokens.acento, Color(0xFF4FC3FF)],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: Tokens.e8),
                  Icon(icone, color: Tokens.texto, size: 20),
                ]),
              ),
            ),
          ),
        ),
      );
}
