
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/area_gestor.dart';
import '../../dados/biblioteca.dart';
import '../../dados/guardar_ficheiro.dart';
import '../../importar/stbstalker.dart';
import '../../rede/http.dart';
import '../../tarefas/servico_tarefas.dart';
import '../../verificar/exportar.dart';
import '../../verificar/servico.dart';
import '../campo_tv.dart';
import '../design/barra_teclas.dart';
import '../design/design.dart';
import '../design/mensagens.dart';
import '../principal/tela_principal.dart';
import '../realce_foco.dart';
import '../verificar/dialogos_gestor.dart';
import 'indicador_atividade.dart';
import 'painel_atividade.dart';
import 'passo_enviar.dart';
import 'passo_verificar.dart';
import 'tela_como_verifica.dart';
import 'tela_importar.dart';
import 'tela_verificacao.dart';

/// Os ecrãs do Gestor: o resumo (ao entrar), os três passos e o progresso da verificação (que
/// se abre do passo 2).
enum EcraGestor { resumo, importar, verificar, enviar, verificacao }

/// Separador "Gestor": a área de trabalho com as suas próprias listas ([AreaGestor]).
///
/// Abre sempre no resumo, sem nenhum passo aberto: três cartões (1 Importar · 2 Verificar · 3
/// Exportar), cada um com o seu estado, e, com uma verificação a decorrer, a barra do
/// progresso (OK nela abre o progresso). Dentro de cada passo, a faixa dos passos no topo diz em
/// qual se está (← → mudam de passo). Em cima, o [IndicadorAtividade] diz o que está a decorrer.
///
/// Nada espera: com uma verificação a decorrer todos os passos continuam ligados (verificar mais
/// junta à fila; remover uma lista a ser verificada cancela só essa). Os ecrãs vivem num
/// [IndexedStack]: trocar de ecrã (ou de secção) não perde o filtro, a seleção nem o que lá estava.
/// Voltar num passo regressa ao resumo, com o foco no cartão desse passo; no progresso regressa
/// ao passo 2, com o foco onde estava.
class TelaGestor extends StatefulWidget {
  const TelaGestor({super.key, required this.biblioteca, required this.area, required this.servico,
      required this.tarefas, this.pedido, this.baseStb = stbBase, this.guardar = guardarFicheiro});

  /// As listas de Ver TV (recebem os envios) e os canais de teste.
  final Biblioteca biblioteca;
  final AreaGestor area;

  /// Grava os resultados no Gestor.
  final ServicoVerificacao servico;

  /// O trabalho longo que corre fora dos ecrãs (o indicador mostra-o).
  final ServicoTarefas tarefas;

  /// Quem quiser que o Gestor abra um ecrã (a casca, no "Ver resultados" do aviso da verificação)
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
  EcraGestor _ecra = EcraGestor.resumo;

  /// Os passos, pela ordem da faixa.
  static const _passos = [EcraGestor.importar, EcraGestor.verificar, EcraGestor.enviar];
  static const _nomesPassos = ['Importar', 'Verificar', 'Exportar'];

  /// Os nomes na faixa do telemóvel (curtos, para caberem inteiros os três).
  static const _nomesCurtos = ['Importar', 'Verificar', 'Enviar'];

  /// As marcadas do passo 3 (ids): ficam ao mudar de passo; as que saem do Gestor saem daqui.
  final _marcadas = <String>{};

  /// As importações em curso e o seu resumo (sobrevivem a sair do ecrã de importar).
  final _registo = RegistoImportacoes();

  /// Quando acabou a última exportação desta sessão (null antes da primeira).
  DateTime? _ultimaExportacao;

  /// O passo 2 ("Verificar mais (fila)" abre-o já filtrado).
  final _passoVerificar = GlobalKey<PassoVerificarState>();
  final _passoEnviar = GlobalKey<PassoEnviarState>();

  /// Os cartões do resumo (o foco volta ao cartão do passo de onde se veio).
  final _focosCartoes = [for (final p in _nomesPassos) FocusNode(debugLabel: 'Cartão $p')];

  /// A barra do progresso no resumo (OK abre o progresso).
  final _focoBarraAtividade = FocusNode(debugLabel: 'Barra da verificação');

  /// A faixa dos passos (uma só paragem do foco) e o "Voltar" por cima dela.
  final _focoFaixa = FocusNode(debugLabel: 'Faixa dos passos');
  final _focoVoltar = FocusNode(debugLabel: 'Voltar');

  /// O primeiro controlo de cada ecrã (recebe o foco ao abrir).
  final _focoOrigens = FocusNode(debugLabel: 'Origens da importação');
  final _focoPesquisa = FocusNode(debugLabel: 'Pesquisar listas');
  final _focoFuncionam = FocusNode(debugLabel: 'As que funcionam');
  final _focoVerificarMais = FocusNode(debugLabel: 'Verificar mais (fila)');
  final _blocoVerificacao = FocusNode(debugLabel: 'Bloco Verificação', canRequestFocus: false, skipTraversal: true);

  /// Onde estava o foco ao sair de cada ecrã (Voltar no progresso devolve-o ao passo 2).
  final _ultimoFoco = <EcraGestor, FocusNode?>{};

  /// O foco do indicador de atividade (o painel devolve-lho ao fechar).
  final _focoIndicador = FocoForaDaEntrada(debugLabel: 'Indicador de atividade');

  /// Tira o registo do Voltar na casca.
  VoidCallback? _tirarVoltar;

  Biblioteca get _b => widget.biblioteca;
  AreaGestor get _g => widget.area;
  ServicoVerificacao get _s => widget.servico;

  @override
  void initState() {
    super.initState();
    _g.addListener(_aoMudarArea);
    widget.pedido?.addListener(_aoPedido);
    _s.addListener(_aoMudarServico);
  }

  /// A barra do progresso desaparece quando a verificação acaba (ou é parada): se tinha o foco,
  /// depois do frame ele passa ao cartão 2 (senão perdia-se, ou o Flutter devolvia-o a um
  /// controlo qualquer do resumo).
  void _aoMudarServico() {
    if (_s.ocupado || !_focoBarraAtividade.hasPrimaryFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // (a barra só existe com o serviço ocupado: se recomeçou, ela voltou e fica com o foco)
      if (!mounted || _ecra != EcraGestor.resumo || _s.ocupado) return;
      _focosCartoes[1].requestFocus();
    });
  }

  /// A casca pediu um ecrã.
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
    _tirarVoltar ??= TelaPrincipal.aoVoltar(context, _voltar);
  }

  @override
  void didUpdateWidget(TelaGestor antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.pedido != widget.pedido) {
      antigo.pedido?.removeListener(_aoPedido);
      widget.pedido?.addListener(_aoPedido);
    }
    if (antigo.servico != widget.servico) {
      antigo.servico.removeListener(_aoMudarServico);
      widget.servico.addListener(_aoMudarServico);
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
    _s.removeListener(_aoMudarServico);
    for (final f in [
      ..._focosCartoes,
      _focoBarraAtividade,
      _focoFaixa,
      _focoVoltar,
      _focoOrigens,
      _focoPesquisa,
      _focoFuncionam,
      _focoVerificarMais,
      _blocoVerificacao,
    ]) {
      f.dispose();
    }
    super.dispose();
  }

  /// As listas do Gestor mudaram: as marcadas que saíram do Gestor saem das marcadas.
  void _aoMudarArea() => _marcadas.removeWhere((id) => _g.porId(id) == null);

  // ---------------------------------------------------------------- ecrãs

  /// Mostra o ecrã `e` e põe-lhe o foco: na faixa (`naFaixa`, ao mudar de passo nela), no
  /// primeiro controlo de um passo, no cartão do passo de onde se veio (no resumo) ou, ao voltar
  /// do progresso ao passo 2, onde lá estava.
  void _abrir(EcraGestor e, {bool naFaixa = false}) {
    final antes = _ecra;
    if (e == antes) return;
    _ultimoFoco[antes] = FocusManager.instance.primaryFocus;
    setState(() => _ecra = e);
    // depois do frame: o ecrã novo já pode receber o foco (o antigo deixa de poder)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _ecra != e) return;
      _alvoDoFoco(e, antes, naFaixa).requestFocus();
    });
  }

  FocusNode _alvoDoFoco(EcraGestor e, EcraGestor antes, bool naFaixa) {
    if (naFaixa && _passos.contains(e)) return _focoFaixa;
    switch (e) {
      case EcraGestor.resumo:
        final i = _passos.indexOf(antes == EcraGestor.verificacao ? EcraGestor.verificar : antes);
        return _focosCartoes[i < 0 ? 0 : i];
      case EcraGestor.importar:
        return _focoOrigens;
      case EcraGestor.verificar:
        final f = antes == EcraGestor.verificacao ? _ultimoFoco[EcraGestor.verificar] : null;
        return f != null && f.context != null && f.canRequestFocus ? f : _focoPesquisa;
      case EcraGestor.enviar:
        // o primeiro chip ativo (sem listas que funcionam, «Funcionam» está desativado)
        return _passoEnviar.currentState?.focoInicio ?? _focoFuncionam;
      case EcraGestor.verificacao:
        return _focoVerificarMais;
    }
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

  /// Abre o progresso da verificação (o indicador do topo no passo 2).
  void _verVerificacao() => _abrir(EcraGestor.verificacao);

  /// No passo 2, a tecla Menu abre as ações de qualquer sítio (também do "Voltar", da faixa e do
  /// indicador, como diz a barra de teclas); a escrever num campo, a tecla fica para o campo.
  KeyEventResult _teclaMenu(KeyEvent e) {
    if (_ecra != EcraGestor.verificar ||
        e is! KeyDownEvent ||
        e.logicalKey != LogicalKeyboardKey.contextMenu ||
        focoAEscrever()) {
      return KeyEventResult.ignored;
    }
    final passo = _passoVerificar.currentState;
    if (passo == null) return KeyEventResult.ignored;
    passo.abrirAcoes();
    return KeyEventResult.handled;
  }

  /// Voltar (do comando ou o botão): num passo regressa ao resumo; no progresso, ao passo 2.
  /// false = não tratou (no resumo, a casca vai para Ver TV).
  bool _voltar() {
    if (_ecra == EcraGestor.resumo) return false;
    // a escrever num campo (colar texto): o Voltar só fecha o teclado (é o CampoTv que o trata)
    if (focoAEscrever()) return true;
    _abrir(_ecra == EcraGestor.verificacao ? EcraGestor.verificar : EcraGestor.resumo);
    return true;
  }

  // ---------------------------------------------------------------- ações

  static String _n(int n, String um, String varios) => '$n ${n == 1 ? um : varios}';

  void _aviso(String t) {
    if (mounted) mostrarMensagem(context, t);
  }

  /// As listas como estão agora no Gestor (as que saíram ficam de fora).
  List<Lista> _atuais(List<Lista> listas) => [for (final l in listas) ?_g.porId(l.id)];

  /// "Verificar selecionadas" (passo 2): juntam-se à fila, mesmo a meio de uma verificação.
  void _verificarSelecionadas(List<Lista> listas) {
    if (listas.isEmpty) return _aviso('Selecione as listas a verificar.');
    final novas = [for (final l in listas) if (!_s.aVerificar(l.id)) l];
    if (novas.isEmpty) {
      return _aviso(listas.length == 1 ? 'A lista selecionada já está na fila.' : 'As listas selecionadas já estão na fila.');
    }
    _s.verificarVarias(novas);
    _aviso(novas.length == 1 ? '1 lista entrou na fila.' : '${novas.length} listas entraram na fila.');
  }

  /// "Verificar mais (fila)" (no progresso): vai ao passo 2 só com as "Por verificar"; aí
  /// escolhem-se as listas e "Verificar selecionadas" junta-as à ronda que decorre.
  void _verificarMais() {
    _abrir(EcraGestor.verificar);
    // depois de _abrir (que põe o foco no passo): o foco vai ao filtro escolhido
    _passoVerificar.currentState?.filtrar({EstadoLista.porVerificar});
  }

  /// "Verificar todas": as que ainda não estão na fila juntam-se a ela; a seleção fica.
  void _verificarTodas() {
    final listas = _g.listas;
    if (listas.isEmpty) return _aviso('Importe listas primeiro.');
    final novas = [for (final l in listas) if (!_s.aVerificar(l.id)) l];
    if (novas.isEmpty) return _aviso('Todas as listas já estão na fila.');
    _s.verificarVarias(novas);
  }

  Future<void> _parar() async {
    if (!await confirmarParar(context, _s) || !mounted) return;
    _aviso('Verificação parada. O relatório fica no ecrã da verificação.');
    // "Parar" desaparece: o foco passa para "Verificar mais (fila)" (depois do frame: o diálogo
    // que fechou devolve o foco ao "Parar" primeiro)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && FocusManager.instance.primaryFocus?.context?.widget is! EditableText) {
        _focoVerificarMais.requestFocus();
      }
    });
  }

  /// "Enviar N listas" (passo 3): vão as marcadas que não estão a ser verificadas (as que estão
  /// ficam de fora e a mensagem final diz quantas são). O diálogo só pergunta como (adicionar ou
  /// substituir); depois o envio corre como tarefa, sem esperar.
  Future<void> _enviar(List<Lista> marcadas) async {
    ({List<Lista> prontas, int aDecorrer}) ponto() {
      final ls = _atuais(marcadas);
      return (prontas: [for (final l in ls) if (!_s.aVerificar(l.id)) l], aDecorrer: ls.where((l) => _s.aVerificar(l.id)).length);
    }

    final antes = ponto();
    if (antes.prontas.isEmpty) {
      return _aviso(marcadas.length == 1
          ? 'A lista marcada ainda está a ser verificada.'
          : 'As listas marcadas ainda estão a ser verificadas.');
    }
    final escolha = await perguntarEnvio(context, n: antes.prontas.length);
    if (escolha == null || !mounted) return;
    final (modo, manter) = escolha;
    // o estado pode ter mudado com o diálogo aberto: conta-se de novo
    final agora = ponto();
    final enviar = agora.prontas;
    if (enviar.isEmpty) return _aviso('Já não há listas para enviar.');
    // o que a tarefa precisa, antes de qualquer await
    final b = _b;
    final ctx = context;
    final aDecorrer = agora.aDecorrer;
    final n = enviar.length;
    widget.tarefas.iniciar(
      'Enviar ${n == 1 ? '1 lista' : '$n listas'} para Ver TV',
      (p) async {
        final ResumoEnvio r;
        try {
          r = await b.receber(enviar, modo, manter: manter);
        } catch (e) {
          throw _ErroTarefa('Não foi possível enviar (${descreverErro(e)}). As listas de Ver TV não mudaram.');
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

  /// "Exportar N listas" (passo 3): a escolha do formato faz-se antes; depois o ficheiro é guardado
  /// numa tarefa (a janela "Guardar como" do sistema é a única espera). Se falhar, "Tentar de
  /// novo" repete tudo com a mesma escolha e volta a perguntar onde guardar.
  Future<void> _exportar(List<Lista> marcadas) async {
    final listas = _atuais(marcadas);
    if (listas.isEmpty) return _aviso('Marque as listas a exportar.');
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
      if (zip == null) return _aviso('Nenhuma das listas marcadas é Stalker (portal + MAC).');
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
          if (r.cancelado) return 'Exportação cancelada.';
          if (mounted) setState(() => _ultimaExportacao = DateTime.now());
          return '$texto Guardado em ${r.destino}';
        },
        repetir: () async => lancar(),
      );
    }

    lancar();
  }

  /// "Remover do gestor" (passo 2): pede confirmação; as que estão a ser verificadas têm a
  /// verificação cancelada (só essas: as outras continuam).
  Future<void> _removerSelecionadas(List<Lista> listas) async {
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
            '${aVerificar}As listas de Ver TV não mudam.',
        acao: 'Remover');
    if (!ok) return;
    // o estado pode ter mudado enquanto o diálogo estava aberto
    for (final l in listas) {
      if (_s.aVerificar(l.id)) _s.cancelar(l.id);
    }
    await _g.remover(listas.map((l) => l.id));
  }

  // ---------------------------------------------------------------- construção

  @override
  Widget build(BuildContext context) {
    final noPasso = _passos.contains(_ecra);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onKeyEvent: (_, e) => _teclaMenu(e),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _barraTopo(),
      if (noPasso) _faixa(),
      Expanded(
        child: IndexedStack(
          index: _ecra.index,
          sizing: StackFit.expand,
          children: [
            _resumo(),
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
            PassoVerificar(
              key: _passoVerificar,
              area: _g,
              servico: _s,
              aoVerificar: _verificarSelecionadas,
              aoVerificarTodas: _verificarTodas,
              aoRemover: _removerSelecionadas,
              focoInicial: _focoPesquisa,
            ),
            PassoEnviar(
              key: _passoEnviar,
              area: _g,
              marcadas: _marcadas,
              // o resumo não mostra as marcadas: nada a reconstruir aqui
              aoMudarMarcadas: () {},
              aoEnviar: _enviar,
              aoExportar: _exportar,
              focoInicial: _focoFuncionam,
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
      BarraTeclas(switch (_ecra) {
        EcraGestor.resumo => const [('OK', 'abrir o passo'), ('←', 'menu')],
        EcraGestor.verificacao => const [('Voltar', 'passo 2 · Verificar'), ('OK', 'escolher')],
        EcraGestor.verificar => const [
            ('Voltar', 'resumo do Gestor'),
            ('← →', 'mudar de passo na faixa'),
            ('OK', 'escolher'),
            ('Menu', 'ações'),
          ],
        _ => const [('Voltar', 'resumo do Gestor'), ('← →', 'mudar de passo na faixa'), ('OK', 'escolher')],
      }),
    ]),
    );
  }

  Widget _barraTopo() {
    // no passo 2 é o indicador da verificação (OK abre o progresso, se houve uma); nos outros
    // ecrãs, o de toda a atividade (OK abre o painel)
    final indicador = _ecra == EcraGestor.verificar
        ? IndicadorAtividade(
            servico: _s, tarefas: widget.tarefas, foco: _focoIndicador, soVerificacao: true, aoAbrir: _verVerificacao)
        : IndicadorAtividade(servico: _s, tarefas: widget.tarefas, foco: _focoIndicador, aoAbrir: _abrirAtividade);
    if (ecraTelemovel(context)) return _barraTopoTelemovel(indicador);
    final titulo = switch (_ecra) {
      EcraGestor.resumo => 'Gestor de listas',
      EcraGestor.importar => 'Importar listas',
      EcraGestor.verificar => 'Verificar listas',
      EcraGestor.enviar => 'Exportar listas',
      EcraGestor.verificacao => 'Verificação',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e12, Tokens.e16, 0),
      child: Row(children: [
        if (_ecra != EcraGestor.resumo) ...[
          TextButton.icon(
            focusNode: _focoVoltar,
            onPressed: _voltar,
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
        // à direita: o indicador só encolhe se não couber; o "i" fica no canto
        Flexible(child: Align(alignment: Alignment.centerRight, child: indicador)),
        if (_temInfo) ...[const SizedBox(width: Tokens.e4), _botaoInfo()],
      ]),
    );
  }

  /// O topo no telemóvel, como uma barra de app: ← só com o ícone (48), o título só no resumo
  /// e no progresso (num passo, a faixa já diz onde se está) e o indicador compacto à direita.
  Widget _barraTopoTelemovel(Widget indicador) {
    final titulo = switch (_ecra) {
      EcraGestor.resumo => 'Gestor de listas',
      EcraGestor.verificacao => 'Verificação',
      _ => null,
    };
    final resumo = _ecra == EcraGestor.resumo;
    return Padding(
      padding: EdgeInsets.fromLTRB(resumo ? Tokens.e16 : Tokens.e4, Tokens.e4, Tokens.e8, 0),
      child: Row(children: [
        if (!resumo)
          IconButton(
            focusNode: _focoVoltar,
            onPressed: _voltar,
            tooltip: 'Voltar',
            icon: const Icon(Icons.arrow_back),
          ),
        Expanded(
          child: titulo == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: EdgeInsets.only(left: resumo ? 0 : Tokens.e4),
                  child: Text(titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Tokens.texto)),
                ),
        ),
        const SizedBox(width: Tokens.e8),
        indicador,
        if (_temInfo) _botaoInfo(),
      ]),
    );
  }

  /// O "i" da verificação (no passo 2 e no progresso): explica como é feita.
  bool get _temInfo => _ecra == EcraGestor.verificar || _ecra == EcraGestor.verificacao;

  Widget _botaoInfo() => IconButton(
        key: const ValueKey('infoVerificacao'),
        onPressed: () => abrirComoVerifica(context),
        tooltip: 'Como é feita a verificação',
        icon: const Icon(Icons.info_outline),
      );

  // ---------------------------------------------------------------- faixa dos passos

  /// A faixa dos passos no topo de cada passo, com o aberto em destaque. É uma só paragem do
  /// foco, da largura da faixa (CIMA a partir do passo chega-lhe, seja qual for a coluna); ← →
  /// abrem o passo ao lado e o foco fica na faixa; BAIXO entra no passo e CIMA vai ao "Voltar".
  Widget _faixa() {
    final atual = _passos.indexOf(_ecra);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e8, Tokens.e16, 0),
      child: Semantics(
        container: true,
        label: 'Passos do Gestor',
        child: Focus(
          focusNode: _focoFaixa,
          onKeyEvent: (_, e) => _teclaFaixa(atual, e),
          child: Builder(builder: (context) {
            final focado = Focus.of(context).hasPrimaryFocus;
            return Row(children: [
              for (final (i, nome) in _nomesPassos.indexed) ...[
                if (i > 0) const SizedBox(width: Tokens.e8),
                Expanded(child: _itemFaixa(i, nome, aberto: i == atual, focado: focado && i == atual)),
              ],
            ]);
          }),
        ),
      ),
    );
  }

  KeyEventResult _teclaFaixa(int atual, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    // BAIXO entra no passo pelo seu primeiro controlo (a faixa é larga: a procura direcional
    // escolheria um qualquer)
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      _alvoDoFoco(_ecra, EcraGestor.resumo, false).requestFocus();
      return KeyEventResult.handled;
    }
    // CIMA vai ao "Voltar" (por cima, à esquerda)
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      _focoVoltar.requestFocus();
      return KeyEventResult.handled;
    }
    final passo = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowRight => atual + 1,
      LogicalKeyboardKey.arrowLeft => atual - 1,
      _ => -1,
    };
    // no 1.º, ESQUERDA segue para a barra das secções
    if (passo < 0 || passo >= _passos.length) return KeyEventResult.ignored;
    _abrir(_passos[passo], naFaixa: true);
    return KeyEventResult.handled;
  }

  /// A faixa baixa (36) na TV e no computador; no telemóvel, 48 (o alvo de toque).
  static bool _faixaCompacta(BuildContext context) =>
      ecraTv(context) ||
      switch (defaultTargetPlatform) {
        TargetPlatform.windows || TargetPlatform.linux || TargetPlatform.macOS => true,
        _ => false,
      };

  Widget _itemFaixa(int i, String nome, {required bool aberto, required bool focado}) {
    // no telemóvel o nome curto, centrado e sempre inteiro (encolhe se a letra for muito grande)
    final telemovel = ecraTelemovel(context);
    final estilo = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: aberto ? Tokens.texto : Tokens.texto2);
    return Semantics(
      button: true,
      selected: aberto,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _abrir(_passos[i], naFaixa: true),
        child: Container(
          key: ValueKey('faixa ${i + 1}'),
          // compacta na TV e no Windows (a 80 %); no telemóvel, o alvo de toque de 48
          height: _faixaCompacta(context) ? 36 : Tokens.alvoToque,
          padding: EdgeInsets.symmetric(horizontal: telemovel ? Tokens.e8 : 14),
          alignment: telemovel ? Alignment.center : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: aberto ? Tokens.acento : Tokens.superficie2,
            borderRadius: BorderRadius.circular(Tokens.raioCampo),
            border: focado ? Border.all(color: Tokens.anelFoco, width: 4) : null,
          ),
          child: telemovel
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_nomesCurtos[i], maxLines: 1, softWrap: false, style: estilo),
                )
              : Text('${i + 1} · $nome', maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- resumo

  /// "agora", "há 3 min", "há 2 h", "ontem" ou "há 3 dias".
  static String _ha(DateTime d) {
    final dif = DateTime.now().difference(d);
    if (dif.inMinutes < 1) return 'agora';
    if (dif.inMinutes < 60) return 'há ${dif.inMinutes} min';
    if (dif.inHours < 24) return 'há ${dif.inHours} h';
    return dif.inDays == 1 ? 'ontem' : 'há ${dif.inDays} dias';
  }

  static const _mut = TextStyle(color: Tokens.texto2, fontSize: 14, fontWeight: FontWeight.w500);

  Widget _resumo() => ListenableBuilder(
        listenable: Listenable.merge([_b, _g, _s, _registo, widget.tarefas]),
        builder: (context, _) => LayoutBuilder(builder: (context, caixa) {
          final listas = _g.listas;
          int conta(EstadoLista e) => listas.where((l) => estadoDe(l) == e).length;
          final vazio = listas.isEmpty;
          final ultima = _registo.ultima;
          final importada = ultima == null ? null : _registo.resumoDe(ultima);
          // a TV (960 com a barra lateral) dá ~740: os três lado a lado
          final largo = caixa.maxWidth >= 560;
          final cartoes = [
            _cartao(0, largo, [
              const Text('Ficheiros, texto, stbstalker ou de Ver TV', style: _mut),
              if (ultima != null)
                _linhaCartao('Última importação',
                    ultima.estado == EstadoTarefa.aDecorrer ? 'a decorrer' : _ha(ultima.fim ?? ultima.inicio)),
              if (importada != null) _linhaCartao('Entraram', _n(importada.novas, 'nova', 'novas')),
            ]),
            _cartao(1, largo, [
              if (vazio)
                const Text('Importe listas primeiro', style: _mut)
              else ...[
                _numeroGrande(conta(EstadoLista.porVerificar), Tokens.aviso, 'por verificar'),
                _linhaCartao('Funcionam', '${conta(EstadoLista.funciona)}', cor: Tokens.ok),
                _linhaCartao('Não funcionam', '${conta(EstadoLista.naoFunciona)}', cor: Tokens.mau),
              ],
            ]),
            _cartao(2, largo, [
              if (vazio)
                const Text('Importe listas primeiro', style: _mut)
              else ...[
                _numeroGrande(conta(EstadoLista.funciona), Tokens.texto, 'prontas a enviar'),
              ],
              _linhaCartao('Em Ver TV', _n(_b.listas.length, 'lista', 'listas')),
              if (_ultimaExportacao case final quando?) _linhaCartao('Última exportação', _ha(quando)),
            ]),
          ];
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e4, Tokens.e16, Tokens.e16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${_n(listas.length, 'lista', 'listas')} no Gestor · escolhe por onde começar', style: _mut),
              const SizedBox(height: Tokens.e12),
              if (largo)
                IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (final (i, c) in cartoes.indexed) ...[
                      if (i > 0) const SizedBox(width: Tokens.e16),
                      Expanded(child: c),
                    ],
                  ]),
                )
              else
                for (final (i, c) in cartoes.indexed) ...[if (i > 0) const SizedBox(height: Tokens.e12), c],
              if (_s.ocupado) ...[const SizedBox(height: Tokens.e16), _barraAtividade()],
            ]),
          );
        }),
      );

  /// Um cartão do resumo, baixo: o número e o nome do passo numa linha, o estado (o número
  /// grande com o rótulo ao lado e até duas linhas) e "OK: abrir →".
  Widget _cartao(int i, bool largo, List<Widget> corpo) {
    // a dica do comando só na TV e no computador; ao toque, a seta › diz que o cartão abre
    final dica = mostrarDicasComando(context);
    return CartaoModerno(
        focusNode: _focosCartoes[i],
        escalaFoco: 1.02,
        padding: const EdgeInsets.symmetric(horizontal: Tokens.e12, vertical: 10),
        onTap: () => _abrir(_passos[i]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Tokens.acento, shape: BoxShape.circle),
              child: Text('${i + 1}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Tokens.texto)),
            ),
            const SizedBox(width: Tokens.e8),
            Expanded(
              child: Text(_nomesPassos[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Tokens.texto)),
            ),
            if (!dica) const Icon(Icons.chevron_right, color: Tokens.texto2),
          ]),
          const SizedBox(height: 6),
          for (final w in corpo) Padding(padding: const EdgeInsets.only(bottom: 2), child: w),
          if (dica) ...[
            // lado a lado (com a mesma altura), "OK: abrir →" fica em baixo em todos
            if (largo) const Spacer() else const SizedBox(height: Tokens.e4),
            const Text('OK: abrir →',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Tokens.anelFoco)),
          ],
        ]),
      );
  }

  /// O número grande com o rótulo ao lado ("5 por verificar").
  static Widget _numeroGrande(int n, Color cor, String rotulo) => Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('$n', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: cor, height: 1.1)),
            const SizedBox(width: 6),
            Flexible(child: Text(rotulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: _mut)),
          ]);

  static Widget _linhaCartao(String rotulo, String valor, {Color cor = Tokens.texto}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 2),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Tokens.bordaVidro))),
        child: Row(children: [
          Expanded(
            child: Text(rotulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Tokens.texto, fontSize: 14, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: Tokens.e8),
          Text(valor, style: TextStyle(color: cor, fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
      );

  /// A barra do progresso no resumo: "A verificar 2/5", a barra e "faltam cerca de 40 s" (só
  /// quando há estimativa). OK nela abre o progresso.
  Widget _barraAtividade() {
    final estimativa = _s.estimativaRestante;
    final fracao = _s.total == 0 ? 0.0 : (_s.feitas / _s.total).clamp(0.0, 1.0);
    return Semantics(
      liveRegion: true,
      child: RealceFoco(
        raio: Tokens.raioBotao,
        construir: (_, aoMudarFoco) => Material(
          color: Tokens.superficie,
          borderRadius: BorderRadius.circular(Tokens.raioBotao),
          child: InkWell(
            key: const ValueKey('barraAtividade'),
            focusNode: _focoBarraAtividade,
            onFocusChange: aoMudarFoco,
            borderRadius: BorderRadius.circular(Tokens.raioBotao),
            onTap: () => _abrir(EcraGestor.verificacao),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.e16, vertical: Tokens.e12),
              child: Row(children: [
                Text('A verificar ${_s.feitas}/${_s.total}',
                    style: const TextStyle(color: Tokens.texto, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(width: Tokens.e12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                        value: fracao, minHeight: 8, color: Tokens.acento, backgroundColor: Tokens.fundoNeutro),
                  ),
                ),
                if (estimativa != null) ...[
                  const SizedBox(width: Tokens.e12),
                  Text(TelaVerificacao.textoEstimativa(estimativa), style: _mut),
                ],
              ]),
            ),
          ),
        ),
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
