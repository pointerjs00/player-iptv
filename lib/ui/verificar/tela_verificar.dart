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
import '../realce_foco.dart';
import '../tema.dart';
import 'dialogos_gestor.dart';

/// Separador "Gestor": a área de trabalho com as suas próprias listas ([AreaGestor]). Entram por
/// ficheiros/colar, pela pesquisa do stbstalker ou "Importar do Player"; verificam-se, selecionam-se
/// e exportam-se (Accounts.json ou .ini) ou enviam-se para o Player.
class TelaVerificar extends StatefulWidget {
  const TelaVerificar({super.key, required this.biblioteca, required this.area, required this.servico,
      this.baseStb = stbBase});

  /// As listas do Player (recebem os envios) e os canais de teste.
  final Biblioteca biblioteca;
  final AreaGestor area;

  /// Grava os resultados no Gestor.
  final ServicoVerificacao servico;

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

  @override
  void dispose() {
    _focoVerificarTodas.dispose();
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

  Widget _secaoStb() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const CabecalhoSeccao(
        titulo: 'Listas do stbstalker',
        subtitulo: 'Junta as listas publicadas no blog entre duas datas.',
        icone: Icons.travel_explore,
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

  /// Uma secção do ecrã num painel de vidro (entra em cascata).
  Widget _seccao(int i, Widget filho) => Padding(
        padding: const EdgeInsets.only(bottom: Tokens.e16),
        child: entradaEmCascata(i, SuperficieVidro(padding: const EdgeInsets.all(Tokens.e16 + 4), child: filho)),
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
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_b, _g, widget.servico]),
      builder: (context, _) {
        final s = widget.servico;
        final listas = _g.listas;
        _selecao.removeWhere((id) => _g.porId(id) == null);
        // CustomScrollView: as secções em cima e as linhas das listas preguiçosas (SliverList.builder),
        // para não construir centenas de linhas em cada passo da verificação
        return CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e16, Tokens.e16, 0),
            sliver: SliverList.list(children: [
              _seccao(0, _secaoStb()),
              _seccao(1, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const CabecalhoSeccao(
                    titulo: 'Listas no Gestor',
                    subtitulo: 'Ficheiros, linhas coladas ou as listas que já estão no Player.',
                    icone: Icons.inventory_2_outlined,
                  ),
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
                  if (listas.isEmpty) ...[
                    const SizedBox(height: Tokens.e12),
                    const Text('O Gestor está vazio: adicione listas, pesquise no stbstalker ou importe as do Player.',
                        style: TextStyle(color: Tokens.texto2)),
                  ],
              ])),
              _seccao(2, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const CabecalhoSeccao(
                    titulo: 'Canais a testar',
                    subtitulo: 'A lista funciona se um deles abrir.',
                    icone: Icons.live_tv_outlined,
                  ),
                  Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, children: [
                    for (final p in perfisCanais.values)
                      FilterChip(
                        label: Text(p.nome),
                        selected: _b.canaisTeste.contains(p.id),
                        onSelected: s.ocupado
                            ? null
                            : (on) {
                                final novo = [for (final id in perfisCanais.keys)
                                  if (id == p.id ? on : _b.canaisTeste.contains(id)) id];
                                if (novo.isEmpty) return _aviso('Escolha pelo menos um canal.');
                                _b.definirCanaisTeste(novo);
                              },
                      ),
                  ]),
                  const SizedBox(height: Tokens.e16),
                  Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    // ligados enquanto verifica (desligar um botão com o foco deixa o comando sem foco)
                    FilledButton.icon(
                      focusNode: _focoVerificarTodas,
                      onPressed: listas.isEmpty
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
                              if (!s.ocupado) s.verificarVarias([for (final l in listas) if (_selecao.contains(l.id)) l]);
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
                    if (s.ocupado)
                      Text('${s.feitas} de ${s.total} verificadas', style: const TextStyle(color: Tokens.texto2)),
                  ]),
                  if (s.ocupado) ...[
                    const SizedBox(height: Tokens.e12),
                    LinearProgressIndicator(value: s.total == 0 ? null : s.feitas / s.total, minHeight: 6),
                  ],
              ])),
              _seccao(3, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const CabecalhoSeccao(
                    titulo: 'Selecionadas',
                    subtitulo: 'Envie-as para o Player, tire-as do Gestor ou exporte-as.',
                    icone: Icons.checklist_rtl,
                  ),
                  Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, children: [
                    ActionChip(label: const Text('Funcionam'), onPressed: () => _selecionar((l) => l.ultima?.estado == 'funciona')),
                    ActionChip(label: const Text('Funcionam + INC'),
                        onPressed: () => _selecionar((l) => const {'funciona', 'inconclusivo'}.contains(l.ultima?.estado))),
                    ActionChip(label: const Text('Todas'), onPressed: () => _selecionar((_) => true)),
                    ActionChip(label: const Text('Nenhuma'), onPressed: () => _selecionar((_) => false)),
                  ]),
                  const SizedBox(height: Tokens.e16),
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
                  const SizedBox(height: Tokens.e24),
                  const Text('Exportar', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: Tokens.e8),
                  // chips (e não um SegmentedButton): com o comando, cada opção mostra o seu realce de foco
                  Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, children: [
                    for (final (v, t) in const [
                      ('json', 'Accounts.json (sfvip player)'),
                      ('ini', 'Ficheiros .ini (Stalker Portal Player)'),
                    ])
                      ChoiceChip(label: Text(t), selected: _formato == v, onSelected: (_) => setState(() => _formato = v)),
                  ]),
                  const SizedBox(height: Tokens.e16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: _selecao.isEmpty ? null : _exportar,
                      icon: const Icon(Icons.download),
                      label: Text('Exportar ${_selecao.length} selecionadas'),
                    ),
                  ),
              ])),
            ]),
          ),
          if (listas.isNotEmpty)
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
                  sliver: SliverMainAxisGroup(slivers: [
                    SliverToBoxAdapter(
                      child: CabecalhoSeccao(
                        titulo: 'Listas no Gestor',
                        subtitulo: '${listas.length} no Gestor · ${_selecao.length} selecionadas',
                        padding: const EdgeInsets.fromLTRB(Tokens.e12, Tokens.e8, Tokens.e12, Tokens.e8),
                      ),
                    ),
                    SliverList.builder(
                      itemCount: listas.length,
                      // o "ink" (foco, toque) pinta-se aqui, por cima do vidro
                      itemBuilder: (_, i) => Material(type: MaterialType.transparency, child: _linha(listas[i], s)),
                    ),
                  ]),
                ),
              ),
            ),
        ]);
      },
    );
  }

  Widget _linha(Lista l, ServicoVerificacao s) {
    final (cor, rotulo, icone) = visualEstado(l.ultima?.estado);
    final passo = s.passos[l.id];
    return RealceFoco(
      construir: (_, aoMudarFoco) => CheckboxListTile(
        onFocusChange: aoMudarFoco,
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
