import 'package:material_ui/material_ui.dart';

import '../../desporto/catalogo.dart';
import '../../desporto/modelo.dart';
import '../../desporto/preferencias_jogos.dart';
import '../../idioma/idioma.dart';
import '../design/design.dart';
import '../design/mensagens.dart';
import '../jogos/folha_onde_ver.dart' show nomeQualidade;
import 'linha_opcao.dart';

String _tipo(TipoCompeticao t) => switch (t) {
      TipoCompeticao.liga => tr('Ligas'),
      TipoCompeticao.taca => tr('Taças'),
      TipoCompeticao.europeia => tr('Competições europeias'),
      TipoCompeticao.selecoes => tr('Seleções'),
      TipoCompeticao.circuito => tr('Circuitos de ténis'),
    };

/// Definições › Jogos: as competições seguidas, as equipas favoritas, a qualidade preferida,
/// mostrar os jogos sem canal e limpar as associações manuais de canais.
class SecaoJogos extends StatefulWidget {
  const SecaoJogos({super.key, required this.preferencias});
  final PreferenciasJogos preferencias;

  @override
  State<SecaoJogos> createState() => _SecaoJogosState();
}

class _SecaoJogosState extends State<SecaoJogos> {
  final _equipa = TextEditingController();

  PreferenciasJogos get _p => widget.preferencias;

  @override
  void initState() {
    super.initState();
    _p.addListener(_mudou);
  }

  @override
  void dispose() {
    _p.removeListener(_mudou);
    _equipa.dispose();
    super.dispose();
  }

  void _mudou() {
    if (mounted) setState(() {});
  }

  void _adicionarEquipa() {
    final t = _equipa.text.trim();
    if (t.isEmpty) return;
    if (!_p.equipasFavoritas.contains(t)) _p.equipasFavoritas = [..._p.equipasFavoritas, t];
    _equipa.clear();
    mostrarMensagem(context, tr('Guardado'));
  }

  @override
  Widget build(BuildContext context) {
    final seguidas = _p.competicoes;
    final porTipo = <TipoCompeticao, List<Competicao>>{};
    for (final c in catalogoCompeticoes) {
      porTipo.putIfAbsent(c.tipo, () => []).add(c);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SwitchListTile(
        contentPadding: paddingLinhaOpcao,
        title: Text(tr('Mostrar jogos sem canal'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        subtitle: Text(tr('Também os jogos que ainda não têm canal anunciado.'),
            style: const TextStyle(fontSize: 13.5, color: Tokens.texto2)),
        value: _p.mostrarSemCanal,
        onChanged: (v) => _p.mostrarSemCanal = v,
      ),
      const SeparadorOpcao(),
      LinhaOpcao(
        titulo: tr('Qualidade preferida'),
        explicacao: tr('Entre fontes igualmente fiáveis, experimenta primeiro esta.'),
        empilhar: true,
        controlo: Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, children: [
          for (final q in Qualidade.values)
            ChoiceChip(label: Text(nomeQualidade(q)), selected: _p.qualidade == q, onSelected: (_) => _p.qualidade = q),
        ]),
      ),
      const SeparadorOpcao(),
      LinhaOpcao(
        titulo: tr('Equipas favoritas'),
        explicacao: tr('Ficam em destaque nos jogos.'),
        empilhar: true,
        controlo: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _equipa,
                decoration: InputDecoration(hintText: tr('Nome da equipa')),
                onSubmitted: (_) => _adicionarEquipa(),
              ),
            ),
            const SizedBox(width: Tokens.e8),
            OutlinedButton(onPressed: _adicionarEquipa, child: Text(tr('Adicionar'))),
          ]),
          if (_p.equipasFavoritas.isNotEmpty) ...[
            const SizedBox(height: Tokens.e8),
            Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, children: [
              for (final e in _p.equipasFavoritas)
                InputChip(
                  label: Text(e),
                  onDeleted: () => _p.equipasFavoritas = [..._p.equipasFavoritas]..remove(e),
                  deleteButtonTooltipMessage: tr('Tirar'),
                ),
            ]),
          ],
        ]),
      ),
      const SeparadorOpcao(),
      for (final MapEntry(key: tipo, value: comps) in porTipo.entries) ...[
        LinhaOpcao(
          titulo: _tipo(tipo),
          explicacao: tr('As competições que aparecem nos Jogos.'),
          empilhar: true,
          controlo: Wrap(spacing: Tokens.e8, runSpacing: Tokens.e8, children: [
            for (final c in comps)
              FilterChip(label: Text(c.nome), selected: seguidas.contains(c.id), onSelected: (_) => _p.alternarCompeticao(c.id)),
          ]),
        ),
        const SeparadorOpcao(),
      ],
      LinhaOpcao(
        titulo: tr('Associações de canais'),
        explicacao: tr('Os canais que marcou à mão no «Onde ver» («Este não é o canal»).'),
        controlo: OutlinedButton(
          onPressed: _p.temAssociacoes
              ? () {
                  _p.limparAssociacoes();
                  mostrarMensagem(context, tr('Associações apagadas'));
                }
              : null,
          child: Text(tr('Limpar')),
        ),
      ),
    ]);
  }
}
