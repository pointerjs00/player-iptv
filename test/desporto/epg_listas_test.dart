import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/desporto/armazem_desporto.dart';
import 'package:player_iptv/desporto/casador.dart';
import 'package:player_iptv/desporto/cliente_desporto.dart';
import 'package:player_iptv/desporto/fontes/epg_listas.dart';
import 'package:player_iptv/desporto/modelo.dart';
import 'package:player_iptv/desporto/onde_ver.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';

class _Fontes extends ChangeNotifier implements FontesDosCanais {
  _Fontes(this.porCanal);
  final Map<String, List<FonteCanal>> porCanal;
  @override
  List<FonteCanal> fontes(String canalTv) => porCanal[canalTv] ?? const [];
  @override
  int get listasSemCache => 0;
  @override
  Future<void> atualizar() async {}
}

Lista _lista(String id, Tipo tipo) => Lista(id: id, ordem: int.parse(id), conta: Conta('c$id', tipo, 'http://l$id.invalido'));

String _b64(String s) => base64.encode(utf8.encode(s));
int _s(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

/// A programação dos canais portugueses tirada das próprias listas (Xtream e portal MAC).
void main() {
  final dia = DateTime(2026, 11, 30);
  final jogo = DateTime.utc(2026, 11, 30, 20, 15);

  group('leitura', () {
    test('Xtream (get_simple_data_table): títulos em base64 e horas em segundos', () {
      final ps = lerEpgXtream({
        'epg_listings': [
          {'title': _b64('Benfica x Famalicão - Liga Portugal (Direto)'), 'start_timestamp': '${_s(jogo)}',
              'stop_timestamp': '${_s(jogo.add(const Duration(hours: 2)))}'},
          {'title': _b64('Lixo'), 'start_timestamp': 'x', 'stop_timestamp': '1'},
        ],
      });
      expect(ps, hasLength(1));
      expect(ps.single.titulo, 'Benfica x Famalicão - Liga Portugal (Direto)');
      expect(ps.single.inicio, jogo);
    });

    test('portal MAC (get_simple_data_table): o nome e as horas', () {
      final ps = lerEpgStalker({
        'js': {
          'data': [
            {'name': 'Benfica x Famalicão', 'start_timestamp': _s(jogo), 'stop_timestamp': _s(jogo) + 7200},
          ],
        },
      });
      expect(ps.single.titulo, 'Benfica x Famalicão');
      expect(ps.single.fim, jogo.add(const Duration(hours: 2)));
    });
  });

  group('grelha das listas', () {
    late Directory pasta;
    late ClienteDesporto cliente;
    late List<(String, String)> pedidos; // (lista, canal)
    setUp(() async {
      pasta = Directory.systemTemp.createTempSync('epg_listas');
      cliente = ClienteDesporto(await ArmazemDesporto.abrir(pasta), agora: () => DateTime.utc(2026, 11, 27, 19));
      pedidos = [];
    });
    tearDown(() => pasta.deleteSync(recursive: true));

    final m3u = FonteCanal(_lista('1', Tipo.m3u), const Canal(id: 'a', nome: 'BTV', grupo: 'PT'), canalTv: 'btv');
    final falha = FonteCanal(_lista('2', Tipo.xtream), const Canal(id: 'b', nome: 'BTV HD', grupo: 'PT'), canalTv: 'btv');
    final boa = FonteCanal(_lista('3', Tipo.stalker), const Canal(id: 'c', nome: 'BENFICA TV', grupo: 'PT'), canalTv: 'btv');

    Future<List<ProgramaEpg>> obter(Conta conta, Canal canal, DateTime d) async {
      pedidos.add((conta.nome, canal.id));
      if (canal.id == 'b') throw const SocketException('não respondeu');
      return [
        (inicio: jogo, fim: jogo.add(const Duration(hours: 2)), titulo: 'Futebol: SL Benfica x FC Famalicão (Direto)'),
        // de outro dia: fica de fora
        (inicio: jogo.add(const Duration(days: 2)), fim: jogo.add(const Duration(days: 2, hours: 2)), titulo: 'Outro'),
      ];
    }

    test('as listas M3U não têm guia; uma que falha passa à seguinte; o resultado vira emissão do canal', () async {
      final l = await grelhaDasListas(cliente, _Fontes({'btv': [m3u, falha, boa]}), dia, obter: obter);
      expect(pedidos, [('c2', 'b'), ('c3', 'c')]);
      final e = l.dados.single;
      expect(e.canal, 'btv');
      expect(e.origem, 'epg');
      expect(e.direto, isTrue);
      expect(e.inicio, jogo);
    });

    test('fica em cache: a 2.ª vez não pede nada; em dados móveis só a cache', () async {
      await grelhaDasListas(cliente, _Fontes({'btv': [boa]}), dia, obter: obter);
      pedidos.clear();
      final l = await grelhaDasListas(cliente, _Fontes({'btv': [boa]}), dia, obter: obter);
      expect(pedidos, isEmpty);
      expect(l.dados, hasLength(1));
      final sem = await grelhaDasListas(cliente, _Fontes({'btv': [boa]}), DateTime(2026, 12, 1), obter: obter, soCache: true);
      expect(pedidos, isEmpty);
      expect(sem.dados, isEmpty);
    });

    test('casa com o jogo como Provável (direto no EPG)', () async {
      final l = await grelhaDasListas(cliente, _Fontes({'btv': [boa]}), dia, obter: obter);
      final j = Jogo(
          id: 'fotmob:5887688', desporto: Desporto.futebol, competicaoId: 'liga-portugal',
          casa: 'Benfica', fora: 'Famalicão', inicio: jogo);
      final t = casar([j], l.dados).single;
      expect(t.canal, 'btv');
      expect(t.confianca, Confianca.provavel);
    });

    test('todas as fontes falharam: é uma falha (o estado diz que as listas não deram o guia)', () async {
      expect(() => grelhaDasListas(cliente, _Fontes({'btv': [falha]}), dia, obter: obter), throwsA(isA<SocketException>()));
    });
  });

  group('regra: os jogos em casa do Benfica na Liga dão na BTV', () {
    Jogo j(String casa, String fora, {String comp = 'liga-portugal'}) => Jogo(
        id: 'x:$casa', desporto: Desporto.futebol, competicaoId: comp, casa: casa, fora: fora,
        inicio: DateTime.utc(2026, 11, 30, 20, 15));

    test('em casa, na Liga Portugal → BTV, Provável', () {
      final t = transmissoesConhecidas([j('Benfica', 'Famalicão')]).single;
      expect((t.canal, t.confianca, t.origem), ('btv', Confianca.provavel, 'regra'));
    });

    test('fora de casa, noutra competição ou a equipa B → nada', () {
      expect(transmissoesConhecidas([j('Famalicão', 'Benfica'), j('Benfica', 'Ajax', comp: 'champions'), j('Benfica B', 'Feirense')]),
          isEmpty);
    });
  });
}
