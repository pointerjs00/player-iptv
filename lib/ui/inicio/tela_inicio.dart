import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/area_gestor.dart';
import '../../dados/biblioteca.dart';
import '../../importar/importar.dart';
import '../../verificar/servico.dart';
import '../../protocolos/protocolo.dart';
import '../../rede/http.dart';
import '../../modelo/conta.dart';
import '../../modelo/canal.dart';
import '../campo_tv.dart';
import '../conteudo/tela_conteudo.dart';
import '../design/barra_teclas.dart';
import '../design/design.dart';
import '../principal/tela_principal.dart';
import 'acoes_lista.dart';
import 'cartao_continuar.dart';
import 'cartao_lista.dart';
import 'favoritos_inicio.dart';
import '../design/mensagens.dart';

/// Ver TV, o Início: "Continuar a ver" (o último canal visto), os favoritos de todas as listas e
/// as listas em cartões (com o estado da última verificação, pesquisa e filtro por estado). Sem
/// listas, explica como as trazer do Gestor. Não gere nada: adicionar, verificar, exportar e
/// enviar listas para o Player faz-se no Gestor. As secções, o Voltar e a confirmação da saída
/// são da casca ([TelaPrincipal]).
class TelaInicio extends StatefulWidget {
  const TelaInicio({super.key, required this.biblioteca, this.area, this.servico, this.abrirLista, this.abrirCanal});

  /// As listas do Player.
  final Biblioteca biblioteca;

  /// As listas do Gestor: o menu do cartão envia para aqui.
  final AreaGestor? area;

  /// A verificação do Player (grava nas listas do Player): sem ela não há "Verificar agora".
  final ServicoVerificacao? servico;

  /// Para testes: pede os canais de uma lista (em vez do protocolo da conta).
  final AbrirLista? abrirLista;

  /// Para testes: em vez de abrir o player (ver [TelaConteudo.abrir]).
  final FutureOr<int?> Function(List<Canal> canais, int i)? abrirCanal;

  @override
  State<TelaInicio> createState() => _TelaInicioState();
}

class _TelaInicioState extends State<TelaInicio> {
  String _q = '';

  /// O texto da pesquisa (fica ao mudar de disposição, estreita ↔ larga).
  final _pesquisa = TextEditingController();

  /// O resumo da cache de cada lista (pelo id): contagens, favoritos e o número do canal visto.
  Map<String, ResumoLista> _resumos = const {};
  late ResumosInicio _resumidor = ResumosInicio(widget.biblioteca);
  int _geracao = 0;

  /// Se o Início está à vista (a rota dele é a de cima e a secção está ativa). Tapado (lista
  /// aberta, player, outra secção), as mudanças só marcam [_pendente]: lê-se ao voltar.
  bool _visivel = false;
  bool _pendente = true;

  /// O foco de cada cartão (pelo id da lista): depois de eliminar, o foco passa ao cartão ao lado.
  final _focos = <String, FocusNode>{};

  FocusNode _focoCartao(String id) => _focos.putIfAbsent(id, () => FocusNode(debugLabel: 'Cartão $id'));

  @override
  void initState() {
    super.initState();
    widget.biblioteca.addListener(_mudou);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visivel = TickerMode.valuesOf(context).enabled && (ModalRoute.of(context)?.isCurrent ?? true);
    if (_visivel && _pendente) _carregar();
  }

  @override
  void didUpdateWidget(TelaInicio old) {
    super.didUpdateWidget(old);
    if (old.biblioteca != widget.biblioteca) {
      old.biblioteca.removeListener(_mudou);
      widget.biblioteca.addListener(_mudou);
      _resumidor = ResumosInicio(widget.biblioteca);
      _mudou();
    }
  }

  @override
  void dispose() {
    widget.biblioteca.removeListener(_mudou);
    _pesquisa.dispose();
    for (final f in _focos.values) {
      f.dispose();
    }
    super.dispose();
  }

  /// Os resumos vêm das caches de canais, lidas fora do build; só se relêem as listas que mudaram
  /// ([ResumosInicio]).
  Future<void> _carregar() async {
    _pendente = false;
    final b = widget.biblioteca;
    final minha = ++_geracao;
    final resumos = await _resumidor.atualizar(visto: b.ultimoVisto);
    if (!mounted || minha != _geracao) return;
    setState(() => _resumos = resumos);
  }

  void _mudou() {
    if (_visivel) {
      _carregar();
    } else {
      _pendente = true;
    }
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
    mostrarMensagem(context, texto);
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
    final acao = await mostrarMenuLista(context, l, comGestor: area != null, comVerificar: widget.servico != null);
    if (acao == null || !mounted) return;
    switch (acao) {
      case AcaoLista.atualizar:
        unawaited(_atualizarCanais(l));
      case AcaoLista.verificar:
        unawaited(_verificar(l));
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

  /// "Atualizar canais": pede os canais ao servidor sem sair do Início; o progresso e o fim vão
  /// em mensagens e a navegação continua livre.
  Future<void> _atualizarCanais(Lista l) async {
    final avisar = mensageiroDe(context);
    final nome = l.nomeMostrado;
    avisar('A atualizar os canais de $nome…', tipo: MensagemTipo.progresso, duracao: const Duration(minutes: 2));
    try {
      final c = await (widget.abrirLista ?? _abrirPeloProtocolo)(l.conta);
      await widget.biblioteca.guardarCanais(l.id, c);
      avisar('Canais de $nome atualizados · ${c.canais.length}', tipo: MensagemTipo.sucesso);
    } catch (e) {
      avisar('Não foi possível atualizar $nome: ${e is ErroLista ? e.mensagem : descreverErro(e)}',
          tipo: MensagemTipo.erro);
    }
  }

  /// "Verificar agora": testa a lista pelo serviço do Player; o estado novo aparece no cartão.
  Future<void> _verificar(Lista l) async {
    final servico = widget.servico;
    if (servico == null) return;
    final avisar = mensageiroDe(context);
    final nome = l.nomeMostrado;
    avisar('A verificar $nome…', tipo: MensagemTipo.progresso, duracao: const Duration(minutes: 2));
    await servico.verificar(l);
    final atual = widget.biblioteca.porId(l.id);
    if (atual == null) return;
    final e = estadoDe(atual);
    avisar('$nome: ${e.rotulo}',
        tipo: switch (e) {
          EstadoLista.funciona => MensagemTipo.sucesso,
          EstadoLista.naoFunciona => MensagemTipo.erro,
          _ => MensagemTipo.info,
        });
  }

  static Future<ConteudoLista> _abrirPeloProtocolo(Conta conta) => Protocolo.para(conta).abrir(conta);

  void _abrir(Lista l, {bool atualizar = false, String? continuar}) => Navigator.of(context).push(rotaSuave<void>(
        TelaConteudo(biblioteca: widget.biblioteca, lista: l, atualizar: atualizar, abrirLista: widget.abrirLista,
            abrir: widget.abrirCanal, continuar: continuar),
      ));

  Widget _titulo(String texto, bool tv) => Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.e24, Tokens.e16, Tokens.e24, Tokens.e8),
        child: Text(texto,
            style: TextStyle(color: Tokens.texto2, fontSize: tv ? 17 : 14, fontWeight: FontWeight.w700)),
      );

  Widget _continuar(bool tv) {
    final visto = widget.biblioteca.ultimoVisto;
    final lista = visto == null ? null : widget.biblioteca.porId(visto.lista);
    if (visto == null || lista == null) return const SizedBox.shrink();
    return Padding(
      // margem para o cartão focado crescer e brilhar sem ser cortado
      padding: const EdgeInsets.fromLTRB(Tokens.e24, Tokens.e16, Tokens.e24, Tokens.e4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          height: CartaoContinuar.altura(tv, fatorTexto(context)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: entradaEmCascata(0, CartaoContinuar(
              visto: visto,
              lista: lista,
              numero: _resumos[lista.id]?.numeroVisto,
              autofocus: true,
              aoAbrir: () => _abrir(lista, continuar: visto.canal),
            )),
          ),
        ),
      ),
    );
  }

  Widget _filaFavoritos(bool tv) {
    final f = favoritosDeResumos(widget.biblioteca.listas, _resumos);
    if (f.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _titulo('Favoritos · ${f.length}', tv),
      SizedBox(
        // com margem para o cartão focado crescer; cresce com a letra do sistema
        height: (tv ? 96 : 80) * fatorTexto(context) + 16,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Tokens.e24, vertical: Tokens.e8),
          itemCount: f.length,
          separatorBuilder: (_, _) => const SizedBox(width: Tokens.e12),
          itemBuilder: (_, i) => SizedBox(
            width: tv ? 250 : 210,
            child: letraPresa(CartaoModerno(
              onTap: () => _abrir(f[i].lista, continuar: f[i].canal.id),
              padding: EdgeInsets.symmetric(horizontal: Tokens.e16, vertical: tv ? 14 : 10),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f[i].canal.nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: tv ? 18 : 15, fontWeight: FontWeight.w700)),
                    Text(f[i].lista.nomeMostrado,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Tokens.texto2, fontSize: tv ? 14 : 12.5)),
                  ]),
            )),
          ),
        ),
      ),
    ]);
  }

  /// A pesquisa e os filtros por estado. Os filtros vão sempre numa só fila (com scroll para o
  /// lado quando não cabem): partidos em duas linhas (num `Wrap`), do último filtro da primeira
  /// linha → não tinha nada à direita e ↓ saltava para os cartões (por baixo dele não há outro
  /// filtro), e o comando nunca chegava aos da segunda linha («Por verificar»). Ao lado da
  /// pesquisa quando há largura; por baixo dela no ecrã estreito.
  Widget _pesquisaEFiltros() {
    final pesquisa = CampoTv(
      controller: _pesquisa,
      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Pesquisar listas'),
      onChanged: (v) => setState(() => _q = v),
    );
    final filtros = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // margem para o anel do foco não ser cortado
      padding: const EdgeInsets.all(Tokens.e4),
      child: Row(children: [
        for (final (i, (v, t)) in _filtros.indexed) ...[
          if (i > 0) const SizedBox(width: Tokens.e8),
          ChoiceChip(label: Text(t), selected: _filtro == v, onSelected: (_) => setState(() => _filtro = v)),
        ],
      ]),
    );
    return LayoutBuilder(
      builder: (_, c) => c.maxWidth < 560
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [pesquisa, filtros])
          : Row(children: [
              SizedBox(width: 280, child: pesquisa),
              const SizedBox(width: Tokens.e8),
              Expanded(child: filtros),
            ]),
    );
  }

  Widget _listas() => ListenableBuilder(
        listenable: widget.biblioteca,
        builder: (context, _) {
          final todas = widget.biblioteca.listas;
          if (todas.isEmpty) return _vazio(context);
          final vis = _visiveis();
          final tv = ecraTv(context);
          // só os primeiros entram em cascata (entradaEmCascata ignora índices > 30)
          Widget cartao(int i, {bool emGrelha = true}) => entradaEmCascata(i, CartaoLista(
                lista: vis[i],
                resumo: _resumos[vis[i].id],
                emGrelha: emGrelha,
                // com "Continuar a ver" o foco começa nele
                autofocus: i == 0 && widget.biblioteca.ultimoVisto == null,
                aoAbrir: () => _abrir(vis[i]),
                focusNode: _focoCartao(vis[i].id),
                aoMenu: () => _menu(vis[i]),
              ));
          return CustomScrollView(slivers: [
            SliverToBoxAdapter(child: _continuar(tv)),
            SliverToBoxAdapter(child: _filaFavoritos(tv)),
            SliverToBoxAdapter(child: _titulo('Listas · ${todas.length}', tv)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Tokens.e16, 0, Tokens.e16, Tokens.e4),
                child: _pesquisaEFiltros(),
              ),
            ),
            if (vis.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(Tokens.e32),
                  child: Center(child: Text('Nenhuma lista com este filtro.', style: TextStyle(color: Tokens.texto2))),
                ),
              )
            else
              SliverPadding(
                // margem para o cartão focado crescer (1.04) e brilhar sem ser cortado
                padding: const EdgeInsets.all(Tokens.e24),
                // no telemóvel, um cartão por linha (com o nome inteiro), cada um com a altura do
                // que mostra; na grelha, todos com a mesma altura (que cresce com a letra)
                sliver: MediaQuery.sizeOf(context).width < 600
                    ? SliverList.separated(
                        itemCount: vis.length,
                        separatorBuilder: (_, _) => const SizedBox(height: Tokens.e12),
                        itemBuilder: (_, i) => cartao(i, emGrelha: false),
                      )
                    : SliverGrid(
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: tv ? 340 : 320,
                          mainAxisExtent: CartaoLista.altura(tv, fatorTexto(context)),
                          crossAxisSpacing: Tokens.e12,
                          mainAxisSpacing: Tokens.e12,
                        ),
                        delegate: SliverChildBuilderDelegate(childCount: vis.length, (_, i) => cartao(i)),
                      ),
              ),
          ]);
        },
      );

  Widget _passo(int n, String titulo, String texto, bool tv) => Container(
        width: tv ? 250 : 220,
        padding: const EdgeInsets.all(Tokens.e16),
        decoration: BoxDecoration(
          color: Tokens.superficie2,
          borderRadius: BorderRadius.circular(Tokens.raioCartao),
          border: Border.all(color: Tokens.bordaVidro),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Tokens.gradienteAcento),
            child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: Tokens.e12),
          Text(titulo, style: TextStyle(fontSize: tv ? 19 : 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: Tokens.e4),
          Text(texto, style: TextStyle(color: Tokens.texto2, fontSize: tv ? 15 : 13.5)),
        ]),
      );

  /// A primeira vez (sem listas): para onde ir e o que acontece lá.
  Widget _vazio(BuildContext context) {
    final tv = ecraTv(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Tokens.e24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: entradaEmCascata(0, Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Ainda não há listas para ver',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: Tokens.e8),
            const Text(
                'As listas entram pelo Gestor. Lá podes importá-las, ver quais funcionam e enviar as boas para aqui.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Tokens.texto2)),
            const SizedBox(height: Tokens.e24),
            Wrap(spacing: Tokens.e16, runSpacing: Tokens.e16, alignment: WrapAlignment.center, children: [
              _passo(1, 'Importar', 'Ficheiro, texto colado ou listas do stbstalker', tv),
              _passo(2, 'Verificar', 'Testamos 3 canais de cada lista', tv),
              _passo(3, 'Enviar', 'As que funcionam aparecem aqui', tv),
            ]),
            // dentro da casca: muda para o Gestor e o foco vai para "Adicionar listas". A cópia de
            // segurança não se importa a partir daqui (é nas Definições): não há segundo botão.
            if (context.getInheritedWidgetOfExactType<SeccaoAtual>() != null) ...[
              const SizedBox(height: Tokens.e24),
              FilledButton.icon(
                autofocus: true,
                onPressed: () => TelaPrincipal.irPara(context, Seccao.gestor),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Ir para o Gestor'),
              ),
            ],
          ])),
        ),
      ),
    );
  }

  // sem barra própria: a marca e as secções estão na casca
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          Expanded(child: _listas()),
          const BarraTeclas([('OK', 'abrir'), ('OK mantido', 'opções da lista'), ('←', 'menu')]),
        ]),
      );
}
