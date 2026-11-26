import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/estatisticas.dart';
import '../../idioma/idioma.dart';
import '../design/design.dart';
import 'cartao_semana.dart';

/// As Estatísticas (do cartão «A tua semana»): os totais, os canais mais vistos, as listas mais
/// usadas, o tempo por dia da semana e por hora do dia, nos últimos 30 dias. Só leitura: ↑ ↓
/// (ou o rato e o toque) deslizam; Voltar fecha.
class TelaEstatisticas extends StatefulWidget {
  const TelaEstatisticas({super.key, required this.estatisticas, this.agora});

  final Estatisticas estatisticas;

  /// Só para os testes: o relógio.
  final DateTime Function()? agora;

  @override
  State<TelaEstatisticas> createState() => _TelaEstatisticasState();
}

class _TelaEstatisticasState extends State<TelaEstatisticas> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// ↑ ↓ (comando, teclado): deslizam a página (não há nada focável dentro dela).
  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent || !_scroll.hasClients) return KeyEventResult.ignored;
    final passo = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowDown => 240.0,
      LogicalKeyboardKey.arrowUp => -240.0,
      LogicalKeyboardKey.pageDown => 600.0,
      LogicalKeyboardKey.pageUp => -600.0,
      _ => 0.0,
    };
    if (passo == 0) return KeyEventResult.ignored;
    final p = _scroll.position;
    _scroll.animateTo((p.pixels + passo).clamp(0.0, p.maxScrollExtent),
        duration: duracaoAnimada(context, Tokens.duracaoMedia), curve: Tokens.curva);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.estatisticas;
    final agora = (widget.agora ?? DateTime.now)();
    final tv = ecraTv(context);
    final semana = e.semana(agora);
    final mais = e.maisVistos(agora);
    final listas = e.listasMaisUsadas(agora);
    final total30 = mais.isEmpty ? Duration.zero : e.maisVistos(agora, n: 1 << 20).fold(Duration.zero, (a, c) => a + c.tempo);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Estatísticas'))),
      body: Focus(
        autofocus: true,
        onKeyEvent: _tecla,
        child: e.vazio
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(Tokens.e32),
                  child: Text(
                      tr('Ainda não há tempo de visualização. As estatísticas aparecem aqui depois de veres canais.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Tokens.texto2)),
                ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(Tokens.e24, Tokens.e8, Tokens.e24, Tokens.e32),
                    children: [
                      Wrap(spacing: Tokens.e16, runSpacing: Tokens.e16, children: [
                        _Numero(tr('Esta semana'), textoDuracao(semana.total), comparacaoSemana(semana), tv: tv),
                        _Numero(tr('Últimos 30 dias'), textoDuracao(total30), tr('{0} canais diferentes', [mais.length]),
                            tv: tv),
                        _Numero(tr('Dias seguidos'), '${e.diasSeguidos(agora)}',
                            tr('com pelo menos {0} vistos', [textoDuracao(Estatisticas.minimoDia)]), tv: tv),
                      ]),
                      _Seccao(tr('Canais mais vistos · 30 dias'), [
                        for (final (i, c) in mais.indexed)
                          _Linha(posicao: i + 1, nome: c.nome, detalhe: c.lista, tempo: c.tempo, maximo: mais.first.tempo),
                      ]),
                      if (listas.isNotEmpty)
                        _Seccao(tr('Listas mais usadas · 30 dias'), [
                          for (final (i, l) in listas.take(5).indexed)
                            _Linha(posicao: i + 1, nome: l.$1, tempo: l.$2, maximo: listas.first.$2),
                        ]),
                      _Seccao(tr('Por dia da semana · 30 dias'),
                          [_Colunas(valores: e.porDiaDaSemana(agora), rotulos: diasAbreviados(), altura: 120)]),
                      _Seccao(tr('Por hora do dia · 30 dias'), [
                        _Colunas(
                            valores: e.porHora(agora),
                            rotulos: [for (var h = 0; h < 24; h++) h % 3 == 0 ? '$h h' : ''],
                            altura: 120),
                      ]),
                      Padding(
                        padding: const EdgeInsets.only(top: Tokens.e16),
                        child: Text(tr('Os dados ficam só neste aparelho. Desligam-se ou apagam-se em Definições › Imagem e som.'),
                            style: const TextStyle(color: Tokens.texto2, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// Um número grande com o rótulo por cima e uma nota por baixo.
class _Numero extends StatelessWidget {
  const _Numero(this.rotulo, this.valor, this.nota, {required this.tv});
  final String rotulo, valor, nota;
  final bool tv;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: tv ? 300 : 280,
        child: SuperficieVidro(
          padding: const EdgeInsets.all(Tokens.e16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rotulo.toUpperCase(),
                style: const TextStyle(color: Tokens.texto2, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
            const SizedBox(height: Tokens.e4),
            Text(valor,
                style: TextStyle(fontFamily: Tokens.letraTitulos, fontSize: tv ? 38 : 32, fontWeight: FontWeight.w700)),
            Text(nota, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Tokens.texto2, fontSize: 13)),
          ]),
        ),
      );
}

class _Seccao extends StatelessWidget {
  const _Seccao(this.titulo, this.filhos);
  final String titulo;
  final List<Widget> filhos;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Tokens.e24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(titulo,
              style: const TextStyle(fontFamily: Tokens.letraTitulos, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: Tokens.e12),
          SuperficieVidro(
            padding: const EdgeInsets.all(Tokens.e16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: filhos),
          ),
        ]),
      );
}

/// Uma linha do top: posição, nome (e a lista), uma barra do tempo e o tempo.
class _Linha extends StatelessWidget {
  const _Linha({required this.posicao, required this.nome, required this.tempo, required this.maximo, this.detalhe});
  final int posicao;
  final String nome;
  final String? detalhe;
  final Duration tempo, maximo;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(
            width: 32,
            child: Text('$posicao',
                style: const TextStyle(fontFamily: Tokens.letraTitulos, color: Tokens.anelFoco, fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            flex: 3,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (detalhe != null && detalhe!.isNotEmpty)
                Text(detalhe!, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Tokens.texto2, fontSize: 12.5)),
            ]),
          ),
          const SizedBox(width: Tokens.e12),
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Tokens.raioPilula),
              child: LinearProgressIndicator(
                value: maximo.inSeconds == 0 ? 0 : tempo.inSeconds / maximo.inSeconds,
                minHeight: 8,
                color: posicao == 1 ? Tokens.acento : Tokens.acento2,
                backgroundColor: Tokens.vidroForte,
              ),
            ),
          ),
          const SizedBox(width: Tokens.e12),
          SizedBox(
            width: 76,
            child: Text(textoDuracao(tempo), textAlign: TextAlign.right, style: const TextStyle(color: Tokens.texto2)),
          ),
        ]),
      );
}

/// Um gráfico de colunas (dias da semana ou horas do dia), a coluna maior em azul elétrico.
class _Colunas extends StatelessWidget {
  const _Colunas({required this.valores, required this.rotulos, required this.altura});
  final List<Duration> valores;
  final List<String> rotulos;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final maximo = valores.fold<int>(0, (m, d) => d.inSeconds > m ? d.inSeconds : m);
    return SizedBox(
      height: altura + 22,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < valores.length; i++)
          Expanded(
            child: Tooltip(
              message: '${rotulos[i].isEmpty ? '$i h' : rotulos[i]}: ${textoDuracao(valores[i])}',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Container(
                    height: 3 + (altura - 3) * (maximo == 0 ? 0 : valores[i].inSeconds / maximo),
                    decoration: BoxDecoration(
                      color: maximo > 0 && valores[i].inSeconds == maximo ? Tokens.acento : Tokens.acento2.withValues(alpha: .55),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 16,
                    child: Text(rotulos[i], maxLines: 1, overflow: TextOverflow.visible, softWrap: false,
                        style: const TextStyle(fontSize: 11, color: Tokens.texto2)),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}
