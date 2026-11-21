import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/leitor_partilhado.dart';

void main() {
  late List<List<String>> pedidos;
  late DateTime t;
  late LeitorPartilhado leitor;
  setUp(() {
    pedidos = [];
    t = DateTime(2026, 11, 18, 21);
    leitor = LeitorPartilhado((ps) async {
      pedidos.add(ps);
      return {for (final p in ps) p: '$p@${t.second}'};
    }, agora: () => t);
  });

  test('lê de uma vez só o que falta; o que foi lido há pouco vem da memória', () async {
    expect(await leitor.ler(['time-pos', 'width']), {'time-pos': 'time-pos@0', 'width': 'width@0'});
    t = t.add(const Duration(milliseconds: 200));
    expect(await leitor.ler(['width', 'height']), {'width': 'width@0', 'height': 'height@0'});
    expect(pedidos, [
      ['time-pos', 'width'],
      ['height'],
    ]);
  });

  test('passada a validade, lê de novo', () async {
    await leitor.ler(['time-pos']);
    t = t.add(const Duration(seconds: 1));
    expect(await leitor.ler(['time-pos']), {'time-pos': 'time-pos@1'});
    expect(pedidos, hasLength(2));
  });

  test('tudo na memória: nenhum pedido', () async {
    await leitor.ler(['a', 'b']);
    await leitor.ler(['b']);
    expect(pedidos, hasLength(1));
  });

  test('esquecer (depois de um seek, ao mudar de canal): a leitura seguinte é nova', () async {
    await leitor.ler(['time-pos']);
    leitor.esquecer();
    await leitor.ler(['time-pos']);
    expect(pedidos, hasLength(2));
  });

  test('uma leitura que acaba depois de esquecer não volta a pôr valores velhos na memória', () async {
    final f = leitor.ler(['time-pos']);
    leitor.esquecer();
    await f;
    await leitor.ler(['time-pos']);
    expect(pedidos, hasLength(2));
  });
}
