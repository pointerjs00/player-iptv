
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/area_gestor.dart';
import '../../dados/biblioteca.dart';
import '../../dados/guardar_ficheiro.dart';
import '../../importar/importar.dart';
import '../../importar/stbstalker.dart';
import '../../rede/http.dart';
import '../../tarefas/servico_tarefas.dart';
import '../../verificar/exportar.dart';
import '../../verificar/servico.dart';
import '../design/barra_teclas.dart';
import '../design/design.dart';
import '../design/mensagens.dart';
import '../navegacao_blocos.dart';
import '../principal/tela_principal.dart';
import '../realce_foco.dart';
import '../tema.dart';
import '../verificar/dialogos_gestor.dart';
import 'indicador_atividade.dart';
import 'painel_atividade.dart';
import 'tela_importar.dart';
import 'tela_verificacao.dart';

/// Os ecrãs do Gestor: o principal e os sub-ecrãs que se abrem dos passos 1 e 2.
enum EcraGestor { principal, importar, verificacao }

/// Separador "Gestor": a área de trabalho com as suas próprias listas ([AreaGestor]).
///
/// O ecrã principal tem sempre à vista os três passos (1 Importar · 2 Verificar · 3 Enviar ou
/// exportar, cada um com o seu estado), os filtros pelo estado, a tabela das listas com caixas para
/// marcar e a barra das selecionadas (`Verificar (entra na fila)` · `Enviar para o Player` ·
/// `Exportar` · `Remover`). Em cima, o [IndicadorAtividade] diz o que está a decorrer.
///
/// Nada espera: com uma verificação a decorrer todos os botões continuam ligados (verificar mais
/// junta à fila; remover uma lista a ser verificada cancela só essa). Os sub-ecrãs vivem num
/// [IndexedStack]: trocar de ecrã (ou de secção) não perde o filtro, a seleção nem o que lá estava.
/// Voltar num sub-ecrã regressa ao principal, com o foco no passo de onde se veio.
class TelaGestor extends StatefulWidget {
  const TelaGestor({super.key, required this.biblioteca, required this.area, required this.servico,
      required this.tarefas, this.pedido, this.baseStb = stbBase, this.guardar = guardarFicheiro});

  /// As listas do Player (recebem os envios) e os canais de teste.
  final Biblioteca biblioteca;
  final AreaGestor area;

  /// Grava os resultados no Gestor.
  final ServicoVerificacao servico;

  /// O trabalho longo que corre fora dos ecrãs (o indicador mostra-o).
  final ServicoTarefas tarefas;

  /// Quem quiser que o Gestor abra um sub-ecrã (a casca, no "Ver resultados" do aviso da verificação)
  /// põe aqui o ecrã; o Gestor abre-o e volta a pôr null.
  final ValueNotifier<EcraGestor?>? pedido;

  /// O blog a pesquisar (injetável para os testes).
  final String baseStb;

  /// Guarda o ficheiro exportado (injetável para os testes; por omissão, a janela do sistema).
  final Future<ResultadoGuardar> Function(String nome, Uint8List bytes, String mimeType) guardar;

  @override
  State<TelaGestor> createState() => _TelaGestorState();
}

class _TelaGestorState extends State<TelaGestor> {
  EcraGestor _ecra = EcraGestor.principal;
  final _selecao = <String>{};

  /// O filtro da tabela pelo estado (null = todas).
  EstadoLista? _filtro;

  /// Os passos (o foco volta ao passo de onde se abriu um sub-ecrã).
  final _focosPassos = [for (final p in ['Importar', 'Verificar', 'Enviar']) FocusNode(debugLabel: 'Passo $p')];

  /// O passo 3 traz o foco para a barra das selecionadas.
  final _focoEnviar = FocusNode(debugLabel: 'Enviar para o Player');

  /// As importações em curso e o seu resumo (sobrevivem a sair do ecrã de importar).
  final _registo = RegistoImportacoes();

  /// O primeiro controlo de cada sub-ecrã (recebe o foco ao abrir).
  final _focoOrigens = FocusNode(debugLabel: 'Origens da importação');
  final _focoVerificarMais = FocusNode(debugLabel: 'Verificar mais (fila)');

  final _focosFiltros = [for (final (_, t) in _filtros) FocusNode(debugLabel: 'Filtro $t')];

  /// Os blocos para CIMA/BAIXO no ecrã principal (ver [moverEntreBlocos]); a tabela vem depois.
  final _blocos = [
    for (final b in ['Passos', 'Seleção', 'Filtros'])
      FocusNode(debugLabel: 'Bloco $b', canRequestFocus: false, skipTraversal: true),
  ];
  final _blocoVerificacao = FocusNode(debugLabel: 'Bloco Verificação', canRequestFocus: false, skipTraversal: true);

  /// O foco de cada linha (pelo id): se a linha com o foco sai da tabela (mudou de estado com um
  /// filtro ativo, ou foi removida), o foco passa à que fica no lugar dela.
  final _focosLinhas = <String, FocusNode>{};
  String? _linhaFocada;
  List<String> _ordemVista = const [];

  /// O foco do indicador de atividade (o painel devolve-lho ao fechar).
  final _focoIndicador = FocoForaDaEntrada(debugLabel: 'Indicador de atividade');

  /// Tira o registo do Voltar na casca.
  VoidCallback? _tirarVoltar;

  FocusNode _focoLinha(String id) => _focosLinhas.putIfAbsent(id, () => FocusNode(debugLabel: 'Linha'));

  Biblioteca get _b => widget.biblioteca;
  AreaGestor get _g => widget.area;
  ServicoVerificacao get _s => widget.servico;

  @override
  void initState() {
    super.initState();
    _g.addListener(_aoMudarArea);
    widget.pedido?.addListener(_aoPedido);
  }

  /// A casca pediu um sub-ecrã.
  void _aoPedido() {
    final e = widget.pedido?.value;
    if (e == null) return;
    widget.pedido!.value = null;
    if (e != _ecra) return _abrir(e);
    // já lá está: só leva o foco ao primeiro controlo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _ecra == EcraGestor.verificacao) _focoVerificarMais.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tirarVoltar ??= TelaPrincipal.aoVoltar(context, _voltarAoPrincipal);
  }

  @override
  void didUpdateWidget(TelaGestor antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.pedido != widget.pedido) {
      antigo.pedido?.removeListener(_aoPedido);
      widget.pedido?.addListener(_aoPedido);
    }
    if (antigo.area != widget.area) {
      antigo.area.removeListener(_aoMudarArea);
      widget.area.addListener(_aoMudarArea);
    }
  }

  @override
  void dispose() {
    _tirarVoltar?.call();
    widget.pedido?.removeListener(_aoPedido);
    _focoIndicador.dispose();
    _registo.dispose();
    _g.removeListener(_aoMudarArea);
    for (final f in [
      ..._focosPassos,
      _focoEnviar,
      _focoOrigens,
      _focoVerificarMais,
      ..._focosFiltros,
      ..._blocos,
      _blocoVerificacao,
      ..._focosLinhas.values,
    ]) {
      f.dispose();
    }
    super.dispose();
  }

  /// As listas do Gestor mudaram (verificação, remoção...): fora do build, vê se a linha com o
  /// foco saiu da tabela e, depois do frame (quando as linhas antigas já saíram da árvore),
  /// liberta o foco das linhas que já não existem.
  void _aoMudarArea() {
    _vigiarLinhaFocada(_visiveis());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focosLinhas.removeWhere((id, f) {
        if (_g.porId(id) != null || f.context != null || f.hasFocus) return false;
        f.dispose();
        return true;
      });
    });
  }

  // ---------------------------------------------------------------- ecrãs

  /// Mostra o ecrã `e` e põe-lhe o foco: no primeiro controlo de um sub-ecrã, ou (ao voltar ao
  /// principal) no passo de onde se veio.
  void _abrir(EcraGestor e) {
    final antes = _ecra;
    if (e == antes) return;
    setState(() => _ecra = e);
    // depois do frame: o ecrã novo já pode receber o foco (o antigo deixa de poder)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _ecra != e) return;
      switch (e) {
        case EcraGestor.principal:
          _focosPassos[antes.index - 1].requestFocus();
        case EcraGestor.importar:
          _focoOrigens.requestFocus();
        case EcraGestor.verificacao:
          _focoVerificarMais.requestFocus();
      }
    });
  }

  /// O indicador abre o painel de atividade; ao fechar, o foco volta ao indicador.
  Future<void> _abrirAtividade() async {
    var mudouDeEcra = false;
    await abrirPainelAtividade(context, servico: _s, tarefas: widget.tarefas, aoVerVerificacao: () {
      mudouDeEcra = true;
      _abrir(EcraGestor.verificacao);
    });
    if (mounted && !mudouDeEcra) _focoIndicador.requestFocus();
  }

  /// Voltar (do comando ou o botão): num sub-ecrã regressa ao principal. false = não tratou.
  bool _voltarAoPrincipal() {
    if (_ecra == EcraGestor.principal) return false;
    // a escrever num campo (colar texto): o Voltar só fecha o teclado (é o CampoTv que o trata)
    final contexto = FocusManager.instance.primaryFocus?.context;
    final campo = contexto?.widget is EditableText
        ? contexto!.widget as EditableText
        : contexto?.findAncestorWidgetOfExactType<EditableText>();
    if (campo != null && !campo.readOnly) return true;
    _abrir(EcraGestor.principal);
    return true;
  }

  // ---------------------------------------------------------------- seleção e filtros

  /// Os filtros da tabela.
  static const _filtros = <(EstadoLista?, String)>[
    (null, 'Todas'),
    (EstadoLista.funciona, 'Funcionam'),
    (EstadoLista.inconclusiva, 'Inconclusivas'),
    (EstadoLista.naoFunciona, 'Não funcionam'),
    (EstadoLista.porVerificar, 'Por verificar'),
  ];

  static String _n(int n, String um, String varios) => '$n ${n == 1 ? um : varios}';

  List<Lista> get _selecionadas => [for (final l in _g.listas) if (_selecao.contains(l.id)) l];

  List<Lista> _visiveis() => [for (final l in _g.listas) if (_filtro == null || estadoDe(l) == _filtro) l];

  void _selecionar(bool Function(Lista) criterio) =>
      setState(() => _selecao..clear()..addAll([for (final l in _g.listas) if (criterio(l)) l.id]));

  /// A linha com o foco saiu da tabela: o foco passa à linha que ficou no lugar dela (ou, sem
  /// linhas, ao filtro escolhido). Sem isto o foco perdia-se (ficava invisível).
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
        _focosFiltros[_filtros.indexWhere((f) => f.$1 == _filtro)].requestFocus();
      } else {
        _focoLinha(vis[antes.clamp(0, vis.length - 1)].id).requestFocus();
      }
    });
  }

  // ---------------------------------------------------------------- ações

  void _aviso(String t) {
    if (mounted) mostrarMensagem(context, t);
  }

  /// "Verificar (entra na fila)": as selecionadas juntam-se à fila, mesmo a meio de uma verificação.
  void _verificarSelecionadas() {
    final listas = _selecionadas;
    if (listas.isEmpty) return _aviso('Selecione as listas a verificar.');
    final novas = [for (final l in listas) if (!_s.aVerificar(l.id)) l];
    if (novas.isEmpty) {
      return _aviso(listas.length == 1 ? 'A lista selecionada já está na fila.' : 'As listas selecionadas já estão na fila.');
    }
    _s.verificarVarias(novas);
    _aviso(novas.length == 1 ? '1 lista entrou na fila.' : '${novas.length} listas entraram na fila.');
  }

  /// "Verificar mais (fila)": vai ao ecrã principal só com as "Por verificar"; aí escolhem-se as
  /// listas e "Verificar (entra na fila)" junta-as à ronda que decorre.
  void _verificarMais() {
    setState(() => _filtro = EstadoLista.porVerificar);
    _abrir(EcraGestor.principal);
    // depois de _abrir (que põe o foco no passo): o foco vai ao filtro escolhido
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _ecra == EcraGestor.principal) {
        _focosFiltros[_filtros.indexWhere((f) => f.$1 == _filtro)].requestFocus();
      }
    });
  }

  /// "Verificar todas" (no sub-ecrã): as que ainda não estão na fila juntam-se a ela; a seleção fica.
  void _verificarTodas() {
    final listas = _g.listas;
    if (listas.isEmpty) return _aviso('Importe listas primeiro.');
    final novas = [for (final l in listas) if (!_s.aVerificar(l.id)) l];
    if (novas.isEmpty) return _aviso('Todas as listas já estão na fila.');
    _s.verificarVarias(novas);
  }

  void _parar() {
    final tinhaFoco = FocusManager.instance.primaryFocus?.context?.widget is! EditableText;
    _s.parar();
    _aviso('Verificação parada. As listas que faltavam ficaram como estavam.');
    // "Parar" desaparece: o foco passa para "Verificar mais (fila)"
    if (tinhaFoco) _focoVerificarMais.requestFocus();
  }

  /// "Enviar para o Player": vão as selecionadas que não estão a ser verificadas (as que estão ficam
  /// de fora e a mensagem final diz quantas são): as que funcionam, também as inconclusivas, ou todas,
  /// seja qual for o estado. A escolha faz-se antes; depois o envio corre como tarefa, sem esperar.
  Future<void> _enviar() async {
    if (_selecionadas.isEmpty) return _aviso('Selecione as listas a enviar.');
    ({List<Lista> prontas, int aDecorrer}) ponto() {
      final sel = _selecionadas;
      return (prontas: [for (final l in sel) if (!_s.aVerificar(l.id)) l], aDecorrer: sel.where((l) => _s.aVerificar(l.id)).length);
    }

    int conta(List<Lista> ls, EstadoLista e) => ls.where((l) => estadoDe(l) == e).length;
    final antes = ponto();
    final f = conta(antes.prontas, EstadoLista.funciona), i = conta(antes.prontas, EstadoLista.inconclusiva);
    if (antes.prontas.isEmpty) return _aviso('As listas selecionadas ainda estão a ser verificadas.');
    final escolha = await perguntarEnvio(context, funcionam: f, inconclusivas: i, todas: antes.prontas.length);
    if (escolha == null || !mounted) return;
    final (modo, que) = escolha;
    // o estado pode ter mudado com o diálogo aberto: conta-se de novo
    final agora = ponto();
    final enviar = [
      for (final l in agora.prontas)
        if (switch (que) {
          QueEnviar.funcionam => estadoDe(l) == EstadoLista.funciona,
          QueEnviar.funcionamEInconclusivas =>
            estadoDe(l) == EstadoLista.funciona || estadoDe(l) == EstadoLista.inconclusiva,
          QueEnviar.todas => true,
        })
          l,
    ];
    if (enviar.isEmpty) return _aviso('Já não há listas com resultado para enviar.');
    // o que a tarefa precisa, antes de qualquer await
    final b = _b;
    final ctx = context;
    final aDecorrer = agora.aDecorrer;
    final n = enviar.length;
    widget.tarefas.iniciar(
      'Enviar ${n == 1 ? '1 lista' : '$n listas'} para o Player',
      (p) async {
        final ResumoEnvio r;
        try {
          r = await b.receber(enviar, modo);
        } catch (e) {
          throw _ErroTarefa('Não foi possível enviar (${descreverErro(e)}). As listas do Player não mudaram.');
        }
        return textoResultadoEnvio(n, r, aDecorrer: aDecorrer);
      },
      rotuloAcao: 'Ir para Ver TV',
      aoAcao: () {
        if (ctx.mounted) TelaPrincipal.irPara(ctx, Seccao.verTv);
      },
      // o Player muda de uma vez: não há meio envio para parar
      cancelavel: false,
    );
  }

  /// "Exportar": a escolha do formato faz-se antes; depois o ficheiro é guardado numa tarefa (a
  /// janela "Guardar como" do sistema é a única espera). Se falhar, "Tentar de novo" repete tudo
  /// com a mesma escolha e volta a perguntar onde guardar.
  Future<void> _exportar() async {
    final listas = _selecionadas;
    if (listas.isEmpty) return _aviso('Selecione as listas a exportar.');
    final n = listas.length;
    final formato = await perguntarExportacao(context, n);
    if (formato == null || !mounted) return;
    final String nome, mime, texto;
    final Uint8List bytes;
    if (formato == 'json') {
      (nome, mime, texto) = ('Accounts.json', 'application/json', '$n listas exportadas.');
      bytes = exportarAccountsJson(listas);
    } else {
      final (zip, ignoradas) = exportarZipIni(listas);
      if (zip == null) return _aviso('Nenhuma das listas selecionadas é Stalker (portal + MAC).');
      (nome, mime, bytes) = ('listas_stalker.zip', 'application/zip', zip);
      texto = 'Listas exportadas.${ignoradas > 0 ? ' $ignoradas sem MAC (Xtream/M3U) ficaram de fora.' : ''}';
    }
    final guardar = widget.guardar;
    final tarefas = widget.tarefas;
    void lancar() {
      tarefas.iniciar(
        'Exportar ${n == 1 ? '1 lista' : '$n listas'}',
        (p) async {
          final ResultadoGuardar r;
          // a partir daqui o ficheiro está a ser gravado: já não se pode parar
          p.naoCancelavel();
          try {
            r = await guardar(nome, bytes, mime);
          } on ErroGuardar catch (e) {
            throw _ErroTarefa(e.mensagem);
          } catch (e) {
            throw _ErroTarefa(mensagemErroGuardar(e));
          }
          return r.cancelado ? 'Exportação cancelada.' : '$texto Guardado em ${r.destino}';
        },
        repetir: () async => lancar(),
      );
    }

    lancar();
  }

  /// "Remover": pede confirmação; as que estão a ser verificadas têm a verificação cancelada (só
  /// essas: as outras continuam).
  Future<void> _removerSelecionadas() async {
    final listas = _selecionadas;
    if (listas.isEmpty) return _aviso('Selecione as listas a remover.');
    final n = listas.length;
    final m = listas.where((l) => _s.aVerificar(l.id)).length;
    final aVerificar = switch (m) {
      0 => '',
      _ when n == 1 => 'Está a ser verificada: a verificação é cancelada. ',
      1 => 'Uma delas está a ser verificada: essa verificação é cancelada. ',
      _ => '$m delas estão a ser verificadas: essas verificações são canceladas. ',
    };
    final ok = await confirmar(context,
        icone: Icons.remove_circle_outline,
        titulo: 'Remover do Gestor?',
        texto: '${n == 1 ? 'A lista selecionada sai' : 'As $n listas selecionadas saem'} do Gestor. '
            '${aVerificar}As listas do Player não mudam.',
        acao: 'Remover');
    if (!ok) return;
    // o estado pode ter mudado enquanto o diálogo estava aberto
    for (final l in listas) {
      if (_s.aVerificar(l.id)) _s.cancelar(l.id);
    }
    await _g.remover(listas.map((l) => l.id));
  }

  /// O passo 3: o foco vai para a barra das selecionadas.
  void _irParaEnviar() {
    _focoEnviar.requestFocus();
    if (_selecao.isEmpty) _aviso('Marque as listas na tabela e escolha "Enviar para o Player" ou "Exportar".');
  }

  // ---------------------------------------------------------------- construção

  @override
  Widget build(BuildContext context) {
    final sub = _ecra != EcraGestor.principal;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _barraTopo(),
      Expanded(
        child: IndexedStack(
          index: _ecra.index,
          sizing: StackFit.expand,
          children: [
            _principal(),
            // escondido, o progresso sem fim da importação não pede frames
            TickerMode(
              enabled: _ecra == EcraGestor.importar,
              child: TelaImportar(
                biblioteca: _b,
                area: _g,
                servico: _s,
                tarefas: widget.tarefas,
                registo: _registo,
                baseStb: widget.baseStb,
                focoOrigens: _focoOrigens,
              ),
            ),
            TelaVerificacao(
              biblioteca: _b,
              area: _g,
              servico: _s,
              focoVerificarMais: _focoVerificarMais,
              bloco: _blocoVerificacao,
              aoVerificarMais: _verificarMais,
              aoVerificarTodas: _verificarTodas,
              aoParar: _parar,
            ),
          ],
        ),
      ),
      BarraTeclas(sub
          ? const [('Voltar', 'ecrã principal do Gestor'), ('OK', 'escolher')]
          : const [('OK', 'abrir o passo ou marcar a lista'), ('←', 'menu')]),
    ]);
  }

  Widget _barraTopo() {
    final titulo = switch (_ecra) {
      EcraGestor.principal => 'Gestor de listas',
      EcraGestor.importar => 'Importar listas',
      EcraGestor.verificacao => 'Verificação',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e12, Tokens.e16, 0),
      child: Row(children: [
        if (_ecra != EcraGestor.principal) ...[
          TextButton.icon(
            onPressed: _voltarAoPrincipal,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Voltar'),
          ),
          const SizedBox(width: Tokens.e8),
        ],
        Expanded(
          child: Text(titulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Tokens.texto)),
        ),
        const SizedBox(width: Tokens.e12),
        Flexible(
            child: IndicadorAtividade(
                servico: _s, tarefas: widget.tarefas, foco: _focoIndicador, aoAbrir: _abrirAtividade)),
      ]),
    );
  }

  /// Um bloco do ecrã principal para CIMA/BAIXO.
  Widget _bloco(int i, Widget filho) => Padding(
        padding: const EdgeInsets.only(bottom: Tokens.e12),
        child: Focus(
          focusNode: _blocos[i],
          canRequestFocus: false,
          skipTraversal: true,
          includeSemantics: false,
          child: filho,
        ),
      );

  /// O estado do passo 2: "8 funcionam · 2 inconclusivas · 1 não funciona · 3 por verificar".
  String _resumoVerificacao(Map<EstadoLista, int> contagens, int total) {
    if (total == 0) return 'Importe listas primeiro';
    if (_s.ocupado) return 'A verificar ${_s.feitas}/${_s.total}';
    int c(EstadoLista e) => contagens[e] ?? 0;
    return [
      if (c(EstadoLista.funciona) > 0) _n(c(EstadoLista.funciona), 'funciona', 'funcionam'),
      if (c(EstadoLista.inconclusiva) > 0) _n(c(EstadoLista.inconclusiva), 'inconclusiva', 'inconclusivas'),
      if (c(EstadoLista.naoFunciona) > 0) _n(c(EstadoLista.naoFunciona), 'não funciona', 'não funcionam'),
      if (c(EstadoLista.porVerificar) > 0) '${c(EstadoLista.porVerificar)} por verificar',
    ].join(' · ');
  }

  Widget _principal() => ListenableBuilder(
        listenable: Listenable.merge([_b, _g, _s]),
        builder: (context, _) => LayoutBuilder(builder: (context, caixa) {
          final listas = _g.listas;
          _selecao.removeWhere((id) => _g.porId(id) == null);
          final contagens = <EstadoLista, int>{};
          for (final l in listas) {
            contagens.update(estadoDe(l), (n) => n + 1, ifAbsent: () => 1);
          }
          final visiveis = _visiveis();
          final vazio = listas.isEmpty;
          // a TV (960 com a barra lateral) dá ~740: passos lado a lado e as 4 colunas
          final largo = caixa.maxWidth >= 560;
          final nSel = _selecao.length;
          // CustomScrollView: os blocos em cima e as linhas preguiçosas (SliverList.builder), para
          // não construir centenas de linhas em cada passo da verificação
          return Focus(
            canRequestFocus: false,
            skipTraversal: true,
            includeSemantics: false,
            onKeyEvent: (_, e) => moverEntreBlocos(_blocos, e),
            child: CustomScrollView(slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e12, Tokens.e16, 0),
                sliver: SliverList.list(children: [
                  _bloco(0, _passos(largo, [
                    (
                      'Importar',
                      vazio ? 'O Gestor está vazio' : _n(listas.length, 'lista no Gestor', 'listas no Gestor'),
                      () => _abrir(EcraGestor.importar),
                    ),
                    ('Verificar', _resumoVerificacao(contagens, listas.length), () => _abrir(EcraGestor.verificacao)),
                    (
                      'Enviar ou exportar',
                      vazio
                          ? 'Importe listas primeiro'
                          : nSel == 0
                              ? 'Nenhuma selecionada'
                              : _n(nSel, 'selecionada', 'selecionadas'),
                      _irParaEnviar,
                    ),
                  ])),
                  _bloco(1, _marcarESelecionadas(nSel)),
                  // os filtros por cima da tabela: BAIXO num filtro vai às linhas
                  _bloco(
                    2,
                    Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, children: [
                      for (final (i, (e, t)) in _filtros.indexed)
                        ChoiceChip(
                          focusNode: _focosFiltros[i],
                          label: Text('$t · ${e == null ? listas.length : contagens[e] ?? 0}'),
                          selected: _filtro == e,
                          onSelected: (_) => setState(() => _filtro = e),
                        ),
                    ]),
                  ),
                  if (vazio)
                    const Padding(
                      padding: EdgeInsets.only(top: Tokens.e8, bottom: Tokens.e16),
                      child: Text('Ainda não há listas. Comece pelo passo 1: adicione ficheiros ou linhas coladas, '
                          'pesquise no stbstalker ou importe as do Player.',
                          style: TextStyle(color: Tokens.texto2)),
                    )
                  else ...[
                    _cabecalhoTabela(largo),
                    if (visiveis.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: Tokens.e12, bottom: Tokens.e16),
                        child: Text('Nenhuma lista com este estado.', style: TextStyle(color: Tokens.texto2)),
                      ),
                  ],
                ]),
              ),
              if (visiveis.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(Tokens.e16, 0, Tokens.e16, Tokens.e16),
                  // o vidro por trás da parte visível da tabela (sem construir as linhas todas)
                  sliver: DecoratedSliver(
                    decoration: BoxDecoration(
                      color: Tokens.vidro,
                      borderRadius: BorderRadius.circular(Tokens.raioCartao),
                      border: Border.all(color: Tokens.bordaVidro),
                    ),
                    sliver: SliverPadding(
                      padding: const EdgeInsets.all(Tokens.e8),
                      sliver: SliverList.builder(
                        itemCount: visiveis.length,
                        // o "ink" (foco, toque) pinta-se aqui, por cima do vidro
                        itemBuilder: (_, i) =>
                            Material(type: MaterialType.transparency, child: _linha(visiveis[i], largo)),
                      ),
                    ),
                  ),
                ),
            ]),
          );
        }),
      );

  /// Os três passos, sempre à vista: lado a lado (ou um por linha num ecrã estreito).
  Widget _passos(bool largo, List<(String, String, VoidCallback)> passos) {
    final cartoes = [
      for (final (i, (titulo, estado, abrir)) in passos.indexed)
        CartaoModerno(
          focusNode: _focosPassos[i],
          escalaFoco: 1.02,
          raio: Tokens.raioBotao,
          padding: const EdgeInsets.all(Tokens.e12),
          onTap: abrir,
          child: Row(children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: const BoxDecoration(gradient: Tokens.gradienteAcento, shape: BoxShape.circle),
              child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700, color: Tokens.texto)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Tokens.texto)),
                const SizedBox(height: 2),
                Text(estado,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: Tokens.texto2)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Tokens.texto2),
          ]),
        ),
    ];
    if (!largo) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, c) in cartoes.indexed) ...[if (i > 0) const SizedBox(height: Tokens.e8), c],
      ]);
    }
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, c) in cartoes.indexed) ...[if (i > 0) const SizedBox(width: Tokens.e8), Expanded(child: c)],
      ]),
    );
  }

  /// Marcar listas e a barra das selecionadas. Sempre ligada: sem seleção, cada botão diz o que falta.
  Widget _marcarESelecionadas(int n) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Selecionadas: $n', style: const TextStyle(color: Tokens.texto, fontWeight: FontWeight.w600)),
          const Text('· Marcar:', style: TextStyle(color: Tokens.texto2)),
          ActionChip(
              label: const Text('Funcionam'),
              onPressed: () => _selecionar((l) => estadoDe(l) == EstadoLista.funciona)),
          ActionChip(
              label: const Text('Funcionam + inconclusivas'),
              onPressed: () => _selecionar(
                  (l) => const {EstadoLista.funciona, EstadoLista.inconclusiva}.contains(estadoDe(l)))),
          ActionChip(label: const Text('Todas'), onPressed: () => _selecionar((_) => true)),
          ActionChip(label: const Text('Nenhuma'), onPressed: () => _selecionar((_) => false)),
        ]),
        const SizedBox(height: Tokens.e8),
        _barraSelecionadas(),
      ]);

  /// A barra das selecionadas.
  Widget _barraSelecionadas() => Wrap(
        spacing: Tokens.e8,
        runSpacing: Tokens.e8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: _verificarSelecionadas,
            icon: const Icon(Icons.playlist_add_check),
            label: const Text('Verificar (entra na fila)'),
          ),
          OutlinedButton.icon(
            focusNode: _focoEnviar,
            onPressed: _enviar,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Enviar para o Player'),
          ),
          OutlinedButton.icon(
            onPressed: _exportar,
            icon: const Icon(Icons.download),
            label: const Text('Exportar'),
          ),
          OutlinedButton.icon(
            onPressed: _removerSelecionadas,
            icon: const Icon(Icons.remove_circle_outline),
            label: const Text('Remover'),
          ),
        ],
      );

  /// As colunas da tabela (o cabeçalho e cada linha usam as mesmas larguras).
  static Widget _colunas(bool largo, Widget lista, Widget estado, Widget canais, Widget validade) =>
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(flex: 5, child: lista),
        const SizedBox(width: Tokens.e8),
        Expanded(flex: 5, child: estado),
        if (largo) ...[
          const SizedBox(width: Tokens.e8),
          SizedBox(width: 64, child: canais),
          const SizedBox(width: Tokens.e8),
          SizedBox(width: 96, child: validade),
        ],
      ]);

  /// A largura da caixa de cada linha (para o cabeçalho ficar alinhado com as colunas).
  static const _larguraCaixa = 40.0;

  Widget _cabecalhoTabela(bool largo) {
    Text t(String s) => Text(s,
        style: const TextStyle(color: Tokens.texto2, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .8));
    return Padding(
      // o vidro da tabela (8) + o ListTile (16 à esquerda, 24 à direita) + a caixa + o espaço do ListTile (16)
      padding: const EdgeInsets.fromLTRB(Tokens.e8 + 16 + _larguraCaixa + 16, Tokens.e4, Tokens.e8 + 24, Tokens.e8),
      child: _colunas(largo, t('LISTA'), t('ESTADO'), t('CANAIS'), t('VALIDADE')),
    );
  }

  /// Os canais de teste que abriram na última verificação ("2/3"); "—" sem o saber.
  static String _canais(UltimaVerificacao? u) {
    if (u == null) return '—';
    if (u.canais.isEmpty) return u.estado == 'funciona' ? '1/1' : '—';
    return '${u.canais.where((c) => c['estado'] == 'funciona').length}/${u.canais.length}';
  }

  static String _validade(UltimaVerificacao? u) {
    final v = textoValidade(u?.validade ?? '');
    if (v.isEmpty) return '—';
    return v.startsWith('até ') ? v.substring(4) : v;
  }

  Widget _linha(Lista l, bool largo) {
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
    return RealceFoco(
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
          Text(l.nomeMostrado, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          estado,
          Text(_canais(u), style: pequeno),
          Text(_validade(u), style: pequeno),
        ),
        subtitle: motivo.isEmpty
            ? null
            : Text(motivo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Tokens.texto2)),
        controlAffinity: ListTileControlAffinity.leading,
        dense: true,
      ),
    );
  }
}

/// Uma falha de uma tarefa, com a mensagem já pronta para mostrar.
class _ErroTarefa implements Exception {
  const _ErroTarefa(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}
