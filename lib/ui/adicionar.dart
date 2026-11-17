import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../dados/area_gestor.dart';
import 'campo_tv.dart';
import 'design/tokens.dart';
import '../importar/importar.dart';
import '../rede/http.dart';
import '../modelo/conta.dart';

/// Importa ficheiros (Accounts.json, .ini, .m3u, .txt, historico.json) para o Gestor.
Future<String> importarFicheiros(AreaGestor b) async {
  final ficheiros = await FilePicker.pickFiles(dialogTitle: 'Escolher listas');
  if (ficheiros.isEmpty) return '';
  final importadas = <Importada>[];
  final erros = <String>[];
  for (final f in ficheiros) {
    try {
      final texto = utf8.decode(await f.readAsBytes(), allowMalformed: true);
      importadas.addAll(importarFicheiro(f.name, texto, caminho: f.path));
    } on ErroImportacao catch (e) {
      erros.add('${f.name}: ${e.mensagem}');
    } catch (e) {
      erros.add('${f.name}: ${descreverErro(e)}');
    }
  }
  final novas = await b.adicionar(importadas);
  return _resumo(novas, importadas.length - novas, erros);
}

/// Junta ao Gestor listas coladas (uma por linha) ou um URL de lista M3U.
Future<String> importarTexto(AreaGestor b, String texto) async {
  final contas = lerLinhas(texto);
  if (contas.isEmpty) return 'Não foi encontrada nenhuma lista no texto.';
  final novas = await b.adicionar([for (final c in contas) Importada(c)]);
  return _resumo(novas, contas.length - novas, const []);
}

String _resumo(int novas, int repetidas, List<String> erros) {
  final p = <String>[];
  p.add(novas == 1 ? '1 lista nova' : '$novas listas novas');
  if (repetidas > 0) p.add(repetidas == 1 ? '1 já existia' : '$repetidas já existiam');
  var t = '${p.join(', ')}.';
  if (erros.isNotEmpty) t += ' Com problemas: ${erros.join('; ')}';
  return t;
}

/// Diálogo "Adicionar listas" (ao Gestor): ficheiros ou colar.
Future<void> mostrarAdicionar(BuildContext context, AreaGestor b) async {
  final ctrl = TextEditingController();
  final mensagem = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.playlist_add_rounded, color: Tokens.acento2, size: 32),
      title: const Text('Adicionar listas'),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FilledButton.icon(
            autofocus: true,
            onPressed: () async {
              final m = await importarFicheiros(b);
              if (ctx.mounted) Navigator.pop(ctx, m);
            },
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Escolher ficheiros (Accounts.json, .ini, .m3u, .txt)'),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Tokens.e16),
            child: Row(children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: Tokens.e12),
                child: Text('ou cole aqui, uma por linha:', style: TextStyle(color: Tokens.texto2)),
              ),
              Expanded(child: Divider()),
            ]),
          ),
          // o comando da TV não fica preso no campo: o teclado só abre com OK (ver CampoTv)
          CampoTv(
            controller: ctrl,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: 'http://portal.com/c/ 00:1A:79:00:00:01\nhttp://servidor:8080/get.php?username=…\nhttp://…/lista.m3u',
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () async {
          final m = await importarTexto(b, ctrl.text);
          if (ctx.mounted) Navigator.pop(ctx, m);
        },
            child: const Text('Adicionar')),
      ],
    ),
  );
  if (mensagem != null && mensagem.isNotEmpty && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
  }
}

/// Para testes: as contas de um texto colado.
List<Conta> contasColadas(String t) => lerLinhas(t);
