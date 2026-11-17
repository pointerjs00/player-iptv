import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/player/estatisticas.dart';

void main() {
  testWidgets('lê o mpv a cada segundo e mostra os valores e o veredicto', (t) async {
    var leituras = 0;
    var buffer = 8.0;
    Future<Map<String, String>> ler() async {
      leituras++;
      return {
        'hwdec-current': 'mediacodec',
        'video-codec': 'h264',
        'width': '1920',
        'height': '1080',
        'container-fps': '25',
        'display-fps': '50',
        'demuxer-cache-duration': '$buffer',
        'paused-for-cache': 'no',
      };
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
    expect(find.textContaining('fluido'), findsOneWidget);

    buffer = 1.0; // o buffer a esvaziar
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(leituras, 2);
    expect(find.textContaining('rede (buffer a esvaziar)'), findsOneWidget);

    await t.pumpWidget(const SizedBox()); // sai: o temporizador para
    await t.pump(const Duration(seconds: 3));
    expect(leituras, 2);
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
