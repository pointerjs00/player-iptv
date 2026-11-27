import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/desporto/casador.dart';
import 'package:player_iptv/desporto/modelo.dart';

/// Casar os jogos com as emissões dos canais (spec §7; Review Focus 1).
void main() {
  Jogo jogo(String id, String casa, String fora, DateTime inicio,
          {Desporto d = Desporto.futebol, bool feminino = false, String? torneio}) =>
      Jogo(id: id, desporto: d, competicaoId: 'x', casa: casa, fora: fora, inicio: inicio, feminino: feminino, torneio: torneio);
  Emissao emissao(String canal, String titulo, DateTime inicio,
          {String origem = 'meo', bool? direto, Duration duracao = const Duration(hours: 2), String? modalidade}) =>
      Emissao(canal: canal, inicio: inicio, fim: inicio.add(duracao), titulo: titulo, origem: origem, direto: direto,
          modalidade: modalidade);

  final h20 = DateTime.utc(2026, 11, 27, 20);

  test('Feyenoord–FC Porto: MEO (Provável) e Sport TV em direto (Confirmado) → fica a mais alta', () {
    final j = jogo('j', 'Feyenoord', 'FC Porto', h20);
    final t = casar([j], [
      emissao('sporttv1', 'Feyenoord x FC Porto - Liga dos Campeões', h20.subtract(const Duration(minutes: 5))),
      emissao('sporttv1', 'Futebol: FEYENOORD X FC PORTO - UEFA CHAMPIONS LEAGUE', h20, origem: 'sporttv', direto: true),
    ]);
    expect(t, hasLength(1));
    expect(t.single.canal, 'sporttv1');
    expect(t.single.confianca, Confianca.confirmado);
  });

  test('só a MEO: Provável; o EPG de uma lista: Possível', () {
    final j = jogo('j', 'Marítimo', 'Nacional', h20);
    expect(casar([j], [emissao('sporttv1', 'Marítimo x CD Nacional - Liga Portugal Betclic (Direto)', h20)]).single.confianca,
        Confianca.provavel);
    expect(casar([j], [emissao('sporttv1', 'Marítimo x CD Nacional', h20, origem: 'epg')]).single.confianca,
        Confianca.possivel);
  });

  test('ligado pelo id (guia de TV do FotMob): Confirmado', () {
    final j = jogo('fotmob:1', 'Marítimo', 'Nacional', h20);
    final t = casar([j], const [], ligadasPorId: [('fotmob:1', emissao('sporttv1', 'Marítimo x Nacional', h20, origem: 'fotmob'))]);
    expect(t.single.confianca, Confianca.confirmado);
    expect(t.single.origem, 'fotmob');
  });

  test('a equipa B não é a principal', () {
    final j = jogo('j', 'Sporting CP', 'Amarante FC', h20);
    expect(casar([j], [emissao('sportingtv', 'Sporting CP B x Amarante FC - Liga Portugal 2', h20)]), isEmpty);
  });

  test('um jogo masculino não casa com uma emissão feminina (e vice-versa)', () {
    final j = jogo('j', 'Benfica', 'Sporting', h20);
    expect(casar([j], [emissao('btv', 'Futebol Fem.: Benfica x Sporting - Liga BPI', h20)]), isEmpty);
    final f = jogo('f', 'Benfica', 'Sporting', h20, feminino: true);
    expect(casar([f], [emissao('btv', 'Futebol Fem.: Benfica x Sporting - Liga BPI', h20)]), hasLength(1));
  });

  test('a repetição da DAZN no dia seguinte e uma emissão 2 h depois não casam', () {
    final j = jogo('j', 'Ajax', 'FC Thun', DateTime.utc(2026, 11, 26, 20));
    expect(casar([j], [emissao('dazn2', 'Ajax x FC Thun - UEFA Conference League', DateTime.utc(2026, 11, 26, 22, 30))]),
        isEmpty);
    expect(casar([j], [emissao('dazn2', 'Ajax x FC Thun - UEFA Conference League', DateTime.utc(2026, 11, 27, 22, 30))]),
        isEmpty);
  });

  test('as repetições da Sport TV (não DIRETO) não casam', () {
    final j = jogo('j', 'Indiana Pacers', 'Oklahoma City Thunder', h20, d: Desporto.basquetebol);
    expect(
        casar([j], [
          emissao('sporttv2', 'Basquetebol: INDIANA PACERS X OKLAHOMA CITY THUNDER - NBA', h20,
              origem: 'sporttv', direto: false, modalidade: 'basquetebol'),
        ]),
        isEmpty);
  });

  test('antevisões e enchimento não casam', () {
    final j = jogo('j', 'Marítimo', 'Nacional', h20);
    expect(
        casar([j], [
          emissao('sporttv1', 'Futebol: ANTEVISÃO MARÍTIMO X CD NACIONAL - LIGA PORTUGAL', h20.subtract(const Duration(minutes: 20)),
              origem: 'sporttv', direto: true),
          emissao('sporttv1', 'Fora de Horas: Sem Transmissão', h20),
        ]),
        isEmpty);
  });

  test('outra modalidade com os mesmos nomes não casa (basquetebol do Benfica ≠ futebol)', () {
    final j = jogo('j', 'Benfica', 'Porto', h20);
    expect(casar([j], [emissao('btv', 'Basquetebol: Benfica x FC Porto - Liga Betclic', h20)]), isEmpty);
  });

  test('a ordem das equipas trocada (campo neutro) também casa', () {
    final j = jogo('j', 'Portugal', 'Espanha', h20);
    expect(casar([j], [emissao('rtp1', 'Espanha x Portugal - Liga das Nações', h20)]), hasLength(1));
  });

  test('ténis: a emissão do torneio cobre os encontros desse torneio (Possível)', () {
    final a = jogo('a', 'Jannik Sinner', 'Carlos Alcaraz', DateTime.utc(2026, 11, 15, 14), d: Desporto.tenis, torneio: 'ATP Finals');
    final b = jogo('b', 'Novak Djokovic', 'Taylor Fritz', DateTime.utc(2026, 11, 15, 20), d: Desporto.tenis, torneio: 'ATP Finals');
    final t = casar([a, b], [
      emissao('sporttv2', 'Ténis: ATP Finals (Direto)', DateTime.utc(2026, 11, 15, 13, 30), duracao: const Duration(hours: 3)),
    ]);
    expect(t.map((x) => (x.jogoId, x.confianca)), [('a', Confianca.possivel)]);
  });
}
