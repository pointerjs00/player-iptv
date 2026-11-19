import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/area_gestor.dart';
import '../../dados/biblioteca.dart';
import '../../modelo/canal.dart';
import '../../verificar/servico.dart';
import '../design/design.dart';
import '../campo_tv.dart';
import '../realce_foco.dart';

/// O passo 2 do Gestor, "Verificar": a pesquisa, os filtros pelo estado, a seleção rápida, a tabela
/// `LISTA · ESTADO · MOTIVO · TESTE` e, em baixo, a barra de ações nos azuis da app (`Verificar
/// selecionadas` · `Verificar todas` · `Ver verificação` · `Remover do gestor`).
///
/// Guarda a pesquisa, o filtro e a seleção (ids; os que saem do Gestor saem da seleção). As linhas
/// são preguiçosas (`SliverList.builder`). BAIXO na última linha vai à barra; CIMA na barra volta
/// à última linha que teve o foco.
class PassoVerificar extends StatefulWidget {
  const PassoVerificar({
    super.key,
    required this.area,
    required this.servico,
    required this.aoVerificar,
    required this.aoVerificarTodas,
    required this.aoVerVerificacao,
    required this.aoRemover,
    this.focoInicial,
    this.agora,
  });

  final AreaGestor area;
  final ServicoVerificacao servico;

  /// "Verificar selecionadas": as listas marcadas (pela ordem do Gestor).
  final ValueChanged<List<Lista>> aoVerificar;
  final VoidCallback aoVerificarTodas;
  final VoidCallback aoVerVerificacao;

  /// "Remover do gestor": quem chama confirma e remove.
  final Future<void> Function(List<Lista>) aoRemover;

  /// O controlo que recebe o foco quando o passo abre (por omissão, a pesquisa não o pede).
  final FocusNode? focoInicial;

  /// O relógio da coluna TESTE (trocável nos testes).
  final DateTime Function()? agora;

  @override
  State<PassoVerificar> createState() => _PassoVerificarState();
}

class _PassoVerificarState extends State<PassoVerificar> {
  static const _filtros = <(EstadoLista?, String)>[
    (null, 'Todas'),
    (EstadoLista.funciona, 'Funcionam'),
    (EstadoLista.inconclusiva, 'Inconclusivas'),
    (EstadoLista.naoFunciona, 'Não funcionam'),
    (EstadoLista.porVerificar, 'Por verificar'),
  ];

  final _pesquisa = TextEditingController();
  EstadoLista? _filtro;
  final _selecao = <String>{};

  final _focosLinhas = <String, FocusNode>{};
  String? _linhaFocada;
  List<String> _ordemVista = const [];

  final _focoVerSel = FocusNode(debugLabel: 'Verificar selecionadas');
  final _focoVerTodas = FocusNode(debugLabel: 'Verificar todas');
  final _focoVerVer = FocusNode(debugLabel: 'Ver verificação');
  final _focoRemover = FocusNode(debugLabel: 'Remover do gestor');

  List<FocusNode> get _focosBarra => [_focoVerSel, _focoVerTodas, _focoVerVer, _focoRemover];

  AreaGestor get _g => widget.area;
  ServicoVerificacao get _s => widget.servico;

  @override
  void initState() {
    super.initState();
    _focoVerSel.addListener(() => _seDesligou(_focoVerSel));
    _focoRemover.addListener(() => _seDesligou(_focoRemover));
  }

  /// O botão com o foco ficou desativado (a seleção esvaziou-se): o foco passa a "Verificar
  /// todas", que está sempre ativo (senão perdia-se e deixava de se ver).
  void _seDesligou(FocusNode no) {
    if (no.hasFocus || no.canRequestFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final atual = FocusManager.instance.primaryFocus;
      if (mounted && _focoVerTodas.canRequestFocus && (atual == null || atual is FocusScopeNode)) {
        _focoVerTodas.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _pesquisa.dispose();
    for (final f in _focosLinhas.values) {
      f.dispose();
    }
    for (final f in _focosBarra) {
      f.dispose();
    }
    super.dispose();
  }

  FocusNode _focoLinha(String id) => _focosLinhas.putIfAbsent(id, () => FocusNode(debugLabel: 'Linha'));

  List<Lista> _visiveis() {
    final q = semAcentos(_pesquisa.text.trim());
    return [
      for (final l in _g.listas)
        if ((_filtro == null || estadoDe(l) == _filtro) && (q.isEmpty || semAcentos(l.nomeMostrado).contains(q))) l,
    ];
  }

  List<Lista> get _selecionadas => [for (final l in _g.listas) if (_selecao.contains(l.id)) l];

  void _marcar(bool Function(Lista) criterio) =>
      setState(() => _selecao..clear()..addAll([for (final l in _visiveis()) if (criterio(l)) l.id]));

  /// Já houve uma verificação nesta sessão (a decorrer, ou acabou uma ronda).
  bool get _houveVerificacao => _s.ocupado || _s.fimRonda != null;

  DateTime get _agora => (widget.agora ?? DateTime.now)();

  /// "nunca", "agora", "há 5 min", "há 2 h", "ontem", "há 3 dias", ou a data.
  static String _teste(DateTime? d, DateTime agora) {
    if (d == null) return 'nunca';
    final dif = agora.difference(d);
    if (dif.inMinutes < 1) return 'agora';
    if (dif.inMinutes < 60) return 'há ${dif.inMinutes} min';
    final dia = DateTime(d.year, d.month, d.day);
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final dias = hoje.difference(dia).inDays;
    if (dias == 0) return 'há ${dif.inHours} h';
    if (dias == 1) return 'ontem';
    if (dias < 30) return 'há $dias dias';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  /// A linha com o foco saiu da tabela (filtro, pesquisa, remoção): o foco passa à que ficou no
  /// lugar dela ou, sem linhas, à pesquisa.
  void _vigiarLinhaFocada(List<Lista> visiveis) {
    final id = _linhaFocada;
    if (id == null || visiveis.any((l) => l.id == id)) return;
    final no = _focosLinhas[id];
    _linhaFocada = null;
    if (no == null || !no.hasPrimaryFocus) return;
    final antes = _ordemVista.indexOf(id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final vis = _visiveis();
      if (vis.isNotEmpty) _focoLinha(vis[antes.clamp(0, vis.length - 1)].id).requestFocus();
    });
  }

  KeyEventResult _teclaLinha(String id, KeyEvent e, bool ultima) {
    if (e is KeyUpEvent || !ultima || e.logicalKey != LogicalKeyboardKey.arrowDown) return KeyEventResult.ignored;
    final alvo = _focosBarra.where((f) => f.canRequestFocus).firstOrNull;
    if (alvo == null) return KeyEventResult.ignored;
    alvo.requestFocus();
    return KeyEventResult.handled;
  }

  KeyEventResult _teclaBarra(KeyEvent e) {
    if (e is KeyUpEvent || e.logicalKey != LogicalKeyboardKey.arrowUp) return KeyEventResult.ignored;
    final vis = _visiveis();
    if (vis.isEmpty) return KeyEventResult.ignored;
    final id = vis.any((l) => l.id == _linhaFocada) ? _linhaFocada! : vis.last.id;
    final no = _focoLinha(id);
    if (!no.canRequestFocus || no.context == null) return KeyEventResult.ignored;
    no.requestFocus();
    return KeyEventResult.handled;
  }

  static String _n(int n, String um, String varios) => '$n ${n == 1 ? um : varios}';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([_g, _s, _pesquisa]),
        builder: (context, _) => LayoutBuilder(builder: (context, caixa) {
          final listas = _g.listas;
          _selecao.removeWhere((id) => _g.porId(id) == null);
          final contagens = <EstadoLista, int>{};
          for (final l in listas) {
            contagens.update(estadoDe(l), (n) => n + 1, ifAbsent: () => 1);
          }
          final visiveis = _visiveis();
          _vigiarLinhaFocada(visiveis);
          final largo = caixa.maxWidth >= 560;
          final agora = _agora;
          final ultimaId = visiveis.isEmpty ? null : visiveis.last.id;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e12, Tokens.e16, 0),
              child: Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 300,
                  child: CampoTv(
                    controller: _pesquisa,
                    focusNode: widget.focoInicial,
                    decoration: const InputDecoration(
                      hintText: 'Pesquisar listas…',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                ),
                for (final (e, t) in _filtros)
                  ChoiceChip(
                    label: Text('$t · ${e == null ? listas.length : contagens[e] ?? 0}'),
                    selected: _filtro == e,
                    onSelected: (_) => setState(() => _filtro = e),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e8, Tokens.e16, Tokens.e8),
              child: Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('Selecionar:', style: TextStyle(color: Tokens.texto2, fontWeight: FontWeight.w500)),
                ActionChip(label: const Text('Todas as visíveis'), onPressed: () => _marcar((_) => true)),
                ActionChip(
                    label: const Text('Por verificar'),
                    onPressed: () => _marcar((l) => estadoDe(l) == EstadoLista.porVerificar)),
                ActionChip(label: const Text('Nenhuma'), onPressed: () => _marcar((_) => false)),
              ]),
            ),
            if (listas.isEmpty)
              const Padding(
                padding: EdgeInsets.all(Tokens.e16),
                child: Text('Ainda não há listas. Comece pelo passo 1: importe as listas.',
                    style: TextStyle(color: Tokens.texto2)),
              )
            else ...[
              _cabecalho(largo),
              Expanded(
                child: visiveis.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(Tokens.e16),
                        child: Text('Nenhuma lista com este filtro.', style: TextStyle(color: Tokens.texto2)),
                      )
                    : CustomScrollView(slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(Tokens.e16, 0, Tokens.e16, Tokens.e8),
                          sliver: SliverList.builder(
                            itemCount: visiveis.length,
                            itemBuilder: (_, i) => Padding(
                              padding: const EdgeInsets.only(bottom: Tokens.e4),
                              child: Material(
                                type: MaterialType.transparency,
                                child: _linha(visiveis[i], largo, agora, visiveis[i].id == ultimaId),
                              ),
                            ),
                          ),
                        ),
                      ]),
              ),
            ],
            if (listas.isEmpty) const Spacer(),
            _barra(),
          ]);
        }),
      );

  /// As colunas (o cabeçalho e cada linha usam as mesmas larguras).
  static Widget _colunas(bool largo, Widget lista, Widget estado, Widget motivo, Widget teste) =>
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(flex: 4, child: lista),
        const SizedBox(width: Tokens.e12),
        SizedBox(width: 170, child: estado),
        if (largo) ...[
          const SizedBox(width: Tokens.e12),
          Expanded(flex: 4, child: motivo),
        ],
        const SizedBox(width: Tokens.e12),
        SizedBox(width: 84, child: teste),
      ]);

  /// O espaço à esquerda da linha até à coluna LISTA: margem do tile (16) + caixa (40) + espaço (16).
  static const _recuoTile = 16.0;
  static const _caixa = 40.0;

  Widget _cabecalho(bool largo) {
    Text t(String s) => Text(s,
        style: const TextStyle(color: Tokens.texto2, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .8));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.e16 + _recuoTile + _caixa + 16, Tokens.e4, Tokens.e16 + _recuoTile, Tokens.e8),
      child: _colunas(largo, t('LISTA'), t('ESTADO'), t('MOTIVO'), t('TESTE')),
    );
  }

  Widget _linha(Lista l, bool largo, DateTime agora, bool ultima) {
    final passo = _s.passos[l.id];
    final u = l.ultima;
    final motivo = u?.motivo ?? '';
    final Widget estado = passo == null
        ? Align(alignment: Alignment.centerLeft, child: PilulaEstado(estadoDe(l)))
        : Text(passo == 'na fila' ? 'Na fila' : 'A verificar · $passo',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Tokens.anelFoco, fontWeight: FontWeight.w600));
    const pequeno = TextStyle(color: Tokens.texto2, fontSize: 13);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, e) => _teclaLinha(l.id, e, ultima),
      child: RealceFoco(
        construir: (_, aoMudarFoco) => CheckboxListTile(
          focusNode: _focoLinha(l.id),
          onFocusChange: (f) {
            aoMudarFoco(f);
            if (f) {
              _linhaFocada = l.id;
              _ordemVista = [for (final x in _visiveis()) x.id];
            }
          },
          value: _selecao.contains(l.id),
          onChanged: (v) => setState(() => v == true ? _selecao.add(l.id) : _selecao.remove(l.id)),
          title: _colunas(
            largo,
            Text(l.nomeMostrado, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            estado,
            Text(motivo.isEmpty ? '—' : motivo, maxLines: 1, overflow: TextOverflow.ellipsis, style: pequeno),
            Text(_teste(u?.data, agora), maxLines: 1, style: pequeno),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: _recuoTile),
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
        ),
      ),
    );
  }

  /// A barra de ações, em baixo, sobre `superficie3`.
  Widget _barra() {
    final sel = _selecionadas;
    final n = sel.length;
    final verTexto = _s.ocupado ? 'Ver verificação · ${_s.feitas}/${_s.total}' : 'Ver verificação';
    final podeVer = _houveVerificacao;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, e) => _teclaBarra(e),
      child: Container(
        key: const ValueKey('barraAcoes'),
        margin: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e8, Tokens.e16, Tokens.e12),
        padding: const EdgeInsets.symmetric(horizontal: Tokens.e12, vertical: Tokens.e8),
        decoration: BoxDecoration(color: Tokens.superficie3, borderRadius: BorderRadius.circular(Tokens.raioBotao)),
        child: Semantics(
          container: true,
          label: 'Ações de verificação',
          child: Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(n == 0 ? 'Nenhuma selecionada' : _n(n, 'selecionada', 'selecionadas'),
                style: const TextStyle(color: Tokens.texto, fontWeight: FontWeight.w600)),
            FilledButton(
              focusNode: _focoVerSel,
              onPressed: n == 0 ? null : () => widget.aoVerificar(sel),
              child: const Text('Verificar selecionadas'),
            ),
            OutlinedButton(
              focusNode: _focoVerTodas,
              onPressed: _g.listas.isEmpty ? null : widget.aoVerificarTodas,
              child: const Text('Verificar todas'),
            ),
            OutlinedButton(
              focusNode: _focoVerVer,
              onPressed: podeVer ? widget.aoVerVerificacao : null,
              child: podeVer
                  ? Text(verTexto)
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(verTexto),
                      const Text('nenhuma verificação', style: TextStyle(fontSize: 11)),
                    ]),
            ),
            OutlinedButton(
              focusNode: _focoRemover,
              style: OutlinedButton.styleFrom(foregroundColor: Tokens.mau),
              onPressed: n == 0 ? null : () => widget.aoRemover(sel),
              child: const Text('Remover do gestor'),
            ),
          ]),
        ),
      ),
    );
  }
}
