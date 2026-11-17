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
    v.comecar();
    v.tocando(true);
    expect(abriu, 0);
  });

  test('I8: imagem (largura > 0) e buffering acabado contam como aberto', () {
    v.comecar();
    v.largura(1920);
    expect(abriu, 0);
    v.buffering(false);
    expect(abriu, 1);
  });

  test('I8: o tempo a andar com imagem também conta como aberto', () {
    v.comecar();
    v.largura(1280);
    v.tempo(const Duration(milliseconds: 500));
    expect(abriu, 1);
  });

  test('I8: um stream que não chega a dar imagem mostra o erro ao fim do prazo', () async {
    v.comecar();
    v.tocando(true);
    v.buffering(true);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(abriu, 0);
    expect(falhas, ['o canal não começou a tempo (sem imagem em 0.3 s)']);
  });

  test('I8: trocar de canal recomeça o prazo; depois de abrir não há erro', () async {
    v.comecar();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    v.comecar();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(falhas, isEmpty);
    v.largura(720);
    v.buffering(false);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(abriu, 1);
    expect(falhas, isEmpty);
  });
}
