import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'design/ecra.dart';
import 'design/movimento.dart';
import 'design/sombra.dart';
import 'design/tokens.dart';
import 'tema.dart';

/// O realce do foco para o comando da TV: uma borda de 3 px na cor de acento (índigo) com um
/// brilho violeta por fora, e um fundo ligeiramente mais claro (e, nos cartões, um aumento).
abstract final class Realce {
  static const borda = BorderSide(color: Cores.acento, width: 3);

  /// Nos botões cheios (já da cor de acento) a borda clara vê-se melhor.
  static const bordaClara = BorderSide(color: Cores.texto, width: 3);

  /// O fundo de quem tem o foco (o `focusColor` do tema e o overlay dos botões).
  static final fundo = Cores.acento.withValues(alpha: .22);
  static const duracao = Tokens.duracaoRapida;

  /// O brilho violeta à volta de quem tem o foco (pintado só por fora: não tapa o conteúdo).
  static const brilho = [BoxShadow(color: Color(0x8C9B6CFF), blurRadius: 16)];
}

const _canalTv = MethodChannel('player_iptv/tv');

/// Android TV (ou sem ecrã tátil)? Pergunta-se ao Android (MainActivity).
Future<bool> _eTvAndroid() async =>
    Platform.isAndroid && (await _canalTv.invokeMethod<bool>('eTv') ?? false);

/// Na TV o realce do foco fica sempre ligado: no modo automático, um toque (por exemplo no
/// emulador ou num comando com rato) escondia-o e com as setas não voltava.
Future<void> configurarRealceFoco({Future<bool> Function()? eTv}) async {
  bool tv;
  try {
    tv = await (eTv ?? _eTvAndroid)();
  } catch (_) {
    tv = false;
  }
  EcraTv.nativo = tv; // ecraTv(): tamanhos maiores (vista de longe)
  if (tv) FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
}

/// Mostra o realce à volta de `child` quando `focado` (e o modo de realce é o do teclado/comando).
class MolduraFoco extends StatelessWidget {
  const MolduraFoco({super.key, required this.focado, required this.child, this.raio = 12, this.escala = 1});

  final bool focado;
  final Widget child;
  final double raio;

  /// O tamanho com o foco (1 = não cresce).
  final double escala;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // reconstrói quando o modo de realce muda (TemaConformeRealce troca o tema)
    final ver = focado && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final r = BorderRadius.circular(raio);
    return AnimatedScale(
      scale: ver ? escala : 1,
      duration: duracaoAnimada(context, Realce.duracao),
      curve: Tokens.curva,
      // o brilho só por fora (por baixo pintaria de violeta um cartão de vidro)
      child: SombraExterior(
        duration: duracaoAnimada(context, Realce.duracao),
        raio: raio,
        sombras: ver ? Realce.brilho : const [],
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: ver
              // só a borda: o fundo mais claro é o focusColor do tema (o InkWell pinta-o; uma cor
              // aqui esconderia o ink do ListTile)
              ? BoxDecoration(borderRadius: r, border: Border.fromBorderSide(Realce.borda))
              : BoxDecoration(borderRadius: r),
          child: child,
        ),
      ),
    );
  }
}

/// Para widgets que dizem quando ganham/perdem o foco (`onFocusChange` do ListTile, InkWell...):
/// `construir(context, aoMudarFoco)` passa `aoMudarFoco` ao widget e o realce fica à volta dele.
class RealceFoco extends StatefulWidget {
  const RealceFoco({super.key, required this.construir, this.raio = 12, this.escala = 1});

  final Widget Function(BuildContext context, ValueChanged<bool> aoMudarFoco) construir;
  final double raio;
  final double escala;

  @override
  State<RealceFoco> createState() => _RealceFocoState();
}

class _RealceFocoState extends State<RealceFoco> {
  bool _focado = false;

  void _mudou(bool f) {
    if (mounted && f != _focado) setState(() => _focado = f);
  }

  @override
  Widget build(BuildContext context) => MolduraFoco(
        focado: _focado,
        raio: widget.raio,
        escala: widget.escala,
        child: widget.construir(context, _mudou),
      );
}

/// Para o `builder` do MaterialApp: o tema com o realce de foco só no modo de realce do
/// teclado/comando. No telemóvel ou com o rato (modo toque), um botão com foco automático não
/// ganha borda; ao carregar numa tecla, o tema muda e os widgets focados mostram o realce.
class TemaConformeRealce extends StatefulWidget {
  const TemaConformeRealce({super.key, required this.child});
  final Widget child;

  @override
  State<TemaConformeRealce> createState() => _TemaConformeRealceState();
}

class _TemaConformeRealceState extends State<TemaConformeRealce> {
  static final _comRealce = temaApp();
  static final _semRealce = temaApp(realceFoco: false);

  void _mudou(FocusHighlightMode _) {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_mudou);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_mudou);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: FocusManager.instance.highlightMode == FocusHighlightMode.traditional ? _comRealce : _semRealce,
        child: widget.child,
      );
}
