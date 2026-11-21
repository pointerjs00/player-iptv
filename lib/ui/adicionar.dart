import 'dart:convert';

import 'package:file_picker/file_picker.dart';

import '../dados/area_gestor.dart';
import '../importar/importar.dart';
import '../modelo/conta.dart';
import '../rede/http.dart';
import '../tarefas/servico_tarefas.dart';

/// O que uma importação trouxe para o Gestor: os números do painel "Resultado".
class ResumoImportacao {
  ResumoImportacao({
    this.encontradas = 0,
    this.novas = 0,
    this.repetidas = 0,
    this.erros = const [],
    this.idsNovas = const [],
  });

  /// As listas que a origem tinha (antes de ver o que o Gestor já tinha).
  final int encontradas;

  /// As que entraram no Gestor, e quais (para "Verificar as n novas").
  final int novas;
  List<String> idsNovas;

  /// As que o Gestor já tinha.
  final int repetidas;

  /// O que correu mal (um ficheiro ilegível, um blog sem posts...), sem links nem credenciais.
  final List<String> erros;

  /// Uma frase com o resumo ("2 listas novas, 1 já existia.").
  String get texto {
    if (encontradas == 0 && novas == 0) return erros.isEmpty ? 'Não foi encontrada nenhuma lista.' : erros.join('; ');
    final p = <String>[
      novas == 1 ? '1 lista nova' : '$novas listas novas',
      if (repetidas > 0) repetidas == 1 ? '1 já existia' : '$repetidas já existiam',
    ];
    var t = '${p.join(', ')}.';
    if (erros.isNotEmpty) t += ' Com problemas: ${erros.join('; ')}';
    return t;
  }
}

/// Junta ao Gestor o que `juntar` traz e diz quais as listas novas. As novas veem-se logo a
/// seguir ao arranque de `juntar` (a parte síncrona do `adicionar` já as pôs no Gestor), por isso
/// duas importações em simultâneo não trocam os ids.
Future<ResumoImportacao> juntarAoGestor(AreaGestor g, Future<int> Function() juntar,
    {required int encontradas, List<String> erros = const []}) async {
  final antes = {for (final l in g.listas) l.id};
  final gravacao = juntar();
  final ids = [for (final l in g.listas) if (!antes.contains(l.id)) l.id];
  await gravacao;
  return ResumoImportacao(
      encontradas: encontradas, novas: ids.length, repetidas: encontradas - ids.length, erros: erros, idsNovas: ids);
}

/// Pergunta os ficheiros (Accounts.json, .ini, .m3u, .txt, historico.json) e importa-os para o
/// Gestor. null = não escolheu nenhum.
Future<ResumoImportacao?> importarFicheiros(AreaGestor b, {Progresso? p}) async {
  final ficheiros = await FilePicker.pickFiles(dialogTitle: 'Escolher listas');
  if (ficheiros.isEmpty) return null;
  return importarEscolhidos(b, ficheiros, p: p);
}

/// Importa os ficheiros já escolhidos (corre numa tarefa: `p` mostra o ficheiro a ler).
Future<ResumoImportacao> importarEscolhidos(AreaGestor b, List<PlatformFile> ficheiros, {Progresso? p}) async {
  final importadas = <Importada>[];
  final erros = <String>[];
  for (final (i, f) in ficheiros.indexed) {
    p?.call(i / ficheiros.length, f.name);
    try {
      final texto = utf8.decode(await f.readAsBytes(), allowMalformed: true);
      importadas.addAll(importarFicheiro(f.name, texto, caminho: f.path));
    } on ErroImportacao catch (e) {
      erros.add('${f.name}: ${e.mensagem}');
    } catch (e) {
      erros.add('${f.name}: ${descreverErro(e)}');
    }
  }
  return juntarAoGestor(b, () => b.adicionar(importadas), encontradas: importadas.length, erros: erros);
}

/// Junta ao Gestor listas coladas (uma por linha) ou um URL de lista M3U.
Future<ResumoImportacao> importarTexto(AreaGestor b, String texto) async {
  final contas = lerLinhas(texto);
  if (contas.isEmpty) return ResumoImportacao(erros: const ['Não foi encontrada nenhuma lista no texto.']);
  return juntarAoGestor(b, () => b.adicionar([for (final c in contas) Importada(c)]), encontradas: contas.length);
}

/// Para testes: as contas de um texto colado.
List<Conta> contasColadas(String t) => lerLinhas(t);
