import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../desporto/catalogo.dart';
import '../../desporto/fontes/fotmob.dart' show logoCompeticaoFotmob;
import '../../desporto/modelo.dart';
import '../../desporto/preferencias_jogos.dart';
import '../../idioma/idioma.dart';
import '../design/design.dart';
import 'tela_jogos.dart' show nomeDesporto;

/// «Competições»: as competições seguidas, pela ordem dos blocos nos Jogos, e o modo «Reordenar»
/// (ver docs/2026-11-27-ordem-competicoes-design.md). Com o comando, OK pega numa competição,
/// CIMA/BAIXO movem-na e OK (ou Voltar) larga-a; com toque ou rato, arrasta-se pela pega.
class TelaCompeticoes extends StatefulWidget {
  const TelaCompeticoes({super.key, required this.preferencias});
  final PreferenciasJogos preferencias;

  @override
  State<TelaCompeticoes> createState() => _TelaCompeticoesState();
}

class _TelaCompeticoesState extends State<TelaCompeticoes> {
  PreferenciasJogos get _p => widget.preferencias;
  bool _reordenar = false;

  /// A competição pegada com o comando (a mover com CIMA/BAIXO).
  String? _pegada;

  /// Um foco por competição: a linha que se move continua com o foco.
  final _focos = <String, FocusNode>{};
  FocusNode _foco(String id) => _focos.putIfAbsent(id, () => FocusNode(debugLabel: 'Competição $id'));

  @override
  void initState() {
    super.initState();
    _p.addListener(_mudou);
  }

  @override
  void dispose() {
    _p.removeListener(_mudou);
    for (final f in _focos.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _mudou() {
    if (mounted) setState(() {});
  }

  void _alternarModo() => setState(() {
        _reordenar = !_reordenar;
        _pegada = null;
      });

  /// Voltar: larga a pegada; sem nenhuma, sai do modo. Devolve false se não havia nada a fazer.
  bool _recuar() {
    if (_pegada != null) {
      setState(() => _pegada = null);
      return true;
    }
    if (_reordenar) {
      _alternarModo();
      return true;
    }
    return false;
  }

  void _mover(String id, int para) {
    _p.moverCompeticao(id, para);
    // a linha mudou de sítio: continua à vista (o foco é o mesmo nó)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _focos[id]?.context;
      if (mounted && c != null) Scrollable.ensureVisible(c, alignmentPolicy: ScrollPositionAlignmentPolicy.explicit);
    });
  }

  KeyEventResult _tecla(String id, int i, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if ((k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack) && _recuar()) return KeyEventResult.handled;
    if (_pegada != id) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      // na primeira/última não faz nada, mas a tecla fica aqui (o foco não sai da pegada)
      _mover(id, k == LogicalKeyboardKey.arrowUp ? i - 1 : i + 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _logo(Competicao c) {
    final semLogo = Icon(
        switch (c.desporto) {
          Desporto.futebol => Icons.sports_soccer_rounded,
          Desporto.tenis => Icons.sports_tennis_rounded,
          Desporto.basquetebol => Icons.sports_basketball_rounded,
        },
        size: 22,
        color: Tokens.texto2);
    final f = c.fotmob;
    return SizedBox(
      width: 28,
      height: 28,
      child: f == null
          ? semLogo
          : Image.network(logoCompeticaoFotmob(f), width: 28, height: 28, errorBuilder: (_, _, _) => semLogo),
    );
  }

  Widget _linha(Competicao c, int i) {
    final pegada = _pegada == c.id;
    return Padding(
      key: ValueKey(c.id),
      padding: const EdgeInsets.only(bottom: Tokens.e8),
      child: Semantics(
        label: pegada ? tr('A mover: {0}', [c.nome]) : null,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          includeSemantics: false,
          onKeyEvent: (_, e) => _tecla(c.id, i, e),
          child: CartaoModerno(
            focusNode: _foco(c.id),
            // na TV o comando começa na primeira competição
            autofocus: i == 0,
            escalaFoco: 1.01,
            destaque: pegada,
            padding: const EdgeInsets.symmetric(horizontal: Tokens.e16, vertical: Tokens.e12),
            // fora do modo, OK não faz nada (as linhas recebem o foco só para se ver a lista)
            onTap: () {
              if (_reordenar) setState(() => _pegada = pegada ? null : c.id);
            },
            child: Row(children: [
              _logo(c),
              const SizedBox(width: Tokens.e12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(c.nome,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Tokens.texto)),
                  Text(nomeDesporto(c.desporto), style: const TextStyle(fontSize: 12.5, color: Tokens.texto2)),
                ]),
              ),
              if (pegada) const Icon(Icons.swap_vert_rounded, color: Tokens.anelFoco),
              if (_reordenar)
                ReorderableDragStartListener(
                  index: i,
                  child: const Padding(
                    padding: EdgeInsets.all(Tokens.e8),
                    child: Icon(Icons.drag_handle_rounded, color: Tokens.texto2),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ids = _p.ordemCompeticoes;
    final comps = [for (final id in ids) competicaoPorId(id)!];
    final Widget corpo = comps.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(Tokens.e24),
              child: Text(tr('Não segues nenhuma competição. Escolhe-as em Definições › Jogos.'),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: Tokens.texto2)),
            ),
          )
        : ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.fromLTRB(Tokens.e16, 0, Tokens.e16, Tokens.e16),
            itemCount: comps.length,
            onReorderItem: (de, para) => _mover(comps[de].id, para),
            itemBuilder: (_, i) => _linha(comps[i], i),
          );
    return PopScope(
      // a reordenar, o Voltar do sistema larga a pegada ou sai do modo (não fecha o ecrã)
      canPop: !_reordenar,
      onPopInvokedWithResult: (fechou, _) {
        if (!fechou) _recuar();
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e16, Tokens.e16, 0),
          child: CabecalhoSeccao(
            icone: Icons.emoji_events_outlined,
            titulo: tr('Competições'),
            subtitulo: _reordenar
                ? tr('OK pega e larga, ↑/↓ movem; ou arrasta pela pega')
                : tr('A ordem dos blocos nos Jogos'),
            acoes: [
              if (comps.length > 1)
                _reordenar
                    ? FilledButton.icon(
                        onPressed: _alternarModo, icon: const Icon(Icons.check_rounded), label: Text(tr('Concluído')))
                    : OutlinedButton.icon(
                        onPressed: _alternarModo,
                        icon: const Icon(Icons.swap_vert_rounded),
                        label: Text(tr('Reordenar'))),
            ],
          ),
        ),
        Expanded(child: corpo),
      ]),
    );
  }
}
