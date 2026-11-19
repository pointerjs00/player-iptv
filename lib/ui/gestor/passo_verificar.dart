import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/area_gestor.dart';
import '../../dados/biblioteca.dart';
import '../../modelo/canal.dart';
import '../../verificar/servico.dart';
import '../design/design.dart';
import '../campo_tv.dart';
import '../realce_foco.dart';

/// As ações do menu «Ações».
enum _Acao { verificarSelecionadas, verificarTodas, remover }

/// O passo 2 do Gestor, "Verificar": numa linha a pesquisa, os estados (de escolha múltipla:
/// nenhum ligado mostra todas) e o botão `Ações (N)`; por baixo a tabela `☐ LISTA · ESTADO ·
/// MOTIVO · TESTE`, de linhas baixas, com a ☐ do cabeçalho a selecionar / desselecionar as
/// visíveis.
///
/// `Ações (N)` (ou a tecla Menu do comando, de qualquer sítio do passo, menos a escrever num
/// campo) abre o menu `Verificar selecionadas` · `Verificar todas` · `Remover do gestor`. O
/// progresso da verificação abre-se no indicador do topo (na `TelaGestor`).
///
/// Guarda a pesquisa, os estados e a seleção (ids; os que saem do Gestor saem da seleção). As
/// linhas são preguiçosas (`SliverList.builder`).
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

  /// Abre o progresso da verificação (o indicador do topo, na `TelaGestor`, faz o mesmo).
  final VoidCallback aoVerVerificacao;

  /// "Remover do gestor": quem chama confirma e remove.
  final Future<void> Function(List<Lista>) aoRemover;

  /// O controlo que recebe o foco quando o passo abre (por omissão, a pesquisa não o pede).
  final FocusNode? focoInicial;

  /// O relógio da coluna TESTE (trocável nos testes).
  final DateTime Function()? agora;

  @override
  State<PassoVerificar> createState() => PassoVerificarState();
}

/// O estado do passo 2 ([filtrar] serve a quem o abre com estados já escolhidos).
class PassoVerificarState extends State<PassoVerificar> {
  static const _estados = <(EstadoLista, String)>[
    (EstadoLista.funciona, 'Funcionam'),
    (EstadoLista.inconclusiva, 'Inconclusivas'),
    (EstadoLista.naoFunciona, 'Não funcionam'),
    (EstadoLista.porVerificar, 'Por verificar'),
  ];

  /// A altura de cada linha da tabela (fixa e baixa: na TV cabem pelo menos 12).
  static const alturaLinha = 32.0;

  final _pesquisa = TextEditingController();

  /// Os estados ligados (vazio = todas).
  final _filtro = <EstadoLista>{};
  final _selecao = <String>{};

  final _focosEstados = [for (final (_, t) in _estados) FocusNode(debugLabel: 'Filtro $t')];
  final _focoCabecalho = FocusNode(debugLabel: 'Selecionar as visíveis');
  final _focoAcoes = FocusNode(debugLabel: 'Ações');
  final _chaveAcoes = GlobalKey(debugLabel: 'Ações');

  final _focosLinhas = <String, FocusNode>{};
  String? _linhaFocada;
  List<String> _ordemVista = const [];

  AreaGestor get _g => widget.area;
  ServicoVerificacao get _s => widget.servico;

  @override
  void initState() {
    super.initState();
    for (final f in _focosEstados) {
      f.addListener(() => _estadoAVista(f));
    }
  }

  /// Um estado com o foco fica todo à vista na sua linha (que desliza para o lado quando não
  /// cabem todos): também quando o foco lá chega sem as setas (por exemplo, [filtrar]). Senão,
  /// meio tapado, DIREITA não chegava a `Ações`.
  void _estadoAVista(FocusNode f) {
    final ctx = f.context;
    if (!f.hasPrimaryFocus || ctx == null) return;
    final pos = Scrollable.maybeOf(ctx, axis: Axis.horizontal)?.position;
    final caixa = ctx.findRenderObject();
    if (pos == null || caixa == null || !caixa.attached) return;
    pos.ensureVisible(caixa, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
    pos.ensureVisible(caixa, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart);
  }

  /// Mostra só as listas com os `estados` (vazio = todas), sem pesquisa, e põe o foco no 1.º
  /// desses estados (sem nenhum, na pesquisa).
  void filtrar(Set<EstadoLista> estados) {
    _pesquisa.clear();
    setState(() => _filtro
      ..clear()
      ..addAll(estados));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final i = _estados.indexWhere((e) => estados.contains(e.$1));
      (i >= 0 ? _focosEstados[i] : widget.focoInicial ?? _focosEstados.first).requestFocus();
    });
  }

  @override
  void dispose() {
    _pesquisa.dispose();
    for (final f in [..._focosEstados, ..._focosLinhas.values, _focoCabecalho, _focoAcoes]) {
      f.dispose();
    }
    super.dispose();
  }

  FocusNode _focoLinha(String id) => _focosLinhas.putIfAbsent(id, () => FocusNode(debugLabel: 'Linha'));

  List<Lista> _visiveis() {
    final q = semAcentos(_pesquisa.text.trim());
    return [
      for (final l in _g.listas)
        if ((_filtro.isEmpty || _filtro.contains(estadoDe(l))) && (q.isEmpty || semAcentos(l.nomeMostrado).contains(q))) l,
    ];
  }

  List<Lista> get _selecionadas => [for (final l in _g.listas) if (_selecao.contains(l.id)) l];

  /// A ☐ do cabeçalho: true com todas as visíveis selecionadas, false com nenhuma, null (o traço)
  /// com parte delas.
  bool? _estadoCabecalho(List<Lista> visiveis) {
    final n = visiveis.where((l) => _selecao.contains(l.id)).length;
    if (n == 0) return false;
    return n == visiveis.length ? true : null;
  }

  /// OK na ☐ do cabeçalho: com todas as visíveis selecionadas desseleciona-as; senão a seleção
  /// passa a ser exatamente as visíveis.
  void _alternarVisiveis() {
    final vis = _visiveis();
    setState(() {
      if (vis.isNotEmpty && _estadoCabecalho(vis) == true) {
        _selecao.removeAll(vis.map((l) => l.id));
      } else {
        _selecao
          ..clear()
          ..addAll(vis.map((l) => l.id));
      }
    });
  }

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

  /// A linha com o foco saiu da tabela (estados, pesquisa, remoção): o foco passa à que ficou no
  /// lugar dela ou, sem linhas, ao botão `Ações` (senão perdia-se e deixava de se ver).
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
      if (vis.isEmpty) {
        _focoAcoes.requestFocus();
      } else {
        _focoLinha(vis[antes.clamp(0, vis.length - 1)].id).requestFocus();
      }
    });
  }

  /// A tecla Menu do comando abre as ações (a escrever num campo, a tecla fica para o campo).
  KeyEventResult _tecla(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.contextMenu) return KeyEventResult.ignored;
    final contexto = FocusManager.instance.primaryFocus?.context;
    final campo = contexto?.widget is EditableText
        ? contexto!.widget as EditableText
        : contexto?.findAncestorWidgetOfExactType<EditableText>();
    if (campo != null && !campo.readOnly) return KeyEventResult.ignored;
    _abrirAcoes();
    return KeyEventResult.handled;
  }

  /// O menu das ações, por baixo do botão `Ações`. Voltar fecha-o e o foco volta a quem o tinha.
  Future<void> _abrirAcoes() async {
    final botao = _chaveAcoes.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (botao == null || overlay == null || !botao.attached) return;
    final caixa = Rect.fromPoints(
      botao.localToGlobal(botao.size.bottomLeft(Offset.zero), ancestor: overlay),
      botao.localToGlobal(botao.size.bottomRight(Offset.zero), ancestor: overlay),
    );
    final n = _selecionadas.length;
    final itens = [
      (_Acao.verificarSelecionadas, 'Verificar selecionadas', Icons.playlist_add_check, n > 0),
      (_Acao.verificarTodas, 'Verificar todas', Icons.fact_check_outlined, _g.listas.isNotEmpty),
      (_Acao.remover, 'Remover do gestor', Icons.remove_circle_outline, n > 0),
    ];
    final primeiro = itens.indexWhere((i) => i.$4);
    final escolha = await showMenu<_Acao>(
      context: context,
      position: RelativeRect.fromRect(caixa, Offset.zero & overlay.size),
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 360),
      items: [
        for (final (i, (acao, texto, icone, ligado)) in itens.indexed)
          PopupMenuItem(
            value: acao,
            enabled: ligado,
            child: _ItemMenu(
              focoAoAbrir: i == primeiro,
              child: Row(children: [
                Icon(icone, size: 20, color: acao == _Acao.remover && ligado ? Tokens.mau : null),
                const SizedBox(width: Tokens.e12),
                Flexible(
                  child: Text(texto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: acao == _Acao.remover && ligado ? const TextStyle(color: Tokens.mau) : null),
                ),
              ]),
            ),
          ),
      ],
    );
    if (!mounted || escolha == null) return;
    // a seleção como está agora (pode ter mudado com o menu aberto)
    final sel = _selecionadas;
    switch (escolha) {
      case _Acao.verificarSelecionadas:
        if (sel.isNotEmpty) widget.aoVerificar(sel);
      case _Acao.verificarTodas:
        widget.aoVerificarTodas();
      case _Acao.remover:
        if (sel.isNotEmpty) await widget.aoRemover(sel);
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        onKeyEvent: (_, e) => _tecla(e),
        child: ListenableBuilder(
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
            // a linha de cima e o cabeçalho deslizam com as linhas (que continuam preguiçosas)
            final topo = [
              _linhaDeCima(caixa.maxWidth, contagens),
              if (listas.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(Tokens.e16),
                  child: Text('Ainda não há listas. Comece pelo passo 1: importe as listas.',
                      style: TextStyle(color: Tokens.texto2)),
                )
              else ...[
                _cabecalho(largo, visiveis),
                if (visiveis.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(Tokens.e16),
                    child: Text('Nenhuma lista com estes estados.', style: TextStyle(color: Tokens.texto2)),
                  ),
              ],
            ];
            return CustomScrollView(slivers: [
              SliverList.list(children: topo),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Tokens.e16, 0, Tokens.e16, Tokens.e8),
                sliver: SliverList.builder(
                  itemCount: visiveis.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Material(
                      type: MaterialType.transparency,
                      child: _linha(visiveis[i], largo, agora),
                    ),
                  ),
                ),
              ),
            ]);
          }),
        ),
      );

  /// A pesquisa, os estados e, à direita, `Ações (N)`: numa só linha quando cabem (TV, Windows),
  /// senão em várias.
  Widget _linhaDeCima(double largura, Map<EstadoLista, int> contagens) {
    final pesquisa = CampoTv(
      controller: _pesquisa,
      focusNode: widget.focoInicial,
      // baixa (40), como os estados e Ações: a linha de cima não come linhas à tabela
      decoration: const InputDecoration(
        hintText: 'Pesquisar listas…',
        prefixIcon: Icon(Icons.search),
        prefixIconConstraints: BoxConstraints(minWidth: 40, minHeight: 36),
        contentPadding: EdgeInsets.symmetric(horizontal: Tokens.e12, vertical: 10),
        isDense: true,
      ),
    );
    final estados = [
      for (final (i, (e, t)) in _estados.indexed)
        FilterChip(
          focusNode: _focosEstados[i],
          label: Text('$t · ${contagens[e] ?? 0}'),
          selected: _filtro.contains(e),
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          onSelected: (v) => setState(() => v ? _filtro.add(e) : _filtro.remove(e)),
        ),
    ];
    final n = _selecionadas.length;
    final acoes = FilledButton(
      key: const ValueKey('botaoAcoes'),
      focusNode: _focoAcoes,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: Tokens.e16, vertical: Tokens.e8),
      ),
      onPressed: _abrirAcoes,
      child: Row(key: _chaveAcoes, mainAxisSize: MainAxisSize.min, children: [
        Text('Ações ($n)'),
        const SizedBox(width: Tokens.e4),
        const Icon(Icons.arrow_drop_down, size: 20),
      ]),
    );
    const margem = EdgeInsets.fromLTRB(Tokens.e16, Tokens.e8, Tokens.e16, Tokens.e4);
    // no telemóvel não cabe numa linha: em várias
    if (largura < 700) {
      return Padding(
        padding: margem,
        child: Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(width: 260, child: pesquisa),
          ...estados,
          acoes,
        ]),
      );
    }
    // na TV e no Windows, uma só linha (de altura fixa): se os estados não couberem, deslizam
    // para o lado (o foco leva-os à vista); Ações fica sempre à direita
    return Padding(
      padding: margem,
      child: Row(children: [
        SizedBox(width: 200, child: pesquisa),
        const SizedBox(width: Tokens.e8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final (i, c) in estados.indexed) ...[if (i > 0) const SizedBox(width: Tokens.e8), c],
            ]),
          ),
        ),
        const SizedBox(width: Tokens.e8),
        acoes,
      ]),
    );
  }

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

  /// O espaço à esquerda da linha até à coluna LISTA: margem do tile + caixa + espaço.
  static const _recuoTile = 12.0;
  static const _caixa = 40.0;
  static const _espacoTitulo = 12.0;

  /// Linhas baixas (a caixa de cada linha e a do cabeçalho usam a mesma).
  static const _densidade = VisualDensity(vertical: VisualDensity.minimumDensity);

  Widget _cabecalho(bool largo, List<Lista> visiveis) {
    Text t(String s) => Text(s,
        style: const TextStyle(color: Tokens.texto2, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .8));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.e16 + _recuoTile, 0, Tokens.e16 + _recuoTile, Tokens.e4),
      child: Row(children: [
        SizedBox(
          width: _caixa,
          child: RealceFoco(
            raio: 6,
            construir: (_, aoMudarFoco) => Focus(
              canRequestFocus: false,
              skipTraversal: true,
              includeSemantics: false,
              onFocusChange: aoMudarFoco,
              child: Checkbox(
                key: const ValueKey('caixaCabecalho'),
                focusNode: _focoCabecalho,
                tristate: true,
                value: _estadoCabecalho(visiveis),
                semanticLabel: 'Selecionar as visíveis',
                visualDensity: _densidade,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: visiveis.isEmpty ? null : (_) => _alternarVisiveis(),
              ),
            ),
          ),
        ),
        const SizedBox(width: _espacoTitulo),
        Expanded(child: _colunas(largo, t('LISTA'), t('ESTADO'), t('MOTIVO'), t('TESTE'))),
      ]),
    );
  }

  Widget _linha(Lista l, bool largo, DateTime agora) {
    final passo = _s.passos[l.id];
    final u = l.ultima;
    final motivo = u?.motivo ?? '';
    final Widget estado = passo == null
        ? Align(alignment: Alignment.centerLeft, child: PilulaEstado(estadoDe(l)))
        : Text(passo == 'na fila' ? 'Na fila' : 'A verificar · $passo',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Tokens.anelFoco, fontWeight: FontWeight.w600));
    const pequeno = TextStyle(color: Tokens.texto2, fontSize: 13);
    return SizedBox(
      height: alturaLinha,
      child: RealceFoco(
        raio: 8,
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
          horizontalTitleGap: _espacoTitulo,
          minVerticalPadding: 0,
          minTileHeight: alturaLinha,
          visualDensity: _densidade,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
        ),
      ),
    );
  }
}

/// O conteúdo de um item do menu, com o realce do foco (o do resto da app: o fundo do InkWell
/// do `PopupMenuItem` não chega na TV). Com [focoAoAbrir] põe o foco no item quando o menu abre:
/// com o comando, o 1.º item ligado fica logo escolhido.
class _ItemMenu extends StatefulWidget {
  const _ItemMenu({required this.focoAoAbrir, required this.child});
  final bool focoAoAbrir;
  final Widget child;

  @override
  State<_ItemMenu> createState() => _ItemMenuState();
}

class _ItemMenuState extends State<_ItemMenu> {
  @override
  void initState() {
    super.initState();
    if (!widget.focoAoAbrir) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Focus.maybeOf(context)?.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) => MolduraFoco(
        // o foco é do InkWell do item (Focus.of reconstrói quando ele muda)
        focado: Focus.maybeOf(context)?.hasPrimaryFocus ?? false,
        raio: 8,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: Tokens.e8),
          alignment: Alignment.centerLeft,
          child: widget.child,
        ),
      );
}
