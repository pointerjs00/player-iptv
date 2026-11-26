import 'package:material_ui/material_ui.dart';

import '../../dados/estatisticas.dart';
import '../../idioma/idioma.dart';
import '../design/design.dart';

/// Os dias da semana abreviados (segunda primeiro), para os gráficos.
List<String> diasAbreviados() => [tr('Seg'), tr('Ter'), tr('Qua'), tr('Qui'), tr('Sex'), tr('Sáb'), tr('Dom')];

/// "+1 h 20 que na semana anterior", "−35 min…", "Igual à semana anterior" ou, sem semana
/// anterior, "Primeira semana com dados".
String comparacaoSemana(ResumoSemana s) {
  if (s.anterior == Duration.zero) return tr('Primeira semana com dados');
  final d = s.total - s.anterior;
  if (d.inMinutes.abs() < 1) return tr('Igual à semana anterior');
  return d.isNegative
      ? tr('{0} que na semana anterior', ['−${textoDuracao(-d)}'])
      : tr('{0} que na semana anterior', ['+${textoDuracao(d)}']);
}

/// «A tua semana» no Início: as horas vistas nos últimos 7 dias (e a comparação com os 7
/// anteriores), um gráfico de barras dos dias e os 3 canais mais vistos. OK (ou toque) abre as
/// Estatísticas.
class CartaoSemana extends StatelessWidget {
  const CartaoSemana({super.key, required this.resumo, required this.hoje, required this.aoAbrir});

  final ResumoSemana resumo;

  /// O dia de hoje (o último dos 7: o dia da semana de cada barra conta a partir dele).
  final DateTime hoje;
  final VoidCallback aoAbrir;

  /// A altura na TV e no computador (no telemóvel cresce com o que mostra).
  static double altura(bool tv, [double fator = 1]) => (tv ? 150 : 136) * fator;

  @override
  Widget build(BuildContext context) {
    final tv = ecraTv(context);
    final telemovel = ecraTelemovel(context);
    final s = resumo;
    final resumoTexto = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('A TUA SEMANA'),
          style: TextStyle(color: Tokens.acento, fontSize: tv ? 12.5 : 11, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
      const SizedBox(height: Tokens.e4),
      Text(textoDuracao(s.total),
          key: const Key('semana-total'),
          maxLines: 1,
          style: TextStyle(
              fontFamily: Tokens.letraTitulos, fontSize: tv ? 36 : 30, fontWeight: FontWeight.w700, height: 1.1)),
      Text(comparacaoSemana(s),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: s.total >= s.anterior || s.anterior == Duration.zero ? Tokens.ok : Tokens.aviso,
              fontSize: tv ? 13.5 : 12.5,
              fontWeight: FontWeight.w600)),
    ]);
    final grafico = _Barras(porDia: s.porDia, hoje: hoje, altura: tv ? 70 : 60);
    final topo = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (i, c) in s.maisVistos.indexed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            SizedBox(
              width: 18,
              child: Text('${i + 1}',
                  style: TextStyle(fontFamily: Tokens.letraTitulos, color: Tokens.anelFoco, fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: Text(c.nome, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: tv ? 15 : 13.5, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: Tokens.e8),
            Text(textoDuracao(c.tempo), style: TextStyle(color: Tokens.texto2, fontSize: tv ? 13.5 : 12)),
          ]),
        ),
    ]);
    final conteudo = telemovel
        ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: resumoTexto), Expanded(child: grafico)]),
            if (s.maisVistos.isNotEmpty) ...[const SizedBox(height: Tokens.e12), topo],
          ])
        : Row(children: [
            SizedBox(width: tv ? 220 : 200, child: resumoTexto),
            const SizedBox(width: Tokens.e16),
            Expanded(flex: 3, child: grafico),
            if (s.maisVistos.isNotEmpty) ...[
              const SizedBox(width: Tokens.e24),
              Expanded(flex: 4, child: topo),
            ],
            const SizedBox(width: Tokens.e8),
            const Icon(Icons.chevron_right_rounded, color: Tokens.texto2),
          ]);
    return letraPresa(Semantics(
      button: true,
      label: tr('A tua semana: {0}. Abrir as estatísticas', [textoDuracao(s.total)]),
      child: CartaoModerno(
        key: const Key('cartao-semana'),
        onTap: aoAbrir,
        escalaFoco: 1.02,
        padding: EdgeInsets.symmetric(horizontal: tv ? 20 : Tokens.e16, vertical: Tokens.e12),
        child: conteudo,
      ),
    ));
  }
}

/// Um gráfico de barras pequeno dos 7 dias (o de hoje em azul elétrico) com a inicial do dia
/// por baixo. Só desenho: o número está ao lado.
class _Barras extends StatelessWidget {
  const _Barras({required this.porDia, required this.hoje, required this.altura});

  final List<Duration> porDia;
  final DateTime hoje;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final maximo = porDia.fold<int>(0, (m, d) => d.inSeconds > m ? d.inSeconds : m);
    final dias = diasAbreviados();
    return ExcludeSemantics(
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < porDia.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: maximo == 0 ? 0 : porDia[i].inSeconds / maximo),
                  duration: duracaoAnimada(context, Tokens.duracaoLenta * 2),
                  curve: Tokens.curva,
                  builder: (_, v, _) => Container(
                    height: 4 + (altura - 4) * v,
                    decoration: BoxDecoration(
                      color: i == porDia.length - 1 ? Tokens.acento : Tokens.acento2.withValues(alpha: .55),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: i == porDia.length - 1
                          ? [BoxShadow(color: Tokens.acento.withValues(alpha: .5), blurRadius: 10)]
                          : const [],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(dias[DateTime(hoje.year, hoje.month, hoje.day - (porDia.length - 1 - i)).weekday - 1],
                    maxLines: 1,
                    style: TextStyle(
                        fontSize: 11,
                        color: i == porDia.length - 1 ? Tokens.texto : Tokens.texto2,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
      ]),
    );
  }
}
