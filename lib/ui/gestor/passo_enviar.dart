import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/area_gestor.dart';
import '../../dados/biblioteca.dart';
import '../design/design.dart';
import '../realce_foco.dart';

/// O passo 3 do Gestor, "Enviar ou exportar": à esquerda a marcação das listas (os atalhos
/// `Marcar:` e uma linha com caixa por lista) e à direita os dois destinos, cada um com o seu
/// botão (`Enviar N listas` · `Exportar N listas`). No ecrã estreito os cartões vão por baixo.
///
/// O conjunto [marcadas] (ids) pertence à `TelaGestor`, para sobreviver a mudar de passo: este
/// widget mexe nele e avisa por [aoMudarMarcadas]. Os ids que saem do Gestor saem do conjunto.
/// → numa linha vai aos cartões; ← nos cartões volta à última linha com o foco.
class PassoEnviar extends StatefulWidget {
  const PassoEnviar({
    super.key,
    required this.area,
    required this.marcadas,
    required this.aoMudarMarcadas,
    required this.aoEnviar,
    required this.aoExportar,
    this.focoInicial,
  });

  final AreaGestor area;
  final Set<String> marcadas;
  final VoidCallback aoMudarMarcadas;

  /// As listas marcadas (pela ordem do Gestor).
  final ValueChanged<List<Lista>> aoEnviar;
  final ValueChanged<List<Lista>> aoExportar;

  /// O controlo que recebe o foco quando o passo abre (o chip "As que funcionam").
  final FocusNode? focoInicial;

  @override
  State<PassoEnviar> createState() => _PassoEnviarState();
}

class _PassoEnviarState extends State<PassoEnviar> {
  final _focoFuncionam = FocusNode(debugLabel: 'As que funcionam');
  final _focoEnviar = FocusNode(debugLabel: 'Enviar');
  final _focoExportar = FocusNode(debugLabel: 'Exportar');
  final _focosLinhas = <String, FocusNode>{};

  /// O deslocamento da fila dos chips de marcar (com a barra, para o rato).
  final _rolChips = ScrollController();
  String? _linhaFocada;

  AreaGestor get _g => widget.area;
  FocusNode get _focoChip => widget.focoInicial ?? _focoFuncionam;

  @override
  void initState() {
    super.initState();
    _focoEnviar.addListener(() => _seDesligou(_focoEnviar));
    _focoExportar.addListener(() => _seDesligou(_focoExportar));
  }

  /// O botão com o foco ficou desativado (já não há marcadas): o foco passa ao chip "As que
  /// funcionam" (senão perdia-se e deixava de se ver).
  void _seDesligou(FocusNode no) {
    if (no.hasFocus || no.canRequestFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final atual = FocusManager.instance.primaryFocus;
      if (mounted && (atual == null || atual is FocusScopeNode)) _focoChip.requestFocus();
    });
  }

  @override
  void dispose() {
    _focoFuncionam.dispose();
    _focoEnviar.dispose();
    _focoExportar.dispose();
    _rolChips.dispose();
    for (final f in _focosLinhas.values) {
      f.dispose();
    }
    super.dispose();
  }

  FocusNode _focoLinha(String id) => _focosLinhas.putIfAbsent(id, () => FocusNode(debugLabel: 'Linha'));

  void _marcar(bool Function(EstadoLista) criterio) {
    widget.marcadas
      ..clear()
      ..addAll([for (final l in _g.listas) if (criterio(estadoDe(l))) l.id]);
    widget.aoMudarMarcadas();
    setState(() {});
  }

  void _alternar(String id, bool marcar) {
    marcar ? widget.marcadas.add(id) : widget.marcadas.remove(id);
    widget.aoMudarMarcadas();
    setState(() {});
  }

  KeyEventResult _teclaLinha(KeyEvent e) {
    if (e is KeyUpEvent || e.logicalKey != LogicalKeyboardKey.arrowRight) return KeyEventResult.ignored;
    final alvo = [_focoEnviar, _focoExportar].where((f) => f.canRequestFocus).firstOrNull;
    if (alvo == null) return KeyEventResult.ignored;
    alvo.requestFocus();
    return KeyEventResult.handled;
  }

  KeyEventResult _teclaCartoes(KeyEvent e) {
    if (e is KeyUpEvent || e.logicalKey != LogicalKeyboardKey.arrowLeft) return KeyEventResult.ignored;
    final id = _g.porId(_linhaFocada ?? '') != null ? _linhaFocada! : _g.listas.firstOrNull?.id;
    if (id == null) return KeyEventResult.ignored;
    final no = _focoLinha(id);
    if (!no.canRequestFocus || no.context == null) return KeyEventResult.ignored;
    no.requestFocus();
    return KeyEventResult.handled;
  }

  static String _n(int n, String um, String varios) => '$n ${n == 1 ? um : varios}';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _g,
        builder: (context, _) => LayoutBuilder(builder: (context, caixa) {
          final listas = _g.listas;
          widget.marcadas.removeWhere((id) => _g.porId(id) == null);
          final sel = [for (final l in listas) if (widget.marcadas.contains(l.id)) l];
          final largo = caixa.maxWidth >= 720;
          final lista = SliverList.builder(
            itemCount: listas.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Material(type: MaterialType.transparency, child: _linha(listas[i])),
            ),
          );
          final rodape = Padding(
            padding: const EdgeInsets.only(top: Tokens.e8),
            child: Text('${_n(sel.length, 'marcada', 'marcadas')} · OK marca/desmarca uma lista',
                style: const TextStyle(color: Tokens.texto2, fontSize: 13, fontWeight: FontWeight.w500)),
          );
          final cartoes = _cartoes(sel);
          if (largo) {
            return Padding(
              padding: const EdgeInsets.all(Tokens.e16),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Semantics(
                    container: true,
                    label: 'Marcar listas',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _marcarBarra(listas),
                      const SizedBox(height: Tokens.e8),
                      Expanded(child: CustomScrollView(slivers: [lista])),
                      rodape,
                    ]),
                  ),
                ),
                const SizedBox(width: Tokens.e16),
                // na TV (~740) os cartões estreitam para a lista caber ao lado
                SizedBox(
                    width: (caixa.maxWidth * .4).clamp(280.0, 380.0), child: SingleChildScrollView(child: cartoes)),
              ]),
            );
          }
          return CustomScrollView(slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e16, Tokens.e16, Tokens.e8),
              sliver: SliverToBoxAdapter(child: _marcarBarra(listas)),
            ),
            SliverPadding(padding: const EdgeInsets.symmetric(horizontal: Tokens.e16), sliver: lista),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Tokens.e16, 0, Tokens.e16, Tokens.e16),
              sliver: SliverToBoxAdapter(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  rodape,
                  const SizedBox(height: Tokens.e12),
                  cartoes,
                ]),
              ),
            ),
          ]);
        }),
      );

  Widget _marcarBarra(List<Lista> listas) {
    final funcionam = listas.where((l) => estadoDe(l) == EstadoLista.funciona).length;
    final ateInconcl =
        listas.where((l) => estadoDe(l) == EstadoLista.funciona || estadoDe(l) == EstadoLista.inconclusiva).length;
    ActionChip chip(String texto, VoidCallback aoCarregar, {FocusNode? foco}) => ActionChip(
          focusNode: foco,
          label: Text(texto),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onPressed: aoCarregar,
        );
    final chips = [
      chip('As que funcionam ($funcionam)', () => _marcar((e) => e == EstadoLista.funciona), foco: _focoChip),
      chip('+ inconclusivas ($ateInconcl)',
          () => _marcar((e) => e == EstadoLista.funciona || e == EstadoLista.inconclusiva)),
      chip('Todas (${listas.length})', () => _marcar((_) => true)),
      chip('Nenhuma', () => _marcar((_) => false)),
    ];
    // numa só linha, com «Marcar:» fixo: se os chips não couberem, deslizam para o lado (o foco
    // leva-os à vista; com o rato há a barra)
    return Row(children: [
      const Text('Marcar:', style: TextStyle(color: Tokens.texto2, fontWeight: FontWeight.w500)),
      const SizedBox(width: Tokens.e8),
      Expanded(
        child: Scrollbar(
          controller: _rolChips,
          child: SingleChildScrollView(
            controller: _rolChips,
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final (i, c) in chips.indexed) ...[if (i > 0) const SizedBox(width: Tokens.e8), c],
            ]),
          ),
        ),
      ),
    ]);
  }

  /// Linhas baixas, como as do passo 2 (a mesma altura, [Tokens.alturaLinhaTabela]).
  static const _densidade = VisualDensity(vertical: VisualDensity.minimumDensity);

  Widget _linha(Lista l) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, e) => _teclaLinha(e),
        child: SizedBox(
          height: Tokens.alturaLinhaTabela,
          child: RealceFoco(
            raio: 8,
            construir: (_, aoMudarFoco) => CheckboxListTile(
              focusNode: _focoLinha(l.id),
              onFocusChange: (f) {
                aoMudarFoco(f);
                if (f) _linhaFocada = l.id;
              },
              value: widget.marcadas.contains(l.id),
              onChanged: (v) => _alternar(l.id, v == true),
              title: Row(children: [
                Expanded(
                    child: Text(l.nomeMostrado,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                const SizedBox(width: Tokens.e12),
                // compacta: não passa a altura da linha, nem com a letra do sistema maior
                PilulaEstado(estadoDe(l), compacta: true),
              ]),
              contentPadding: const EdgeInsets.symmetric(horizontal: Tokens.e12),
              horizontalTitleGap: Tokens.e12,
              minVerticalPadding: 0,
              minTileHeight: Tokens.alturaLinhaTabela,
              visualDensity: _densidade,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
          ),
        ),
      );

  Widget _cartao({required String titulo, required String texto, required Widget botao}) => Container(
        padding: const EdgeInsets.all(Tokens.e12),
        decoration: BoxDecoration(color: Tokens.superficie3, borderRadius: BorderRadius.circular(Tokens.raioCartao)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(titulo, style: const TextStyle(color: Tokens.texto, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: Tokens.e4),
          Text(texto, style: const TextStyle(color: Tokens.texto2, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: Tokens.e8),
          botao,
        ]),
      );

  Widget _cartoes(List<Lista> sel) {
    final n = sel.length;
    final listas = _n(n, 'lista', 'listas');
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, e) => _teclaCartoes(e),
      child: Semantics(
        container: true,
        label: 'Para onde',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _cartao(
            titulo: 'Enviar para o Player',
            texto: 'Adicionar às que já lá estão, ou substituir (escolhes a seguir).',
            botao: FilledButton(
              focusNode: _focoEnviar,
              onPressed: n == 0 ? null : () => widget.aoEnviar(sel),
              child: Text('Enviar $listas'),
            ),
          ),
          const SizedBox(height: Tokens.e12),
          _cartao(
            titulo: 'Exportar para ficheiro',
            texto: 'Accounts.json (sfvip) ou .ini num zip (Stalker). O ficheiro leva os dados de acesso.',
            botao: OutlinedButton(
              focusNode: _focoExportar,
              onPressed: n == 0 ? null : () => widget.aoExportar(sel),
              child: Text('Exportar $listas'),
            ),
          ),
        ]),
      ),
    );
  }
}
