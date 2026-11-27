/// O cliente das fontes dos «Jogos»: pede o texto de um endereço, usa a cache enquanto vale e,
/// sem rede, devolve a cache antiga marcada como velha.
library;

import 'dart:convert';

import '../rede/http.dart';
import 'armazem_desporto.dart';

class Resposta {
  const Resposta(this.valor, this.data, {this.velho = false});
  final String valor;

  /// Quando chegou da rede (UTC).
  final DateTime data;

  /// Passou da validade (não houve rede, ou só se podia usar a cache).
  final bool velho;
}

/// O que um adaptador leu, com a data e se é velho (para o ecrã dizer «dados de há 2 h»).
class Lido<T> {
  const Lido(this.dados, {this.data, this.velho = false});
  final T dados;
  final DateTime? data;
  final bool velho;

  static Lido<T> de<T>(Resposta? r, T Function(String) ler, T vazio) =>
      r == null ? Lido(vazio) : Lido(ler(r.valor), data: r.data, velho: r.velho);
}

/// "AAAAMMDD" (ou com `sep` entre as partes) do dia de calendário.
String diaTexto(DateTime dia, [String sep = '']) =>
    '${dia.year.toString().padLeft(4, '0')}$sep${dia.month.toString().padLeft(2, '0')}$sep${dia.day.toString().padLeft(2, '0')}';

/// Quanto tempo vale cada fonte (spec §6).
abstract final class Validade {
  static const jogosHoje = Duration(minutes: 30);
  static const jogosOutrosDias = Duration(hours: 6);
  static const guiaFotmob = Duration(hours: 1);
  static const meo = Duration(hours: 6);
  static const sportTv = Duration(hours: 3);
  static const espnHoje = Duration(minutes: 30);
  static const fpb = Duration(hours: 24);
}

typedef ObterTexto = Future<String> Function(Uri uri, Map<String, String> cabecalhos);

/// Identificação genérica (sem dados do utilizador).
const _cabecalhos = {'User-Agent': 'TVIntel/1.0', 'Accept': 'application/json, text/html;q=0.9, */*;q=0.5'};

Future<String> _obterDaRede(Uri uri, Map<String, String> cabecalhos) async =>
    utf8.decode(await obterBytes(uri.toString(), headers: cabecalhos, maxBytes: 8 * 1024 * 1024), allowMalformed: true);

class ClienteDesporto {
  ClienteDesporto(this.armazem, {ObterTexto? obter, DateTime Function()? agora})
      : _obter = obter ?? _obterDaRede,
        agora = agora ?? (() => DateTime.now().toUtc());

  final ArmazemDesporto armazem;
  final ObterTexto _obter;
  final DateTime Function() agora;

  /// O texto de `uri` (guardado em `chave`): da cache se tiver menos de `validade`, senão da
  /// rede. Sem rede, a cache antiga (`velho`); sem rede nem cache, o erro. Com `soCache`
  /// (dados móveis) não se pede nada: a cache (velha se passou da validade) ou null.
  Future<Resposta?> texto(String chave, Uri uri, Duration validade, {bool soCache = false}) async {
    final g = await armazem.ler(chave);
    final t = agora();
    if (g != null && t.difference(g.data) < validade) return Resposta(g.texto, g.data);
    if (soCache) return g == null ? null : Resposta(g.texto, g.data, velho: true);
    try {
      final novo = await _obter(uri, _cabecalhos);
      await armazem.gravar(chave, novo, t);
      return Resposta(novo, t);
    } catch (_) {
      if (g == null) rethrow;
      return Resposta(g.texto, g.data, velho: true);
    }
  }
}
