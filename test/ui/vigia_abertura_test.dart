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

  test('I8: playing=true (o media_kit diz isto logo no open) não tira o "a abrir"', () {
    v..comecar()..abrindo();
    v.tocando(true);
    expect(abriu, 0);
  });

  test('I8: imagem (largura > 0) e buffering acabado contam como aberto', () {
    v..comecar()..abrindo();
    v.largura(1920);
    expect(abriu, 0);
    v.buffering(false);
    expect(abriu, 1);
  });

  test('I8: o tempo a andar com imagem também conta como aberto', () {
    v..comecar()..abrindo();
    v.largura(1280);
    v.tempo(const Duration(milliseconds: 500));
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
    v.buffering(false);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(abriu, 1);
    expect(falhas, isEmpty);
  });

  test('I8 residual: o canal antigo (ainda a tocar enquanto o link novo se resolve) não conta', () {
    v..comecar()..abrindo();
    v.largura(1920);
    v.buffering(false);
    expect(abriu, 1);
    // cima/baixo: outro canal; o antigo continua a mandar posição e buffering
    v.comecar();
    v.tempo(const Duration(seconds: 5));
    v.buffering(false);
    v.largura(1920);
    expect(abriu, 1, reason: 'antes do open() deste pedido, os eventos são do canal antigo');
    v.abrindo();
    v.tempo(const Duration(seconds: 6));
    expect(abriu, 1, reason: 'a imagem do canal antigo não conta para o novo');
    v.largura(1280);
    expect(abriu, 2);
  });

  test('I8 residual: um canal novo que encrava mostra o erro mesmo com o antigo a andar', () async {
    v..comecar()..abrindo();
    v.largura(1920);
    v.buffering(false);
    v.comecar();
    v.tempo(const Duration(seconds: 5));
    v.abrindo();
    v.buffering(true);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(abriu, 1);
    expect(falhas, ['o canal não começou a tempo (sem imagem em 0.3 s)']);
  });
}
