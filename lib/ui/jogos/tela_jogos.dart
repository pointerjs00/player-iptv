import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../desporto/catalogo.dart';
import '../../desporto/modelo.dart';
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

/// «Jogos»: os jogos das competições seguidas, os canais onde dão e, em cada canal, as fontes de
/// todas as listas (ver docs/2026-11-27-jogos-design.md §10).
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

  /// O dia escolhido, em dias a partir de hoje (-1 a +5).
  int _dia = 0;
  Desporto? _desporto;
  String? _competicao;
  bool _soDireto = false;

  /// O jogo da coluna à direita (o da linha com o foco).
  String? _escolhido;

  DateTime get _diaEscolhido => DateTime(_hoje.year, _hoje.month, _hoje.day + _dia);

  @override
  void initState() {
    super.initState();
    widget.servico.addListener(_mudou);
    widget.fontes.addListener(_mudou);
    widget.preferencias.addListener(_mudou);
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
    super.dispose();
  }

  void _mudou() {
    if (mounted) setState(() {});
  }

  void _escolherDia(int d) {
    if (d == _dia) return;
    setState(() {
      _dia = d;
      _competicao = null;
      _escolhido = null;
    });
    unawaited(widget.servico.carregar(_diaEscolhido));
  }

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

  String _nomeDia(int d) {
    if (d == -1) return tr('Ontem');
    if (d == 0) return tr('Hoje');
    if (d == 1) return tr('Amanhã');
    final dia = DateTime(_hoje.year, _hoje.month, _hoje.day + d);
    final semana = [tr('Seg'), tr('Ter'), tr('Qua'), tr('Qui'), tr('Sex'), tr('Sáb'), tr('Dom')][dia.weekday - 1];
    return '$semana ${dia.day}';
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

  Widget _chip(String rotulo, bool escolhido, VoidCallback aoEscolher, {IconData? icone}) => Padding(
        padding: const EdgeInsets.only(right: Tokens.e8),
        child: FilterChip(
          avatar: icone == null ? null : Icon(icone, size: 16),
          showCheckmark: false,
          label: Text(rotulo),
          selected: escolhido,
          onSelected: (_) => aoEscolher(),
        ),
      );

  Widget _filtros(List<JogoComCanais> doDia) {
    final desportos = {for (final j in doDia) j.jogo.desporto};
    final competicoes = <String>{for (final j in doDia) j.jogo.competicaoId};
    final mostrarSem = widget.preferencias.mostrarSemCanal;
    return SizedBox(
      height: 48,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (var d = -1; d <= 5; d++) _chip(_nomeDia(d), d == _dia, () => _escolherDia(d)),
        const SizedBox(width: Tokens.e8),
        _chip(tr('Em direto'), _soDireto, () => setState(() => _soDireto = !_soDireto), icone: Icons.circle),
        _chip(tr('Mostrar jogos sem canal'), mostrarSem, () => widget.preferencias.mostrarSemCanal = !mostrarSem),
        if (desportos.length > 1)
          for (final d in Desporto.values)
            if (desportos.contains(d))
              _chip(switch (d) { Desporto.futebol => tr('Futebol'), Desporto.tenis => tr('Ténis'), Desporto.basquetebol => tr('Basquetebol') },
                  _desporto == d, () => setState(() => _desporto = _desporto == d ? null : d)),
        for (final id in competicoes)
          _chip(competicaoPorId(id)?.nome ?? id, _competicao == id,
              () => setState(() => _competicao = _competicao == id ? null : id)),
      ]),
    );
  }

  Widget _vazio(String texto, {String? acao, VoidCallback? aoAcao}) => Center(
        child: Padding(
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
    final jogos = s.jogos(FiltroJogos(dia,
        desporto: _desporto,
        competicao: _competicao,
        soDireto: _soDireto,
        soComCanal: !widget.preferencias.mostrarSemCanal));
    final largo = MediaQuery.sizeOf(context).width >= larguraColunaJogo;
    final estado = _estado();
    final aCarregar = s.estado.carga == Carga.aCarregar;

    Widget corpo;
    if (!s.temDia(dia)) {
      corpo = aCarregar ? const Center(child: CircularProgressIndicator()) : _vazio(tr('Sem dados dos jogos deste dia'));
    } else if (doDia.isEmpty) {
      corpo = _vazio(tr('Nenhum jogo das tuas competições neste dia'));
    } else if (jogos.isEmpty) {
      final soFaltaCanal = !widget.preferencias.mostrarSemCanal && _competicao == null && !_soDireto;
      corpo = soFaltaCanal
          ? _vazio(tr('Ainda sem canal anunciado'),
              acao: tr('Mostrar jogos sem canal'), aoAcao: () => widget.preferencias.mostrarSemCanal = true)
          : _vazio(tr('Nenhum jogo com estes filtros'));
    } else {
      final escolhido = jogos.firstWhere((j) => j.jogo.id == _escolhido, orElse: () => jogos.first);
      final lista = ListView.separated(
        padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e4, Tokens.e16, Tokens.e16),
        itemCount: jogos.length,
        separatorBuilder: (_, _) => const SizedBox(height: Tokens.e8),
        itemBuilder: (_, i) {
          final j = jogos[i];
          return LinhaJogo(
            key: ValueKey(j.jogo.id),
            item: j,
            aoOndeVer: _ondeVer,
            aoVer: () => _ver(j),
            aoDetalhe: () => _detalhe(j),
            aoFocar: largo && _escolhido != j.jogo.id ? () => setState(() => _escolhido = j.jogo.id) : null,
          );
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

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e16, Tokens.e16, 0),
        child: CabecalhoSeccao(
          icone: Icons.sports_soccer_rounded,
          titulo: tr('Jogos'),
          subtitulo: estado ?? (aCarregar ? tr('A atualizar…') : tr('Onde dá o jogo e ver com um toque')),
          acoes: [
            IconButton(
              tooltip: tr('Atualizar'),
              onPressed: aCarregar ? null : () => unawaited(_atualizar()),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.e16, 0, 0, Tokens.e8),
        child: _filtros(doDia),
      ),
      Expanded(child: corpo),
    ]);
  }
}
