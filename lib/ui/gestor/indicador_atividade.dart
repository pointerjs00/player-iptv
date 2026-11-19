import 'package:material_ui/material_ui.dart';

import '../../tarefas/servico_tarefas.dart';
import '../../verificar/servico.dart';
import '../design/design.dart';

/// O título das tarefas de pesquisa no stbstalker (o indicador reconhece-as por ele).
const tituloTarefaStb = 'Pesquisa no stbstalker';

/// O que está a decorrer no Gestor, numa linha: "A verificar 11/17 · 1 tarefa a decorrer".
/// Sem nada a decorrer diz "Nada a decorrer". Com [aoAbrir] é um botão (abre o painel de
/// atividade); sem ele só mostra o texto e o comando não pára nele.
class IndicadorAtividade extends StatelessWidget {
  const IndicadorAtividade({super.key, required this.servico, required this.tarefas, this.aoAbrir});

  final ServicoVerificacao servico;
  final ServicoTarefas tarefas;
  final VoidCallback? aoAbrir;

  /// O texto do indicador ('' sem nada a decorrer).
  static String texto(ServicoVerificacao s, ServicoTarefas tarefas) {
    final n = tarefas.emCurso.length;
    final stb = [for (final t in tarefas.emCurso) if (t.titulo.startsWith(tituloTarefaStb)) t];
    return [
      if (s.ocupado) 'A verificar ${s.feitas}/${s.total}',
      // a pesquisa mais recente: "stbstalker: 24 encontradas"
      if (stb.isNotEmpty) 'stbstalker: ${stb.last.detalhe.isEmpty ? 'a procurar' : stb.last.detalhe}',
      if (n > 0) '$n ${n == 1 ? 'tarefa' : 'tarefas'} a decorrer',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([servico, tarefas]),
        builder: (context, _) {
          final t = texto(servico, tarefas);
          final ativo = t.isNotEmpty;
          final conteudo = Row(mainAxisSize: MainAxisSize.min, children: [
            // um ícone parado (uma roda a girar sempre à vista não deixava o ecrã sossegar)
            Icon(ativo ? Icons.autorenew : Icons.check_circle_outline,
                size: 16, color: ativo ? Tokens.anelFoco : Tokens.texto2),
            const SizedBox(width: Tokens.e8),
            Flexible(
              child: Text(ativo ? t : 'Nada a decorrer',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: ativo ? Tokens.texto : Tokens.texto2, fontSize: 13)),
            ),
          ]);
          final caixa = Container(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.e12, vertical: 6),
            decoration: BoxDecoration(
              color: ativo ? Tokens.superficie3 : Tokens.vidro,
              borderRadius: BorderRadius.circular(Tokens.raioPilula),
              border: Border.all(color: Tokens.bordaVidro),
            ),
            child: conteudo,
          );
          final abrir = aoAbrir;
          return Semantics(
            liveRegion: true,
            label: ativo ? t : 'Nada a decorrer',
            excludeSemantics: abrir == null,
            child: abrir == null
                ? caixa
                : TextButton(
                    onPressed: abrir,
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, shape: const StadiumBorder()),
                    child: caixa,
                  ),
          );
        },
      );
}
