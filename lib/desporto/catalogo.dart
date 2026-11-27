/// As competições seguidas e os canais portugueses (spec §4 e §5). Os ids do FotMob foram
/// confirmados a 27/11/2026 abrindo a página de cada competição; as que não têm id confirmado
/// reconhecem-se pelo nome e pelo país na resposta dos jogos do dia.
library;

import 'modelo.dart';

const _f = Desporto.futebol;

const catalogoCompeticoes = <Competicao>[
  // ligas
  Competicao(id: 'liga-portugal', desporto: _f, nome: 'Liga Portugal Betclic', tipo: TipoCompeticao.liga, fotmob: 61),
  Competicao(id: 'liga-portugal-2', desporto: _f, nome: 'Liga Portugal 2', tipo: TipoCompeticao.liga, fotmob: 185),
  Competicao(id: 'premier-league', desporto: _f, nome: 'Premier League', tipo: TipoCompeticao.liga, fotmob: 47),
  Competicao(id: 'laliga', desporto: _f, nome: 'LaLiga', tipo: TipoCompeticao.liga, fotmob: 87),
  Competicao(id: 'bundesliga', desporto: _f, nome: 'Bundesliga', tipo: TipoCompeticao.liga, fotmob: 54),
  Competicao(id: 'serie-a', desporto: _f, nome: 'Serie A', tipo: TipoCompeticao.liga, fotmob: 55),
  Competicao(id: 'ligue-1', desporto: _f, nome: 'Ligue 1', tipo: TipoCompeticao.liga, fotmob: 53),
  Competicao(id: 'eredivisie', desporto: _f, nome: 'Eredivisie', tipo: TipoCompeticao.liga, fotmob: 57),
  Competicao(id: 'super-lig', desporto: _f, nome: 'Trendyol Süper Lig', tipo: TipoCompeticao.liga, fotmob: 71),
  Competicao(id: 'pro-league', desporto: _f, nome: 'Pro League (Bélgica)', tipo: TipoCompeticao.liga, fotmob: 40),
  Competicao(id: 'premiership', desporto: _f, nome: 'Scottish Premiership', tipo: TipoCompeticao.liga, fotmob: 64),
  Competicao(id: 'saudi-pro-league', desporto: _f, nome: 'Saudi Pro League', tipo: TipoCompeticao.liga, fotmob: 536),
  Competicao(id: 'brasileirao', desporto: _f, nome: 'Brasileirão Betano', tipo: TipoCompeticao.liga, fotmob: 268),
  Competicao(id: 'libertadores', desporto: _f, nome: 'Libertadores', tipo: TipoCompeticao.liga, fotmob: 45),
  // taças
  Competicao(id: 'taca-portugal', desporto: _f, nome: 'Taça de Portugal', tipo: TipoCompeticao.taca, fotmob: 186),
  Competicao(id: 'taca-liga', desporto: _f, nome: 'Taça da Liga', tipo: TipoCompeticao.taca, fotmob: 187),
  Competicao(id: 'fa-cup', desporto: _f, nome: 'FA Cup', tipo: TipoCompeticao.taca, fotmob: 132),
  Competicao(id: 'efl-cup', desporto: _f, nome: 'Taça da Liga inglesa', tipo: TipoCompeticao.taca, fotmob: 133),
  Competicao(id: 'copa-del-rey', desporto: _f, nome: 'Copa del Rey', tipo: TipoCompeticao.taca, fotmob: 138),
  Competicao(id: 'dfb-pokal', desporto: _f, nome: 'DFB-Pokal', tipo: TipoCompeticao.taca, fotmob: 209),
  Competicao(id: 'coppa-italia', desporto: _f, nome: 'Coppa Italia', tipo: TipoCompeticao.taca, fotmob: 141),
  Competicao(id: 'coupe-de-france', desporto: _f, nome: 'Coupe de France', tipo: TipoCompeticao.taca, fotmob: 134),
  Competicao(id: 'knvb-beker', desporto: _f, nome: 'Taça dos Países Baixos', tipo: TipoCompeticao.taca, fotmob: 235),
  Competicao(id: 'taca-turquia', desporto: _f, nome: 'Taça da Turquia', tipo: TipoCompeticao.taca, fotmob: 151),
  Competicao(id: 'taca-belgica', desporto: _f, nome: 'Taça da Bélgica', tipo: TipoCompeticao.taca, fotmob: 149),
  Competicao(id: 'scottish-cup', desporto: _f, nome: 'Taça da Escócia', tipo: TipoCompeticao.taca, fotmob: 137),
  Competicao(id: 'scottish-league-cup', desporto: _f, nome: 'Taça da Liga escocesa', tipo: TipoCompeticao.taca, fotmob: 180),
  Competicao(id: 'copa-do-brasil', desporto: _f, nome: 'Copa do Brasil', tipo: TipoCompeticao.taca, fotmob: 9067),
  Competicao(
      id: 'taca-rei', desporto: _f, nome: 'Taça do Rei (Arábia Saudita)', tipo: TipoCompeticao.taca,
      fotmobNome: r"king'?s cup|kings cup", fotmobPais: 'KSA'),
  // europeias
  Competicao(id: 'champions', desporto: _f, nome: 'Liga dos Campeões', tipo: TipoCompeticao.europeia, fotmob: 42),
  Competicao(id: 'liga-europa', desporto: _f, nome: 'Liga Europa', tipo: TipoCompeticao.europeia, fotmob: 73),
  Competicao(id: 'conference', desporto: _f, nome: 'Liga Conferência', tipo: TipoCompeticao.europeia, fotmob: 10216),
  // seleções
  Competicao(id: 'liga-nacoes', desporto: _f, nome: 'Liga das Nações', tipo: TipoCompeticao.selecoes, fotmob: 9806),
  Competicao(
      id: 'liga-nacoes-bcd', desporto: _f, nome: 'Liga das Nações (B, C e D)', tipo: TipoCompeticao.selecoes,
      fotmobNome: r'nations league [bcd]\b'),
  Competicao(id: 'europeu', desporto: _f, nome: 'Europeu', tipo: TipoCompeticao.selecoes, fotmob: 50),
  Competicao(
      id: 'europeu-qualificacao', desporto: _f, nome: 'Qualificação do Europeu', tipo: TipoCompeticao.selecoes,
      fotmobNome: r'euro qualification|euro qualif'),
  Competicao(id: 'mundial', desporto: _f, nome: 'Mundial', tipo: TipoCompeticao.selecoes, fotmob: 77),
  Competicao(
      id: 'mundial-qualificacao', desporto: _f, nome: 'Qualificação do Mundial (UEFA e CONMEBOL)',
      tipo: TipoCompeticao.selecoes, fotmobNome: r'world cup qualification (uefa|conmebol|south america)'),
  Competicao(id: 'copa-america', desporto: _f, nome: 'Copa América', tipo: TipoCompeticao.selecoes, fotmob: 44),
  Competicao(id: 'amigaveis', desporto: _f, nome: 'Amigáveis de seleções', tipo: TipoCompeticao.selecoes, fotmob: 114),
  // ténis (ESPN; fase 2)
  Competicao(id: 'atp', desporto: Desporto.tenis, nome: 'ATP (250+)', tipo: TipoCompeticao.circuito, espn: 'atp'),
  Competicao(id: 'wta', desporto: Desporto.tenis, nome: 'WTA (250+)', tipo: TipoCompeticao.circuito, espn: 'wta'),
  Competicao(
      id: 'taca-davis', desporto: Desporto.tenis, nome: 'Taça Davis e BJK Cup', tipo: TipoCompeticao.selecoes,
      espn: 'atp', seguidaPorOmissao: false),
  // basquetebol (fase 2)
  Competicao(id: 'nba', desporto: Desporto.basquetebol, nome: 'NBA', tipo: TipoCompeticao.liga, espn: 'nba'),
  Competicao(
      id: 'lpb', desporto: Desporto.basquetebol, nome: 'Liga Betclic (LPB)', tipo: TipoCompeticao.liga,
      fpb: 'Liga Betclic Masculina'),
];

final catalogoCanais = <CanalTv>[
  const CanalTv(
      id: 'sporttvmais', nome: 'Sport TV +', meo: 'SPTVHD', sportTv: 'SPORT.TV +',
      nomesFotmob: ['Sport TV + Plus', 'Sport TV +', 'Sport TV Plus'],
      alternativos: ['sporttv+', 'sporttvplus', 'sporttvmais', 'stv+']),
  for (var n = 1; n <= 7; n++)
    CanalTv(
        id: 'sporttv$n', nome: 'Sport TV $n', meo: 'SPT${n}HD', sportTv: 'SPORT.TV$n',
        nomesFotmob: ['Sport TV $n'], alternativos: ['sporttv$n', 'stv$n']),
  for (var n = 1; n <= 5; n++)
    CanalTv(
        id: 'dazn$n', nome: 'DAZN $n', meo: 'DAZN$n', nomesFotmob: ['DAZN $n'], daznAntigo: true,
        alternativos: ['dazn$n', 'daznsports$n', 'eleven$n', 'elevensports$n']),
  const CanalTv(
      id: 'btv', nome: 'BTV', meo: 'SLBHD', nomesFotmob: ['BTV', 'Benfica TV'],
      alternativos: ['btv', 'benficatv', 'slbenficatv', 'btv1']),
  const CanalTv(id: 'sportingtv', nome: 'Sporting TV', meo: 'SCPHD', nomesFotmob: ['Sporting TV'], alternativos: ['sportingtv']),
  const CanalTv(id: 'portocanal', nome: 'Porto Canal', meo: 'PORTO', nomesFotmob: ['Porto Canal'], alternativos: ['portocanal']),
  const CanalTv(id: 'canal11', nome: 'Canal 11', meo: 'C11', nomesFotmob: ['Canal 11'], alternativos: ['canal11']),
  const CanalTv(id: 'abolatv', nome: 'A Bola TV', meo: 'ABOLA', nomesFotmob: ['A Bola TV'], alternativos: ['abolatv']),
  const CanalTv(id: 'rtp1', nome: 'RTP1', meo: 'RTP1', nomesFotmob: ['RTP1', 'RTP 1'], alternativos: ['rtp1']),
  const CanalTv(id: 'rtp2', nome: 'RTP2', meo: 'RTP2', nomesFotmob: ['RTP2', 'RTP 2'], alternativos: ['rtp2']),
  const CanalTv(id: 'sic', nome: 'SIC', meo: 'SIC', nomesFotmob: ['SIC'], alternativos: ['sic']),
  const CanalTv(id: 'tvi', nome: 'TVI', meo: 'TVI', nomesFotmob: ['TVI'], alternativos: ['tvi']),
  const CanalTv(
      id: 'vmaistvi', nome: 'V+ TVI', meo: 'VMAISTVI', nomesFotmob: ['V+ TVI', 'V+'],
      alternativos: ['v+tvi', 'vmaistvi', 'v+', 'vmais']),
  const CanalTv(
      id: 'eurosport1', nome: 'Eurosport 1', meo: 'EURHD', nomesFotmob: ['Eurosport 1', 'Eurosport'],
      alternativos: ['eurosport1', 'eurosport']),
  const CanalTv(id: 'eurosport2', nome: 'Eurosport 2', meo: 'EURS2HD', nomesFotmob: ['Eurosport 2'], alternativos: ['eurosport2']),
];

CanalTv? canalPorId(String id) {
  for (final c in catalogoCanais) {
    if (c.id == id) return c;
  }
  return null;
}

/// O canal com este nome no guia de TV do FotMob (null = não é um canal português do catálogo).
CanalTv? canalDoFotmob(String nome) {
  final n = nome.trim().toLowerCase();
  for (final c in catalogoCanais) {
    if (c.nomesFotmob.any((x) => x.toLowerCase() == n)) return c;
  }
  return null;
}

/// O canal com este `canal.nome` no guia da Sport TV.
CanalTv? canalDaSportTv(String nome) {
  final n = nome.trim().toUpperCase();
  for (final c in catalogoCanais) {
    if (c.sportTv == n) return c;
  }
  return null;
}

Competicao? competicaoPorId(String id) {
  for (final c in catalogoCompeticoes) {
    if (c.id == id) return c;
  }
  return null;
}
