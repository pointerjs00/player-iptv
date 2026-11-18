import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import 'ecra.dart';
import 'tokens.dart';

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
        EstadoLista.funciona => 'Funciona',
        EstadoLista.inconclusiva => 'Inconclusiva',
        EstadoLista.naoFunciona => 'Não funciona',
        EstadoLista.porVerificar => 'Por verificar',
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
/// Fica maior na TV.
class PilulaEstado extends StatelessWidget {
  const PilulaEstado(this.estado, {super.key, this.detalhe});

  final EstadoLista estado;
  final String? detalhe;

  @override
  Widget build(BuildContext context) {
    final tv = ecraTv(context);
    final tam = tv ? 15.0 : 12.5;
    final cor = estado.cor;
    final d = detalhe;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: tv ? 12 : 10, vertical: tv ? 5 : 3),
      decoration: BoxDecoration(
        color: estado.fundo,
        borderRadius: BorderRadius.circular(Tokens.raioPilula),
        border: Border.all(color: cor.withValues(alpha: .4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(estado.icone, size: tam + 2, color: cor),
        const SizedBox(width: 6),
        Flexible(
          child: Text(d == null || d.isEmpty ? estado.rotulo : '${estado.rotulo} · $d',
              style: TextStyle(color: cor, fontWeight: FontWeight.w600, fontSize: tam)),
        ),
      ]),
    );
  }
}
