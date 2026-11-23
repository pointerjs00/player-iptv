import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../design/componentes.dart';
import '../design/tokens.dart';
import '../realce_foco.dart';
import '../../idioma/idioma.dart';

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
    this.passo = 5,
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

  /// Quanto muda cada ← → (em %): no telemóvel, um degrau do volume do sistema.
  final double passo;

  @override
  State<ControloVolume> createState() => _ControloVolumeState();
}

class _ControloVolumeState extends State<ControloVolume> with SingleTickerProviderStateMixin {
  bool _aEditar = false;

  /// O "pulo" da barra a cada OK (entrar ou sair da edição): mostra que o OK chegou.
  late final _pulo = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  late final _escala = TweenSequence<double>([
    TweenSequenceItem(tween: Tween<double>(begin: 1, end: 1.12).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
    TweenSequenceItem(tween: Tween<double>(begin: 1.12, end: 1).chain(CurveTween(curve: Curves.easeIn)), weight: 60),
  ]).animate(_pulo);

  @override
  void dispose() {
    _pulo.dispose();
    super.dispose();
  }

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
        _pulo.forward(from: 0);
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
      _mudar(widget.volume + (k == LogicalKeyboardKey.arrowLeft ? -widget.passo : widget.passo));
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
        tooltip: widget.silencio ? tr('Ligar o som') : tr('Silêncio'),
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
            increasedValue: '${(widget.volume + widget.passo).clamp(0, 100).round()} %',
            decreasedValue: '${(widget.volume - widget.passo).clamp(0, 100).round()} %',
            onIncrease: widget.volume < 100 ? () => _mudar(widget.volume + widget.passo) : null,
            onDecrease: widget.volume > 0 ? () => _mudar(widget.volume - widget.passo) : null,
            child: ExcludeSemantics(
              child: ScaleTransition(
                key: const ValueKey('volumePulo'),
                scale: _escala,
                child: AnimatedContainer(
                  key: _aEditar ? const ValueKey('volumeAEditar') : null,
                  duration: const Duration(milliseconds: 180),
                  // a editar (depois do OK), a barra ganha a cor de destaque, um fundo e as setas ‹ ›
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Tokens.raioCampo),
                    color: _aEditar ? Tokens.acento.withValues(alpha: .22) : Colors.transparent,
                    border: Border.all(color: _aEditar ? Tokens.acento : Colors.transparent, width: 2),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(right: Tokens.e8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _seta(Icons.chevron_left_rounded),
                      SizedBox(
                        width: widget.largura,
                        // o foco é da caixa toda: o Slider só responde ao toque e ao rato
                        child: ExcludeFocus(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: RoundSliderThumbShape(enabledThumbRadius: _aEditar ? 10 : 7),
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
                      _seta(Icons.chevron_right_rounded),
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
      ),
    ]);
  }

  /// As setas ‹ › só aparecem a editar (← → mudam o volume).
  Widget _seta(IconData icone) => AnimatedSize(
        duration: const Duration(milliseconds: 180),
        child: _aEditar ? Icon(icone, size: 20, color: Tokens.acento) : const SizedBox(height: 20),
      );
}
