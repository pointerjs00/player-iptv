import 'dart:async';

import 'progresso.dart';

/// Continuar um direto quando o servidor fecha a ligação.
///
/// Muitos servidores IPTV fecham a ligação ao fim de uns segundos (visto em portais Stalker a
/// cada 6–35 s) e respondem a uma ligação nova com um bloco do que já passou. Com a reconexão do
/// ffmpeg dentro do mesmo stream, esse bloco entrava a seguir ao que já se tinha visto, com os
/// tempos a recomeçar ("Invalid audio PTS: 33.0 -> 10.0", "Reset playback due to audio timestamp
/// reset"): o vídeo voltava atrás 10–25 s. Por isso o mpv não reconecta
/// (`configuracao_mpv.dart`): toca o buffer até ao fim e, só aí, o player pede o canal de novo
/// (link novo; no Stalker o link antigo já não serve) com "A carregar…" no ecrã. Nunca volta
/// atrás; salta para a frente só o tempo que demorou a reabrir.
///
/// Só nos diretos: um ficheiro com fim (filme de uma lista M3U) acaba normalmente.
/// O que o player faz com um erro durante "A carregar…" (ver [ContinuarDireto.falhou]).
enum Retoma {
  /// Reabre daqui a um pouco (o "A carregar…" fica).
  agendada,

  /// Esta tentativa já tem uma reabertura marcada (outro erro da mesma falha): ignora-se.
  jaAgendada,

  /// Já se tentou o suficiente: o cartão de erro.
  desistir,
}

class ContinuarDireto {
  /// Uma reabertura que deu pelo menos isto de imagem valeu a pena (um portal que corta a cada
  /// 6–10 s continua a ver-se).
  static const proveito = Duration(seconds: 5);

  /// Reaberturas seguidas sem [proveito] antes de desistir (canal morto: cartão de erro).
  static const maximoSemProveito = 3;

  /// As esperas antes de tentar outra vez uma reabertura que falhou (rede, link, 401 passageiro).
  static const esperas = [Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 4)];

  int _semProveito = 0;
  int _falhas = 0;

  /// A tentativa (o `pedido` do player) que já tem uma reabertura marcada, e o temporizador dela.
  int? _pedidoAgendado;
  Timer? _agendada;

  /// O fim do buffer de um direto que estava a tocar: continua-se. A abrir quem decide é o vigia;
  /// com erro, em pausa ou num ficheiro com fim não se faz nada.
  static bool deve(
          {required bool fimDoBuffer,
          required bool aAbrir,
          required bool erro,
          required bool aTocar,
          required bool direto}) =>
      fimDoBuffer && direto && !aAbrir && !erro && aTocar;

  /// Pelas propriedades `seekable` e `partially-seekable` do mpv: o mesmo classificador da barra
  /// de progresso ([eDiretoMpv]). Sem resposta (vazio) trata-se como direto.
  static bool eDireto(String seekable, {String partiallySeekable = ''}) =>
      eDiretoMpv(seekable: seekable, partiallySeekable: partiallySeekable);

  /// Um ficheiro com fim que parou bem antes dele (mais de [margemFim]): foi um corte do
  /// servidor, não o fim (sem isto ficava parado na última imagem). Duração desconhecida: não.
  static bool cortadoAntesDoFim({required Duration posicao, required Duration duracao}) =>
      duracao > Duration.zero && duracao - posicao > margemFim;
  static const margemFim = Duration(seconds: 10);

  /// O que se viu por último (`posicaoAntiga` no stream antigo) fica a que `time-pos` do stream
  /// novo? Pelos PTS: o servidor manda o mesmo TS a cada ligação, só começa noutro ponto
  /// (`demuxer-start-time`). Visto no libmpv da app: ligação A em 10420.003, saltou para o fim do
  /// buffer (29.497); ligação B em 10430.008 -> 19.492 s, que abrir B do início repetia.
  /// null se falta algum.
  static double? posicaoNoNovo({required double? inicioAntigo, required double? posicaoAntiga, required double? inicioNovo}) =>
      inicioAntigo == null || posicaoAntiga == null || inicioNovo == null ? null : inicioAntigo + posicaoAntiga - inicioNovo;

  /// Acima disto a diferença dos PTS não faz sentido (o servidor recomeçou os tempos): não se salta.
  static const saltoMaximo = 600.0;

  /// Depois de reabrir: quanto saltar para a frente (seek relativo) para chegar ao `alvo`
  /// ([posicaoNoNovo]) sem repetir nada. `aFrente`: quanto se pode avançar no cache. Se o alvo ainda
  /// não chegou, `esperar`; na `ultimaTentativa` vai até onde dá. Nunca para trás.
  static ({double? salto, bool esperar}) saltoAoRetomar(
      {required double alvo, required double posicao, required double? aFrente, required bool ultimaTentativa}) {
    final falta = alvo - posicao;
    if (falta < 1 || falta > saltoMaximo) return (salto: null, esperar: false);
    if (aFrente != null && aFrente >= falta) return (salto: falta, esperar: false);
    if (!ultimaTentativa) return (salto: null, esperar: true);
    return (salto: aFrente != null && aFrente >= 1 ? aFrente : null, esperar: false);
  }

  /// O ponto do corte num direto: os dois PTS ([posicaoNoNovo]), ou null se falta algum (então não
  /// há salto por que esperar).
  static ({double inicio, double posicao})? pontoDoCorte({required String inicio, required String posicao}) {
    final i = double.tryParse(inicio.trim()), p = double.tryParse(posicao.trim());
    if (i == null || p == null || !i.isFinite || !p.isFinite) return null;
    return (inicio: i, posicao: p);
  }

  /// Regista uma reabertura depois de `tocou` de imagem desde a anterior; falso = desistir.
  bool permitir({required Duration tocou}) {
    if (tocou >= proveito) {
      _semProveito = 0;
      return true;
    }
    _semProveito++;
    return _semProveito <= maximoSemProveito;
  }

  /// Uma reabertura falhou: quanto esperar antes de tentar outra vez (null = desistir).
  Duration? esperaAntesDeTentar() {
    if (_falhas >= esperas.length) return null;
    return esperas[_falhas++];
  }

  /// Um erro na tentativa `pedido` de reabrir: marca `reabrir` para daqui a [esperas] (uma por
  /// tentativa). Uma falha de ligação costuma chegar como dois erros (a linha do `tcp` e o
  /// "Failed to open"): o segundo da mesma tentativa não gasta outra espera.
  Retoma falhou(int pedido, void Function() reabrir) {
    if (_pedidoAgendado == pedido) return Retoma.jaAgendada;
    final espera = esperaAntesDeTentar();
    if (espera == null) return Retoma.desistir;
    _pedidoAgendado = pedido;
    _agendada?.cancel();
    _agendada = Timer(espera, reabrir);
    return Retoma.agendada;
  }

  /// Voltou a haver imagem: as falhas esquecem-se.
  void abriu() {
    _falhas = 0;
    _pedidoAgendado = null;
  }

  /// Canal novo (escolhido pelo utilizador) ou o player fechou: tudo recomeça e uma reabertura
  /// marcada é cancelada.
  void reiniciar() {
    _semProveito = 0;
    _falhas = 0;
    _pedidoAgendado = null;
    _agendada?.cancel();
    _agendada = null;
  }
}

/// O que uma ligação deu de imagem nova, para o [ContinuarDireto.permitir]: a posição no corte menos
/// a posição de onde a ligação começou (num VOD reaberto em `start:`, o ponto do filme; depois do
/// salto automático para onde se estava, o ponto depois do salto), ou o tempo de parede, o maior.
/// Assim os saltos à mão para o fim do buffer contam, mas o salto automático e o ponto do filme não.
class LigacaoDireto {
  double? _inicio;

  /// A primeira imagem chegou com o `time-pos` em `posicao` (só a primeira vez conta).
  void abriu(double? posicao) => _inicio ??= posicao;

  /// O salto automático depois de reabrir deixou o `time-pos` em `posicao`.
  void saltou(double posicao) => _inicio = posicao;

  Duration proveito({required Duration parede, required double? posicaoNoCorte}) {
    final c = posicaoNoCorte;
    final deu = c == null || !c.isFinite ? 0.0 : c - (_inicio ?? 0);
    final d = deu <= 0 ? Duration.zero : Duration(microseconds: (deu * 1e6).round());
    return d > parede ? d : parede;
  }
}

/// O som enquanto se espera pelo salto depois de reabrir: desligado (o bocado repetido não se ouve),
/// e só volta com o salto feito e a primeira imagem à vista. Mudar o silêncio da sessão durante a
/// espera não o liga. Cada método devolve o que pôr em `mute` no mpv agora (null: nada).
class MudoDuranteSalto {
  bool _aEsconder = false;
  bool _esperaImagem = false;

  String comecar() {
    _aEsconder = true;
    _esperaImagem = false;
    return 'yes';
  }

  String? acabouSalto({required bool silencio, required bool temImagem}) {
    if (!_aEsconder) return null;
    if (!temImagem) {
      _esperaImagem = true;
      return null;
    }
    _aEsconder = false;
    return silencio ? 'yes' : 'no';
  }

  String? primeiraImagem({required bool silencio}) {
    if (!_aEsconder || !_esperaImagem) return null;
    _aEsconder = false;
    _esperaImagem = false;
    return silencio ? 'yes' : 'no';
  }

  /// O utilizador mudou o silêncio: vai para o mpv, menos enquanto se esconde o som.
  String? mudouSilencio(bool silencio) => _aEsconder ? null : (silencio ? 'yes' : 'no');

  void reiniciar() {
    _aEsconder = false;
    _esperaImagem = false;
  }
}
