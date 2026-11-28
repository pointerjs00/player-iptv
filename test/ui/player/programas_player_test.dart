import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/guia/programa.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/ui/player/configuracao_mpv.dart';
import 'package:player_iptv/ui/player/player_canais.dart';
import 'package:player_iptv/ui/tema.dart';

import '../motor_falso.dart';

const _canais = [
  Canal(id: '1', nome: 'RTP 1', grupo: 'PT'),
  Canal(id: '2', nome: 'SIC', grupo: 'PT'),
];

/// Um programa de uma hora que começou há 10 minutos, e o seguinte.
(Programa?, Programa?) _agoraE(String atual, String seguinte) {
  final agora = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final inicio = agora - 600;
  return (Programa(inicio, inicio + 3600, atual), Programa(inicio + 3600, inicio + 5400, seguinte));
}

/// A barra do player: o programa a dar e o seguinte do canal que toca.
void main() {
  testWidgets('a barra mostra o programa atual e o seguinte, e muda com o canal e com o tempo', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final motor = MotorFalso();
    final guia = {'1': _agoraE('Telejornal', 'Prós e Contras'), '2': _agoraE('Jornal da Noite', 'Casados')};
    final pedidos = <String>[];
    await t.pumpWidget(MaterialApp(
      theme: temaApp(),
      home: Scaffold(
        body: PlayerCanais(
          canais: _canais,
          indice: 0,
          nomeLista: 'Lista A',
          aoSair: () {},
          resolver: (c, {continuar = false}) async => FonteVideo('http://exemplo.invalido/${c.id}.ts', const {}),
          criarMotor: (ModoDescodificacao modo, bool hardware) => motor,
          programasDe: (c) async {
            pedidos.add(c.id);
            return guia[c.id] ?? (null, null);
          },
        ),
      ),
    ));
    await t.pump();
    await t.pump();
    Future<void> mostrarBarra() async {
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
    }

    Future<void> esconderBarra() async {
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
    }

    await mostrarBarra();
    expect(find.text('Telejornal'), findsOneWidget);
    expect(find.text('Prós e Contras'), findsOneWidget);
    expect(find.text('AGORA'), findsOneWidget);
    expect(find.text('A SEGUIR'), findsOneWidget);
    expect(t.takeException(), isNull, reason: 'a barra com a programação cabe');

    await esconderBarra();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp); // o canal seguinte
    await t.pumpAndSettle();
    await mostrarBarra();
    expect(find.text('SIC'), findsWidgets);
    expect(find.text('Jornal da Noite'), findsOneWidget);
    expect(find.text('Casados'), findsOneWidget);
    expect(find.text('Telejornal'), findsNothing, reason: 'o programa do canal anterior não fica');

    // o programa acaba: a leitura seguinte (a cada 30 s) já traz o novo
    await esconderBarra();
    guia['2'] = _agoraE('Casados', 'Notícias');
    await t.pump(const Duration(seconds: 31));
    await mostrarBarra();
    expect(find.text('Notícias'), findsOneWidget);
    expect(pedidos.where((p) => p == '2').length, greaterThanOrEqualTo(2));

    // sem programação para o canal, a barra fica como era (sem «AGORA»)
    await esconderBarra();
    guia.remove('2');
    await t.pump(const Duration(seconds: 31));
    await mostrarBarra();
    expect(find.text('AGORA'), findsNothing);

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
