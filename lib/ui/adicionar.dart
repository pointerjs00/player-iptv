import 'dart:convert';

import 'package:file_picker/file_picker.dart';

import '../dados/area_gestor.dart';
import '../importar/importar.dart';
import '../modelo/conta.dart';
import '../rede/http.dart';
import '../tarefas/servico_tarefas.dart';
import '../idioma/idioma.dart';

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
    if (encontradas == 0 && novas == 0) return erros.isEmpty ? tr('Não foi encontrada nenhuma lista.') : erros.join('; ');
    final p = <String>[
      novas == 1 ? tr('1 lista nova') : tr('{0} listas novas', [novas]),
      if (repetidas > 0) repetidas == 1 ? tr('1 já existia') : tr('{0} já existiam', [repetidas]),
    ];
    var t = '${p.join(', ')}.';
    if (erros.isNotEmpty) t += tr(' Com problemas: {0}', [erros.join('; ')]);
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
  final ficheiros = await FilePicker.pickFiles(dialogTitle: tr('Escolher listas'));
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
  if (contas.isEmpty) return ResumoImportacao(erros: [tr('Não foi encontrada nenhuma lista no texto.')]);
  return juntarAoGestor(b, () => b.adicionar([for (final c in contas) Importada(c)]), encontradas: contas.length);
}

/// Para testes: as contas de um texto colado.
List<Conta> contasColadas(String t) => lerLinhas(t);

/// As formas de adicionar uma lista à mão (como no IPTV Extreme).
enum FormaLista {
  portalMac('Portal MAC'),
  xtreamLink('Xtream (link)'),
  xtreamConta('Xtream (servidor e conta)'),
  m3u('Lista M3U'),
  varias('Várias (colar)');

  const FormaLista(this._nome);
  final String _nome;
  String get nome => tr(_nome);
}

final _reMacLivre = RegExp(r'^[0-9A-F]{2}([:-]?[0-9A-F]{2}){5}$');

/// O endereço com http:// se não tiver esquema; null se não for um endereço.
String? _endereco(String t) {
  var e = t.trim();
  if (e.isEmpty) return null;
  if (!RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(e)) e = 'http://$e';
  final u = Uri.tryParse(e);
  if (u == null || u.host.isEmpty || !(u.scheme == 'http' || u.scheme == 'https')) return null;
  return e;
}

/// O MAC como 00:1A:79:12:34:56 (aceita minúsculas, "-" ou sem separadores); null se não for um MAC.
String? macNormalizado(String t) {
  final m = t.trim().toUpperCase();
  if (!_reMacLivre.hasMatch(m)) return null;
  final hex = m.replaceAll(RegExp('[:-]'), '');
  return [for (var i = 0; i < 12; i += 2) hex.substring(i, i + 2)].join(':');
}

/// A conta escrita nos campos de [forma] (não serve para [FormaLista.varias]), ou o que está mal.
({Conta? conta, String? erro}) contaManual(FormaLista forma,
    {String endereco = '', String mac = '', String utilizador = '', String password = ''}) {
  ({Conta? conta, String? erro}) erro(String e) => (conta: null, erro: e);
  final url = _endereco(endereco);
  switch (forma) {
    case FormaLista.portalMac:
      if (url == null) return erro(tr('Escreva o endereço do portal (por exemplo http://portal.com:8080/c/).'));
      final m = macNormalizado(mac);
      if (m == null) return erro(tr('O MAC tem de ter 6 pares, como 00:1A:79:12:34:56.'));
      return (conta: Conta(hostDe(url), Tipo.stalker, url, mac: m), erro: null);
    case FormaLista.xtreamLink:
      final x = url == null ? null : xtreamDeUrl(url);
      if (x == null) {
        return erro(tr('O link tem de ter o utilizador e a palavra-passe (…/get.php?username=…&password=…).'));
      }
      return (conta: Conta(hostDe(url!), Tipo.xtream, x.$1, utilizador: x.$2, password: x.$3), erro: null);
    case FormaLista.xtreamConta:
      if (url == null) return erro(tr('Escreva o endereço do servidor (por exemplo http://servidor.com:8080).'));
      final u = utilizador.trim(), p = password.trim();
      if (u.isEmpty || p.isEmpty) return erro(tr('Escreva o utilizador e a palavra-passe.'));
      // só a raiz do servidor (http://host:porta): um caminho a mais não faz parte da conta
      final s = Uri.parse(url);
      return (conta: Conta(hostDe(url), Tipo.xtream, '${s.scheme}://${s.authority}', utilizador: u, password: p), erro: null);
    case FormaLista.m3u:
      if (url == null) return erro(tr('Escreva o endereço da lista M3U.'));
      return (conta: Conta(hostDe(url), Tipo.m3u, url), erro: null);
    case FormaLista.varias:
      return erro('Use importarTexto para várias listas.');
  }
}

/// Junta ao Gestor uma conta escrita à mão.
Future<ResumoImportacao> importarConta(AreaGestor b, Conta c) =>
    juntarAoGestor(b, () => b.adicionar([Importada(c)]), encontradas: 1);
