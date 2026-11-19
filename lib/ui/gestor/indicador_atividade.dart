import 'package:material_ui/material_ui.dart';

import '../../tarefas/servico_tarefas.dart';
import '../../verificar/servico.dart';
import '../design/design.dart';

/// O título das tarefas de pesquisa no stbstalker (o indicador reconhece-as por ele).
const tituloTarefaStb = 'Pesquisa no stbstalker';

/// O que está a decorrer no Gestor, numa linha: "A verificar 11/17 · 1 tarefa a decorrer".
/// Sem nada a decorrer diz "Nada a decorrer". Com [aoAbrir] é um botão (abre o painel de
/// atividade); sem ele só mostra o texto e o comando não pára nele.
///
/// Com [soVerificacao] (no passo 2 do Gestor) só fala da verificação: "A verificar 2/5" ou
/// "nada a decorrer"; e só é botão (o [aoAbrir] abre o progresso) se houve uma verificação nesta
/// sessão (a decorrer, ou acabou uma ronda).
class IndicadorAtividade extends StatelessWidget {
  const IndicadorAtividade(
      {super.key, required this.servico, required this.tarefas, this.aoAbrir, this.foco, this.soVerificacao = false});

  final ServicoVerificacao servico;
  final ServicoTarefas tarefas;
  final VoidCallback? aoAbrir;

  /// O foco do botão (o painel de atividade devolve-lhe o foco ao fechar).
  final FocusNode? foco;

  /// Só a verificação (o indicador do passo 2).
  final bool soVerificacao;

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
          final t = soVerificacao
              ? (servico.ocupado ? 'A verificar ${servico.feitas}/${servico.total}' : '')
              : texto(servico, tarefas);
          final ativo = t.isNotEmpty;
          final vazio = soVerificacao ? 'nada a decorrer' : 'Nada a decorrer';
          final conteudo = Row(mainAxisSize: MainAxisSize.min, children: [
            // um ícone parado (uma roda a girar sempre à vista não deixava o ecrã sossegar)
            Icon(ativo ? Icons.autorenew : Icons.check_circle_outline,
                size: 16, color: ativo ? Tokens.anelFoco : Tokens.texto2),
            const SizedBox(width: Tokens.e8),
            Flexible(
              child: Text(ativo ? t : vazio,
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
          final houve = servico.ocupado || servico.fimRonda != null;
          final abrir = soVerificacao && !houve ? null : aoAbrir;
          return Semantics(
            liveRegion: true,
            label: ativo ? t : vazio,
            excludeSemantics: abrir == null,
            child: abrir == null
                ? caixa
                : TextButton(
                    focusNode: foco,
                    onPressed: abrir,
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, shape: const StadiumBorder()),
                    child: caixa,
                  ),
          );
        },
      );
}
