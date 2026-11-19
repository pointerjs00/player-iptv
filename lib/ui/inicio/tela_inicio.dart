import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/area_gestor.dart';
import '../../dados/biblioteca.dart';
import '../../importar/importar.dart';
import '../../modelo/canal.dart';
import '../campo_tv.dart';
import '../conteudo/tela_conteudo.dart';
import '../design/design.dart';
import '../principal/tela_principal.dart';
import 'acoes_lista.dart';
import 'cartao_continuar.dart';
import 'cartao_lista.dart';

/// Ver TV: as listas do Player em cartões (com o estado da última verificação, pesquisa e filtro
/// por estado). Não gere nada: adicionar, verificar, exportar e enviar listas para o Player
/// faz-se no Gestor. No topo, "Continuar a ver" (o último canal visto). As secções, o Voltar e a
/// confirmação da saída são da casca ([TelaPrincipal]).
class TelaInicio extends StatefulWidget {
  const TelaInicio({super.key, required this.biblioteca, this.area, this.abrirLista, this.abrirCanal});

  /// As listas do Player.
  final Biblioteca biblioteca;

  /// As listas do Gestor: o menu do cartão envia para aqui.
  final AreaGestor? area;

  /// Para testes: pede os canais de uma lista (em vez do protocolo da conta).
  final AbrirLista? abrirLista;

  /// Para testes: em vez de abrir o player (ver [TelaConteudo.abrir]).
  final FutureOr<int?> Function(List<Canal> canais, int i)? abrirCanal;

  @override
  State<TelaInicio> createState() => _TelaInicioState();
}

class _TelaInicioState extends State<TelaInicio> {
  String _q = '';

  /// O foco de cada cartão (pelo id da lista): depois de eliminar, o foco passa ao cartão ao lado.
  final _focos = <String, FocusNode>{};

  FocusNode _focoCartao(String id) => _focos.putIfAbsent(id, () => FocusNode(debugLabel: 'Cartão $id'));

  @override
  void dispose() {
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
                // dentro da casca: muda para o Gestor e o foco vai para "Adicionar listas"
                if (context.getInheritedWidgetOfExactType<SeccaoAtual>() != null) ...[
                  const SizedBox(height: Tokens.e24),
                  FilledButton.icon(
                    autofocus: true,
                    onPressed: () => TelaPrincipal.irPara(context, Seccao.gestor),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Ir para o Gestor'),
                  ),
                ],
              ]),
            )),
          ),
        ),
      );

  // sem barra própria: a marca e as secções estão na casca
  @override
  Widget build(BuildContext context) => Scaffold(body: _listas());
}
