import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import 'ecra.dart';
import 'tokens.dart';
import '../../idioma/idioma.dart';

/// Os estados de uma lista, com as mesmas palavras e cores em todo o lado.
enum EstadoLista { funciona, inconclusiva, naoFunciona, porVerificar }

/// O estado da última verificação da lista (sem verificação: por verificar).
EstadoLista estadoDe(Lista l) => switch (l.ultima?.estado) {
      'funciona' => EstadoLista.funciona,
      'inconclusivo' => EstadoLista.inconclusiva,
      'nao_funciona' => EstadoLista.naoFunciona,
      _ => EstadoLista.porVerificar,
    };

extension ApresentacaoEstadoLista on EstadoLista {
  String get rotulo => switch (this) {
        EstadoLista.funciona => tr('Funciona'),
        EstadoLista.inconclusiva => tr('Inconclusiva'),
        EstadoLista.naoFunciona => tr('Não funciona'),
        EstadoLista.porVerificar => tr('Por verificar'),
      };

  Color get cor => switch (this) {
        EstadoLista.funciona => Tokens.ok,
        EstadoLista.inconclusiva => Tokens.aviso,
        EstadoLista.naoFunciona => Tokens.mau,
        EstadoLista.porVerificar => Tokens.neutro,
      };

  Color get fundo => switch (this) {
        EstadoLista.funciona => Tokens.fundoOk,
        EstadoLista.inconclusiva => Tokens.fundoAviso,
        EstadoLista.naoFunciona => Tokens.fundoMau,
        EstadoLista.porVerificar => Tokens.fundoNeutro,
      };

  IconData get icone => switch (this) {
        EstadoLista.funciona => Icons.check_circle_outline,
        EstadoLista.inconclusiva => Icons.warning_amber_rounded,
        EstadoLista.naoFunciona => Icons.cancel_outlined,
        EstadoLista.porVerificar => Icons.help_outline,
      };
}

/// O estado de uma lista numa pílula ("Funciona", ou "Funciona · verificada há 2 h" com [detalhe]).
/// Fica maior na TV. O estado nunca se corta: sem espaço, corta-se só o detalhe (com
/// reticências, numa linha, ou em [linhasDetalhe] linhas; null = as que precisar). [compacta]
/// é para as linhas baixas das tabelas: mais justa e sem crescer com a letra do sistema.
class PilulaEstado extends StatelessWidget {
  const PilulaEstado(this.estado, {super.key, this.detalhe, this.linhasDetalhe = 1, this.compacta = false});

  final EstadoLista estado;
  final String? detalhe;
  final int? linhasDetalhe;
  final bool compacta;

  @override
  Widget build(BuildContext context) {
    final tv = ecraTv(context);
    final tam = compacta ? (tv ? 12.5 : 11.5) : (tv ? 15.0 : 12.5);
    final cor = estado.cor;
    final d = detalhe;
    final estilo = TextStyle(color: cor, fontWeight: FontWeight.w600, fontSize: tam, height: compacta ? 1.2 : null);
    final margem = compacta
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 1)
        : EdgeInsets.symmetric(horizontal: tv ? 12 : 10, vertical: tv ? 5 : 3);
    final espaco = compacta ? 4.0 : 6.0;
    Widget caixa(Widget conteudo) => Container(
          padding: margem,
          decoration: BoxDecoration(
            color: estado.fundo,
            borderRadius: BorderRadius.circular(Tokens.raioPilula),
            border: Border.all(color: cor.withValues(alpha: .4)),
          ),
          child: conteudo,
        );
    final icone = Icon(estado.icone, size: tam + 2, color: cor);
    final completo = d == null || d.isEmpty ? estado.rotulo : '${estado.rotulo} · $d';
    Widget linha(List<Widget> textos) =>
        caixa(Row(mainAxisSize: MainAxisSize.min, children: [icone, SizedBox(width: espaco), ...textos]));
    final pilula = LayoutBuilder(builder: (context, c) {
      double largura(String texto) {
        final p = TextPainter(
          text: TextSpan(text: texto, style: DefaultTextStyle.of(context).style.merge(estilo)),
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
          maxLines: 1,
        )..layout();
        final w = p.width;
        p.dispose();
        return margem.horizontal + 2 + icone.size! + espaco + w;
      }

      // cabe tudo (o caso normal): um só texto
      if (!c.hasBoundedWidth || largura(completo) <= c.maxWidth) {
        return linha([Text(completo, maxLines: 1, softWrap: false, style: estilo)]);
      }
      // sem espaço nem para o estado inteiro (letra muito grande, cartão estreito): o estado
      // encolhe (nunca se corta) e o detalhe sai
      if (largura(estado.rotulo) > c.maxWidth) {
        return linha([
          Flexible(
            child: FittedBox(
                fit: BoxFit.scaleDown, child: Text(estado.rotulo, maxLines: 1, softWrap: false, style: estilo)),
          ),
        ]);
      }
      // o estado inteiro; o detalhe no espaço que sobra (cortado ou em várias linhas)
      return linha([
        Text(estado.rotulo, maxLines: 1, softWrap: false, style: estilo),
        Flexible(
          child: Text(' · $d',
              maxLines: linhasDetalhe, overflow: linhasDetalhe == null ? null : TextOverflow.ellipsis, style: estilo),
        ),
      ]);
    });
    return compacta ? MediaQuery.withNoTextScaling(child: pilula) : pilula;
  }
}
