import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../desporto/catalogo.dart';
import '../../desporto/hora_lisboa.dart';
import '../../desporto/nomes.dart';
import '../../desporto/preferencias_jogos.dart';
import '../../desporto/servico_jogos.dart';
import '../../idioma/idioma.dart';
import '../design/design.dart';
import 'linha_jogo.dart';
import 'tela_jogos.dart' show nomeDiaJogos, primeiroDia, ultimoDia;

/// Todos os jogos de uma competição, de todos os dias que a app cobre ([primeiroDia] a
/// [ultimoDia]), por dia e pela hora. Os dias que ainda não foram carregados pedem-se ao abrir
/// (um de cada vez, com a cache de cada fonte). Abre-se do ecrã «Competições».
class TelaJogosCompeticao extends StatefulWidget {
  const TelaJogosCompeticao({
    super.key,
    required this.competicaoId,
    required this.servico,
    required this.preferencias,
    required this.aoOndeVer,
    required this.aoVer,
    required this.aoDetalhe,
    this.agora,
  });

  final String competicaoId;
  final ServicoJogos servico;
  final PreferenciasJogos preferencias;

  /// O «Onde ver» de um canal, o «▶ Ver» e o detalhe de um jogo (os do ecrã «Jogos»).
  final ValueChanged<String> aoOndeVer;
  final ValueChanged<JogoComCanais> aoVer;
  final ValueChanged<JogoComCanais> aoDetalhe;

  /// Só para os testes: o relógio (o dia de hoje).
  final DateTime Function()? agora;

  @override
  State<TelaJogosCompeticao> createState() => _TelaJogosCompeticaoState();
}

class _TelaJogosCompeticaoState extends State<TelaJogosCompeticao> {
  late final DateTime _hoje = () {
    final a = (widget.agora ?? DateTime.now)().toLocal();
    return DateTime(a.year, a.month, a.day);
  }();

  late final _dias = [
    for (var d = primeiroDia; d <= ultimoDia; d++) DateTime(_hoje.year, _hoje.month, _hoje.day + d),
  ];

  bool _aCarregar = true;

  @override
  void initState() {
    super.initState();
    widget.servico.addListener(_mudou);
    widget.preferencias.addListener(_mudou);
    unawaited(widget.servico.carregarDias(_dias).whenComplete(() {
      if (mounted) setState(() => _aCarregar = false);
    }));
  }

  @override
  void dispose() {
    widget.servico.removeListener(_mudou);
    widget.preferencias.removeListener(_mudou);
    super.dispose();
  }

  void _mudou() {
    if (mounted) setState(() {});
  }

  /// Quantos dias depois de hoje é o dia (de Lisboa) do jogo.
  int _diaDe(JogoComCanais j) {
    final l = utcParaLisboa(j.jogo.inicio);
    // arredondado: nos dias da mudança da hora há 23 ou 25 horas entre duas meias-noites
    return (DateTime(l.year, l.month, l.day).difference(_hoje).inHours / 24).round();
  }

  @override
  Widget build(BuildContext context) {
    final comp = competicaoPorId(widget.competicaoId);
    final jogos = widget.servico
        .jogosDaCompeticao(widget.competicaoId, _dias, soComCanal: !widget.preferencias.mostrarSemCanal);
    final favoritas = widget.preferencias.equipasFavoritas;
    final itens = <Object>[];
    int? dia;
    for (final j in jogos) {
      final d = _diaDe(j);
      if (d != dia) itens.add(d);
      dia = d;
      itens.add(j);
    }
    final Widget corpo = jogos.isEmpty
        ? Center(
            child: _aCarregar
                ? const CircularProgressIndicator()
                : Padding(
                    padding: const EdgeInsets.all(Tokens.e24),
                    child: Text(tr('Nenhum jogo desta competição nestes dias'),
                        textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: Tokens.texto2)),
                  ),
          )
        : ListView.builder(
            padding: const EdgeInsets.fromLTRB(Tokens.e16, 0, Tokens.e16, Tokens.e16),
            itemCount: itens.length,
            itemBuilder: (_, i) => switch (itens[i]) {
              final int d => Padding(
                  padding: EdgeInsets.fromLTRB(Tokens.e4, i == 0 ? Tokens.e4 : Tokens.e16, Tokens.e4, Tokens.e8),
                  child: Text(nomeDiaJogos(_hoje, d),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Tokens.texto)),
                ),
              final JogoComCanais j => Padding(
                  padding: const EdgeInsets.only(bottom: Tokens.e8),
                  child: LinhaJogo(
                    key: ValueKey(j.jogo.id),
                    item: j,
                    mostrarCompeticao: false,
                    autofocus: identical(j, jogos.first),
                    aoOndeVer: widget.aoOndeVer,
                    aoVer: () => widget.aoVer(j),
                    aoDetalhe: () => widget.aoDetalhe(j),
                    destaque: favoritas.any((e) => mesmaEquipa(e, j.jogo.casa) || mesmaEquipa(e, j.jogo.fora)),
                  ),
                ),
              _ => const SizedBox.shrink(),
            },
          );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Tokens.e8, Tokens.e16, Tokens.e16, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (Navigator.of(context).canPop())
            Padding(
              padding: const EdgeInsets.only(right: Tokens.e4),
              child: IconButton(
                tooltip: tr('Voltar'),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
          Expanded(
            child: CabecalhoSeccao(
              icone: Icons.emoji_events_outlined,
              titulo: comp?.nome ?? widget.competicaoId,
              subtitulo: _aCarregar ? tr('A atualizar…') : tr('Todos os jogos, por dia e pela hora'),
            ),
          ),
        ]),
      ),
      Expanded(child: corpo),
    ]);
  }
}
