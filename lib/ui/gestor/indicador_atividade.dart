import 'package:material_ui/material_ui.dart';

import '../../tarefas/servico_tarefas.dart';
import '../../verificar/servico.dart';
import '../design/design.dart';
import '../../idioma/idioma.dart';

/// O título das tarefas de pesquisa no stbstalker (o indicador reconhece-as por ele).
const tituloTarefaStb = 'Pesquisa no stbstalker';

/// O que está a decorrer no Gestor, numa linha: "A verificar 11/17 · 1 tarefa a decorrer".
/// Sem nada a decorrer diz "Nada a decorrer". Com [aoAbrir] é um botão (abre o painel de
/// atividade); sem ele só mostra o texto e o comando não pára nele.
///
/// No telemóvel ([ecraTelemovel]) só mostra o ícone e o contador; o texto todo fica na dica
/// (toque longo) e na leitura do ecrã.
class IndicadorAtividade extends StatelessWidget {
  const IndicadorAtividade(
      {super.key, required this.servico, required this.tarefas, this.aoAbrir, this.foco});

  final ServicoVerificacao servico;
  final ServicoTarefas tarefas;
  final VoidCallback? aoAbrir;

  /// O foco do botão (o painel de atividade devolve-lhe o foco ao fechar).
  final FocusNode? foco;

  /// O texto do indicador ('' sem nada a decorrer).
  static String texto(ServicoVerificacao s, ServicoTarefas tarefas) {
    final n = tarefas.emCurso.length;
    final stb = [for (final t in tarefas.emCurso) if (t.titulo.startsWith(tr(tituloTarefaStb))) t];
    return [
      if (s.ocupado) tr('A verificar {0}/{1}', [s.feitas, s.total]),
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
          final completo = ativo ? t : tr('Nada a decorrer');
          final telemovel = ecraTelemovel(context);
          // no telemóvel só o ícone e o contador ("2/5", ou o número de tarefas); o texto todo fica
          // na dica (toque longo) e na leitura do ecrã
          final contador = !telemovel
              ? null
              : servico.ocupado
                  ? '${servico.feitas}/${servico.total}'
                  : tarefas.emCurso.isNotEmpty
                      ? '${tarefas.emCurso.length}'
                      : '';
          final conteudo = Row(mainAxisSize: MainAxisSize.min, children: [
            // um ícone parado (uma roda a girar sempre à vista não deixava o ecrã sossegar)
            Icon(ativo ? Icons.autorenew : Icons.check_circle_outline,
                size: telemovel ? 20 : 16, color: ativo ? Tokens.anelFoco : Tokens.texto2),
            if (contador == null) ...[
              const SizedBox(width: Tokens.e8),
              Flexible(
                child: Text(completo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: ativo ? Tokens.texto : Tokens.texto2, fontSize: 13)),
              ),
            ] else if (contador.isNotEmpty) ...[
              const SizedBox(width: Tokens.e4),
              // (o rótulo já o diz)
              ExcludeSemantics(
                child: Text(contador,
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(color: Tokens.texto, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ]);
          final caixa = Container(
            padding: telemovel
                ? const EdgeInsets.symmetric(horizontal: Tokens.e8, vertical: Tokens.e4)
                : const EdgeInsets.symmetric(horizontal: Tokens.e12, vertical: 6),
            decoration: BoxDecoration(
              color: ativo ? Tokens.superficie3 : Tokens.vidro,
              borderRadius: BorderRadius.circular(Tokens.raioPilula),
              border: Border.all(color: Tokens.bordaVidro),
            ),
            child: conteudo,
          );
          final abrir = aoAbrir;
          final botao = abrir == null
              ? (telemovel
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: Tokens.alvoToque, minHeight: Tokens.alvoToque),
                      child: Center(widthFactor: 1, heightFactor: 1, child: caixa),
                    )
                  : caixa)
              : TextButton(
                  focusNode: foco,
                  onPressed: abrir,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: const StadiumBorder(),
                    minimumSize: telemovel ? const Size.square(Tokens.alvoToque) : null,
                  ),
                  child: caixa,
                );
          return Semantics(
            liveRegion: true,
            label: completo,
            excludeSemantics: abrir == null,
            // a dica repete o rótulo: fica fora da leitura do ecrã
            child: telemovel ? Tooltip(message: completo, excludeFromSemantics: true, child: botao) : botao,
          );
        },
      );
}
