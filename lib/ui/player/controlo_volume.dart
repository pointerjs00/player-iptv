import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../design/componentes.dart';
import '../design/tokens.dart';
import '../realce_foco.dart';

/// O volume na barra do player (todas as plataformas): o botão do silêncio e a barra do volume
/// do player (0–100), com a percentagem.
///
/// Ao toque e ao rato, a barra arrasta-se. Com o comando ou o teclado a barra é uma paragem do
/// foco: OK entra na edição (← → mudam o volume em [passo]); OK, Voltar, ↑ ou ↓ saem dela. Fora
/// da edição as setas andam pelos botões da barra, como nos outros controlos.
class ControloVolume extends StatefulWidget {
  const ControloVolume({
    super.key,
    required this.volume,
    required this.silencio,
    required this.aoMudar,
    required this.aoSilencio,
    this.aoAtividade,
    this.largura = 120,
    this.tamanhoIcone = 26,
    this.estiloIcone,
  });

  /// 0–100.
  final double volume;
  final bool silencio;
  final ValueChanged<double> aoMudar;
  final ValueChanged<bool> aoSilencio;

  /// Qualquer mexida (a barra não se esconde enquanto se ajusta o volume).
  final VoidCallback? aoAtividade;

  /// A largura da barra do volume.
  final double largura;
  final double tamanhoIcone;
  final ButtonStyle? estiloIcone;

  static const passo = 5.0;

  @override
  State<ControloVolume> createState() => _ControloVolumeState();
}

class _ControloVolumeState extends State<ControloVolume> {
  bool _aEditar = false;

  void _editar(bool sim) {
    if (mounted && sim != _aEditar) setState(() => _aEditar = sim);
  }

  void _mudar(double v) {
    widget.aoAtividade?.call();
    final n = v.clamp(0.0, 100.0);
    if (n != widget.volume) widget.aoMudar(n);
    // mexer no volume tira o silêncio (como nos outros players)
    if (widget.silencio && n > 0) widget.aoSilencio(false);
  }

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    final k = e.logicalKey;
    if (teclasOk.contains(k)) {
      if (e is KeyDownEvent) {
        widget.aoAtividade?.call();
        _editar(!_aEditar);
      }
      return KeyEventResult.handled;
    }
    if (!_aEditar) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.escape) {
      // Voltar sai da edição (não esconde a barra nem sai do player)
      if (e is KeyDownEvent) _editar(false);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      _editar(false);
      return KeyEventResult.ignored;
    }
    if (k != LogicalKeyboardKey.arrowLeft && k != LogicalKeyboardKey.arrowRight) return KeyEventResult.ignored;
    if (e is! KeyUpEvent) {
      _mudar(widget.volume + (k == LogicalKeyboardKey.arrowLeft ? -ControloVolume.passo : ControloVolume.passo));
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final mudo = widget.silencio || widget.volume <= 0;
    final icone = mudo
        ? Icons.volume_off_rounded
        : widget.volume < 50
            ? Icons.volume_down_rounded
            : Icons.volume_up_rounded;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        key: const ValueKey('volumeSilencio'),
        icon: Icon(icone, size: widget.tamanhoIcone),
        tooltip: widget.silencio ? 'Ligar o som' : 'Silêncio',
        color: Tokens.texto,
        style: widget.estiloIcone,
        onPressed: () {
          widget.aoAtividade?.call();
          widget.aoSilencio(!widget.silencio);
        },
      ),
      RealceFoco(
        raio: Tokens.raioCampo,
        construir: (context, aoMudarFoco) => Focus(
          onFocusChange: (f) {
            if (!f) _editar(false);
            aoMudarFoco(f);
          },
          onKeyEvent: _tecla,
          child: Semantics(
            slider: true,
            label: 'Volume',
            value: '${widget.volume.round()} %',
            increasedValue: '${(widget.volume + ControloVolume.passo).clamp(0, 100).round()} %',
            decreasedValue: '${(widget.volume - ControloVolume.passo).clamp(0, 100).round()} %',
            onIncrease: widget.volume < 100 ? () => _mudar(widget.volume + ControloVolume.passo) : null,
            onDecrease: widget.volume > 0 ? () => _mudar(widget.volume - ControloVolume.passo) : null,
            child: ExcludeSemantics(
              child: DecoratedBox(
                key: _aEditar ? const ValueKey('volumeAEditar') : null,
                // a editar (depois do OK), a barra ganha a cor de destaque
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Tokens.raioCampo),
                  border: Border.all(color: _aEditar ? Tokens.acento : Colors.transparent, width: 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(right: Tokens.e8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                      width: widget.largura,
                      // o foco é da caixa toda: o Slider só responde ao toque e ao rato
                      child: ExcludeFocus(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                          ),
                          child: Slider(
                            key: const ValueKey('volumeBarra'),
                            value: mudo ? 0 : widget.volume.clamp(0, 100),
                            max: 100,
                            onChanged: _mudar,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text('${mudo ? 0 : widget.volume.round()} %',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontSize: 13, color: Tokens.texto2, fontFeatures: [FontFeature.tabularFigures()])),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
