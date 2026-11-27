import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/desporto/onde_ver.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/protocolos/protocolo.dart';
import 'package:player_iptv/ui/design/mensagens.dart';
import 'package:player_iptv/ui/player/abrir_canal.dart';
import 'package:player_iptv/ui/player/cartao_erro.dart';
import 'package:player_iptv/ui/player/configuracao_mpv.dart';
import 'package:player_iptv/ui/player/player_canais.dart';
import 'package:player_iptv/ui/tema.dart';

import '../motor_falso.dart';

/// Guarda as mensagens mostradas (a troca de fonte avisa com uma).
class _Mensagens extends ControladorMensagens {
  final textos = <String>[];
  @override
  void mostrar(String texto,
      {MensagemTipo tipo = MensagemTipo.info,
      String? acao,
      VoidCallback? aoAcao,
      Duration duracao = const Duration(seconds: 4)}) {
    textos.add(texto);
  }
}

/// O mesmo canal em três listas.
const _fontes = [
  Canal(id: '11', nome: 'SPORT TV 1', grupo: 'PT'),
  Canal(id: '22', nome: 'SPORT TV 1 FHD', grupo: 'Desporto'),
  Canal(id: '33', nome: 'SPORTTV1', grupo: 'Portugal'),
];
const _listas = ['Lista A', 'Lista B', 'Lista C'];

typedef _Montado = ({MotorFalso motor, _Mensagens mensagens, List<int> pedidos, List<int> funcionou});

Future<_Montado> _montar(WidgetTester t,
    {required Future<FonteVideo> Function(int i) resolver, bool trocaAutomatica = true}) async {
  t.view.physicalSize = const Size(1920, 1080);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final motor = MotorFalso();
  final mensagens = _Mensagens();
  final pedidos = <int>[];
  final funcionou = <int>[];
  await t.pumpWidget(MaterialApp(
    theme: temaApp(),
    home: MensagensHost(
      controlador: mensagens,
      child: Scaffold(
        body: PlayerCanais(
          canais: _fontes,
          indice: 0,
          nomeLista: _listas.first,
          listaDe: (c) => _listas[_fontes.indexOf(c)],
          trocaAutomatica: trocaAutomatica,
          aoFuncionar: funcionou.add,
          aoSair: () {},
          resolver: (c, {continuar = false}) {
            final i = _fontes.indexOf(c);
            pedidos.add(i);
            return resolver(i);
          },
          criarMotor: (ModoDescodificacao modo, bool hardware) => motor,
        ),
      ),
    ),
  ));
  await t.pump();
  await t.pump();
  return (motor: motor, mensagens: mensagens, pedidos: pedidos, funcionou: funcionou);
}

Future<void> _abrirComImagem(WidgetTester t, MotorFalso m) async {
  m.tamanho(const Size(1920, 1080));
  await t.pump();
  m.tempo(Duration.zero);
  await t.pump();
  m.tempo(const Duration(milliseconds: 500));
  await t.pump();
}

Future<void> _sair(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

Future<FonteVideo> _ok(int i) async => FonteVideo('http://exemplo.invalido/$i.ts', const {});
Future<FonteVideo> _falha(int i) async => throw ErroLista('a lista não respondeu');

void main() {
  testWidgets('as 2 primeiras fontes falham: toca a 3.ª, com 2 mensagens e cada uma tentada uma vez', (t) async {
    final m = await _montar(t, resolver: (i) => i < 2 ? _falha(i) : _ok(i));
    await t.pump();
    await t.pump();
    expect(m.pedidos, [0, 1, 2]);
    expect(m.mensagens.textos, hasLength(2));
    expect(m.mensagens.textos.first, contains('Lista A'));
    expect(m.mensagens.textos.first, contains('Lista B'));
    expect(m.mensagens.textos.last, contains('Lista C'));
    expect(m.motor.aberturas.map((a) => a.url), ['http://exemplo.invalido/2.ts']);
    expect(find.byType(CartaoErroCanal), findsNothing);
    await _abrirComImagem(t, m.motor);
    expect(m.funcionou, [2], reason: 'o êxito fica para «funcionou da última vez»');
    await _sair(t);
  });

  testWidgets('um erro do motor (não do protocolo) também passa à fonte seguinte', (t) async {
    final m = await _montar(t, resolver: _ok);
    m.motor.erro('Failed to open http://exemplo.invalido/0.ts');
    await t.pump();
    await t.pump();
    expect(m.pedidos, [0, 1]);
    expect(m.motor.aberturas.last.url, 'http://exemplo.invalido/1.ts');
    await _sair(t);
  });

  testWidgets('as 3 falham: o cartão de erro diz quantas, e não se tenta outra vez', (t) async {
    final m = await _montar(t, resolver: _falha);
    await t.pump();
    await t.pump();
    expect(m.pedidos, [0, 1, 2]);
    expect(find.textContaining('Nenhuma das 3 fontes funcionou'), findsOneWidget);
    await t.pump(const Duration(seconds: 30));
    expect(m.pedidos, [0, 1, 2], reason: 'sem ciclo');
    await _sair(t);
  });

  testWidgets('sair durante a troca: nada mais abre', (t) async {
    final lenta = Completer<FonteVideo>();
    final m = await _montar(t, resolver: (i) => i == 0 ? _falha(i) : lenta.future);
    await t.pump();
    expect(m.pedidos, [0, 1]);
    await _sair(t);
    lenta.complete(const FonteVideo('http://exemplo.invalido/1.ts', {}));
    await t.pump(const Duration(seconds: 30));
    expect(m.motor.aberturas, isEmpty, reason: 'a fonte que chegou depois de sair não toca');
    expect(m.pedidos, [0, 1]);
  });

  testWidgets('sem troca automática, um erro mostra o cartão como antes', (t) async {
    final m = await _montar(t, resolver: _falha, trocaAutomatica: false);
    await t.pump();
    expect(m.pedidos, [0]);
    expect(find.byType(CartaoErroCanal), findsOneWidget);
    expect(m.mensagens.textos, isEmpty);
    await _sair(t);
  });

  group('fontes de várias listas', () {
    Lista lista(String id, String host) =>
        Lista(id: id, ordem: int.parse(id), conta: Conta('c$id', Tipo.xtream, 'http://$host', utilizador: 'u', password: 'p'));
    final fontes = [
      FonteCanal(lista('1', 'um.invalido'), _fontes[0], canalTv: 'sporttv1'),
      FonteCanal(lista('2', 'dois.invalido'), _fontes[1], canalTv: 'sporttv1'),
    ];

    test('o resolver da fonte 2 usa a conta da lista 2', () async {
      final r = resolverDasFontes(fontes);
      final f = await r(_fontes[1]);
      expect(f.url, startsWith('http://dois.invalido/'));
      expect(f.url, endsWith('/22.ts'));
      expect((await r(_fontes[0])).url, startsWith('http://um.invalido/'));
    });

    test('o tempo visto fica na lista da fonte que tocou', () {
      final somas = <(String, String)>[];
      final contar = tempoVistoDasFontes(fontes,
          criar: (id, nome) => (c, d) => somas.add((id, c.id)));
      contar(_fontes[1], const Duration(seconds: 15));
      contar(_fontes[0], const Duration(seconds: 15));
      expect(somas, [('2', '22'), ('1', '11')]);
    });
  });
}
