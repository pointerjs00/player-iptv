import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../desporto/fontes/fotmob.dart' show logoCompeticaoFotmob;
import '../../desporto/modelo.dart';
import '../../desporto/nomes.dart';
import '../../desporto/onde_ver.dart';
import '../../desporto/preferencias_jogos.dart';
import '../../desporto/servico_jogos.dart';
import '../../idioma/idioma.dart';
import '../design/design.dart';
import '../design/mensagens.dart';
import '../player/abrir_canal.dart';
import '../poupanca_dados.dart';
import 'folha_onde_ver.dart';
import 'linha_jogo.dart';
import 'painel_jogo.dart';

/// Abre as fontes no player (nos testes, um falso).
typedef AbrirFontesJogo = Future<void> Function(BuildContext context, List<FonteCanal> fontes,
    {ValueChanged<FonteCanal>? aoFuncionar});

Future<void> _abrirNoPlayer(BuildContext context, List<FonteCanal> fontes, {ValueChanged<FonteCanal>? aoFuncionar}) =>
    abrirFontes(context, fontes, aoFuncionar: aoFuncionar);

/// A partir desta largura, o detalhe do jogo com o foco fica numa coluna à direita.
const larguraColunaJogo = 900.0;

/// Os dias que se podem escolher, a partir de hoje (o guia de TV do FotMob dá 7 dias).
const primeiroDia = -1, ultimoDia = 6;

String nomeDesporto(Desporto d) => switch (d) {
      Desporto.futebol => tr('Futebol'),
      Desporto.tenis => tr('Ténis'),
      Desporto.basquetebol => tr('Basquetebol'),
    };

/// «Jogos»: os jogos das competições seguidas, por competição, os canais onde dão e, em cada canal,
/// as fontes de todas as listas (ver docs/2026-11-27-jogos-design.md §10).
class TelaJogos extends StatefulWidget {
  const TelaJogos({
    super.key,
    required this.servico,
    required this.fontes,
    required this.preferencias,
    this.abrir = _abrirNoPlayer,
    this.agora,
  });

  final ServicoJogos servico;
  final FontesDosCanais fontes;
  final PreferenciasJogos preferencias;
  final AbrirFontesJogo abrir;

  /// Só para os testes: o relógio (o dia de hoje).
  final DateTime Function()? agora;

  @override
  State<TelaJogos> createState() => _TelaJogosState();
}

class _TelaJogosState extends State<TelaJogos> {
  late final DateTime _hoje = () {
    final a = (widget.agora ?? DateTime.now)().toLocal();
    return DateTime(a.year, a.month, a.day);
  }();

  /// O dia escolhido, em dias a partir de hoje ([primeiroDia] a [ultimoDia]).
  int _dia = 0;
  Desporto? _desporto;
  Set<String> _competicoes = {};
  bool _soDireto = false;
  final _pesquisa = TextEditingController();

  /// O jogo da coluna à direita (o da linha com o foco).
  String? _escolhido;

  DateTime get _diaEscolhido => DateTime(_hoje.year, _hoje.month, _hoje.day + _dia);
  bool get _soComCanal => !widget.preferencias.mostrarSemCanal;

  /// Os filtros do botão «Filtros» que estão a mudar a lista.
  int get _filtrosAtivos => (_soComCanal ? 1 : 0) + (_desporto != null ? 1 : 0) + (_competicoes.isNotEmpty ? 1 : 0);

  @override
  void initState() {
    super.initState();
    widget.servico.addListener(_mudou);
    widget.fontes.addListener(_mudou);
    widget.preferencias.addListener(_mudou);
    _pesquisa.addListener(_mudou);
    // o ecrã vive na casca desde que a app abre: carrega-se uma vez (depois, o dia que se
    // escolher e «Atualizar»)
    if (!widget.servico.temDia(_diaEscolhido)) unawaited(widget.servico.carregar(_diaEscolhido));
    unawaited(widget.fontes.atualizar());
  }

  @override
  void dispose() {
    widget.servico.removeListener(_mudou);
    widget.fontes.removeListener(_mudou);
    widget.preferencias.removeListener(_mudou);
    _pesquisa.dispose();
    super.dispose();
  }

  void _mudou() {
    if (mounted) setState(() {});
  }

  void _escolherDia(int d) {
    d = d.clamp(primeiroDia, ultimoDia);
    if (d == _dia) return;
    setState(() {
      _dia = d;
      _escolhido = null;
    });
    unawaited(widget.servico.carregar(_diaEscolhido));
  }

  void _limparFiltros() => setState(() {
        _desporto = null;
        _competicoes = {};
        _soDireto = false;
        _pesquisa.clear();
        widget.preferencias.mostrarSemCanal = true;
      });

  Future<void> _atualizar() async {
    if (!await PoupancaDados.atual.autorizar(context, AcaoDados.jogos) || !mounted) return;
    await Future.wait([widget.servico.carregar(_diaEscolhido, forcar: true), widget.fontes.atualizar()]);
  }

  void _registar(FonteCanal f) {
    final c = f.canalTv;
    if (c != null) widget.preferencias.registarFuncionou(c, f.lista.id, f.canal.id, DateTime.now().toUtc());
  }

  Future<void> _abrir(List<FonteCanal> fontes) async {
    if (fontes.isEmpty) {
      mostrarMensagem(context, tr('Nenhuma das tuas listas tem os canais deste jogo'));
      return;
    }
    await widget.abrir(context, fontes, aoFuncionar: _registar);
  }

  Future<void> _ondeVer(String canalTv) async {
    final escolha =
        await mostrarOndeVer(context, canalTv: canalTv, fontes: widget.fontes, preferencias: widget.preferencias);
    if (escolha != null && mounted) await _abrir(escolha);
  }

  void _ver(JogoComCanais j) => unawaited(_abrir(fontesDoJogo(j, widget.fontes, widget.preferencias)));

  void _detalhe(JogoComCanais j) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (ctx) => Scaffold(
        appBar: AppBar(title: Text('${j.jogo.casa} – ${j.jogo.fora}')),
        body: ListView(padding: const EdgeInsets.all(Tokens.e16), children: [
          PainelJogo(
            item: j,
            fontes: widget.fontes,
            focavel: true,
            aoOndeVer: _ondeVer,
            aoVer: () => _ver(j),
          ),
        ]),
      ),
    ));
  }

  /// «Hoje, 27 nov», «Seg, 30 nov».
  String _nomeDia(int d) {
    final dia = DateTime(_hoje.year, _hoje.month, _hoje.day + d);
    final nome = switch (d) {
      -1 => tr('Ontem'),
      0 => tr('Hoje'),
      1 => tr('Amanhã'),
      _ => [tr('Seg'), tr('Ter'), tr('Qua'), tr('Qui'), tr('Sex'), tr('Sáb'), tr('Dom')][dia.weekday - 1],
    };
    final mes = [
      tr('jan'), tr('fev'), tr('mar'), tr('abr'), tr('mai'), tr('jun'),
      tr('jul'), tr('ago'), tr('set'), tr('out'), tr('nov'), tr('dez'),
    ][dia.month - 1];
    return '$nome, ${dia.day} $mes';
  }

  String? _estado() {
    final e = widget.servico.estado;
    final partes = <String>[
      for (final f in {for (final f in e.falhas) nomeFonte(f)}) tr('{0} indisponível', [f]),
    ];
    final v = e.velhoDesde;
    if (v != null) {
      final m = DateTime.now().toUtc().difference(v).inMinutes;
      final quanto = m < 60 ? tr('{0} min', [m < 1 ? 1 : m]) : tr('{0} h', [m ~/ 60]);
      partes.insert(0, tr('Sem rede: a mostrar os dados de há {0}', [quanto]));
    }
    return partes.isEmpty ? null : partes.join(' · ');
  }

  /// Os filtros que não cabem na fila: só com canal, o desporto e as competições do dia.
  Future<void> _abrirFiltros(List<JogoComCanais> doDia) => showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, mudar) {
          void aplicar(VoidCallback f) {
            setState(f);
            mudar(() {});
          }

          final desportos = {for (final j in doDia) j.jogo.desporto};
          final grupos = agruparPorCompeticao(doDia);
          Widget titulo(String t) => Padding(
                padding: const EdgeInsets.only(top: Tokens.e16, bottom: Tokens.e8),
                child: Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              );
          return Dialog(
            insetPadding: const EdgeInsets.all(Tokens.e16),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.sizeOf(ctx).height * .85),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Tokens.e16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  CabecalhoSeccao(icone: Icons.tune_rounded, titulo: tr('Filtros')),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    autofocus: true,
                    title: Text(tr('Só jogos com canal')),
                    subtitle: Text(tr('Esconde os jogos que ainda não têm canal anunciado.'),
                        style: const TextStyle(fontSize: 13, color: Tokens.texto2)),
                    value: _soComCanal,
                    onChanged: (v) => aplicar(() => widget.preferencias.mostrarSemCanal = !v),
                  ),
                  if (desportos.length > 1) ...[
                    titulo(tr('Desporto')),
                    Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, children: [
                      ChoiceChip(
                          label: Text(tr('Todos')), selected: _desporto == null, onSelected: (_) => aplicar(() => _desporto = null)),
                      for (final d in Desporto.values)
                        if (desportos.contains(d))
                          ChoiceChip(
                              label: Text(nomeDesporto(d)), selected: _desporto == d, onSelected: (_) => aplicar(() => _desporto = d)),
                    ]),
                  ],
                  if (grupos.isNotEmpty) ...[
                    titulo(tr('Competições')),
                    Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, children: [
                      for (final g in grupos)
                        FilterChip(
                          label: Text('${g.competicao.nome} (${g.jogos.length})'),
                          selected: _competicoes.contains(g.competicao.id),
                          onSelected: (sim) => aplicar(() => _competicoes = sim
                              ? {..._competicoes, g.competicao.id}
                              : ({..._competicoes}..remove(g.competicao.id))),
                        ),
                    ]),
                  ],
                  const SizedBox(height: Tokens.e16),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(
                      onPressed: () => aplicar(() {
                        _desporto = null;
                        _competicoes = {};
                        widget.preferencias.mostrarSemCanal = true;
                      }),
                      child: Text(tr('Limpar filtros')),
                    ),
                    const SizedBox(width: Tokens.e8),
                    FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(tr('Fechar'))),
                  ]),
                ]),
              ),
            ),
          );
        }),
      );

  /// A fila de cima: «Filtros», «Ao vivo» e o dia com as setas (como no Sofascore).
  Widget _fila(List<JogoComCanais> doDia) {
    final n = _filtrosAtivos;
    final aoVivo = doDia.where((j) => j.jogo.aDecorrer).length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        FilterChip(
          avatar: const Icon(Icons.tune_rounded, size: 18),
          showCheckmark: false,
          label: Text(n == 0 ? tr('Filtros') : tr('Filtros ({0})', [n])),
          selected: n > 0,
          onSelected: (_) => unawaited(_abrirFiltros(doDia)),
        ),
        const SizedBox(width: Tokens.e8),
        FilterChip(
          avatar: Icon(Icons.circle, size: 10, color: _soDireto ? null : Tokens.mau),
          showCheckmark: false,
          label: Text(aoVivo == 0 ? tr('Ao vivo') : tr('Ao vivo ({0})', [aoVivo])),
          selected: _soDireto,
          onSelected: (_) => setState(() => _soDireto = !_soDireto),
        ),
        const SizedBox(width: Tokens.e12),
        IconButton(
          tooltip: tr('Dia anterior'),
          onPressed: _dia > primeiroDia ? () => _escolherDia(_dia - 1) : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 120),
          child: Text(_nomeDia(_dia),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
        IconButton(
          tooltip: tr('Dia seguinte'),
          onPressed: _dia < ultimoDia ? () => _escolherDia(_dia + 1) : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        if (_dia != 0) ...[
          const SizedBox(width: Tokens.e4),
          ActionChip(
            avatar: const Icon(Icons.today_rounded, size: 18),
            label: Text(tr('Hoje')),
            onPressed: () => _escolherDia(0),
          ),
        ],
      ]),
    );
  }

  Widget _vazio(String texto, {String? acao, VoidCallback? aoAcao}) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Tokens.e24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.sports_soccer_rounded, size: 40, color: Tokens.texto2),
            const SizedBox(height: Tokens.e12),
            Text(texto, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: Tokens.texto2)),
            if (acao != null) ...[
              const SizedBox(height: Tokens.e12),
              OutlinedButton(onPressed: aoAcao, child: Text(acao)),
            ],
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.servico;
    final dia = _diaEscolhido;
    final doDia = s.jogos(FiltroJogos(dia, soComCanal: false));
    final pesquisa = _pesquisa.text.trim();
    final jogos = s.jogos(FiltroJogos(dia,
        desporto: _desporto,
        competicoes: _competicoes,
        soDireto: _soDireto,
        soComCanal: _soComCanal,
        equipa: pesquisa));
    final largo = MediaQuery.sizeOf(context).width >= larguraColunaJogo;
    final favoritas = widget.preferencias.equipasFavoritas;
    final estado = _estado();
    final aCarregar = s.estado.carga == Carga.aCarregar;

    Widget corpo;
    if (!s.temDia(dia)) {
      corpo = aCarregar ? const Center(child: CircularProgressIndicator()) : _vazio(tr('Sem dados dos jogos deste dia'));
    } else if (doDia.isEmpty) {
      corpo = _vazio(tr('Nenhum jogo das tuas competições neste dia'));
    } else if (jogos.isEmpty) {
      if (pesquisa.isNotEmpty) {
        corpo = _vazio(tr('Nenhum jogo de «{0}» neste dia', [pesquisa]), acao: tr('Limpar a pesquisa'), aoAcao: _pesquisa.clear);
      } else if (_soComCanal && _desporto == null && _competicoes.isEmpty && !_soDireto) {
        corpo = _vazio(tr('Ainda sem canal anunciado'),
            acao: tr('Mostrar jogos sem canal'), aoAcao: () => widget.preferencias.mostrarSemCanal = true);
      } else {
        corpo = _vazio(tr('Nenhum jogo com estes filtros'), acao: tr('Limpar filtros'), aoAcao: _limparFiltros);
      }
    } else {
      final grupos = agruparPorCompeticao(jogos);
      final itens = <Object>[for (final g in grupos) ...[g, ...g.jogos]];
      final emOrdem = [for (final g in grupos) ...g.jogos];
      final escolhido = emOrdem.firstWhere((j) => j.jogo.id == _escolhido, orElse: () => emOrdem.first);
      final lista = ListView.builder(
        padding: const EdgeInsets.fromLTRB(Tokens.e16, 0, Tokens.e16, Tokens.e16),
        itemCount: itens.length,
        itemBuilder: (_, i) => switch (itens[i]) {
          final GrupoJogos g => CabecalhoCompeticao(g, primeiro: i == 0),
          final JogoComCanais j => Padding(
              padding: const EdgeInsets.only(bottom: Tokens.e8),
              child: LinhaJogo(
                key: ValueKey(j.jogo.id),
                item: j,
                mostrarCompeticao: false,
                aoOndeVer: _ondeVer,
                aoVer: () => _ver(j),
                aoDetalhe: () => _detalhe(j),
                aoFocar: largo && _escolhido != j.jogo.id ? () => setState(() => _escolhido = j.jogo.id) : null,
                destaque: favoritas.any((e) => mesmaEquipa(e, j.jogo.casa) || mesmaEquipa(e, j.jogo.fora)),
              ),
            ),
          _ => const SizedBox.shrink(),
        },
      );
      corpo = !largo
          ? lista
          : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: lista),
              SizedBox(
                width: 340,
                child: SuperficieVidro(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(Tokens.e16),
                    child: PainelJogo(
                      item: escolhido,
                      fontes: widget.fontes,
                      aoOndeVer: _ondeVer,
                      aoVer: () => _ver(escolhido),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Tokens.e16),
            ]);
    }

    final campoPesquisa = TextField(
      controller: _pesquisa,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search_rounded),
        hintText: tr('Pesquisar equipa'),
        suffixIcon: pesquisa.isEmpty
            ? null
            : IconButton(tooltip: tr('Limpar a pesquisa'), onPressed: _pesquisa.clear, icon: const Icon(Icons.close_rounded)),
      ),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e16, Tokens.e16, 0),
        child: CabecalhoSeccao(
          icone: Icons.sports_soccer_rounded,
          titulo: tr('Jogos'),
          subtitulo: estado ?? (aCarregar ? tr('A atualizar…') : tr('Onde dá o jogo e ver com um toque')),
          acoes: [
            if (largo) SizedBox(width: 320, child: campoPesquisa),
            IconButton(
              tooltip: tr('Atualizar'),
              onPressed: aCarregar ? null : () => unawaited(_atualizar()),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
      if (!largo)
        Padding(padding: const EdgeInsets.fromLTRB(Tokens.e16, 0, Tokens.e16, Tokens.e8), child: campoPesquisa),
      Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.e16, 0, Tokens.e16, Tokens.e8),
        child: _fila(doDia),
      ),
      Expanded(child: corpo),
    ]);
  }
}

/// O título de um bloco de jogos: o logótipo, o nome da competição e quantos jogos tem.
class CabecalhoCompeticao extends StatelessWidget {
  const CabecalhoCompeticao(this.grupo, {super.key, this.primeiro = false});
  final GrupoJogos grupo;
  final bool primeiro;

  @override
  Widget build(BuildContext context) {
    final c = grupo.competicao;
    final logo = c.fotmob == null ? null : logoCompeticaoFotmob(c.fotmob!);
    const semLogo = Icon(Icons.emoji_events_outlined, size: 20, color: Tokens.texto2);
    return Padding(
      padding: EdgeInsets.fromLTRB(Tokens.e4, primeiro ? Tokens.e4 : Tokens.e16, Tokens.e4, Tokens.e8),
      child: Row(children: [
        SizedBox(
          width: 24,
          height: 24,
          child: logo == null ? semLogo : Image.network(logo, width: 24, height: 24, errorBuilder: (_, _, _) => semLogo),
        ),
        const SizedBox(width: Tokens.e8),
        Expanded(
          child: Text(c.nome,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Tokens.texto)),
        ),
        Text(grupo.jogos.length == 1 ? tr('1 jogo') : tr('{0} jogos', [grupo.jogos.length]),
            style: const TextStyle(fontSize: 12.5, color: Tokens.texto2)),
      ]),
    );
  }
}
