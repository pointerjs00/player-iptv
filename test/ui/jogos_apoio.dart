/// O que os testes do ecrã «Jogos» partilham: um serviço com jogos feitos à mão, as fontes falsas
/// e o registo do que se abriu no player.
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/desporto/armazem_desporto.dart';
import 'package:player_iptv/desporto/cliente_desporto.dart';
import 'package:player_iptv/desporto/modelo.dart';
import 'package:player_iptv/desporto/onde_ver.dart';
import 'package:player_iptv/desporto/preferencias_jogos.dart';
import 'package:player_iptv/desporto/servico_jogos.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/jogos/tela_jogos.dart';

final hojeJogos = DateTime(2026, 11, 27);
DateTime agoraJogos() => DateTime(2026, 11, 27, 18);

/// Um serviço que não vai às fontes: os jogos põem-se com [ServicoJogos.definir].
class ServicoFalso extends ServicoJogos {
  ServicoFalso(super.cliente, super.preferencias);
  final cargas = <DateTime>[];

  @override
  Future<void> carregar(DateTime dia, {bool forcar = false}) async => cargas.add(dia);

  /// Os pedidos do ao vivo (o dia de cada um).
  final aoVivo = <DateTime>[];

  @override
  Future<void> atualizarAoVivo(DateTime dia) async => aoVivo.add(dia);
}

class FontesFalsas extends ChangeNotifier implements FontesDosCanais {
  FontesFalsas(this.porCanal, {this.semCache = 0});
  final Map<String, List<FonteCanal>> porCanal;
  final int semCache;
  int atualizacoes = 0;

  @override
  List<FonteCanal> fontes(String canalTv) => porCanal[canalTv] ?? const [];

  @override
  int get listasSemCache => semCache;

  @override
  Future<void> atualizar() async => atualizacoes++;
}

Lista listaJogos(String id) => Lista(
    id: id, ordem: int.parse(id), conta: Conta('c$id', Tipo.m3u, 'http://lista$id.invalido/l.m3u'), nomeProprio: 'Lista $id');

FonteCanal fonteJogos(String lista, String canalTv, String nome) =>
    FonteCanal(listaJogos(lista), Canal(id: '$canalTv-$lista', nome: nome, grupo: 'PT'), canalTv: canalTv);

Transmissao transmissao(String jogo, String canal, [Confianca c = Confianca.confirmado]) =>
    Transmissao(jogoId: jogo, canal: canal, confianca: c, origem: 'teste');

JogoComCanais jogoTeste(int n, String casa, String fora, List<String> canais,
    {EstadoJogo estado = EstadoJogo.agendado, String comp = 'liga-portugal'}) {
  final id = 'fotmob:$n';
  return JogoComCanais(
    Jogo(
      id: id,
      desporto: Desporto.futebol,
      competicaoId: comp,
      casa: casa,
      fora: fora,
      inicio: DateTime.utc(2026, 11, 27, 14 + n ~/ 2, n.isEven ? 0 : 30),
      estado: estado,
      resultado: estado == EstadoJogo.aoVivo ? '1–0' : null,
      minuto: estado == EstadoJogo.aoVivo ? "67'" : null,
      ronda: '12',
    ),
    [for (final c in canais) transmissao(id, c)],
  );
}

/// 8 jogos: o 1.º com dois canais, o 4.º sem canal.
List<JogoComCanais> jogosTeste() => [
      jogoTeste(0, 'Marítimo', 'Nacional', ['sporttv1', 'sporttv2'], estado: EstadoJogo.aoVivo),
      jogoTeste(1, 'Benfica', 'Porto', ['btv']),
      jogoTeste(2, 'Feyenoord', 'Ajax', ['sporttv3'], comp: 'eredivisie'),
      jogoTeste(3, 'Moreirense', 'Santa Clara', []),
      jogoTeste(4, 'Arsenal', 'Chelsea', ['dazn1'], comp: 'premier-league'),
      jogoTeste(5, 'Braga', 'Vitória SC', ['sporttv1']),
      jogoTeste(6, 'Gil Vicente', 'Rio Ave', ['sporttv2']),
      jogoTeste(7, 'Famalicão', 'Estoril', ['sporttv4']),
    ];

FontesFalsas fontesTeste() => FontesFalsas({
      'sporttv1': [fonteJogos('1', 'sporttv1', 'PT: SPORT TV 1'), fonteJogos('2', 'sporttv1', 'SPORT TV 1 FHD')],
      'sporttv2': [fonteJogos('2', 'sporttv2', 'SPORT TV 2 FHD')],
      'btv': [fonteJogos('1', 'btv', 'BENFICA TV')],
    });

/// O que o ecrã montado tem à mão.
class Montagem {
  Montagem(this.pasta, this.servico, this.fontes, this.prefs);
  final Directory pasta;
  final ServicoFalso servico;
  final FontesFalsas fontes;
  final PreferenciasJogos prefs;
  final abertas = <List<FonteCanal>>[];
  ValueChanged<FonteCanal>? aoFuncionar;

  Widget tela() => TelaJogos(
        servico: servico,
        fontes: fontes,
        preferencias: prefs,
        agora: agoraJogos,
        abrir: (context, f, {aoFuncionar}) async {
          abertas.add(f);
          this.aoFuncionar = aoFuncionar;
        },
      );
}

/// Fora da zona falsa dos testes de widgets (ficheiros a sério).
Future<Montagem> prepararJogos({List<JogoComCanais>? jogos, FontesFalsas? fontes, EstadoJogos? estado}) async {
  final pasta = Directory.systemTemp.createTempSync('jogos_ui');
  final prefs = await PreferenciasJogos.abrir(pasta);
  final armazem = await ArmazemDesporto.abrir(Directory('${pasta.path}/cache'));
  final servico = ServicoFalso(ClienteDesporto(armazem, obter: (_, _) async => throw StateError('sem rede')), prefs);
  servico.definir(hojeJogos, jogos ?? jogosTeste(), estado: estado ?? const EstadoJogos(carga: Carga.pronto));
  return Montagem(pasta, servico, fontes ?? fontesTeste(), prefs);
}

void arrumarJogos(Montagem m) {
  try {
    m.pasta.deleteSync(recursive: true);
  } on FileSystemException {
    /* Windows */
  }
}
