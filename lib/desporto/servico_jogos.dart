/// O serviço dos «Jogos»: pede os jogos (FotMob) e as grelhas (guia de TV do FotMob, Sport TV e o
/// guia das próprias listas), casa-os e diz o estado de cada fonte. Uma fonte que falha não impede as outras.
/// Em dados móveis, sem `forcar`, só se usa a cache e o guia do FotMob.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../modelo/canal.dart' show semAcentos;
import '../idioma/idioma.dart';
import 'casador.dart';
import 'catalogo.dart';
import 'cliente_desporto.dart';
import 'fontes/fotmob.dart';
import 'fontes/epg_listas.dart';
import 'fontes/sporttv.dart';
import 'modelo.dart';
import 'onde_ver.dart';
import 'preferencias_jogos.dart';

/// As fontes do serviço (para o estado dizer qual falhou).
enum FonteJogos { fotmob, guiaFotmob, listas, sportTv }

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
/// As competições em `ordem` (a escolhida no ecrã «Competições») vêm primeiro, por essa ordem; as
/// outras depois, pela ordem do catálogo.
List<GrupoJogos> agruparPorCompeticao(List<JogoComCanais> jogos, {List<String> ordem = const []}) {
  final n = ordem.length;
  final escolhida = {for (final (i, id) in ordem.indexed) id: i};
  final catalogo = {for (final (i, c) in catalogoCompeticoes.indexed) c.id: n + i};
  final posicao = {...catalogo, ...escolhida};
  final porComp = <String, List<JogoComCanais>>{};
  for (final j in jogos) {
    porComp.putIfAbsent(j.jogo.competicaoId, () => []).add(j);
  }
  final ids = porComp.keys.where((id) => competicaoPorId(id) != null).toList()
    ..sort((a, b) => posicao[a]!.compareTo(posicao[b]!));
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

/// O nome de cada fonte para o estado («Sport TV indisponível»).
String nomeFonte(FonteJogos f) => switch (f) {
      FonteJogos.fotmob => 'FotMob',
      FonteJogos.guiaFotmob => 'FotMob',
      FonteJogos.listas => tr('Guia das listas'),
      FonteJogos.sportTv => 'Sport TV',
    };

String _chaveDia(DateTime d) => diaTexto(d);

class ServicoJogos extends ChangeNotifier {
  ServicoJogos(this.cliente, this.preferencias,
      {Future<bool> Function()? emDadosMoveis, this.fontes, this.obterEpg = obterEpgDaLista})
      : _emDadosMoveis = emDadosMoveis ?? (() async => false);

  /// Os canais das listas (para o guia das listas). null: sem essa fonte.
  final FontesDosCanais? fontes;

  /// Como se pede a grelha de um canal a uma lista (nos testes, um falso).
  final ObterEpgCanal obterEpg;

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

    final jogosF = tentar(FonteJogos.fotmob, () => jogosFotmob(cliente, dia, preferencias.competicoes, soCache: soCache));
    // o guia do FotMob é um pedido pequeno para 7 dias: pede-se mesmo em dados móveis
    final guiaF = tentar(FonteJogos.guiaFotmob, () => guiaTvFotmob(cliente));
    final sportTvF = tentar(FonteJogos.sportTv, () => guiaSportTv(cliente, soCache: soCache));
    final fs = fontes;
    final listasF = fs == null
        ? Future<List<Emissao>?>.value(null)
        : tentar(FonteJogos.listas, () async {
            await fs.atualizar(); // o índice dos canais primeiro (só relê as listas que mudaram)
            return grelhaDasListas(cliente, fs, dia, obter: obterEpg, soCache: soCache);
          });
    final jogos = await jogosF ?? const <Jogo>[];
    final guia = await guiaF ?? const <(String, Emissao)>[];
    final emissoes = <Emissao>[
      ...?await sportTvF,
      ...?await listasF,
    ];
    if (pedido != _pedido) return; // outro dia pedido entretanto

    final casadas = casar(jogos, emissoes, ligadasPorId: guia);
    final ja = {for (final t in casadas) (t.jogoId, t.canal)};
    final transmissoes = [
      ...casadas,
      for (final t in transmissoesConhecidas(jogos)) if (!ja.contains((t.jogoId, t.canal))) t,
    ];
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
