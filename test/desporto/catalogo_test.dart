import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/desporto/catalogo.dart';
import 'package:player_iptv/desporto/modelo.dart';

/// O catálogo das competições seguidas e dos canais portugueses (spec §4 e §5).
void main() {
  test('não há ids repetidos (competições, ids do FotMob e canais)', () {
    final ids = catalogoCompeticoes.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
    final fotmob = [for (final c in catalogoCompeticoes) if (c.fotmob != null) c.fotmob];
    expect(fotmob.toSet().length, fotmob.length);
    final canais = catalogoCanais.map((c) => c.id).toList();
    expect(canais.toSet().length, canais.length);
  });

  test('cada competição tem uma fonte (id ou nome no FotMob, ESPN ou FPB)', () {
    for (final c in catalogoCompeticoes) {
      expect(c.fotmob != null || c.fotmobNome != null || c.espn != null || c.fpb != null, isTrue, reason: c.id);
    }
  });

  test('as competições de futebol pedidas, com os ids confirmados a 27/11', () {
    Competicao por(int id) => catalogoCompeticoes.singleWhere((c) => c.fotmob == id);
    expect(por(61).nome, 'Liga Portugal Betclic');
    expect(por(40).nome, 'Pro League (Bélgica)');
    expect(por(186).nome, 'Taça de Portugal');
    expect(por(187).nome, 'Taça da Liga');
    expect(por(42).nome, 'Liga dos Campeões');
    expect(por(9806).desporto, Desporto.futebol);
    // 36 confirmadas + as que se reconhecem pelo nome (Taça do Rei, Liga das Nações B–D, qualificações)
    expect(catalogoCompeticoes.where((c) => c.desporto == Desporto.futebol && c.fotmob != null).length, 36);
    expect(catalogoCompeticoes.where((c) => c.fotmob == null && c.fotmobNome != null), isNotEmpty);
  });

  test('todas as de futebol são seguidas por omissão', () {
    for (final c in catalogoCompeticoes.where((c) => c.desporto == Desporto.futebol)) {
      expect(c.seguidaPorOmissao, isTrue, reason: c.id);
    }
  });

  test('cada canal tem nome, a MEO conhece os de desporto e o FotMob chama-os pelo nome', () {
    for (final c in catalogoCanais) {
      expect(c.nome, isNotEmpty);
      expect(c.alternativos, isNotEmpty, reason: c.id);
    }
    CanalTv canal(String id) => catalogoCanais.singleWhere((c) => c.id == id);
    expect(canal('sporttv1').meo, 'SPT1HD');
    expect(canal('sporttvmais').meo, 'SPTVHD');
    expect(canal('sporttvmais').sportTv, 'SPORT.TV +');
    expect(canal('dazn2').meo, 'DAZN2');
    expect(canal('btv').meo, 'SLBHD');
    expect(canal('eurosport1').meo, 'EURHD');
    expect(canalDoFotmob('Sport TV 1')?.id, 'sporttv1');
    expect(canalDoFotmob('Sport TV + Plus')?.id, 'sporttvmais');
    expect(canalDoFotmob('Canal 11')?.id, 'canal11');
    expect(canalDoFotmob('Fanatiz'), isNull);
    expect(canalDaSportTv('SPORT.TV3')?.id, 'sporttv3');
    expect(catalogoCanais.length, 25);
  });
}
