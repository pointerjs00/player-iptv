import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/dados/copia_seguranca.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/importar/m3u.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';

Importada _imp(String linha) => Importada(contaDeLinha(linha)!, null);

const _rtp = Canal(id: 'c1', nome: 'RTP 1', grupo: 'Portugal', logo: 'http://l/rtp.png', numero: 101);

void main() {
  late Directory pasta, pasta2;
  setUp(() {
    pasta = Directory.systemTemp.createTempSync('nav');
    pasta2 = Directory.systemTemp.createTempSync('nav2');
  });
  tearDown(() {
    for (final p in [pasta, pasta2]) {
      try {
        p.deleteSync(recursive: true);
      } on FileSystemException {/* Windows */}
    }
  });

  group('Canal: número do portal', () {
    test('vai e volta no JSON (sem número fica null)', () {
      expect(Canal.deJson(_rtp.paraJson()).numero, 101);
      expect(Canal.deJson(const Canal(id: 'x', nome: 'X', grupo: 'G').paraJson()).numero, isNull);
    });

    test('M3U: o tvg-chno é o número', () {
      final c = lerM3u('#EXTM3U\n#EXTINF:-1 tvg-chno="7" group-title="G",Sete\nhttp://s/7\n'
          '#EXTINF:-1 group-title="G",Sem\nhttp://s/8\n');
      expect(c.canais.map((x) => x.numero), [7, null]);
    });
  });

  group('Biblioteca: grupos escondidos e ordem, por lista', () {
    test('esconder/mostrar e ordenar persistem só nessa lista', () async {
      final b = await Biblioteca.abrir(pasta);
      await b.adicionar([_imp('http://a.com/l.m3u'), _imp('http://b.com/l.m3u')]);
      final a = b.listas.first.id;
      await b.esconderGrupo(a, 'Adultos', true);
      await b.esconderGrupo(a, 'UK', true);
      await b.esconderGrupo(a, 'UK', false);
      await b.definirOrdem(a, OrdemCanais.az);
      final r = await Biblioteca.abrir(pasta);
      expect(r.listas.first.gruposEscondidos, {'Adultos'});
      expect(r.listas.first.ordemCanais, OrdemCanais.az);
      expect(r.listas.last.gruposEscondidos, isEmpty);
      expect(r.listas.last.ordemCanais, OrdemCanais.lista);
    });

    test('ordenarCanais: A–Z sem acentos nem maiúsculas; "lista" mantém a ordem', () {
      const cs = [
        Canal(id: '1', nome: 'sic', grupo: 'G'),
        Canal(id: '2', nome: 'Água TV', grupo: 'G'),
        Canal(id: '3', nome: 'BBC', grupo: 'G'),
      ];
      expect(ordenarCanais(cs, OrdemCanais.az).map((c) => c.id), ['2', '3', '1']);
      expect(identical(ordenarCanais(cs, OrdemCanais.lista), cs), isTrue);
    });
  });

  group('Biblioteca: último canal visto', () {
    test('regista, persiste, e some com a lista', () async {
      final b = await Biblioteca.abrir(pasta);
      await b.adicionar([_imp('http://a.com/l.m3u')]);
      final id = b.listas.single.id;
      expect(b.ultimoVisto, isNull);
      await b.registarVisto(id, _rtp);
      final r = await Biblioteca.abrir(pasta);
      final u = r.ultimoVisto!;
      expect((u.lista, u.canal, u.nome, u.grupo, u.logo), (id, 'c1', 'RTP 1', 'Portugal', 'http://l/rtp.png'));
      await r.remover(id);
      expect(r.ultimoVisto, isNull);
      expect((await Biblioteca.abrir(pasta)).ultimoVisto, isNull);
    });

    test('uma lista que não existe não se regista', () async {
      final b = await Biblioteca.abrir(pasta);
      await b.registarVisto('nada', _rtp);
      expect(b.ultimoVisto, isNull);
    });
  });

  group('Cópia de segurança: grupos escondidos, ordem e último visto', () {
    Future<(Biblioteca, AreaGestor)> encher() async {
      final b = await Biblioteca.abrir(pasta);
      final area = await AreaGestor.abrir(pasta);
      await b.adicionar([_imp('http://a.com/l.m3u'), _imp('http://b.com/l.m3u')]);
      await b.esconderGrupo(b.listas.last.id, 'Adultos', true);
      await b.definirOrdem(b.listas.last.id, OrdemCanais.az);
      await b.registarVisto(b.listas.last.id, _rtp);
      return (b, area);
    }

    test('substituir: tudo volta igual', () async {
      final (b, area) = await encher();
      final copia = lerCopia(utf8.decode(codificarCopia(b, area, Preferencias.omissao())));
      final b2 = await Biblioteca.abrir(pasta2);
      await restaurarCopia(copia, ModoRestauro.substituir,
          biblioteca: b2, area: await AreaGestor.abrir(pasta2), preferencias: Preferencias.omissao());
      final r = await Biblioteca.abrir(pasta2);
      expect(r.listas.last.gruposEscondidos, {'Adultos'});
      expect(r.listas.last.ordemCanais, OrdemCanais.az);
      expect(r.ultimoVisto!.lista, r.listas.last.id);
      expect(r.ultimoVisto!.canal, 'c1');
    });

    test('juntar: une os escondidos, a ordem A–Z entra e o último visto aponta para a lista local', () async {
      final (b, area) = await encher();
      final copia = lerCopia(utf8.decode(codificarCopia(b, area, Preferencias.omissao())));
      final b2 = await Biblioteca.abrir(pasta2);
      await b2.adicionar([_imp('http://b.com/l.m3u')]);
      final local = b2.listas.single.id;
      await b2.esconderGrupo(local, 'UK', true);
      await restaurarCopia(copia, ModoRestauro.juntar,
          biblioteca: b2, area: await AreaGestor.abrir(pasta2), preferencias: Preferencias.omissao());
      final l = b2.porId(local)!;
      expect(l.gruposEscondidos, {'UK', 'Adultos'});
      expect(l.ordemCanais, OrdemCanais.az);
      expect(b2.ultimoVisto!.lista, local, reason: 'sem último visto local, fica o do ficheiro (na lista local)');
    });

    test('juntar: o último visto local fica', () async {
      final (b, area) = await encher();
      final copia = lerCopia(utf8.decode(codificarCopia(b, area, Preferencias.omissao())));
      final b2 = await Biblioteca.abrir(pasta2);
      await b2.adicionar([_imp('http://z.com/l.m3u')]);
      await b2.registarVisto(b2.listas.single.id, const Canal(id: 'z', nome: 'Z', grupo: 'G'));
      await restaurarCopia(copia, ModoRestauro.juntar,
          biblioteca: b2, area: await AreaGestor.abrir(pasta2), preferencias: Preferencias.omissao());
      expect(b2.ultimoVisto!.canal, 'z');
    });

    test('um ficheiro antigo (sem estes campos) continua a importar-se', () async {
      final (b, area) = await encher();
      final m = jsonDecode(utf8.decode(codificarCopia(b, area, Preferencias.omissao()))) as Map<String, dynamic>;
      (m['biblioteca'] as Map).remove('ultimo_visto');
      for (final l in (m['biblioteca'] as Map)['listas'] as List) {
        (l as Map)
          ..remove('grupos_escondidos')
          ..remove('ordem_canais');
      }
      expect(m['versao'], 1);
      final copia = lerCopia(jsonEncode(m));
      final b2 = await Biblioteca.abrir(pasta2);
      await restaurarCopia(copia, ModoRestauro.substituir,
          biblioteca: b2, area: await AreaGestor.abrir(pasta2), preferencias: Preferencias.omissao());
      expect(b2.listas, hasLength(2));
      expect(b2.listas.last.gruposEscondidos, isEmpty);
      expect(b2.ultimoVisto, isNull);
    });
  });
}
