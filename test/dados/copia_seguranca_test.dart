import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/dados/copia_seguranca.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/desporto/preferencias_jogos.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';

void main() {
  late Directory pasta, pasta2;
  late Biblioteca bib;
  late AreaGestor area;
  late Preferencias prefs;

  UltimaVerificacao ultima(String estado, [int ano = 2026]) =>
      UltimaVerificacao(estado: estado, data: DateTime(ano, 3, 4), validade: '2027-10-16');

  Future<void> encher() async {
    await bib.adicionar([
      Importada(contaDeLinha('http://nxtbox.uk/c/ 00:1A:79:00:00:01')!, ultima('funciona')),
      Importada(contaDeLinha('http://xt.com:8080/get.php?username=u&password=p')!),
    ]);
    await bib.alternarFavorito(bib.listas.first.id, '42');
    await bib.alternarFavorito(bib.listas.first.id, '43');
    await bib.editar(bib.listas.last.id, bib.listas.last.conta, nomeProprio: 'A minha');
    await bib.definirCanaisTeste(['rtp1', 'dazn1']);
    await area.adicionar([Importada(contaDeLinha('http://so-gestor.com/c/ 00:1A:79:00:00:09')!, ultima('inconclusivo'))]);
    prefs
      ..volume = 33
      ..timeoutVerificacao = 17
      ..userAgent = 'MeuPlayer/1.0';
  }

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('copia');
    pasta2 = Directory.systemTemp.createTempSync('copia2');
    bib = await Biblioteca.abrir(pasta);
    area = await AreaGestor.abrir(pasta);
    prefs = Preferencias.omissao();
  });
  tearDown(() {
    for (final p in [pasta, pasta2]) {
      try {
        p.deleteSync(recursive: true);
      } on FileSystemException {/* Windows */}
    }
  });

  List<Object?> forma(Iterable<Lista> ls) => [for (final l in ls) l.paraJson()];

  test('exportar -> importar (substituir) devolve a mesma biblioteca, o Gestor e as definições', () async {
    await encher();
    final texto = utf8.decode(codificarCopia(bib, area, prefs));
    final copia = lerCopia(texto);

    final bib2 = await Biblioteca.abrir(pasta2);
    final area2 = await AreaGestor.abrir(pasta2);
    final prefs2 = Preferencias.omissao();
    final r = await restaurarCopia(copia, ModoRestauro.substituir, biblioteca: bib2, area: area2, preferencias: prefs2);

    expect(forma(bib2.listas), forma(bib.listas));
    expect(forma(area2.listas), forma(area.listas));
    expect(bib2.canaisTeste, ['rtp1', 'dazn1']);
    expect(prefs2.volume, 33);
    expect(prefs2.timeoutVerificacao, 17);
    expect(prefs2.userAgent, 'MeuPlayer/1.0');
    expect(bib2.listas.first.favoritos, {'42', '43'});
    expect(bib2.listas.last.nome, 'A minha');
    expect(r.listasPlayer, 2);
    expect(r.listasGestor, 1);

    // e ficou no disco
    final bib3 = await Biblioteca.abrir(pasta2);
    expect(forma(bib3.listas), forma(bib.listas));
  });

  test('as preferências dos Jogos vão na cópia e voltam ao importar (equipas, ordem, ordenação)', () async {
    await encher();
    final jogos = await PreferenciasJogos.abrir(Directory('${pasta.path}/desporto'));
    jogos
      ..equipasFavoritas = ['Benfica', 'Arsenal']
      ..competicoes = {'liga-portugal', 'champions'}
      ..ordemCompeticoes = ['champions', 'liga-portugal']
      ..ordenarPorHora = true;
    final copia = lerCopia(utf8.decode(codificarCopia(bib, area, prefs, jogos: jogos)));

    final jogos2 = await PreferenciasJogos.abrir(Directory('${pasta2.path}/desporto'));
    await restaurarCopia(copia, ModoRestauro.substituir,
        biblioteca: await Biblioteca.abrir(pasta2),
        area: await AreaGestor.abrir(pasta2),
        preferencias: Preferencias.omissao(),
        jogos: jogos2);
    expect(jogos2.equipasFavoritas, ['Benfica', 'Arsenal']);
    expect(jogos2.ordemCompeticoes, ['champions', 'liga-portugal']);
    expect(jogos2.ordenarPorHora, isTrue);
    await jogos2.guardar();
    final jogos3 = await PreferenciasJogos.abrir(Directory('${pasta2.path}/desporto'));
    expect(jogos3.equipasFavoritas, ['Benfica', 'Arsenal'], reason: 'ficou no disco');
  });

  test('sem as preferências dos Jogos (edição de partilha) a cópia não tem a secção e importar não lhes toca', () async {
    await encher();
    final texto = utf8.decode(codificarCopia(bib, area, prefs));
    expect((jsonDecode(texto) as Map).containsKey('jogos'), isFalse);
    final jogos2 = await PreferenciasJogos.abrir(Directory('${pasta2.path}/desporto'));
    jogos2.equipasFavoritas = ['Porto'];
    await restaurarCopia(lerCopia(texto), ModoRestauro.substituir,
        biblioteca: await Biblioteca.abrir(pasta2),
        area: await AreaGestor.abrir(pasta2),
        preferencias: Preferencias.omissao(),
        jogos: jogos2);
    expect(jogos2.equipasFavoritas, ['Porto']);
  });

  test('o ficheiro tem formato, versão e data', () async {
    await encher();
    final m = jsonDecode(utf8.decode(codificarCopia(bib, area, prefs, agora: DateTime.utc(2026, 11, 17)))) as Map;
    expect(m['formato'], 'player-iptv-copia');
    expect(m['versao'], 1);
    expect(m['criada'], '2026-11-17T00:00:00.000Z');
  });

  test('juntar: sem duplicar, une favoritos e fica com o resultado mais recente', () async {
    await encher();
    final texto = utf8.decode(codificarCopia(bib, area, prefs));
    final copia = lerCopia(texto);

    final bib2 = await Biblioteca.abrir(pasta2);
    final area2 = await AreaGestor.abrir(pasta2);
    await bib2.adicionar([
      Importada(contaDeLinha('http://nxtbox.uk/c/ 00:1A:79:00:00:01')!, ultima('nao_funciona', 2025)),
      Importada(contaDeLinha('http://local.com/c/ 00:1A:79:00:00:05')!),
    ]);
    await bib2.alternarFavorito(bib2.listas.first.id, '99');
    final idLocal = bib2.listas.first.id;
    final prefs2 = Preferencias.omissao()..volume = 80;

    final r = await restaurarCopia(copia, ModoRestauro.juntar, biblioteca: bib2, area: area2, preferencias: prefs2);

    expect(bib2.listas, hasLength(3)); // a nxtbox não duplica
    final nxt = bib2.listas.firstWhere((l) => l.conta.endereco.contains('nxtbox'));
    expect(nxt.id, idLocal);
    expect(nxt.favoritos, {'99', '42', '43'});
    expect(nxt.ultima!.estado, 'funciona'); // a do ficheiro é mais recente
    expect(bib2.listas.map((l) => l.ordem).toSet(), hasLength(3)); // nomes NNN sem repetir
    expect(bib2.canaisTeste, ['rtp1']); // juntar não mexe nos canais de teste
    expect(r.listasPlayer, 1); // só a xtream era nova
    expect(area2.listas, hasLength(1));
    expect(prefs2.volume, 33); // as definições do ficheiro aplicam-se
    // importar outra vez não muda nada
    final r2 = await restaurarCopia(copia, ModoRestauro.juntar, biblioteca: bib2, area: area2, preferencias: prefs2);
    expect(bib2.listas, hasLength(3));
    expect(r2.listasPlayer, 0);
  });

  test('substituir apaga a cache de canais das listas que saem', () async {
    await encher();
    final copia = lerCopia(utf8.decode(codificarCopia(bib, area, prefs)));
    final bib2 = await Biblioteca.abrir(pasta2);
    final area2 = await AreaGestor.abrir(pasta2);
    await bib2.adicionar([Importada(contaDeLinha('http://local.com/c/ 00:1A:79:00:00:05')!)]);
    final id = bib2.listas.single.id;
    await bib2.guardarCanais(id, ConteudoLista(['G'], const []));
    expect(await bib2.canaisEmCache(id), isNotNull);
    await restaurarCopia(copia, ModoRestauro.substituir,
        biblioteca: bib2, area: area2, preferencias: Preferencias.omissao());
    expect(await bib2.canaisEmCache(id), isNull);
    expect(bib2.listas.map((l) => l.conta.endereco), isNot(contains('http://local.com/c/')));
  });

  group('ficheiro inválido: erro legível, nada muda', () {
    for (final (nome, texto) in [
      ('vazio', ''),
      ('não é JSON', 'isto não é json'),
      ('JSON de outra forma', '[1, 2, 3]'),
      ('sem o formato', '{"versao": 1, "biblioteca": {"listas": []}}'),
      ('outro formato', '{"formato": "outra-coisa", "versao": 1}'),
      ('sem versão', '{"formato": "player-iptv-copia"}'),
      ('versão mais recente', '{"formato": "player-iptv-copia", "versao": 99, "biblioteca": {"listas": []}}'),
      ('listas que não são lista', '{"formato": "player-iptv-copia", "versao": 1, "biblioteca": {"listas": 5}}'),
      ('uma lista estragada', '{"formato": "player-iptv-copia", "versao": 1, "biblioteca": {"listas": [{"id": "a"}]}}'),
      ('sem nada para restaurar', '{"formato": "player-iptv-copia", "versao": 1}'),
    ]) {
      test(nome, () {
        expect(() => lerCopia(texto), throwsA(isA<ErroCopia>().having((e) => e.mensagem, 'mensagem', isNotEmpty)));
      });
    }

    test('a mensagem da versão mais recente é em português', () {
      try {
        lerCopia('{"formato": "player-iptv-copia", "versao": 99}');
        fail('devia lançar');
      } on ErroCopia catch (e) {
        expect(e.mensagem, contains('mais recente'));
      }
    });

    test('depois do erro a biblioteca fica como estava', () async {
      await encher();
      final antes = forma(bib.listas);
      expect(() => lerCopia('lixo'), throwsA(isA<ErroCopia>()));
      expect(forma(bib.listas), antes);
    });
  });

  test('os campos futuros (ordem, grupos escondidos) não estragam a leitura de uma versão atual', () async {
    await encher();
    final m = jsonDecode(utf8.decode(codificarCopia(bib, area, prefs))) as Map<String, dynamic>;
    m['grupos_escondidos'] = {'x': ['a']};
    (m['biblioteca']['listas'] as List).first['grupos_escondidos'] = ['UK'];
    final copia = lerCopia(jsonEncode(m));
    expect(copia.player, hasLength(2));
  });

  test('uma falha a gravar o Gestor desfaz o que já tinha mudado no Player (memória e disco)', () async {
    await encher();
    final copia = lerCopia(utf8.decode(codificarCopia(bib, area, prefs)));
    final bib2 = await Biblioteca.abrir(pasta2);
    await bib2.adicionar([Importada(contaDeLinha('http://local.com/c/ 00:1A:79:00:00:05')!)]);
    final antes = forma(bib2.listas);
    final ficheiroAntes = File('${pasta2.path}${Platform.pathSeparator}biblioteca.json').readAsStringSync();
    final area2 = await AreaGestor.abrir(pasta2);
    // o ficheiro do Gestor passa a ser uma pasta: gravar falha
    Directory('${pasta2.path}${Platform.pathSeparator}gestor.json').createSync();
    final prefs2 = Preferencias.omissao()..volume = 80;
    await expectLater(
        restaurarCopia(copia, ModoRestauro.substituir, biblioteca: bib2, area: area2, preferencias: prefs2),
        throwsA(isA<ErroCopia>().having((e) => e.alterou, 'alterou', isFalse)));
    expect(forma(bib2.listas), antes);
    expect(bib2.canaisTeste, ['rtp1']);
    expect(area2.listas, isEmpty);
    expect(prefs2.volume, 80);
    expect(File('${pasta2.path}${Platform.pathSeparator}biblioteca.json').readAsStringSync(), ficheiroAntes);
    expect(forma((await Biblioteca.abrir(pasta2)).listas), antes);
  });

  test('I1: substituir com um ficheiro só com a secção do Player não toca no Gestor', () async {
    await encher();
    final m = jsonDecode(utf8.decode(codificarCopia(bib, area, prefs))) as Map<String, dynamic>..remove('gestor');
    final copia = lerCopia(jsonEncode(m));
    final bib2 = await Biblioteca.abrir(pasta2);
    final area2 = await AreaGestor.abrir(pasta2);
    await area2.adicionar([Importada(contaDeLinha('http://meu-gestor.com/c/ 00:1A:79:00:00:07')!)]);
    final gestorAntes = forma(area2.listas);
    final r = await restaurarCopia(copia, ModoRestauro.substituir,
        biblioteca: bib2, area: area2, preferencias: Preferencias.omissao());
    expect(forma(area2.listas), gestorAntes);
    expect(bib2.listas, hasLength(2));
    expect(r.listasGestor, 0);
    expect(r.removidas, 0);
  });

  test('I1: o mesmo para um ficheiro só com o Gestor (o Player e a cache ficam)', () async {
    await encher();
    final m = jsonDecode(utf8.decode(codificarCopia(bib, area, prefs))) as Map<String, dynamic>..remove('biblioteca');
    final copia = lerCopia(jsonEncode(m));
    final bib2 = await Biblioteca.abrir(pasta2);
    await bib2.adicionar([Importada(contaDeLinha('http://local.com/c/ 00:1A:79:00:00:05')!)]);
    final id = bib2.listas.single.id;
    await bib2.guardarCanais(id, ConteudoLista(['G'], const []));
    final area2 = await AreaGestor.abrir(pasta2);
    await restaurarCopia(copia, ModoRestauro.substituir,
        biblioteca: bib2, area: area2, preferencias: Preferencias.omissao());
    expect(bib2.listas, hasLength(1));
    expect(await bib2.canaisEmCache(id), isNotNull);
    expect(area2.listas, hasLength(1));
  });

  test('I2: se as definições não se gravam, as listas voltam atrás e o erro diz que nada mudou', () async {
    await encher();
    final copia = lerCopia(utf8.decode(codificarCopia(bib, area, prefs)));
    final bib2 = await Biblioteca.abrir(pasta2);
    await bib2.adicionar([Importada(contaDeLinha('http://local.com/c/ 00:1A:79:00:00:05')!)]);
    final antes = forma(bib2.listas);
    final id = bib2.listas.single.id;
    await bib2.guardarCanais(id, ConteudoLista(['G'], const []));
    final area2 = await AreaGestor.abrir(pasta2);
    final prefs2 = await Preferencias.abrir(pasta2)
      ..volume = 80;
    await prefs2.guardar();
    final espera = Preferencias.esperaBloqueio;
    Preferencias.esperaBloqueio = const Duration(milliseconds: 300);
    addTearDown(() => Preferencias.esperaBloqueio = espera);
    final lock = File('${pasta2.path}${Platform.pathSeparator}preferencias.lock').openSync(mode: FileMode.append)
      ..lockSync(FileLock.exclusive);
    try {
      await expectLater(
          restaurarCopia(copia, ModoRestauro.substituir, biblioteca: bib2, area: area2, preferencias: prefs2),
          throwsA(isA<ErroCopia>().having((e) => e.alterou, 'alterou', isFalse)));
    } finally {
      lock.unlockSync();
      lock.closeSync();
    }
    expect(forma(bib2.listas), antes);
    expect(bib2.canaisTeste, ['rtp1']);
    expect(area2.listas, isEmpty);
    expect(prefs2.volume, 80);
    expect(prefs2.userAgent, '');
    expect(await bib2.canaisEmCache(id), isNotNull, reason: 'a cache só se apaga depois de tudo gravado');
    expect(forma((await Biblioteca.abrir(pasta2)).listas), antes);
    expect(forma((await AreaGestor.abrir(pasta2)).listas), isEmpty);
  });

  test('desentrelaçamento: uma cópia antiga só com "desentrelacar" restaura o modo certo', () async {
    String copiaCom(Map<String, Object> prefs) => jsonEncode({
          'formato': 'player-iptv-copia',
          'versao': 1,
          'biblioteca': {'listas': []},
          'preferencias': prefs,
        });
    final p = Preferencias.omissao();
    await restaurarCopia(lerCopia(copiaCom({'desentrelacar': false})), ModoRestauro.juntar,
        biblioteca: bib, area: area, preferencias: p);
    expect(p.modoDesentrelacamento, ModoDesentrelacamento.desligado);
    await restaurarCopia(lerCopia(copiaCom({'desentrelacar': true})), ModoRestauro.juntar,
        biblioteca: bib, area: area, preferencias: p);
    expect(p.modoDesentrelacamento, ModoDesentrelacamento.automatico);
  });

  test('desentrelaçamento: exportar -> importar mantém o "Ligado"', () async {
    prefs.modoDesentrelacamento = ModoDesentrelacamento.ligado;
    final copia = lerCopia(utf8.decode(codificarCopia(bib, area, prefs)));
    expect(copia.preferencias!['modo_desentrelacamento'], 'ligado');
    final p = Preferencias.omissao();
    await restaurarCopia(copia, ModoRestauro.juntar, biblioteca: bib, area: area, preferencias: p);
    expect(p.modoDesentrelacamento, ModoDesentrelacamento.ligado);
  });
}
