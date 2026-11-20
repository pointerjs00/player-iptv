import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/player/estatisticas.dart';
import 'package:player_iptv/ui/player/motor_reproducao.dart';

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

  // um desenho de `ms` milissegundos (construção + rasterização), a começar em `inicioMs`
  FrameTiming desenho(int inicioMs, {int constroi = 2, int raster = 3}) {
    int us(int ms) => ms * 1000;
    return FrameTiming(
      vsyncStart: us(inicioMs),
      buildStart: us(inicioMs),
      buildFinish: us(inicioMs + constroi),
      rasterStart: us(inicioMs + constroi),
      rasterFinish: us(inicioMs + constroi + raster),
      rasterFinishWallTime: us(inicioMs + constroi + raster),
    );
  }

  group('MedidorDesenho', () {
    test('sem desenhos: sem valores', () {
      final m = MedidorDesenho();
      expect(m.imagensPorSegundo, isNull);
      expect(m.tempoMedioMs, isNull);
    });

    test('60 desenhos num segundo (os tempos das próprias imagens): 60/s e o tempo médio', () {
      final m = MedidorDesenho();
      m.registar([for (var i = 0; i < 60; i++) desenho(i * 1000 ~/ 60 + 5000)]);
      expect(m.imagensPorSegundo, closeTo(60, 1));
      expect(m.tempoMedioMs, closeTo(5, 0.01));
    });

    test('só conta o último segundo e guarda poucas amostras', () {
      final m = MedidorDesenho();
      m.registar([for (var i = 0; i < 500; i++) desenho(i * 100)]); // 10/s durante 50 s
      expect(m.imagensPorSegundo, closeTo(10, 1));
      expect(m.amostras, lessThanOrEqualTo(MedidorDesenho.maximo));
    });
  });

  group('linhas do desenho', () {
    test('mpv: as duas linhas, sem nota', () {
      final m = MedidorDesenho()..registar([for (var i = 0; i < 30; i++) desenho(i * 33)]);
      final l = linhasDesenho(m);
      expect(l.map((e) => e.$1), ['Imagens desenhadas/s (interface)', 'Tempo de desenho']);
      expect(l[1].$2, '5.0 ms');
      expect(l[0].$2, isNot(contains('interface')));
    });

    test('ExoPlayer: a nota diz que só se mede a interface por cima do vídeo', () {
      final m = MedidorDesenho()..registar([desenho(0)]);
      final l = linhasDesenho(m, soInterface: true);
      expect(l[0].$2, contains('(só a interface por cima do vídeo)'));
    });

    test('sem desenhos: traços', () {
      final l = linhasDesenho(MedidorDesenho());
      expect(l.map((e) => e.$2), ['—', '—']);
    });
  });

  testWidgets('o painel mostra as duas linhas, alimentadas pelos tempos do Flutter (mpv)', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PainelEstatisticas(ler: () async => _mpv())),
      ),
    );
    await t.pump();
    expect(find.text('Imagens desenhadas/s (interface)'), findsOneWidget);
    expect(find.text('Tempo de desenho'), findsOneWidget);
    t.binding.platformDispatcher.onReportTimings!([for (var i = 0; i < 20; i++) desenho(i * 50)]);
    await t.pump(const Duration(seconds: 1));
    expect(find.text('5.0 ms'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('com o ExoPlayer as duas linhas também aparecem, com a nota', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PainelEstatisticas(lerMotor: () async => const EstatisticasMotor(), soInterface: true)),
      ),
    );
    await t.pump();
    expect(find.text('Imagens desenhadas/s (interface)'), findsOneWidget);
    expect(find.text('Tempo de desenho'), findsOneWidget);
    expect(find.textContaining('só a interface por cima do vídeo'), findsWidgets);
    await t.pumpWidget(const SizedBox());
  });
}
