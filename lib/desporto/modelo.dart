/// O modelo dos «Jogos»: competições, jogos, canais portugueses, o que dá em cada canal
/// (emissões) e a ligação entre um jogo e um canal (transmissão). Ver
/// docs/2026-11-27-jogos-design.md.
library;

enum Desporto { futebol, tenis, basquetebol }

/// O tipo de competição (para agrupar nas Definições).
enum TipoCompeticao { liga, taca, europeia, selecoes, circuito }

class Competicao {
  const Competicao({
    required this.id,
    required this.desporto,
    required this.nome,
    required this.tipo,
    this.fotmob,
    this.fotmobNome,
    this.fotmobPais,
    this.espn,
    this.fpb,
    this.seguidaPorOmissao = true,
  });

  /// Identificador estável na app ('liga-portugal', 'atp'…).
  final String id;
  final Desporto desporto;
  final String nome;
  final TipoCompeticao tipo;

  /// O `primaryId` da competição no FotMob (o `id` da resposta muda por época ou fase).
  final int? fotmob;

  /// Quando o id não está confirmado: o nome (expressão regular, sem acentos e em minúsculas)
  /// com que a competição aparece no FotMob, e o país (`ccode`, ex. 'KSA', 'INT').
  final String? fotmobNome;
  final String? fotmobPais;

  /// ESPN: o circuito ('atp', 'wta') ou a liga ('nba').
  final String? espn;

  /// FPB: a competição no calendário (ex. 'Liga Betclic Masculina').
  final String? fpb;
  final bool seguidaPorOmissao;
}

enum EstadoJogo { agendado, aoVivo, intervalo, terminado, adiado, cancelado }

class Jogo {
  const Jogo({
    required this.id,
    required this.desporto,
    required this.competicaoId,
    required this.casa,
    required this.fora,
    required this.inicio,
    this.estado = EstadoJogo.agendado,
    this.casaCurto,
    this.foraCurto,
    this.emblemaCasa,
    this.emblemaFora,
    this.resultado,
    this.minuto,
    this.ronda,
    this.feminino = false,
    this.torneio,
  });

  /// 'fonte:id' (ex. 'fotmob:5887685').
  final String id;
  final Desporto desporto;
  final String competicaoId;
  final String casa, fora;
  final String? casaCurto, foraCurto;
  final String? emblemaCasa, emblemaFora;

  /// Em UTC.
  final DateTime inicio;
  final EstadoJogo estado;

  /// "2–1" (null antes de começar).
  final String? resultado;

  /// "67'" ao vivo.
  final String? minuto;

  /// A jornada ou a ronda.
  final String? ronda;
  final bool feminino;

  /// Ténis: o nome do torneio (para casar com as emissões do torneio).
  final String? torneio;

  bool get aDecorrer => estado == EstadoJogo.aoVivo || estado == EstadoJogo.intervalo;
}

/// Um canal português, com o nome em cada fonte.
class CanalTv {
  const CanalTv({
    required this.id,
    required this.nome,
    required this.alternativos,
    this.meo,
    this.sportTv,
    this.nomesFotmob = const [],
    this.daznAntigo = false,
  });

  final String id;
  final String nome;

  /// O `callLetter` na grelha da MEO.
  final String? meo;

  /// O `canal.nome` no guia da Sport TV.
  final String? sportTv;

  /// Os nomes no guia de TV do FotMob.
  final List<String> nomesFotmob;

  /// Os nomes (já normalizados: minúsculas, sem acentos nem espaços a mais) com que aparece nas
  /// listas IPTV; o primeiro é o principal.
  final List<String> alternativos;

  /// DAZN 1–5: nas listas antigas chamam-se «Eleven» (confiança mais baixa).
  final bool daznAntigo;
}

/// O que dá num canal, de uma grelha.
class Emissao {
  const Emissao({
    required this.canal,
    required this.inicio,
    required this.fim,
    required this.titulo,
    required this.origem,
    this.direto,
    this.modalidade,
    this.evento,
  });

  /// [CanalTv.id].
  final String canal;

  /// Em UTC.
  final DateTime inicio, fim;
  final String titulo;

  /// null = a fonte não diz.
  final bool? direto;

  /// 'meo', 'sporttv', 'fotmob', 'epg'.
  final String origem;

  /// Da fonte, quando a dá à parte do título (Sport TV: «futebol», «LIGA PORTUGAL BETCLIC»).
  final String? modalidade;
  final String? evento;
}

enum Confianca { possivel, provavel, confirmado }

/// O jogo dá neste canal.
class Transmissao {
  const Transmissao({required this.jogoId, required this.canal, required this.confianca, required this.origem});
  final String jogoId;

  /// [CanalTv.id].
  final String canal;
  final Confianca confianca;
  final String origem;
}

enum Qualidade { sd, hd, fhd, uhd }
