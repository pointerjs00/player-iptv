import 'package:material_ui/material_ui.dart';

import '../dados/novidades.dart';
import 'design/design.dart';
import 'realce_foco.dart';
import '../idioma/idioma.dart';

/// Depois de atualizar: as novidades desta versão, com "Ver todas" (o histórico) e "Fechar".
Future<void> mostrarNovidadesDaVersao(BuildContext context) async {
  final n = historicoNovidades.first;
  final todas = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.new_releases_outlined, color: Tokens.acento, size: 32),
      title: Text(tr('Novidades da versão {0}', [n.versao])),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(dataNovidades(n), style: const TextStyle(color: Tokens.texto2, fontSize: 13)),
            const SizedBox(height: Tokens.e12),
            _Itens(n.itens),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Ver todas'))),
        FilledButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Fechar'))),
      ],
    ),
  );
  if (todas == true && context.mounted) await abrirNovidades(context);
}

/// O histórico das novidades (de "Sobre e licenças"). Voltar fecha-o.
Future<void> abrirNovidades(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TelaNovidades()));

/// Todas as versões, a mais recente primeiro. Cada versão recebe o foco, para o comando da TV
/// poder descer pelo texto.
class TelaNovidades extends StatelessWidget {
  const TelaNovidades({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Tokens.fundo,
        appBar: AppBar(backgroundColor: Tokens.fundo, title: Text(tr('Novidades'))),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(Tokens.e16),
              children: [
                for (final (i, n) in historicoNovidades.indexed) _Versao(n, autofocus: i == 0),
              ],
            ),
          ),
        ),
      );
}

class _Itens extends StatelessWidget {
  const _Itens(this.itens);
  final List<String> itens;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final t in itens)
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.e8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('•  ', style: TextStyle(color: Tokens.texto2, height: 1.4)),
              Expanded(child: Text(tr(t), style: const TextStyle(color: Tokens.texto2, height: 1.4))),
            ]),
          ),
      ]);
}

class _Versao extends StatefulWidget {
  const _Versao(this.novidades, {this.autofocus = false});
  final Novidades novidades;
  final bool autofocus;

  @override
  State<_Versao> createState() => _VersaoState();
}

class _VersaoState extends State<_Versao> {
  bool _focado = false;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Tokens.e8),
        child: Focus(
          autofocus: widget.autofocus,
          onFocusChange: (f) => setState(() => _focado = f),
          child: MolduraFoco(
            focado: _focado,
            child: Padding(
              padding: const EdgeInsets.all(Tokens.e12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Flexible(
                    child: Text(tr('Versão {0}', [widget.novidades.versao]),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Tokens.texto)),
                  ),
                  const SizedBox(width: Tokens.e12),
                  Text(dataNovidades(widget.novidades),
                      style: const TextStyle(fontSize: 13, color: Tokens.texto2)),
                ]),
                const SizedBox(height: Tokens.e8),
                _Itens(widget.novidades.itens),
              ]),
            ),
          ),
        ),
      );
}
