/// O serviço dos «Jogos»: pede os jogos (FotMob) e as grelhas (guia de TV do FotMob, MEO e
/// Sport TV), casa-os e diz o estado de cada fonte. Uma fonte que falha não impede as outras.
/// Em dados móveis, sem `forcar`, só se usa a cache e o guia do FotMob.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../modelo/canal.dart' show semAcentos;
import 'casador.dart';
import 'catalogo.dart';
import 'cliente_desporto.dart';
import 'fontes/fotmob.dart';
import 'fontes/meo.dart';
import 'fontes/sporttv.dart';
import 'modelo.dart';
import 'preferencias_jogos.dart';

/// As fontes do serviço (para o estado dizer qual falhou).
enum FonteJogos { fotmob, guiaFotmob, meo, sportTv }

/// Um jogo com os canais onde dá (a confiança mais alta primeiro).
class JogoComCanais {
  const JogoComCanais(this.jogo, this.canais);
  final Jogo jogo;
  final List<Transmissao> canais;

  Competicao? get competicao => competicaoPorId(jogo.competicaoId);
}

/// O que o ecrã mostra. `dia` é o dia de calendário (só ano, mês e dia contam).
class FiltroJogos {
  const FiltroJogos(this.dia,
      {this.desporto, this.competicoes = const {}, this.soDireto = false, this.soComCanal = true, this.equipa = ''});
  final DateTime dia;
  final Desporto? desporto;

  /// Só estas competições (vazio: todas).
  final Set<String> competicoes;
  final bool soDireto;
  final bool soComCanal;

  /// Parte do nome de uma das equipas (sem acentos nem maiúsculas; vazio: todas).
  final String equipa;
}

String _simples(String s) => semAcentos(s.toLowerCase()).trim();

/// Os jogos de uma competição (um bloco no ecrã).
typedef GrupoJogos = ({Competicao competicao, List<JogoComCanais> jogos});

/// Os jogos por competição, pela ordem do catálogo (a Liga Portugal primeiro); dentro de cada
/// uma, pela hora.
List<GrupoJogos> agruparPorCompeticao(List<JogoComCanais> jogos) {
  final ordem = {for (final (i, c) in catalogoCompeticoes.indexed) c.id: i};
  final porComp = <String, List<JogoComCanais>>{};
  for (final j in jogos) {
    porComp.putIfAbsent(j.jogo.competicaoId, () => []).add(j);
  }
  final ids = porComp.keys.where((id) => competicaoPorId(id) != null).toList()
    ..sort((a, b) => ordem[a]!.compareTo(ordem[b]!));
  return [
    for (final id in ids)
      (
        competicao: competicaoPorId(id)!,
        jogos: porComp[id]!..sort((a, b) => a.jogo.inicio.compareTo(b.jogo.inicio)),
      ),
  ];
}

enum Carga { nada, aCarregar, pronto }

class EstadoJogos {
  const EstadoJogos({this.carga = Carga.nada, this.falhas = const {}, this.velhoDesde});
  final Carga carga;

  /// As fontes que falharam na última carga (sem rede nem cache).
  final Set<FonteJogos> falhas;

  /// Algum dado é da cache fora da validade: a data do mais antigo (null: tudo em dia).
  final DateTime? velhoDesde;

  bool get velho => velhoDesde != null;
}

/// O nome de cada fonte para o estado («MEO indisponível»).
String nomeFonte(FonteJogos f) => switch (f) {
      FonteJogos.fotmob => 'FotMob',
      FonteJogos.guiaFotmob => 'FotMob',
      FonteJogos.meo => 'MEO',
      FonteJogos.sportTv => 'Sport TV',
    };

String _chaveDia(DateTime d) => diaTexto(d);

/// Corre as tarefas com no máximo `n` ao mesmo tempo (a MEO são dezenas de pedidos: não se
/// batem todos ao servidor de uma vez). Os resultados ficam pela ordem das tarefas.
Future<List<T>> _poucosDeCada<T>(List<Future<T> Function()> tarefas, [int n = 4]) async {
  final r = List<T?>.filled(tarefas.length, null);
  var proxima = 0;
  Future<void> trabalhador() async {
    while (proxima < tarefas.length) {
      final i = proxima++;
      r[i] = await tarefas[i]();
    }
  }

  await Future.wait([for (var k = 0; k < n; k++) trabalhador()]);
  return r.cast<T>();
}

class ServicoJogos extends ChangeNotifier {
  ServicoJogos(this.cliente, this.preferencias, {Future<bool> Function()? emDadosMoveis})
      : _emDadosMoveis = emDadosMoveis ?? (() async => false);

  final ClienteDesporto cliente;
  final PreferenciasJogos preferencias;
  final Future<bool> Function() _emDadosMoveis;

  /// dia → os jogos com os canais (da última carga desse dia).
  final _porDia = <String, List<JogoComCanais>>{};
  EstadoJogos _estado = const EstadoJogos();
  EstadoJogos get estado => _estado;
  int _pedido = 0;

  /// Carrega o dia `dia`. Os pedidos à rede passam pela cache do [cliente]: mudar de dia e voltar
  /// não pede de novo o que ainda vale.
  Future<void> carregar(DateTime dia, {bool forcar = false}) async {
    final pedido = ++_pedido;
    _estado = EstadoJogos(carga: Carga.aCarregar, falhas: _estado.falhas, velhoDesde: _estado.velhoDesde);
    notifyListeners();
    final soCache = !forcar && await _emDadosMoveis();
    final falhas = <FonteJogos>{};
    DateTime? velhoDesde;
    T? usar<T>(Lido<T> l) {
      final d = l.data;
      if (l.velho && d != null && (velhoDesde == null || d.isBefore(velhoDesde!))) velhoDesde = d;
      return l.dados;
    }

    Future<T?> tentar<T>(FonteJogos f, Future<Lido<T>> Function() pedir) async {
      try {
        return usar(await pedir());
      } catch (e) {
        if (falhas.add(f)) debugPrint('jogos: ${f.name} falhou (${e.runtimeType})');
        return null;
      }
    }

    final hoje = cliente.agora().toLocal();
    final eHoje = hoje.year == dia.year && hoje.month == dia.month && hoje.day == dia.day;
    // a MEO: o dia escolhido e, hoje, também amanhã (os jogos depois da meia-noite)
    final diasMeo = [dia, if (eHoje) DateTime(dia.year, dia.month, dia.day + 1)];
    final canaisMeo = [for (final c in catalogoCanais) if (c.meo != null) c];

    final jogosF = tentar(FonteJogos.fotmob, () => jogosFotmob(cliente, dia, preferencias.competicoes, soCache: soCache));
    // o guia do FotMob é um pedido pequeno para 7 dias: pede-se mesmo em dados móveis
    final guiaF = tentar(FonteJogos.guiaFotmob, () => guiaTvFotmob(cliente));
    final sportTvF = tentar(FonteJogos.sportTv, () => guiaSportTv(cliente, soCache: soCache));
    final meoF = _poucosDeCada([
      for (final d in diasMeo)
        for (final c in canaisMeo) () => tentar(FonteJogos.meo, () => grelhaMeo(cliente, c, d, soCache: soCache)),
    ]);

    final jogos = await jogosF ?? const <Jogo>[];
    final guia = await guiaF ?? const <(String, Emissao)>[];
    final emissoes = <Emissao>[
      ...?await sportTvF,
      for (final g in await meoF) ...?g,
    ];
    if (pedido != _pedido) return; // outro dia pedido entretanto

    final transmissoes = casar(jogos, emissoes, ligadasPorId: guia);
    final porJogo = <String, List<Transmissao>>{};
    for (final t in transmissoes) {
      porJogo.putIfAbsent(t.jogoId, () => []).add(t);
    }
    final lista = [
      for (final j in jogos)
        JogoComCanais(j, (porJogo[j.id] ?? [])..sort((a, b) => b.confianca.index - a.confianca.index)),
    ]..sort((a, b) => a.jogo.inicio.compareTo(b.jogo.inicio));
    _porDia[_chaveDia(dia)] = lista;
    _estado = EstadoJogos(carga: Carga.pronto, falhas: falhas, velhoDesde: velhoDesde);
    notifyListeners();
  }

  /// Os jogos do dia do filtro (os da última carga desse dia), pela hora.
  List<JogoComCanais> jogos(FiltroJogos f) {
    final q = _simples(f.equipa);
    return [
        for (final j in _porDia[_chaveDia(f.dia)] ?? const <JogoComCanais>[])
          if ((f.desporto == null || j.jogo.desporto == f.desporto) &&
              (f.competicoes.isEmpty || f.competicoes.contains(j.jogo.competicaoId)) &&
              (q.isEmpty || _simples(j.jogo.casa).contains(q) || _simples(j.jogo.fora).contains(q)) &&
              (!f.soDireto || j.jogo.aDecorrer) &&
              (!f.soComCanal || j.canais.isNotEmpty))
            j,
      ];
  }

  /// Para os testes do ecrã: os jogos de um dia sem passar pelas fontes.
  @visibleForTesting
  void definir(DateTime dia, List<JogoComCanais> jogos, {EstadoJogos estado = const EstadoJogos(carga: Carga.pronto)}) {
    _porDia[_chaveDia(dia)] = jogos;
    _estado = estado;
    notifyListeners();
  }

  /// O dia já foi carregado (há o que mostrar, mesmo antes de uma nova carga acabar).
  bool temDia(DateTime dia) => _porDia.containsKey(_chaveDia(dia));
}
