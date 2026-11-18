import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/area_gestor.dart';
import '../../dados/biblioteca.dart';
import '../../importar/importar.dart';
import '../../modelo/canal.dart';
import '../adicionar.dart';
import '../campo_tv.dart';
import '../conteudo/tela_conteudo.dart';
import '../design/design.dart';
import '../realce_foco.dart';
import 'acoes_lista.dart';
import 'cartao_continuar.dart';
import 'cartao_lista.dart';

/// Início com os separadores "Player" e "Gestor". O Player mostra as listas em cartões (com o
/// estado da última verificação, pesquisa e filtro por estado) e não gere nada: adicionar,
/// verificar, exportar e enviar listas para o Player faz-se no Gestor. No topo do Player,
/// "Continuar a ver" (o último canal visto). No Android, Voltar no Início pede confirmação.
class TelaInicio extends StatefulWidget {
  const TelaInicio({super.key, required this.biblioteca, this.area, this.separadorGestor, this.abrirLista, this.definicoes,
      this.abrirCanal, this.sair = SystemNavigator.pop});

  /// As listas do Player.
  final Biblioteca biblioteca;

  /// As listas do Gestor: o "+" (só com o separador Gestor ativo) adiciona aqui.
  final AreaGestor? area;

  /// O separador "Gestor".
  final Widget? separadorGestor;

  /// O ecrã de Definições (a roda dentada no topo, nos dois separadores).
  final WidgetBuilder? definicoes;

  /// Para testes: pede os canais de uma lista (em vez do protocolo da conta).
  final AbrirLista? abrirLista;

  /// Para testes: em vez de abrir o player (ver [TelaConteudo.abrir]).
  final FutureOr<int?> Function(List<Canal> canais, int i)? abrirCanal;

  /// Fecha a app (o segundo Voltar no Início).
  final VoidCallback sair;

  @override
  State<TelaInicio> createState() => _TelaInicioState();
}

class _TelaInicioState extends State<TelaInicio> {
  String _q = '';
  int? _abaFocada; // a aba com o foco do comando (para o realce)

  /// O "+": recebe o foco depois de "Ir para o Gestor" (o botão do ecrã vazio desaparece).
  final _focoMais = FocusNode(debugLabel: 'Adicionar listas');

  /// O foco de cada cartão (pelo id da lista): depois de eliminar, o foco passa ao cartão ao lado.
  final _focos = <String, FocusNode>{};

  FocusNode _focoCartao(String id) => _focos.putIfAbsent(id, () => FocusNode(debugLabel: 'Cartão $id'));

  /// Depois do primeiro Voltar, durante [_tempoSair], o segundo fecha a app.
  static const _tempoSair = Duration(seconds: 2);
  Timer? _podeSair;

  /// Android/TV: Voltar no Início (sem nada por cima) não fecha logo a app. No Windows a janela
  /// fecha-se pelo botão de fechar, como sempre.
  bool get _confirmarSaida => defaultTargetPlatform == TargetPlatform.android;

  void _voltar(BuildContext context) {
    if (_podeSair?.isActive ?? false) {
      _podeSair!.cancel();
      widget.sair();
      return;
    }
    _podeSair = Timer(_tempoSair, () {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Carregue outra vez em Voltar para sair'), duration: _tempoSair));
  }

  @override
  void dispose() {
    _podeSair?.cancel();
    _focoMais.dispose();
    for (final f in _focos.values) {
      f.dispose();
    }
    super.dispose();
  }
  String? _filtro; // null = todas; 'por_verificar' = sem resultado

  static const _filtros = [
    (null, 'Todas'),
    ('funciona', 'Funcionam'),
    ('inconclusivo', 'INC'),
    ('nao_funciona', 'Não funcionam'),
    ('por_verificar', 'Por verificar'),
  ];

  List<Lista> _visiveis() {
    final q = semAcentos(_q.trim());
    return [
      for (final l in widget.biblioteca.listas)
        if ((_filtro == null || (l.ultima?.estado ?? 'por_verificar') == _filtro) &&
            (q.isEmpty || semAcentos('${l.nomeMostrado} ${l.conta.endereco} ${l.conta.nome}').contains(q)))
          l,
    ];
  }

  void _avisar(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _eliminar(Lista l) async {
    if (!await confirmarEliminar(context, l)) return;
    final i = _visiveis().indexWhere((x) => x.id == l.id);
    await widget.biblioteca.remover(l.id);
    _focos.remove(l.id)?.dispose();
    // o cartão com o foco desapareceu: o foco passa ao que ficou no lugar dele (ou ao anterior)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final vis = _visiveis();
      if (vis.isEmpty || i < 0) return;
      _focos[vis[i.clamp(0, vis.length - 1)].id]?.requestFocus();
    });
  }

  /// O menu de ações do cartão (pressão longa, clique direito ou OK mantido).
  Future<void> _menu(Lista l) async {
    final area = widget.area;
    final acao = await mostrarMenuLista(context, l, comGestor: area != null);
    if (acao == null || !mounted) return;
    switch (acao) {
      case AcaoLista.abrir:
        _abrir(l);
      case AcaoLista.atualizar:
        _abrir(l, atualizar: true);
      case AcaoLista.editar:
        final m = await mostrarEditarLista(context, widget.biblioteca, l);
        if (m != null) _avisar(m);
      case AcaoLista.copiarLink:
        // nunca se mostra o link (pode ter credenciais)
        await Clipboard.setData(ClipboardData(text: linkParaCopiar(l.conta)));
        _avisar('Link copiado');
      case AcaoLista.enviarGestor:
        final novas = await area!.adicionar([Importada(l.conta, l.ultima)]);
        _avisar(novas > 0 ? 'Enviada para o Gestor' : 'Já estava no Gestor');
      case AcaoLista.eliminar:
        await _eliminar(l);
    }
  }

  void _abrir(Lista l, {bool atualizar = false, String? continuar}) => Navigator.of(context).push(rotaSuave<void>(
        TelaConteudo(biblioteca: widget.biblioteca, lista: l, atualizar: atualizar, abrirLista: widget.abrirLista,
            abrir: widget.abrirCanal, continuar: continuar),
      ));

  /// "Ir para o Gestor": muda de separador e põe o foco no "+" (que só aparece no Gestor).
  void _irParaGestor(BuildContext context) {
    DefaultTabController.of(context).animateTo(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focoMais.context != null) _focoMais.requestFocus();
    });
  }

  Widget _listas() => ListenableBuilder(
        listenable: widget.biblioteca,
        builder: (context, _) {
          final todas = widget.biblioteca.listas;
          final vis = _visiveis();
          final tv = ecraTv(context);
          final visto = widget.biblioteca.ultimoVisto;
          final listaVista = visto == null ? null : widget.biblioteca.porId(visto.lista);
          return Column(children: [
            if (visto != null && listaVista != null)
              Padding(
                // margem para o cartão focado crescer e brilhar sem ser cortado
                padding: const EdgeInsets.fromLTRB(Tokens.e24, Tokens.e16, Tokens.e24, Tokens.e4),
                child: SizedBox(
                  height: CartaoContinuar.altura(tv),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: entradaEmCascata(0, CartaoContinuar(
                      visto: visto,
                      lista: listaVista,
                      autofocus: true,
                      aoAbrir: () => _abrir(listaVista, continuar: visto.canal),
                    )),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e12, Tokens.e16, Tokens.e4),
              child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 280,
                  child: CampoTv(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Pesquisar listas'),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                ),
                for (final (v, t) in _filtros)
                  ChoiceChip(label: Text(t), selected: _filtro == v, onSelected: (_) => setState(() => _filtro = v)),
              ]),
            ),
            Expanded(
              child: todas.isEmpty
                  ? _vazio(context)
                  : vis.isEmpty
                      ? const Center(
                          child: Text('Nenhuma lista com este filtro.', style: TextStyle(color: Tokens.texto2)))
                      : GridView.builder(
                          // margem para o cartão focado crescer (1.04) e brilhar sem ser cortado
                          padding: const EdgeInsets.all(Tokens.e24),
                          // no telemóvel, um cartão por linha (com o nome inteiro)
                          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: MediaQuery.sizeOf(context).width < 600 ? 600 : (tv ? 400 : 340),
                            mainAxisExtent: CartaoLista.altura(tv),
                            crossAxisSpacing: Tokens.e16,
                            mainAxisSpacing: Tokens.e16,
                          ),
                          itemCount: vis.length,
                          // só os primeiros entram em cascata (entradaEmCascata ignora índices > 30)
                          itemBuilder: (_, i) => entradaEmCascata(i, CartaoLista(
                            lista: vis[i],
                            // com "Continuar a ver" o foco começa nele
                            autofocus: i == 0 && widget.biblioteca.ultimoVisto == null,
                            aoAbrir: () => _abrir(vis[i]),
                            focusNode: _focoCartao(vis[i].id),
                            aoMenu: () => _menu(vis[i]),
                          )),
                        ),
            ),
          ]);
        },
      );

  Widget _vazio(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Tokens.e24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: entradaEmCascata(0, SuperficieVidro(
              padding: const EdgeInsets.all(Tokens.e32),
              elevacao: 2,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Tokens.gradienteAcento),
                  child: const Icon(Icons.live_tv_outlined, size: 36, color: Colors.white),
                ),
                const SizedBox(height: Tokens.e16),
                const Text('Ainda não há listas no Player',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: Tokens.e8),
                const Text('Adicione e verifique listas no Gestor e envie-as para o Player.',
                    textAlign: TextAlign.center, style: TextStyle(color: Tokens.texto2)),
                if (widget.separadorGestor != null) ...[
                  const SizedBox(height: Tokens.e24),
                  FilledButton.icon(
                    autofocus: true,
                    onPressed: () => _irParaGestor(context),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Ir para o Gestor'),
                  ),
                ],
              ]),
            )),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final temGestor = widget.separadorGestor != null;
    return PopScope(
      // o Voltar do comando no Início: "Carregue outra vez em Voltar para sair"
      canPop: !_confirmarSaida,
      onPopInvokedWithResult: (saiu, _) {
        if (!saiu) _voltar(context);
      },
      child: temGestor ? _comAbas() : _corpo(context, gestorAtivo: false),
    );
  }

  Widget _comAbas() {
    return DefaultTabController(
      length: 2,
      // com "reduzir movimento" a troca de abas também é instantânea
      animationDuration: duracaoAnimada(context, kTabScrollDuration),
      child: Builder(builder: (context) {
        final c = DefaultTabController.of(context);
        return ListenableBuilder(listenable: c, builder: (context, _) => _corpo(context, gestorAtivo: c.index == 1));
      }),
    );
  }

  Widget _corpo(BuildContext context, {required bool gestorAtivo}) {
    final temGestor = widget.separadorGestor != null;
    final area = widget.area;
    return Scaffold(
      appBar: AppBar(
        // as abas ficam na mesma linha do "+": CIMA a partir do conteúdo para nas abas (nada
        // por cima delas) e ESQUERDA/DIREITA trocam Player, Gestor e o "+" (só no Gestor)
        title: temGestor
            ? Row(children: [
                // no telemóvel não há espaço para o nome e as abas
                if (MediaQuery.sizeOf(context).width >= 600) ...const [_Marca(), SizedBox(width: Tokens.e16)],
                Expanded(
                  // sem o "+" (no Player), DIREITA na última aba fica nela (não salta para os filtros)
                  child: Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    includeSemantics: false,
                    onKeyEvent: (_, e) => e is! KeyUpEvent &&
                            e.logicalKey == LogicalKeyboardKey.arrowRight &&
                            _abaFocada == 1 &&
                            !(gestorAtivo && area != null) &&
                            widget.definicoes == null
                        ? KeyEventResult.handled
                        : KeyEventResult.ignored,
                    child: TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      dividerColor: Colors.transparent,
                      onFocusChange: (f, i) =>
                          setState(() => _abaFocada = f ? i : (_abaFocada == i ? null : _abaFocada)),
                      tabs: [
                        for (final (i, t) in const ['Player', 'Gestor'].indexed)
                          Tab(child: MolduraFoco(focado: _abaFocada == i, raio: 8, child: _Aba(t))),
                      ],
                    ),
                  ),
                ),
              ])
            : const _Marca(),
        actions: [
          if (gestorAtivo && area != null)
            IconButton(
              focusNode: _focoMais,
              tooltip: 'Adicionar listas',
              onPressed: () => mostrarAdicionar(context, area),
              icon: const Icon(Icons.add),
            ),
          if (widget.definicoes != null)
            IconButton(
              tooltip: 'Definições',
              onPressed: () => Navigator.of(context).push(rotaSuave<void>(widget.definicoes!(context))),
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      body: temGestor ? TabBarView(children: [_listas(), widget.separadorGestor!]) : _listas(),
    );
  }
}

/// O nome da app com o ícone em gradiente.
class _Marca extends StatelessWidget {
  const _Marca();

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(gradient: Tokens.gradienteAcento, borderRadius: BorderRadius.circular(9)),
          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 10),
        const Text('Player IPTV'),
      ]);
}

/// O nome de uma aba (com espaço para a borda do realce).
class _Aba extends StatelessWidget {
  const _Aba(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Text(texto));
}
