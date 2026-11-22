/// Importação de listas: Accounts.json (sfvip), .ini (Stalker Portal Player), .txt/linhas,
/// histórico do verificador (com resultados) e ficheiros M3U.
library;

import 'dart:convert';

import '../modelo/conta.dart';
import 'm3u.dart';
import '../idioma/idioma.dart';

/// O último resultado conhecido de uma lista (vem do verificador ou da própria app).
class UltimaVerificacao {
  const UltimaVerificacao({required this.estado, this.motivo = '', required this.data,
      this.validade = '', this.canais = const []});

  /// 'funciona', 'nao_funciona' ou 'inconclusivo'.
  final String estado;
  final String motivo;
  final DateTime data;
  final String validade;
  final List<Map<String, dynamic>> canais;

  Map<String, dynamic> paraJson() => {
        'estado': estado, 'motivo': motivo, 'data': data.toIso8601String(), 'validade': validade,
        'canais': canais,
      };

  static UltimaVerificacao? deJson(Object? j) {
    if (j is! Map) return null;
    final data = DateTime.tryParse('${j['data']}');
    final estado = '${j['estado'] ?? ''}';
    if (data == null || !const {'funciona', 'nao_funciona', 'inconclusivo'}.contains(estado)) return null;
    return UltimaVerificacao(
      estado: estado, motivo: '${j['motivo'] ?? ''}', data: data, validade: '${j['validade'] ?? ''}',
      canais: [for (final c in (j['canais'] is List ? j['canais'] as List : const [])) if (c is Map) Map<String, dynamic>.from(c)],
    );
  }
}

/// Uma lista importada, com o resultado conhecido (se houver).
class Importada {
  Importada(this.conta, [this.ultima]);
  final Conta conta;
  final UltimaVerificacao? ultima;
}

class ErroImportacao implements Exception {
  ErroImportacao(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}

/// Accounts.json do sfvip: uma lista de dicts (ou um só dict).
List<Conta> lerAccountsJson(String texto) {
  final Object? dados;
  try {
    dados = jsonDecode(_semBom(texto));
  } on FormatException {
    throw ErroImportacao(tr('o ficheiro não é JSON válido'));
  }
  final lista = dados is List ? dados : (dados is Map ? [dados] : const []);
  return [for (final d in lista) ?contaDeDict(d)];
}

/// .ini do Stalker Portal Player: `[DNS] Address=… Mac=…`. O nome do ficheiro é o nome.
Conta? lerIni(String texto, String nomeFicheiro) {
  final valores = <String, String>{};
  for (final l in _semBom(texto).split(RegExp(r'\r?\n'))) {
    final i = l.indexOf('=');
    if (i > 0) valores[l.substring(0, i).trim().toLowerCase()] = l.substring(i + 1).trim();
  }
  final end = valores['address'] ?? valores['portal'] ?? valores['url'] ?? '';
  final mac = (valores['mac'] ?? '').toUpperCase();
  if (end.isEmpty || mac.isEmpty) return null;
  final nome = nomeFicheiro.replaceAll(RegExp(r'\.ini$', caseSensitive: false), '');
  return Conta(nome, Tipo.stalker, end, mac: mac);
}

/// Uma conta por linha ("portal MAC", get.php, URL M3U); o resto ignora-se.
List<Conta> lerLinhas(String texto) =>
    [for (final l in _semBom(texto).split(RegExp(r'\r?\n'))) ?contaDeLinha(l)];

/// O historico.json do verificador: as contas e o resultado mais recente de cada uma.
List<Importada> lerHistoricoVerificador(String texto) {
  final Object? dados;
  try {
    dados = jsonDecode(_semBom(texto));
  } on FormatException {
    throw ErroImportacao(tr('o histórico não é JSON válido'));
  }
  if (dados is! List) throw ErroImportacao(tr('o ficheiro não é um histórico do verificador'));
  final porChave = <String, Importada>{};
  final entradas = [for (final e in dados) if (e is Map) e]
    ..sort((a, b) => '${a['data_hora']}'.compareTo('${b['data_hora']}'));
  for (final e in entradas) {
    final data = DateTime.tryParse('${e['data_hora']}');
    final resultados = e['resultados'];
    if (data == null || resultados is! List) continue;
    for (final r in resultados) {
      if (r is! Map) continue;
      final conta = contaDeDict(r['conta']);
      if (conta == null) continue;
      final ultima = UltimaVerificacao.deJson({
        'estado': r['estado'], 'motivo': r['motivo'], 'data': data.toIso8601String(),
        'validade': r['validade'], 'canais': r['canais'],
      });
      final k = chave(conta);
      // a entrada mais recente ganha; sem resultado (cancelada) mantém o anterior
      if (ultima != null || !porChave.containsKey(k)) {
        porChave[k] = Importada(conta, ultima ?? porChave[k]?.ultima);
      }
    }
  }
  return porChave.values.toList();
}

/// Decide pelo conteúdo (e pelo nome) o que é o ficheiro. `urlM3u`: como guardar uma M3U
/// local (o caminho do ficheiro), para a lista se poder abrir mais tarde.
List<Importada> importarFicheiro(String nome, String texto, {String? caminho}) {
  final n = nome.toLowerCase();
  final t = _semBom(texto).trimLeft();
  if (n.endsWith('.ini')) {
    final c = lerIni(texto, nome);
    if (c == null) throw ErroImportacao(tr('{0}: falta o Address ou o Mac', [nome]));
    return [Importada(c)];
  }
  if (pareceM3u(t)) {
    final alvo = caminho ?? nome;
    final uri = alvo.contains('://') ? alvo : Uri.file(alvo).toString();
    return [Importada(Conta(nome.replaceAll(RegExp(r'\.m3u8?$', caseSensitive: false), ''), Tipo.m3u, uri))];
  }
  if (t.startsWith('[') || t.startsWith('{')) {
    // histórico do verificador (entradas com "resultados") ou Accounts.json
    if (t.startsWith('[') && t.contains('"resultados"')) return lerHistoricoVerificador(texto);
    return [for (final c in lerAccountsJson(texto)) Importada(c)];
  }
  final linhas = lerLinhas(texto);
  if (linhas.isEmpty) throw ErroImportacao(tr('{0}: não foi encontrada nenhuma lista', [nome]));
  return [for (final c in linhas) Importada(c)];
}

String _semBom(String t) => t.startsWith('﻿') ? t.substring(1) : t;
