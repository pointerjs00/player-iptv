import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../design/ecra.dart';
import '../design/movimento.dart';
import '../design/tokens.dart';
import '../realce_foco.dart';
import 'progresso.dart';

/// A barra de progresso da barra de controlos: o tempo decorrido à esquerda, a pista (a parte
/// vista na cor de acento, a já recebida mais clara, e o botão redondo) e o total à direita.
/// Filme: posição e duração. Direto: a janela do cache (ver [JanelaProgresso]).
///
/// Com o foco (comando): esquerda/direita andam [salto] para trás/para a frente (presas, repetem
/// a cada [intervaloRepeticao]); OK é play/pausa; cima/baixo saem sempre da barra ([aoCima],
/// [aoBaixo]) — nunca ficam presos aqui. Rato/toque: arrastar ou tocar na pista.
///
/// Os seeks juntam-se: enquanto um está a caminho, o botão mostra já o alvo novo e os passos
/// seguintes contam a partir dele; quando o seek acaba, vai o último alvo pedido.
class BarraProgresso extends StatefulWidget {
  const BarraProgresso({
    super.key,
    required this.janela,
    required this.aoProcurar,
    required this.focusNode,
    required this.aoCima,
    required this.aoBaixo,
    required this.aoPlayPausa,
    required this.aoAtividade,
    this.semJanela,
  });

  /// null = ainda não se sabe (os tempos ficam "--:--:--"; a barra ocupa o mesmo espaço).
  final JanelaProgresso? janela;

  /// Vai para `alvo` (segundos do mpv, dentro da janela). Acaba quando o seek acabou e a janela
  /// já foi lida de novo.
  final Future<void> Function(JanelaProgresso janela, double alvo) aoProcurar;
  final FocusNode focusNode;
  final VoidCallback aoCima;
  final VoidCallback aoBaixo;
  final VoidCallback aoPlayPausa;

  /// Uma tecla ou um arrasto aqui (adia o esconder da barra).
  final VoidCallback aoAtividade;

  /// Esquerda/direita sem janela conhecida (−1/+1): os saltos de sempre.
  final ValueChanged<int>? semJanela;

  static const salto = Duration(seconds: 10);
  static const intervaloRepeticao = Duration(milliseconds: 250);

  @override
  State<BarraProgresso> createState() => _BarraProgressoState();
}

class _BarraProgressoState extends State<BarraProgresso> {
  static final _ok = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  };

  bool _focado = false;

  /// O alvo pedido e ainda não confirmado por uma leitura (o botão fica lá).
  double? _alvo;
  bool _aEnviar = false;
  bool _arrastar = false;
  Timer? _travaoRepeticao;

  @override
  void dispose() {
    _travaoRepeticao?.cancel();
    super.dispose();
  }

  void _passo(int sinal, {required bool repetido}) {
    final j = widget.janela;
    if (j == null) {
      if (!repetido) widget.semJanela?.call(sinal);
      return;
    }
    if (repetido) {
      if (_travaoRepeticao != null) return;
      _travaoRepeticao = Timer(BarraProgresso.intervaloRepeticao, () => _travaoRepeticao = null);
    }
    final de = _alvo ?? j.posicao;
    final alvo = j.deslocado(BarraProgresso.salto * sinal, de: de);
    if (alvo == de) return; // já na ponta da janela: nada a fazer
    setState(() => _alvo = alvo);
    _enviar();
  }

  Future<void> _enviar() async {
    final j = widget.janela, alvo = _alvo;
    if (_aEnviar || _arrastar || j == null || alvo == null) return;
    _aEnviar = true;
    try {
      await widget.aoProcurar(j, alvo);
    } catch (_) {
      // o player pode estar a fechar
    } finally {
      _aEnviar = false;
    }
    if (!mounted || _arrastar) return;
    if (_alvo != alvo) {
      unawaited(_enviar()); // entretanto pediu-se outro
    } else {
      setState(() => _alvo = null);
    }
  }

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final premida = e is KeyDownEvent;
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight) {
      widget.aoAtividade();
      _passo(k == LogicalKeyboardKey.arrowRight ? 1 : -1, repetido: !premida);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      widget.aoAtividade();
      if (premida) (k == LogicalKeyboardKey.arrowUp ? widget.aoCima : widget.aoBaixo)();
      return KeyEventResult.handled;
    }
    if (_ok.contains(k)) {
      widget.aoAtividade();
      if (premida) widget.aoPlayPausa();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _arrastarPara(double x, double largura) {
    final j = widget.janela;
    if (j == null || largura <= 0) return;
    widget.aoAtividade();
    setState(() {
      _arrastar = true;
      _alvo = j.alvoPorFracao(x / largura);
    });
  }

  void _largar() {
    if (!_arrastar) return;
    _arrastar = false;
    _enviar();
  }

  void _desistir() {
    if (!_arrastar) return;
    setState(() {
      _arrastar = false;
      if (!_aEnviar) _alvo = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tv = ecraTv(context);
    final j = widget.janela;
    final alvo = _alvo;
    final decorrido = j == null ? null : (alvo != null ? j.decorridoEm(alvo) : j.decorrido);
    final total = j?.total;
    final fVisto = j == null ? 0.0 : j.fracao(alvo ?? j.posicao);
    final fBuffer = j == null ? 0.0 : j.fracaoBuffer;
    Theme.of(context); // reconstrói quando o modo de realce muda (TemaConformeRealce troca o tema)
    final realce = _focado && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final estilo = TextStyle(
      fontSize: tv ? 15 : 12,
      color: Tokens.texto,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final duracao = duracaoAnimada(context, Tokens.duracaoRapida);
    String? valorApos(int sinal) => j == null
        ? null
        : '${textoTempo(j.decorridoEm(j.deslocado(BarraProgresso.salto * sinal, de: alvo)))} de ${textoTempo(total)}';
    return Semantics(
      slider: true,
      label: 'Posição',
      value: '${textoTempo(decorrido)} de ${textoTempo(total)}',
      hint: j == null ? null : 'Esquerda e direita: ${BarraProgresso.salto.inSeconds} s para trás ou para a frente',
      increasedValue: valorApos(1),
      decreasedValue: valorApos(-1),
      onIncrease: j == null ? null : () => _passo(1, repetido: false),
      onDecrease: j == null ? null : () => _passo(-1, repetido: false),
      child: MolduraFoco(
        focado: _focado,
        raio: Tokens.raioCampo,
        child: Focus(
          focusNode: widget.focusNode,
          onKeyEvent: _tecla,
          onFocusChange: (f) {
            if (mounted && f != _focado) setState(() => _focado = f);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.e8),
            child: SizedBox(
              height: tv ? 32 : 24,
              child: Row(children: [
                ExcludeSemantics(child: Text(textoTempo(decorrido), style: estilo)),
                const SizedBox(width: Tokens.e12),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) => GestureDetector(
                      key: const ValueKey('pista'),
                      behavior: HitTestBehavior.opaque,
                      excludeFromSemantics: true, // o leitor de ecrã usa aumentar/diminuir
                      onHorizontalDragStart: (d) => _arrastarPara(d.localPosition.dx, c.maxWidth),
                      onHorizontalDragUpdate: (d) => _arrastarPara(d.localPosition.dx, c.maxWidth),
                      onHorizontalDragEnd: (_) => _largar(),
                      onHorizontalDragCancel: _largar,
                      onTapDown: (d) => _arrastarPara(d.localPosition.dx, c.maxWidth),
                      onTapUp: (_) => _largar(),
                      // (antes de um arrasto ganhar ao toque: o arrasto continua a partir daqui)
                      onTapCancel: _desistir,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: realce ? 1 : 0),
                        duration: duracao,
                        curve: Tokens.curva,
                        builder: (_, r, _) => CustomPaint(
                          size: Size.infinite,
                          painter: _Pista(visto: fVisto, buffer: fBuffer, realce: r, tv: tv, conhecida: j != null),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Tokens.e12),
                ExcludeSemantics(child: Text(textoTempo(total), style: estilo)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pista fina: o fundo, o já recebido (mais claro), o visto (acento) e o botão redondo.
/// `realce` (0–1) engrossa a pista e o botão com o foco do comando.
class _Pista extends CustomPainter {
  _Pista({required this.visto, required this.buffer, required this.realce, required this.tv, required this.conhecida});

  final double visto;
  final double buffer;
  final double realce;
  final bool tv;
  final bool conhecida;

  @override
  void paint(Canvas canvas, Size size) {
    final espessura = (tv ? 4.0 : 3.0) + 2 * realce;
    final raioBotao = (tv ? 7.0 : 6.0) + 2 * realce;
    final y = size.height / 2;
    // o botão nunca sai da pista
    final x0 = raioBotao, x1 = size.width - raioBotao;
    if (x1 <= x0) return;
    double x(double f) => x0 + (x1 - x0) * f.clamp(0.0, 1.0);
    final topo = y - espessura / 2;
    RRect troco(double a, double b) =>
        RRect.fromLTRBR(a, topo, b, topo + espessura, Radius.circular(espessura / 2));

    canvas.drawRRect(troco(x0, x1), Paint()..color = const Color(0x33FFFFFF));
    if (!conhecida) return;
    if (buffer > visto) canvas.drawRRect(troco(x(visto), x(buffer)), Paint()..color = const Color(0x5CFFFFFF));
    final xv = x(visto);
    if (xv > x0) {
      canvas.drawRRect(
        troco(x0, xv),
        Paint()..shader = Tokens.gradienteAcento.createShader(Rect.fromLTRB(x0, topo, x1, topo + espessura)),
      );
    }
    if (realce > 0) {
      canvas.drawCircle(Offset(xv, y), raioBotao + 3 * realce,
          Paint()..color = Tokens.acento2.withValues(alpha: .35 * realce));
    }
    canvas.drawCircle(Offset(xv, y), raioBotao, Paint()..color = Tokens.acento);
    canvas.drawCircle(
      Offset(xv, y),
      raioBotao,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Tokens.texto.withValues(alpha: .35 + .65 * realce),
    );
  }

  @override
  bool shouldRepaint(_Pista o) =>
      o.visto != visto || o.buffer != buffer || o.realce != realce || o.tv != tv || o.conhecida != conhecida;
}
