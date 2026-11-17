import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import '../design/design.dart';

/// Uma opção de um [escolherOpcao]: um cartão com ícone, título e descrição.
class OpcaoDialogo<T> {
  const OpcaoDialogo(this.valor, this.icone, this.titulo, this.descricao);
  final T valor;
  final IconData icone;
  final String titulo;
  final String descricao;
}

/// Um diálogo com opções em cartões (CIMA/BAIXO mudam, OK escolhe, Voltar ou "Cancelar" cancela).
/// O foco começa na primeira opção. Devolve o valor escolhido ou null.
Future<T?> escolherOpcao<T>(BuildContext context,
    {required IconData icone, required String titulo, required String texto, required List<OpcaoDialogo<T>> opcoes}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) {
      final tv = ecraTv(ctx);
      // ecrã baixo (a TV a 1080p tem 540 lógicos): sem o ícone de cima e cartões mais baixos,
      // para as opções caberem todas sem deslizar
      final baixo = MediaQuery.sizeOf(ctx).height < 640;
      return AlertDialog(
        icon: baixo ? null : Icon(icone, color: Tokens.acento2, size: 32),
        insetPadding: EdgeInsets.symmetric(horizontal: 40, vertical: baixo ? 8 : 24),
        title: Text(titulo),
        content: SizedBox(
          width: tv ? 560 : 480,
          child: SingleChildScrollView(
            // margem para o cartão focado crescer sem ser cortado
            padding: EdgeInsets.symmetric(horizontal: Tokens.e8, vertical: baixo ? Tokens.e4 : Tokens.e8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(texto, style: const TextStyle(color: Tokens.texto2)),
              SizedBox(height: baixo ? Tokens.e12 : Tokens.e16),
              for (final (i, o) in opcoes.indexed) ...[
                if (i > 0) SizedBox(height: baixo ? Tokens.e8 : Tokens.e12),
                CartaoModerno(
                  autofocus: i == 0,
                  escalaFoco: 1.02,
                  raio: Tokens.raioBotao,
                  padding: EdgeInsets.symmetric(horizontal: Tokens.e16, vertical: baixo ? 10 : Tokens.e16),
                  onTap: () => Navigator.pop(ctx, o.valor),
                  child: Row(children: [
                    Icon(o.icone, color: Tokens.acento2, size: tv ? 30 : 26),
                    const SizedBox(width: Tokens.e16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(o.titulo, style: TextStyle(fontSize: tv && !baixo ? 17 : 15, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(o.descricao,
                            style: TextStyle(color: Tokens.texto2, fontSize: tv && !baixo ? 14 : 12.5)),
                      ]),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar'))],
      );
    },
  );
}

/// "Enviar para o Player": pergunta sempre como (adicionar ou esmagar) e, ao esmagar, o que fica.
/// null = cancelado (em qualquer das perguntas).
Future<ModoEnvio?> perguntarModoEnvio(BuildContext context, int n) async {
  final passo = await escolherOpcao<String>(
    context,
    icone: Icons.send_rounded,
    titulo: 'Enviar para o Player',
    texto: n == 1 ? 'A lista selecionada vai para o Player.' : 'As $n listas selecionadas vão para o Player.',
    opcoes: const [
      OpcaoDialogo('adicionar', Icons.playlist_add_rounded, 'Adicionar às listas do Player',
          'Junta sem duplicar e atualiza o resultado das que já lá estão.'),
      OpcaoDialogo('esmagar', Icons.delete_sweep_outlined, 'Esmagar as listas do Player',
          'Substitui as listas do Player pelas enviadas.'),
    ],
  );
  if (passo == null) return null;
  if (passo == 'adicionar') return ModoEnvio.adicionar;
  if (!context.mounted) return null;
  return escolherOpcao<ModoEnvio>(
    context,
    icone: Icons.delete_sweep_outlined,
    titulo: 'O que fica no Player?',
    texto: 'Além das enviadas. As que saem perdem os favoritos e a cache de canais.',
    opcoes: const [
      OpcaoDialogo(ModoEnvio.esmagarMantendoFuncionais, Icons.check_circle_outline, 'Manter as que funcionam',
          'Do Player ficam só as que funcionam.'),
      OpcaoDialogo(ModoEnvio.esmagarMantendoFuncionaisEInc, Icons.help_outline,
          'Manter as que funcionam e as inconclusivas', 'Do Player ficam as que funcionam e as INC.'),
      OpcaoDialogo(ModoEnvio.esmagarTodas, Icons.delete_forever_outlined, 'Esmagar todas',
          'O Player fica só com as enviadas.'),
    ],
  );
}

/// O texto do fim de um envio para o Player.
String textoResumoEnvio(ResumoEnvio r) {
  String n(int v, String um, String varios) => '$v ${v == 1 ? um : varios}';
  return 'Enviadas para o Player: ${n(r.adicionadas, 'adicionada', 'adicionadas')}, '
      '${n(r.atualizadas, 'atualizada', 'atualizadas')}, ${n(r.removidas, 'removida', 'removidas')}.';
}

/// Uma confirmação simples (o foco começa em "Cancelar"). true = confirmado.
Future<bool> confirmar(BuildContext context,
    {required IconData icone, required String titulo, required String texto, required String acao}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(icone, color: Tokens.mau, size: 32),
      title: Text(titulo),
      content: Text(texto),
      actions: [
        TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(acao)),
      ],
    ),
  );
  return ok == true;
}
