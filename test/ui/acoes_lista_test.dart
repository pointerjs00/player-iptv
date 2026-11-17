import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/inicio/acoes_lista.dart';

void main() {
  group('contaEditada (validação do "Editar")', () {
    final stalker = Conta('Sala', Tipo.stalker, 'http://a.com/c/', mac: '00:1A:79:00:00:01',
        original: {'Name': 'Sala', 'Address': 'http://a.com/c/', 'Mac': '00:1A:79:00:00:01', 'SerialNumber': 'S1'});

    test('MAC muda (minúsculas aceites) e os outros campos do original ficam', () {
      final r = contaEditada(stalker, endereco: ' http://a.com/c/ ', mac: '00:1a:79:00:00:02', utilizador: '', password: '');
      expect(r.erros, isEmpty);
      expect(r.conta!.tipo, Tipo.stalker);
      expect(r.conta!.mac, '00:1A:79:00:00:02');
      expect(r.conta!.nome, 'Sala');
      expect(r.conta!.original!['SerialNumber'], 'S1');
      expect(r.conta!.original!['Mac'], '00:1A:79:00:00:02');
    });

    test('sem MAC, com utilizador e password: Xtream; só um dos dois é erro', () {
      final x = contaEditada(stalker, endereco: 'http://h.com:8080', mac: '', utilizador: 'u', password: 'p');
      expect(x.conta!.tipo, Tipo.xtream);
      expect((x.conta!.utilizador, x.conta!.password), ('u', 'p'));
      final e = contaEditada(stalker, endereco: 'http://h.com:8080', mac: '', utilizador: 'u', password: '');
      expect(e.conta, isNull);
      expect(e.erros.keys, contains('password'));
    });

    test('só o endereço: M3U', () {
      final r = contaEditada(stalker, endereco: 'http://h.com/l.m3u', mac: '', utilizador: '', password: '');
      expect(r.conta!.tipo, Tipo.m3u);
    });

    test('endereço vazio ou sem http(s); MAC inválido', () {
      expect(contaEditada(stalker, endereco: '', mac: '', utilizador: '', password: '').erros.keys, contains('endereco'));
      expect(contaEditada(stalker, endereco: 'ftp://x', mac: '', utilizador: '', password: '').erros.keys,
          contains('endereco'));
      expect(contaEditada(stalker, endereco: 'http://', mac: '', utilizador: '', password: '').erros.keys,
          contains('endereco'));
      expect(contaEditada(stalker, endereco: 'http://a.com/c/', mac: '00:1A:79', utilizador: '', password: '').erros.keys,
          contains('mac'));
    });
  });

  test('linkParaCopiar: Stalker "portal MAC" (cola-se em "Adicionar"), Xtream get.php, M3U a lista', () {
    expect(linkParaCopiar(Conta('', Tipo.stalker, 'http://a.com/c/', mac: '00:1A:79:00:00:01')),
        'http://a.com/c/ 00:1A:79:00:00:01');
    expect(linkParaCopiar(Conta('', Tipo.xtream, 'http://h.com:8080', utilizador: 'u', password: 'p')),
        startsWith('http://h.com:8080/get.php?username=u&password=p'));
    expect(linkParaCopiar(Conta('', Tipo.m3u, 'http://h.com/l.m3u')), 'http://h.com/l.m3u');
  });
}
