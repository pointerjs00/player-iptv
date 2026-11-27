/// Casar os jogos com as emissões das grelhas (spec §7): as duas equipas, a hora de início, o
/// género e a modalidade; antevisões, resumos e repetições ficam de fora. A confiança vem da
/// fonte: ligado pelo id (FotMob) ou Sport TV em DIRETO → Confirmado; MEO → Provável; EPG de
/// uma lista ou só o torneio (ténis) → Possível.
library;

import '../modelo/canal.dart' show semAcentos;
import 'modelo.dart';
import 'nomes.dart';

/// A emissão do jogo começa entre isto antes…
const antesDoInicio = Duration(minutes: 30);

/// …e isto depois do início do jogo.
const depoisDoInicio = Duration(minutes: 15);

const _modalidades = {
  Desporto.futebol: 'futebol',
  Desporto.tenis: 'tenis',
  Desporto.basquetebol: 'basquetebol',
};

bool _mesmaModalidade(Jogo j, Emissao e, TituloEmissao t) {
  final m = t.modalidade ?? e.modalidade;
  if (m == null) return true; // sem modalidade no título: a hora e as equipas decidem
  return semAcentos(m).startsWith(_modalidades[j.desporto]!);
}

bool _aHora(Jogo j, Emissao e) =>
    !e.inicio.isBefore(j.inicio.subtract(antesDoInicio)) && !e.inicio.isAfter(j.inicio.add(depoisDoInicio));

bool _equipas(Jogo j, TituloEmissao t) {
  final a = t.casa, b = t.fora;
  if (a == null || b == null) return false;
  bool igual(String x, String nome, String? curto) => mesmaEquipa(x, nome) || (curto != null && mesmaEquipa(x, curto));
  return (igual(a, j.casa, j.casaCurto) && igual(b, j.fora, j.foraCurto)) ||
      (igual(a, j.fora, j.foraCurto) && igual(b, j.casa, j.casaCurto));
}

bool _torneio(Jogo j, Emissao e, TituloEmissao t) {
  final torneio = j.torneio, comp = t.competicao ?? e.evento;
  if (torneio == null || comp == null || t.casa != null) return false;
  final a = semAcentos(torneio).trim(), b = semAcentos(comp).trim();
  if (a.isEmpty || b.isEmpty || !(a.contains(b) || b.contains(a))) return false;
  return !j.inicio.isBefore(e.inicio) && j.inicio.isBefore(e.fim);
}

Confianca _confianca(Emissao e) => switch (e.origem) {
      'sporttv' || 'fotmob' => Confianca.confirmado,
      // o EPG das listas: a mesma grelha, mas sem a garantia da fonte oficial
      'epg' => e.direto == true ? Confianca.provavel : Confianca.possivel,
      _ => Confianca.possivel,
    };

/// O que se sabe sem grelha: os jogos em casa do Benfica na Liga Portugal dão na BTV (o Benfica
/// tem os direitos dos jogos em casa).
List<Transmissao> transmissoesConhecidas(List<Jogo> jogos) => [
      for (final j in jogos)
        if (j.competicaoId == 'liga-portugal' && !j.feminino && mesmaEquipa(j.casa, 'Benfica'))
          Transmissao(jogoId: j.id, canal: 'btv', confianca: Confianca.provavel, origem: 'regra'),
    ];

/// As transmissões (uma por jogo e canal, com a confiança mais alta).
List<Transmissao> casar(List<Jogo> jogos, List<Emissao> emissoes, {List<(String, Emissao)> ligadasPorId = const []}) {
  final melhor = <(String, String), Transmissao>{};
  void juntar(Transmissao t) {
    final k = (t.jogoId, t.canal);
    final antes = melhor[k];
    if (antes == null || t.confianca.index > antes.confianca.index) melhor[k] = t;
  }

  final ids = {for (final j in jogos) j.id};
  for (final (id, e) in ligadasPorId) {
    if (ids.contains(id)) juntar(Transmissao(jogoId: id, canal: e.canal, confianca: Confianca.confirmado, origem: e.origem));
  }
  final titulos = [for (final e in emissoes) lerTitulo(e.titulo)];
  for (final j in jogos) {
    for (final (k, e) in emissoes.indexed) {
      final t = titulos[k];
      if (t == null || e.direto == false || t.feminino != j.feminino || !_mesmaModalidade(j, e, t)) continue;
      if (_aHora(j, e) && _equipas(j, t)) {
        juntar(Transmissao(jogoId: j.id, canal: e.canal, confianca: _confianca(e), origem: e.origem));
      } else if (j.desporto == Desporto.tenis && _torneio(j, e, t)) {
        juntar(Transmissao(jogoId: j.id, canal: e.canal, confianca: Confianca.possivel, origem: e.origem));
      }
    }
  }
  return melhor.values.toList();
}
