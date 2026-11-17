/// Cópia de segurança: exporta e importa tudo o que a app guarda num só ficheiro `.json`.
///
/// Formato (versão 1): `{"formato": "player-iptv-copia", "versao": 1, "criada": ISO,
/// "biblioteca": {"canais_teste": [...], "listas": [...]}, "gestor": {"listas": [...]},
/// "preferencias": {...}}`. Cada lista leva a conta, o último resultado, os favoritos e o nome
/// próprio ([Lista.paraJson]). Campos novos (grupos escondidos, ordem de listagem) entram como
/// chaves novas dentro de cada lista ou secções novas, e quem lê ignora o que não conhece;
/// só uma mudança incompatível sobe o número da versão.
///
/// O ficheiro leva as credenciais das listas (como a própria biblioteca): é para guardar com
/// cuidado. Nunca vão para logs nem para mensagens de erro.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'area_gestor.dart';
import 'biblioteca.dart';
import 'preferencias.dart';

const _formato = 'player-iptv-copia';

/// A versão do formato que esta app escreve (e a mais recente que sabe ler).
const versaoCopia = 1;

/// O ficheiro não serve como cópia de segurança; [mensagem] já é para o utilizador.
class ErroCopia implements Exception {
  ErroCopia(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}

/// Juntar às listas atuais (sem duplicar) ou trocar tudo pelo conteúdo do ficheiro.
enum ModoRestauro { juntar, substituir }

/// O conteúdo já validado de um ficheiro de cópia de segurança.
class CopiaLida {
  CopiaLida({required this.versao, this.criada, this.player = const [], this.gestor = const [],
      this.canaisTeste, this.preferencias, required this.temPlayer, required this.temGestor});

  final int versao;
  final DateTime? criada;
  final List<Lista> player;
  final List<Lista> gestor;
  final List<String>? canaisTeste;
  final Map<String, dynamic>? preferencias;
  final bool temPlayer, temGestor;
}

/// O que uma restauração mudou.
class ResumoRestauro {
  const ResumoRestauro({this.listasPlayer = 0, this.listasGestor = 0, this.atualizadas = 0, this.removidas = 0});

  /// Listas novas no Player e no Gestor (ao substituir, todas as do ficheiro).
  final int listasPlayer, listasGestor;

  /// Listas que já existiam e ficaram com dados do ficheiro (favoritos, resultado, nome).
  final int atualizadas;

  /// Listas que saíram (só ao substituir).
  final int removidas;
}

/// O ficheiro da cópia (UTF-8, com indentação).
Uint8List codificarCopia(Biblioteca biblioteca, AreaGestor area, Preferencias preferencias, {DateTime? agora}) {
  final mapa = {
    'formato': _formato,
    'versao': versaoCopia,
    'criada': (agora ?? DateTime.now()).toUtc().toIso8601String(),
    'biblioteca': {
      'canais_teste': biblioteca.canaisTeste,
      'listas': [for (final l in biblioteca.listas) l.paraJson()],
    },
    'gestor': {'listas': [for (final l in area.listas) l.paraJson()]},
    'preferencias': preferencias.paraJson(),
  };
  return Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent(' ').convert(mapa)));
}

/// O nome sugerido para o ficheiro: "Player IPTV copia 2026-11-17.json".
String nomeFicheiroCopia([DateTime? agora]) {
  final d = agora ?? DateTime.now();
  String dois(int n) => n.toString().padLeft(2, '0');
  return 'Player IPTV copia ${d.year}-${dois(d.month)}-${dois(d.day)}.json';
}

/// Lê e valida o texto de um ficheiro de cópia. Lança [ErroCopia] (com mensagem legível, sem
/// mostrar o conteúdo) se não servir; nada se altera.
CopiaLida lerCopia(String texto) {
  final Object? raiz;
  try {
    raiz = jsonDecode(texto);
  } on FormatException {
    throw ErroCopia('O ficheiro não é uma cópia de segurança: não tem JSON válido.');
  }
  if (raiz is! Map || raiz['formato'] != _formato) {
    throw ErroCopia('Este ficheiro não é uma cópia de segurança do Player IPTV.');
  }
  final versao = raiz['versao'];
  if (versao is! int || versao < 1) {
    throw ErroCopia('A cópia de segurança não indica a versão e não se pode importar.');
  }
  if (versao > versaoCopia) {
    throw ErroCopia('Esta cópia foi criada por uma versão mais recente da app. Atualize a app para a importar.');
  }

  List<Lista>? listasDe(Object? seccao, String nome) {
    if (seccao == null) return null;
    final lista = seccao is Map ? seccao['listas'] : null;
    if (lista is! List) throw ErroCopia('A cópia de segurança está estragada: as listas $nome não se conseguem ler.');
    final r = <Lista>[];
    for (final (i, j) in lista.indexed) {
      final l = Lista.deJson(j);
      if (l == null) {
        throw ErroCopia('A cópia de segurança está estragada: a lista ${i + 1} $nome não se consegue ler.');
      }
      r.add(l);
    }
    return r;
  }

  final player = listasDe(raiz['biblioteca'], 'do Player');
  final gestor = listasDe(raiz['gestor'], 'do Gestor');
  if (player == null && gestor == null) {
    throw ErroCopia('A cópia de segurança está vazia: não tem listas nem do Player nem do Gestor.');
  }
  final ct = raiz['biblioteca'] is Map ? (raiz['biblioteca'] as Map)['canais_teste'] : null;
  final prefs = raiz['preferencias'];
  return CopiaLida(
    versao: versao,
    criada: DateTime.tryParse('${raiz['criada']}'),
    player: player ?? const [],
    gestor: gestor ?? const [],
    temPlayer: player != null,
    temGestor: gestor != null,
    canaisTeste: ct is List && ct.isNotEmpty ? [for (final c in ct) '$c'] : null,
    preferencias: prefs is Map ? Map<String, dynamic>.from(prefs) : null,
  );
}

/// Aplica a cópia. Ou fica tudo feito ou nada muda: se o Gestor não se grava depois do Player,
/// o Player volta ao que era. As definições aplicam-se (e gravam-se) no fim.
Future<ResumoRestauro> restaurarCopia(CopiaLida copia, ModoRestauro modo,
    {required Biblioteca biblioteca, required AreaGestor area, required Preferencias preferencias}) async {
  final substituir = modo == ModoRestauro.substituir;
  final p = await biblioteca.restaurar(copia.player, substituir: substituir, canaisTeste: copia.canaisTeste);
  final PlanoRestauro g;
  try {
    g = (await area.restaurar(copia.gestor, substituir: substituir)).plano;
  } catch (_) {
    await p.desfazer();
    rethrow;
  }
  await biblioteca.apagarCaches(p.plano.idsSemCache);
  if (copia.preferencias != null) {
    preferencias.aplicar(copia.preferencias!);
    await preferencias.guardar();
  }
  return ResumoRestauro(
    listasPlayer: p.plano.novas,
    listasGestor: g.novas,
    atualizadas: p.plano.atualizadas + g.atualizadas,
    removidas: p.plano.removidas + g.removidas,
  );
}
