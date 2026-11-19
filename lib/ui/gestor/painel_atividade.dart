import 'package:material_ui/material_ui.dart';

import '../../tarefas/servico_tarefas.dart';
import '../../verificar/servico.dart';
import '../design/design.dart';

/// Abre o painel de atividade (ecrã 10b) por cima do ecrã, encostado à direita. Voltar fecha-o e o
/// foco regressa ao que o abriu (o indicador de atividade).
Future<void> abrirPainelAtividade(
  BuildContext context, {
  required ServicoVerificacao servico,
  required ServicoTarefas tarefas,
  VoidCallback? aoVerVerificacao,
}) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fechar a atividade',
      barrierColor: Colors.black54,
      transitionDuration: Tokens.duracaoMedia,
      pageBuilder: (c, _, _) => Align(
        alignment: Alignment.centerRight,
        child: PainelAtividade(
          servico: servico,
          tarefas: tarefas,
          aoFechar: () => Navigator.of(c).pop(),
          aoVerVerificacao: aoVerVerificacao == null
              ? null
              : () {
                  Navigator.of(c).pop();
                  aoVerVerificacao();
                },
        ),
      ),
      transitionBuilder: (_, a, _, filho) =>
          SlideTransition(position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(a), child: filho),
    );

/// O painel lateral "Atividade": o que decorre (a verificação do Gestor e as tarefas) e o que
/// acabou há pouco, com `Ver detalhe`, `Parar` e `Tentar de novo`.
class PainelAtividade extends StatefulWidget {
  const PainelAtividade({
    super.key,
    required this.servico,
    required this.tarefas,
    this.aoFechar,
    this.aoVerVerificacao,
  });

  final ServicoVerificacao servico;
  final ServicoTarefas tarefas;
  final VoidCallback? aoFechar;

  /// "Ver detalhe" da verificação (abre o ecrã da verificação); sem ele o botão não aparece.
  final VoidCallback? aoVerVerificacao;

  @override
  State<PainelAtividade> createState() => _PainelAtividadeState();
}

class _PainelAtividadeState extends State<PainelAtividade> {
  /// As tarefas com o detalhe aberto.
  final _abertas = <String>{};

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.sizeOf(context).width;
    return SizedBox(
      width: largura < 460 ? largura : 420,
      height: double.infinity,
      child: Material(
        color: Tokens.superficie,
        child: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([widget.servico, widget.tarefas]),
            builder: (context, _) {
              final emCurso = widget.tarefas.emCurso;
              final recentes = widget.tarefas.recentes;
              final aDecorrer = emCurso.length + (widget.servico.ocupado ? 1 : 0);
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Tokens.e16, Tokens.e16, Tokens.e8, Tokens.e8),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Atividade',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Tokens.texto)),
                        Semantics(
                          liveRegion: true,
                          child: Text('$aDecorrer a decorrer · ${recentes.length} terminadas',
                              style: const TextStyle(fontSize: 13, color: Tokens.texto2)),
                        ),
                      ]),
                    ),
                    IconButton(
                      autofocus: true,
                      tooltip: 'Fechar',
                      onPressed: widget.aoFechar,
                      icon: const Icon(Icons.close),
                    ),
                  ]),
                ),
                Expanded(
                  child: ListView(padding: const EdgeInsets.symmetric(horizontal: Tokens.e16), children: [
                    if (widget.servico.ocupado) _cartaoVerificacao(),
                    for (final t in emCurso) _cartaoTarefa(t),
                    for (final t in recentes) _cartaoTarefa(t),
                    if (aDecorrer == 0 && recentes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: Tokens.e24),
                        child: Text('Nada a decorrer.', style: TextStyle(color: Tokens.texto2)),
                      ),
                  ]),
                ),
                const Padding(
                  padding: EdgeInsets.all(Tokens.e16),
                  child: Text('Podes fechar este painel e continuar a usar a app. Cada tarefa avisa quando termina.',
                      style: TextStyle(fontSize: 12, color: Tokens.texto2)),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }

  Widget _cartao(String titulo, List<Widget> corpo, List<Widget> botoes) => Container(
        margin: const EdgeInsets.only(bottom: Tokens.e12),
        padding: const EdgeInsets.all(Tokens.e12),
        decoration: BoxDecoration(
          color: Tokens.superficie2,
          borderRadius: BorderRadius.circular(Tokens.raioBotao),
          border: Border.all(color: Tokens.bordaVidro),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600, color: Tokens.texto)),
          const SizedBox(height: Tokens.e8),
          ...corpo,
          if (botoes.isNotEmpty) Wrap(spacing: Tokens.e8, children: botoes),
        ]),
      );

  Widget _cartaoVerificacao() {
    final s = widget.servico;
    return _cartao(
      'Verificação das listas',
      [
        LinearProgressIndicator(value: s.total == 0 ? null : s.feitas / s.total, minHeight: 6),
        const SizedBox(height: Tokens.e4),
        Text('A verificar ${s.feitas}/${s.total}', style: const TextStyle(color: Tokens.texto2)),
      ],
      [
        if (widget.aoVerVerificacao != null) TextButton(onPressed: widget.aoVerVerificacao, child: const Text('Ver detalhe')),
        TextButton(onPressed: s.parar, child: const Text('Parar')),
      ],
    );
  }

  Widget _cartaoTarefa(Tarefa t) {
    final aDecorrer = t.estado == EstadoTarefa.aDecorrer;
    final aberta = _abertas.contains(t.id);
    final corpo = <Widget>[
      if (aDecorrer) ...[
        LinearProgressIndicator(value: t.progresso, minHeight: 6),
        const SizedBox(height: Tokens.e4),
        Text(t.detalhe.isEmpty ? 'A decorrer…' : t.detalhe, style: const TextStyle(color: Tokens.texto2)),
      ] else ...[
        Row(children: [
          Icon(
            switch (t.estado) {
              EstadoTarefa.terminada => Icons.check_circle_outline,
              EstadoTarefa.falhou => Icons.error_outline,
              _ => Icons.cancel_outlined,
            },
            size: 16,
            color: switch (t.estado) {
              EstadoTarefa.terminada => Tokens.ok,
              EstadoTarefa.falhou => Tokens.mau,
              _ => Tokens.texto2,
            },
          ),
          const SizedBox(width: Tokens.e8),
          Expanded(
            child: Text(
              switch (t.estado) {
                EstadoTarefa.terminada => 'Terminada',
                EstadoTarefa.falhou => 'Falhou',
                _ => 'Cancelada',
              },
              style: const TextStyle(color: Tokens.texto),
            ),
          ),
        ]),
        const SizedBox(height: Tokens.e4),
        Text(t.resultado ?? '',
            maxLines: aberta ? null : 2,
            overflow: aberta ? TextOverflow.visible : TextOverflow.ellipsis,
            style: const TextStyle(color: Tokens.texto2)),
      ],
      if (aberta && t.fim != null) ...[
        const SizedBox(height: Tokens.e4),
        Text('Durou ${_duracao(t.fim!.difference(t.inicio))}', style: const TextStyle(color: Tokens.texto2, fontSize: 12)),
      ],
    ];
    return _cartao(t.titulo, corpo, [
      TextButton(
        onPressed: () => setState(() => aberta ? _abertas.remove(t.id) : _abertas.add(t.id)),
        child: const Text('Ver detalhe'),
      ),
      if (aDecorrer) TextButton(onPressed: () => widget.tarefas.cancelar(t.id), child: const Text('Parar')),
      if (t.estado == EstadoTarefa.falhou && t.repetir != null)
        TextButton(onPressed: () => t.repetir!(), child: const Text('Tentar de novo')),
    ]);
  }

  static String _duracao(Duration d) => d.inSeconds < 60 ? '${d.inSeconds} s' : '${d.inMinutes} min ${d.inSeconds % 60} s';
}
