import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/modelo/conta.dart';

Map<String, dynamic> _d([Map<String, dynamic> extra = const {}]) =>
    {for (final k in camposConta) k: k == 'ForceUserAgent' ? false : '', ...extra};

void main() {
  test('nome da lista', () {
    final c = contaDeLinha('http://nxtbox.uk/c/ 00:1A:79:00:00:01')!;
    expect(nomeLista(3, c, '2027-10-16'), '003NXTBOX 161027');
    expect(nomeLista(4, c, 'sem limite'), '004NXTBOX');
    expect(nomeLista(5, c), '005NXTBOX');
    expect(nomeLista(12, contaDeLinha('http://www.Tv-Max.example.com:8080/c/ 00:1A:79:00:00:01')!),
        '012TV-MAX');
    expect(nomeLista(1, contaDeLinha('http://10.0.0.5:8080/c/ 00:1A:79:00:00:01')!), '00110.0.0.5');
    expect(nomeLista(1000, c), '1000NXTBOX');
  });

  test('a mesma lista escrita de outra forma tem a mesma chave', () {
    const mac = '00:1a:79:00:00:01';
    final variantes = ['http://nxtbox.uk', 'http://nxtbox.uk/c/', 'HTTP://NXTBOX.UK:80/c',
        'http://nxtbox.uk/c/portal.php'];
    final chaves = {for (final u in variantes) chave(contaDeLinha('$u $mac')!)};
    expect(chaves, hasLength(1));
    expect(chaves.contains(chave(contaDeLinha('http://nxtbox.uk:8080/c/ $mac')!)), isFalse);
    expect(chaves.contains(chave(contaDeLinha('http://nxtbox.uk/stalker_portal/c/ $mac')!)), isFalse);
    expect(chaves.contains(chave(contaDeLinha('http://nxtbox.uk/c/ 00:1A:79:00:00:02')!)), isFalse);
    expect(chave(contaDeLinha('http://x.com:80/get.php?username=u&password=p')!),
        chave(contaDeLinha('http://X.com/get.php?username=u&password=p&type=m3u')!));
    expect(chave(contaDeLinha('http://x.com/l.m3u?t=A')!) == chave(contaDeLinha('http://x.com/l.m3u?t=a')!),
        isFalse);
  });

  test('deduplicar junta variantes', () {
    final cs = [
      'http://h.com/c/ 00:1A:79:00:00:01', 'http://h.com 00:1a:79:00:00:01',
      'http://h.com:80/c/ 00:1A:79:00:00:01',
    ].map((l) => contaDeLinha(l)!);
    expect(deduplicar(cs), hasLength(1));
  });

  test('linhas', () {
    final s = contaDeLinha('http://h/c/ 00:1A:79:00:00:01')!;
    expect((s.tipo, s.nome), (Tipo.stalker, 'h'));
    expect(contaDeLinha('http://h:80/get.php?username=u&password=p&type=m3u')!.tipo, Tipo.xtream);
    expect(contaDeLinha('http://h/x.m3u')!.tipo, Tipo.m3u);
    expect(contaDeLinha('lixo'), isNull);
    expect(contaDeLinha(''), isNull);
  });

  test('xtream em dict com get.php e credenciais usa a raiz', () {
    final d = contaDeDict(_d({
      'Address': 'http://x.example:8080/get.php?username=u&password=p&type=m3u',
      'Username': 'u', 'Password': 'p',
    }))!;
    final l = contaDeLinha('http://x.example:8080/get.php?username=u&password=p')!;
    expect(d.endereco, 'http://x.example:8080');
    expect(chave(d), chave(l));
    expect((contaParaDict(d)['Address'] as String).endsWith('type=m3u'), isTrue);
  });

  test('link da conta', () {
    final stb = contaDeDict(_d({'Address': 'http://x:8080/c/', 'Mac': '00:1A:79:00:00:01'}))!;
    expect(linkConta(stb), 'http://x:8080/c/');
    final xt = contaDeDict(_d({'Address': 'http://x:8080/', 'Username': 'u 1', 'Password': 'p&2'}))!;
    expect(linkConta(xt), 'http://x:8080/get.php?username=u+1&password=p%262&type=m3u_plus&output=ts');
  });

  test('endpoints stalker', () {
    expect(endpointsStalker('http://h:8080/stalker_portal/c/'),
        ['http://h:8080/stalker_portal/server/load.php', 'http://h:8080/stalker_portal/c/portal.php']);
    expect(endpointsStalker('http://h/c/'), ['http://h/server/load.php', 'http://h/c/portal.php']);
  });

  test('conta vai e volta em JSON', () {
    final c = contaDeLinha('http://h/c/ 00:1A:79:00:00:01')!;
    final d = Conta.deJson(c.paraJson());
    expect(chave(d), chave(c));
  });
}
