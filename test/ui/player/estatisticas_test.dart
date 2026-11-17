import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/player/estatisticas.dart';

Map<String, String> _mpv({double buffer = 8, String fps = '25', String ecra = '50'}) => {
      'hwdec-current': 'mediacodec',
      'video-codec': 'h264',
      'width': '1920',
      'height': '1080',
      'container-fps': fps,
      'display-fps': ecra,
      'demuxer-cache-duration': '$buffer',
      'paused-for-cache': 'no',
    };

void main() {
  testWidgets('lê o mpv a cada segundo e mostra os valores e o veredicto', (t) async {
    var leituras = 0;
    var buffer = 8.0;
    Future<Map<String, String>> ler() async {
      leituras++;
      return _mpv(buffer: buffer);
    }

    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: PainelEstatisticas(ler: ler, extra: const [('Modo', 'Direta (recomendada)')])),
    ));
    await t.pump();
    expect(leituras, 1);
    expect(find.text('Estatísticas'), findsOneWidget);
    expect(find.textContaining('1920×1080'), findsOneWidget);
    expect(find.textContaining('hardware (mediacodec)'), findsOneWidget);
    expect(find.textContaining('Direta (recomendada)'), findsOneWidget);
    expect(find.textContaining('a medir'), findsOneWidget, reason: 'só 1 amostra: ainda sem veredicto');

    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(leituras, 3);
    expect(find.textContaining('fluido'), findsOneWidget);

    buffer = 1.0; // o buffer a esvaziar
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(find.textContaining('rede (buffer a esvaziar)'), findsOneWidget);

    await t.pumpWidget(const SizedBox()); // sai: o temporizador para
    await t.pump(const Duration(seconds: 3));
    expect(leituras, 4);
  });

  testWidgets('outro canal (zapping): as amostras recomeçam, sem "rede" falsa', (t) async {
    var buffer = 20.0;
    Future<Map<String, String>> ler() async => _mpv(buffer: buffer);
    Widget painel(int canal) =>
        MaterialApp(home: Scaffold(body: PainelEstatisticas(ler: ler, geracao: canal)));

    await t.pumpWidget(painel(1));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    expect(find.textContaining('fluido'), findsOneWidget);

    buffer = 1.0; // o canal novo ainda está a encher o buffer
    await t.pumpWidget(painel(2));
    await t.pump();
    for (var i = 0; i < 3; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    expect(find.textContaining('rede (buffer'), findsNothing);
    expect(find.textContaining('fluido'), findsOneWidget);
  });

  testWidgets('Hz do sistema: 50 fps num ecrã a 60 Hz acusa o ecrã mesmo sem display-fps do mpv', (t) async {
    Future<Map<String, String>> ler() async => _mpv(fps: '50', ecra: '');
    await t.pumpWidget(MaterialApp(home: Scaffold(body: PainelEstatisticas(ler: ler, hzEcra: 60))));
    for (var i = 0; i < 3; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    expect(find.textContaining('60.00 (sistema)'), findsOneWidget);
    expect(find.textContaining('ecrã (imagens perdidas'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('uma leitura que falha não rebenta o painel', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: PainelEstatisticas(ler: () async => throw Exception('fechado'))),
    ));
    await t.pump();
    expect(find.text('Estatísticas'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
