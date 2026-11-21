import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/vigia_abertura.dart';

void main() {
  late int abriu;
  late List<String> falhas;
  late VigiaAbertura v;
  setUp(() {
    abriu = 0;
    falhas = [];
    v = VigiaAbertura(
        aoAbrir: () => abriu++, aoFalhar: falhas.add, limite: const Duration(milliseconds: 300));
  });
  tearDown(() => v.parar());

  Duration ms(int n) => Duration(milliseconds: n);

  test('I8: playing=true (o media_kit diz isto logo no open) não tira o "a abrir"', () {
    v..comecar()..abrindo();
    v.tocando(true);
    expect(abriu, 0);
  });

  test('o stop() de dentro do open() (buffering=false, posição 0) não conta como aberto', () {
    // visto no emulador: o media_kit manda buffering=false e posição 0 ao parar o canal antigo
    // dentro do open(); a largura do vídeo chega logo a seguir, antes de haver imagem no ecrã
    v..comecar()..abrindo();
    v.buffering(false);
    v.tempo(Duration.zero);
    v.largura(1280);
    expect(abriu, 0, reason: 'ainda não há imagem no ecrã: o "a abrir" fica');
  });

  test('a largura e o fim do buffering, sem a posição andar, ainda não é imagem', () {
    v..comecar()..abrindo();
    v.buffering(true);
    v.largura(1920);
    v.tempo(ms(40));
    v.buffering(false);
    expect(abriu, 0);
  });

  test('com imagem, abre quando a posição anda 0,3 s (o vídeo está mesmo a tocar)', () {
    v..comecar()..abrindo();
    v.largura(1280);
    v.tempo(ms(40));
    v.tempo(ms(200));
    expect(abriu, 0);
    v.tempo(ms(340));
    expect(abriu, 1);
  });

  test('cache-pause-initial: a posição parada no buffer inicial não conta; abre quando anda', () {
    v..comecar()..abrindo();
    v.buffering(true);
    v.largura(1920);
    v.tempo(ms(50));
    v.tempo(ms(50));
    expect(abriu, 0);
    v.buffering(false);
    v.tempo(ms(60));
    v.tempo(ms(400));
    expect(abriu, 1);
    expect(falhas, isEmpty);
  });

  test('a posição a andar só com som (sem largura) não abre; conta a partir da imagem', () {
    v..comecar()..abrindo();
    v.tempo(ms(100));
    v.tempo(ms(900));
    expect(abriu, 0);
    v.largura(1280);
    v.tempo(ms(1000));
    expect(abriu, 0, reason: 'conta desde que há imagem');
    v.tempo(ms(1350));
    expect(abriu, 1);
  });

  test('um buffering a meio da abertura recomeça a contagem', () {
    v..comecar()..abrindo();
    v.largura(1280);
    v.tempo(ms(100));
    v.buffering(true);
    v.tempo(ms(450)); // o último valor antes da pausa
    expect(abriu, 0);
    v.buffering(false);
    v.tempo(ms(500));
    expect(abriu, 0);
    v.tempo(ms(820));
    expect(abriu, 1);
  });

  test('I8: um stream que não chega a dar imagem mostra o erro ao fim do prazo', () async {
    v..comecar()..abrindo();
    v.tocando(true);
    v.buffering(true);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(abriu, 0);
    expect(falhas, ['o canal não começou a tempo (sem imagem em 0.3 s)']);
  });

  test('I8: trocar de canal recomeça o prazo; depois de abrir não há erro', () async {
    v..comecar()..abrindo();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    v..comecar()..abrindo();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(falhas, isEmpty);
    v.largura(720);
    v.tempo(ms(10));
    v.tempo(ms(400));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(abriu, 1);
    expect(falhas, isEmpty);
  });

  test('I8 residual: o canal antigo (ainda a tocar enquanto o link novo se resolve) não conta', () {
    v..comecar()..abrindo();
    v.largura(1920);
    v.tempo(ms(10));
    v.tempo(ms(400));
    expect(abriu, 1);
    // cima/baixo: outro canal; o antigo continua a mandar posição e buffering
    v.comecar();
    v.tempo(const Duration(seconds: 5));
    v.buffering(false);
    v.largura(1920);
    v.tempo(const Duration(seconds: 6));
    expect(abriu, 1, reason: 'antes do open() deste pedido, os eventos são do canal antigo');
    v.abrindo();
    v.tempo(const Duration(seconds: 7));
    expect(abriu, 1, reason: 'a imagem do canal antigo não conta para o novo');
    v.largura(1280);
    v.tempo(ms(50));
    v.tempo(ms(400));
    expect(abriu, 2);
  });

  test('I8 residual: um canal novo que encrava mostra o erro mesmo com o antigo a andar', () async {
    v..comecar()..abrindo();
    v.largura(1920);
    v.tempo(ms(10));
    v.tempo(ms(400));
    v.comecar();
    v.tempo(const Duration(seconds: 5));
    v.abrindo();
    v.buffering(true);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(abriu, 1);
    expect(falhas, ['o canal não começou a tempo (sem imagem em 0.3 s)']);
  });

  test('M2: a primeira imagem no ecrã (dita pelo motor) abre logo, sem esperar pela posição', () {
    v.imagem(); // antes do open(): é do canal anterior
    expect(abriu, 0);
    v..comecar()..abrindo();
    v.imagem();
    expect(abriu, 1);
    v.tempo(ms(0));
    v.largura(1920);
    v.tempo(ms(500));
    expect(abriu, 1, reason: 'só uma vez');
  });
}
