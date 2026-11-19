import 'package:material_ui/material_ui.dart';

import '../../dados/area_gestor.dart';
import '../../dados/biblioteca.dart';
import '../../dados/guardar_ficheiro.dart';
import '../../importar/importar.dart';
import '../../importar/stbstalker.dart';
import '../../modelo/conta.dart';
import '../../rede/http.dart';
import '../../verificar/canais_teste.dart';
import '../../verificar/exportar.dart';
import '../../verificar/servico.dart';
import '../adicionar.dart';
import '../design/design.dart';
import '../navegacao_blocos.dart';
import '../realce_foco.dart';
import 'dialogos_gestor.dart';
import '../design/mensagens.dart';

/// Separador "Gestor": a área de trabalho com as suas próprias listas ([AreaGestor]), em três
/// passos de cima para baixo (cada um diz no cabeçalho como está):
///
/// 1. **Importar** — ficheiros/colar, a pesquisa do stbstalker ou "Importar do Player";
/// 2. **Verificar** — todas ou as selecionadas, com o progresso;
/// 3. **Enviar / Exportar** — selecionar, "Enviar para o Player" (adicionar/esmagar), remover e
///    exportar (Accounts.json ou .ini).
///
/// Por baixo, os resultados (as listas, com a caixa para selecionar), filtráveis pelo estado.
/// Com o comando, BAIXO/CIMA percorrem os passos pela ordem e chegam às listas.
class TelaVerificar extends StatefulWidget {
  const TelaVerificar({super.key, required this.biblioteca, required this.area, required this.servico,
      this.baseStb = stbBase, this.abrirDefinicoes});

  /// As listas do Player (recebem os envios) e os canais de teste.
  final Biblioteca biblioteca;
  final AreaGestor area;

  /// Grava os resultados no Gestor.
  final ServicoVerificacao servico;

  /// Abre as Definições (onde se escolhem os canais de teste).
  final VoidCallback? abrirDefinicoes;

  /// O blog a pesquisar (injetável para os testes).
  final String baseStb;

  @override
  State<TelaVerificar> createState() => _TelaVerificarState();
}

class _TelaVerificarState extends State<TelaVerificar> {
  final _selecao = <String>{};
  String _formato = 'json';
  late DateTime _inicio = _hoje(), _fim = _hoje();
  bool _pesquisando = false;

  /// "Parar" desaparece quando carregado: o foco passa para "Verificar todas".
  final _focoVerificarTodas = FocusNode();

  /// O filtro dos resultados pelo estado (null = todas; 'por_verificar' = sem resultado).
  String? _filtroEstado;

  /// O foco de cada linha (pelo id): se a linha com o foco sai dos resultados (mudou de estado
  /// com um filtro ativo, ou foi removida), o foco passa à que fica no lugar dela.
  final _focosLinhas = <String, FocusNode>{};
  String? _linhaFocada;
  List<String> _ordemVista = const [];
  final _focosFiltros = [for (final (_, t) in _filtros) FocusNode(debugLabel: 'Filtro $t')];

  /// Os blocos para CIMA/BAIXO: os 3 passos e o cabeçalho dos resultados (ver [moverEntreBlocos]).
  final _blocos = [
    for (final b in ['Importar', 'Verificar', 'Enviar', 'Resultados'])
      FocusNode(debugLabel: 'Passo $b', canRequestFocus: false, skipTraversal: true),
  ];

  FocusNode _focoLinha(String id) => _focosLinhas.putIfAbsent(id, () => FocusNode(debugLabel: 'Linha'));

  @override
  void initState() {
    super.initState();
    widget.area.addListener(_aoMudarArea);
  }

  @override
  void didUpdateWidget(TelaVerificar antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.area != widget.area) {
      antigo.area.removeListener(_aoMudarArea);
      widget.area.addListener(_aoMudarArea);
    }
  }

  /// As listas do Gestor mudaram (verificação, remoção...): fora do build, vê se a linha com o
  /// foco saiu dos resultados e, depois do frame (quando as linhas antigas já saíram da árvore),
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

  @override
  void dispose() {
    widget.area.removeListener(_aoMudarArea);
    _focoVerificarTodas.dispose();
    for (final b in _blocos) {
      b.dispose();
    }
    for (final f in _focosFiltros) {
      f.dispose();
    }
    for (final f in _focosLinhas.values) {
      f.dispose();
    }
    super.dispose();
  }

  String? _resultadoStb;

  static DateTime _hoje() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static String _dd(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _escolherData(bool inicio) async {
    final hoje = _hoje();
    final atual = inicio ? _inicio : _fim;
    final d = await showDatePicker(
      context: context,
      initialDate: atual,
      firstDate: inicio ? DateTime(2015) : _inicio,
      lastDate: inicio ? _fim : hoje,
      helpText: inicio ? 'Data de início' : 'Data de fim',
    );
    if (d == null || !mounted) return;
    setState(() {
      if (inicio) {
        _inicio = d;
      } else {
        _fim = d;
      }
    });
  }

  Future<void> _pesquisarStb() async {
    if (_pesquisando) return; // o botão fica ligado (não perde o foco do comando)
    setState(() {
      _pesquisando = true;
      _resultadoStb = null;
    });
    String msg;
    try {
      final r = await importarEntre(_inicio, _fim, base: widget.baseStb);
      if (r.erro != null) {
        msg = r.erro!;
      } else {
        final novas = await _g.adicionar([
          for (final l in r.linhas)
            if (contaDeLinha(l) case final c?) Importada(c),
        ]);
        final periodo = _inicio == _fim ? 'Em ${_dd(_inicio)}' : 'De ${_dd(_inicio)} a ${_dd(_fim)}';
        final np = r.posts.length;
        msg = '$periodo: ${r.total} ${r.total == 1 ? 'linha' : 'linhas'} em $np '
            '${np == 1 ? 'post' : 'posts'}, $novas ${novas == 1 ? 'lista nova' : 'listas novas'}.';
      }
    } catch (e) {
      msg = 'Não foi possível pesquisar: ${descreverErro(e)}';
    }
    if (!mounted) return;
    setState(() {
      _pesquisando = false;
      _resultadoStb = msg;
    });
  }

  /// A pesquisa do stbstalker (dentro do passo 1).
  Widget _secaoStb() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _subtitulo('Listas do stbstalker'),
      const Padding(
        padding: EdgeInsets.only(bottom: Tokens.e8),
        child: Text('Junta as listas publicadas no blog entre duas datas.', style: TextStyle(color: Tokens.texto2)),
      ),
      Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, crossAxisAlignment: WrapCrossAlignment.end, children: [
        _campoData('Data de início', _inicio, () => _escolherData(true)),
        _campoData('Data de fim', _fim, () => _escolherData(false)),
        FilledButton.icon(
          onPressed: _pesquisarStb,
          icon: _pesquisando
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.search),
          label: const Text('Iniciar pesquisa'),
        ),
      ]),
      if (_resultadoStb != null) ...[
        const SizedBox(height: Tokens.e12),
        Text(_resultadoStb!),
      ],
    ]);
  }

  /// Uma secção do ecrã num painel de vidro (entra em cascata): o bloco `i` para CIMA/BAIXO.
  Widget _seccao(int i, Widget filho) => Padding(
        padding: const EdgeInsets.only(bottom: Tokens.e16),
        child: Focus(
          focusNode: _blocos[i],
          canRequestFocus: false,
          skipTraversal: true,
          includeSemantics: false,
          child: entradaEmCascata(i, SuperficieVidro(padding: const EdgeInsets.all(Tokens.e16 + 4), child: filho)),
        ),
      );

  /// Um passo do Gestor: o número e o nome, o estado (no subtítulo) e o conteúdo.
  Widget _passo(int i,
          {required String titulo, required String estado, required IconData icone, required List<Widget> filhos}) =>
      _seccao(i - 1, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CabecalhoSeccao(titulo: '$i · $titulo', subtitulo: estado, icone: icone),
        ...filhos,
      ]));

  /// Um título pequeno dentro de um passo.
  Widget _subtitulo(String t) => Padding(
        padding: const EdgeInsets.only(bottom: Tokens.e8),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
      );

  Widget _campoData(String rotulo, DateTime d, VoidCallback aoTocar) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rotulo, style: const TextStyle(color: Tokens.texto2, fontSize: 12)),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _pesquisando ? null : aoTocar,
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(_dd(d)),
          ),
        ],
      );

  Biblioteca get _b => widget.biblioteca;
  AreaGestor get _g => widget.area;

  List<Lista> get _selecionadas => [for (final l in _g.listas) if (_selecao.contains(l.id)) l];

  void _selecionar(bool Function(Lista) criterio) =>
      setState(() => _selecao..clear()..addAll([for (final l in _g.listas) if (criterio(l)) l.id]));

  Future<void> _importarDoPlayer() async {
    if (_b.listas.isEmpty) return _aviso('Ainda não há listas no Player.');
    try {
      final n = await _g.importarDoPlayer(_b);
      _aviso(switch (n) {
        0 => 'As listas do Player já estão no Gestor.',
        1 => '1 lista importada do Player.',
        _ => '$n listas importadas do Player.',
      });
    } catch (e) {
      _aviso('Não foi possível importar: ${descreverErro(e)}');
    }
  }

  /// "Enviar para o Player": pede sempre confirmação (como, e o que fica ao esmagar).
  Future<void> _enviar() async {
    final listas = _selecionadas;
    if (listas.isEmpty) return _aviso('Selecione as listas a enviar.');
    final modo = await perguntarModoEnvio(context, listas.length);
    if (modo == null || !mounted) return;
    try {
      _aviso(textoResumoEnvio(await _b.receber(listas, modo)));
    } catch (e) {
      _aviso('Não foi possível enviar (${descreverErro(e)}). As listas do Player não mudaram.');
    }
  }

  Future<void> _removerSelecionadas() async {
    final listas = _selecionadas;
    if (listas.isEmpty) return _aviso('Selecione as listas a remover.');
    final n = listas.length;
    final ok = await confirmar(context,
        icone: Icons.remove_circle_outline,
        titulo: 'Remover do Gestor?',
        texto: '${n == 1 ? 'A lista selecionada sai' : 'As $n listas selecionadas saem'} do Gestor. '
            'As listas do Player não mudam.',
        acao: 'Remover');
    if (ok) await _g.remover(listas.map((l) => l.id));
  }

  Future<void> _limpar() async {
    final n = _g.listas.length;
    if (n == 0) return _aviso('O Gestor já está vazio.');
    final ok = await confirmar(context,
        icone: Icons.delete_sweep_outlined,
        titulo: 'Limpar o Gestor?',
        texto: '${n == 1 ? 'A lista do Gestor sai' : 'As $n listas do Gestor saem'}. As listas do Player não mudam.',
        acao: 'Limpar');
    if (!ok) return;
    if (widget.servico.ocupado) widget.servico.parar();
    await _g.limpar();
  }

  Future<void> _exportar() async {
    final listas = _selecionadas;
    if (listas.isEmpty) return _aviso('Selecione as listas a exportar.');
    try {
      if (_formato == 'json') {
        final r = await guardarFicheiro('Accounts.json', exportarAccountsJson(listas), 'application/json');
        if (!r.cancelado) _aviso('${listas.length} listas exportadas. Guardado em ${r.destino}');
        return;
      }
      final (zip, ignoradas) = exportarZipIni(listas);
      if (zip == null) return _aviso('Nenhuma das listas selecionadas é Stalker (portal + MAC).');
      final r = await guardarFicheiro('listas_stalker.zip', zip, 'application/zip');
      if (!r.cancelado) {
        _aviso('Listas exportadas. Guardado em ${r.destino}.'
            '${ignoradas > 0 ? ' $ignoradas sem MAC (Xtream/M3U) ficaram de fora.' : ''}');
      }
    } on ErroGuardar catch (e) {
      _aviso(e.mensagem);
    } catch (e) {
      _aviso(mensagemErroGuardar(e));
    }
  }

  void _aviso(String t) {
    if (mounted) mostrarMensagem(context, t);
  }

  /// Os filtros dos resultados.
  static const _filtros = [
    (null, 'Todas'),
    ('funciona', 'Funcionam'),
    ('inconclusivo', 'INC'),
    ('nao_funciona', 'Não funcionam'),
    ('por_verificar', 'Por verificar'),
  ];

  static String _estado(Lista l) => l.ultima?.estado ?? 'por_verificar';

  static String _n(int n, String um, String varios) => '$n ${n == 1 ? um : varios}';

  List<Lista> _visiveis() =>
      [for (final l in _g.listas) if (_filtroEstado == null || _estado(l) == _filtroEstado) l];

  /// O estado do passo 2: "8 a funcionar · 2 INC · 1 não funciona · 3 por verificar".
  String _resumoVerificacao(ServicoVerificacao s, Map<String, int> contagens, int total) {
    if (total == 0) return 'Importe listas primeiro';
    if (s.ocupado) return 'A verificar: ${s.feitas} de ${s.total}';
    int c(String e) => contagens[e] ?? 0;
    return [
      if (c('funciona') > 0) '${c('funciona')} a funcionar',
      if (c('inconclusivo') > 0) '${c('inconclusivo')} INC',
      if (c('nao_funciona') > 0) _n(c('nao_funciona'), 'não funciona', 'não funcionam'),
      if (c('por_verificar') > 0) '${c('por_verificar')} por verificar',
    ].join(' · ');
  }

  /// A linha com o foco saiu dos resultados: o foco passa à linha que ficou no lugar dela (ou,
  /// sem linhas, ao filtro escolhido). Sem isto o foco perdia-se (ficava invisível).
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
        _focosFiltros[_filtros.indexWhere((f) => f.$1 == _filtroEstado)].requestFocus();
      } else {
        _focoLinha(vis[antes.clamp(0, vis.length - 1)].id).requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_b, _g, widget.servico]),
      builder: (context, _) {
        final s = widget.servico;
        final listas = _g.listas;
        _selecao.removeWhere((id) => _g.porId(id) == null);
        final contagens = <String, int>{};
        for (final l in listas) {
          contagens.update(_estado(l), (n) => n + 1, ifAbsent: () => 1);
        }
        final visiveis = _visiveis();
        final vazio = listas.isEmpty;
        // CustomScrollView: os passos em cima e as linhas das listas preguiçosas (SliverList.builder),
        // para não construir centenas de linhas em cada passo da verificação
        return Focus(
          canRequestFocus: false,
          skipTraversal: true,
          includeSemantics: false,
          onKeyEvent: (_, e) => moverEntreBlocos(_blocos, e),
          child: CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e16, Tokens.e16, 0),
            sliver: SliverList.list(children: [
              _passo(1,
                  titulo: 'Importar',
                  estado: vazio ? 'O Gestor está vazio' : _n(listas.length, 'lista no Gestor', 'listas no Gestor'),
                  icone: Icons.inventory_2_outlined,
                  filhos: [
                    Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, children: [
                      FilledButton.icon(
                        onPressed: () => mostrarAdicionar(context, _g),
                        icon: const Icon(Icons.playlist_add_rounded),
                        label: const Text('Adicionar listas'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _importarDoPlayer,
                        icon: const Icon(Icons.download_for_offline_outlined),
                        label: const Text('Importar do Player'),
                      ),
                      // fica ligado com o Gestor vazio (um botão desligado perde o foco do comando)
                      OutlinedButton.icon(
                        onPressed: _limpar,
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: const Text('Limpar o Gestor'),
                      ),
                    ]),
                    if (vazio) ...[
                      const SizedBox(height: Tokens.e8),
                      const Text('Adicione ficheiros ou linhas coladas, pesquise no stbstalker ou importe as do Player.',
                          style: TextStyle(color: Tokens.texto2)),
                    ],
                    const SizedBox(height: Tokens.e24),
                    _secaoStb(),
                  ]),
              _passo(2,
                  titulo: 'Verificar',
                  estado: _resumoVerificacao(s, contagens, listas.length),
                  icone: Icons.playlist_add_check,
                  filhos: [
                    Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                      // ligados enquanto verifica (desligar um botão com o foco deixa o comando sem foco)
                      FilledButton.icon(
                        focusNode: _focoVerificarTodas,
                        onPressed: vazio
                            ? null
                            : () {
                                if (!s.ocupado) s.verificarVarias(listas);
                              },
                        icon: const Icon(Icons.playlist_add_check),
                        label: Text('Verificar todas (${listas.length})'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _selecao.isEmpty
                            ? null
                            : () {
                                if (!s.ocupado) s.verificarVarias(_selecionadas);
                              },
                        icon: const Icon(Icons.checklist),
                        label: Text('Verificar as selecionadas (${_selecao.length})'),
                      ),
                      if (s.ocupado)
                        OutlinedButton.icon(
                            onPressed: () {
                              final tinhaFoco = FocusManager.instance.primaryFocus?.context?.widget is! EditableText;
                              s.parar();
                              if (tinhaFoco) _focoVerificarTodas.requestFocus();
                            },
                            icon: const Icon(Icons.stop),
                            label: const Text('Parar')),
                    ]),
                    if (s.ocupado) ...[
                      const SizedBox(height: Tokens.e12),
                      LinearProgressIndicator(value: s.total == 0 ? null : s.feitas / s.total, minHeight: 6),
                      const SizedBox(height: Tokens.e4),
                      Text('${s.feitas} de ${s.total} verificadas', style: const TextStyle(color: Tokens.texto2)),
                    ],
                    const SizedBox(height: Tokens.e12),
                    Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                      Text('Canais de teste: ${perfisDe(_b.canaisTeste).map((p) => p.nome).join(', ')}',
                          style: const TextStyle(color: Tokens.texto2)),
                      if (widget.abrirDefinicoes != null)
                        TextButton.icon(
                          onPressed: widget.abrirDefinicoes,
                          icon: const Icon(Icons.settings_outlined),
                          label: const Text('Alterar nas Definições'),
                        ),
                    ]),
                  ]),
              _passo(3,
                  titulo: 'Enviar / Exportar',
                  estado: vazio
                      ? 'Importe listas primeiro'
                      : _selecao.isEmpty
                          ? 'Nenhuma selecionada'
                          : _n(_selecao.length, 'selecionada', 'selecionadas'),
                  icone: Icons.send_rounded,
                  filhos: [
                    _subtitulo('Selecionar'),
                    Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, children: [
                      ActionChip(
                          label: const Text('Funcionam'),
                          onPressed: () => _selecionar((l) => l.ultima?.estado == 'funciona')),
                      ActionChip(
                          label: const Text('Funcionam + INC'),
                          onPressed: () =>
                              _selecionar((l) => const {'funciona', 'inconclusivo'}.contains(l.ultima?.estado))),
                      ActionChip(label: const Text('Todas'), onPressed: () => _selecionar((_) => true)),
                      ActionChip(label: const Text('Nenhuma'), onPressed: () => _selecionar((_) => false)),
                    ]),
                    const SizedBox(height: Tokens.e16),
                    _subtitulo('Enviar'),
                    // ligados sem seleção (avisam): depois de remover, o foco do comando fica no botão
                    Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, children: [
                      FilledButton.icon(
                        onPressed: _enviar,
                        icon: const Icon(Icons.send_rounded),
                        label: Text('Enviar para o Player (${_selecao.length})'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _removerSelecionadas,
                        icon: const Icon(Icons.remove_circle_outline),
                        label: Text('Remover do Gestor (${_selecao.length})'),
                      ),
                    ]),
                    const SizedBox(height: Tokens.e16),
                    _subtitulo('Exportar'),
                    // chips (e não um SegmentedButton): com o comando, cada opção mostra o seu realce de foco
                    Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, children: [
                      for (final (v, t) in const [
                        ('json', 'Accounts.json (sfvip player)'),
                        ('ini', 'Ficheiros .ini (Stalker Portal Player)'),
                      ])
                        ChoiceChip(
                            label: Text(t), selected: _formato == v, onSelected: (_) => setState(() => _formato = v)),
                    ]),
                    const SizedBox(height: Tokens.e12),
                    Align(
                      alignment: Alignment.centerLeft,
                      // ligado sem seleção (avisa): desligado não se alcançava com as setas
                      child: FilledButton.icon(
                        onPressed: _exportar,
                        icon: const Icon(Icons.download),
                        label: Text('Exportar ${_selecao.length} selecionadas'),
                      ),
                    ),
                  ]),
              // os resultados: o cabeçalho e os filtros aqui (numa caixa normal: dentro do grupo de
              // slivers de baixo, fora do ecrã, a procura direcional saltava os filtros)
              if (!vazio)
                _seccao(3, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CabecalhoSeccao(
                    titulo: 'Resultados',
                    subtitulo: '${_n(listas.length, 'lista', 'listas')} no Gestor · '
                        '${_n(_selecao.length, 'selecionada', 'selecionadas')} · OK marca ou desmarca',
                    icone: Icons.fact_check_outlined,
                    padding: const EdgeInsets.only(bottom: Tokens.e8),
                  ),
                  Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, children: [
                    for (final (i, (v, t)) in _filtros.indexed)
                      ChoiceChip(
                        focusNode: _focosFiltros[i],
                        label: Text('$t (${v == null ? listas.length : contagens[v] ?? 0})'),
                        selected: _filtroEstado == v,
                        onSelected: (_) => setState(() => _filtroEstado = v),
                      ),
                  ]),
                  if (visiveis.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: Tokens.e12),
                      child: Text('Nenhuma lista com este estado.', style: TextStyle(color: Tokens.texto2)),
                    ),
                ])),
            ]),
          ),
          if (visiveis.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Tokens.e16, 0, Tokens.e16, Tokens.e16),
              // o vidro por trás da parte visível da lista (sem construir as linhas todas)
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
                    itemBuilder: (_, i) => Material(type: MaterialType.transparency, child: _linha(visiveis[i], s)),
                  ),
                ),
              ),
            ),
        ]),
        );
      },
    );
  }

  Widget _linha(Lista l, ServicoVerificacao s) {
    final estado = estadoDe(l);
    final (cor, rotulo, icone) = (estado.cor, estado.rotulo, estado.icone);
    final passo = s.passos[l.id];
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
        secondary: Icon(icone, color: cor),
        title: Text(l.nomeMostrado, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(passo ?? (l.ultima == null ? rotulo : '$rotulo · ${l.ultima!.motivo}'),
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: passo == null ? Tokens.texto2 : cor)),
        controlAffinity: ListTileControlAffinity.leading,
        dense: true,
      ),
    );
  }
}
