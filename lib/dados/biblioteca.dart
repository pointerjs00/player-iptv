/// As listas guardadas na app, com a última verificação, os favoritos e a cache de canais.
/// Um ficheiro JSON na pasta de dados da app, escrito de forma atómica.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../importar/importar.dart';
import '../modelo/canal.dart';
import '../modelo/conta.dart';
import '../rede/http.dart' show limiteIsolate;

/// Como se mostram os canais de uma lista.
enum OrdemCanais {
  /// A ordem do portal/lista.
  lista,

  /// Por nome, A–Z (sem acentos nem maiúsculas).
  az,
}

/// Os canais pela `ordem` (a lista original quando é a do portal).
List<Canal> ordenarCanais(List<Canal> canais, OrdemCanais ordem) {
  if (ordem == OrdemCanais.lista || canais.length < 2) return canais;
  final chaves = {for (final c in canais) c: semAcentos(c.nome)};
  return [...canais]..sort((a, b) => chaves[a]!.compareTo(chaves[b]!));
}

/// O último canal visto no Player ("Continuar a ver"): a lista e o que é preciso para o mostrar.
class UltimoVisto {
  const UltimoVisto({required this.lista, required this.canal, required this.nome, this.grupo = '',
      this.logo = '', this.data});

  /// O id da lista e o id do canal.
  final String lista, canal;
  final String nome, grupo, logo;
  final DateTime? data;

  UltimoVisto comLista(String id) =>
      UltimoVisto(lista: id, canal: canal, nome: nome, grupo: grupo, logo: logo, data: data);

  Map<String, dynamic> paraJson() => {
        'lista': lista, 'canal': canal, 'nome': nome, 'grupo': grupo, 'logo': logo,
        if (data != null) 'data': data!.toUtc().toIso8601String(),
      };

  static UltimoVisto? deJson(Object? j) {
    if (j is! Map || j['lista'] is! String || j['canal'] is! String) return null;
    return UltimoVisto(
      lista: j['lista'] as String, canal: j['canal'] as String, nome: '${j['nome'] ?? ''}',
      grupo: '${j['grupo'] ?? ''}', logo: '${j['logo'] ?? ''}', data: DateTime.tryParse('${j['data']}'),
    );
  }
}

/// Quantos canais ficam no histórico "Vistos há pouco" de cada lista.
const maxVistos = 20;

class Lista {
  Lista({required this.id, required this.ordem, required this.conta, this.ultima,
      Set<String>? favoritos, this.nomeProprio = '', Set<String>? gruposEscondidos,
      this.ordemCanais = OrdemCanais.lista, List<String>? vistos, this.favorita = false})
      : vistos = vistos ?? <String>[],
        favoritos = favoritos ?? <String>{},
        gruposEscondidos = gruposEscondidos ?? <String>{};

  final String id;

  /// Nº de ordem (não muda quando se apagam outras): dá o nome NNNHOST.
  final int ordem;

  /// Muda ao editar a lista (ver [Biblioteca.editar]).
  Conta conta;
  UltimaVerificacao? ultima;

  /// O nome escolhido pelo utilizador ('' = o nome gerado NNNHOST DDMMAA).
  String nomeProprio;

  /// Ids dos canais favoritos.
  final Set<String> favoritos;

  /// A lista inteira está nas favoritas (não confundir com [favoritos], os canais).
  bool favorita;

  /// Os grupos escondidos no ecrã de canais (e na pesquisa).
  final Set<String> gruposEscondidos;

  /// Ids dos últimos canais vistos: o mais recente primeiro, sem repetidos, até [maxVistos].
  final List<String> vistos;

  /// Como se ordenam os canais desta lista.
  OrdemCanais ordemCanais;

  String get nome => nomeProprio.trim().isNotEmpty ? nomeProprio.trim() : nomeLista(ordem, conta, ultima?.validade ?? '');

  /// Com INC à frente se a última verificação foi inconclusiva.
  String get nomeMostrado => ultima?.estado == 'inconclusivo' ? '$marcaInc$nome' : nome;

  Map<String, dynamic> paraJson() => {
        'id': id, 'ordem': ordem, 'conta': conta.paraJson(),
        if (ultima != null) 'ultima': ultima!.paraJson(),
        'favoritos': favoritos.toList(),
        if (nomeProprio.trim().isNotEmpty) 'nome_proprio': nomeProprio.trim(),
        if (gruposEscondidos.isNotEmpty) 'grupos_escondidos': gruposEscondidos.toList(),
        if (ordemCanais != OrdemCanais.lista) 'ordem_canais': ordemCanais.name,
        if (vistos.isNotEmpty) 'vistos': vistos,
        if (favorita) 'favorita': true,
      };

  static Lista? deJson(Object? j) {
    if (j is! Map) return null;
    try {
      return Lista(
        id: '${j['id']}', ordem: (j['ordem'] as num).toInt(),
        conta: Conta.deJson(Map<String, dynamic>.from(j['conta'] as Map)),
        ultima: UltimaVerificacao.deJson(j['ultima']),
        favoritos: {for (final f in (j['favoritos'] as List? ?? const [])) '$f'},
        nomeProprio: j['nome_proprio'] is String ? j['nome_proprio'] as String : '',
        gruposEscondidos: {for (final g in (j['grupos_escondidos'] as List? ?? const [])) '$g'},
        ordemCanais: OrdemCanais.values.asNameMap()[j['ordem_canais']] ?? OrdemCanais.lista,
        vistos: {for (final v in (j['vistos'] as List? ?? const [])) '$v'}.take(maxVistos).toList(),
        favorita: j['favorita'] == true,
      );
    } catch (_) {
      return null; // entrada estragada: ignora-se, as outras ficam
    }
  }
}

/// Um conjunto de listas cuja verificação se pode gravar: as do Player ([Biblioteca]) ou as do
/// Gestor (`AreaGestor`). O `ServicoVerificacao` grava os resultados na coleção que verifica.
abstract interface class ColecaoListas implements Listenable {
  List<Lista> get listas;
  Lista? porId(String id);
  Future<void> registarVerificacao(String id, UltimaVerificacao v);
}

/// O que uma restauração (cópia de segurança) vai fazer às listas.
class PlanoRestauro {
  const PlanoRestauro(this.listas, this.novas, this.atualizadas, this.removidas, this.idsSemCache);
  final List<Lista> listas;
  final int novas, atualizadas, removidas;

  /// As listas cuja cache de canais deixa de servir (saíram ou passaram a ser outra conta).
  final Set<String> idsSemCache;
}

/// O resultado de gravar uma restauração e como a desfazer (se outra gravação falhar a seguir).
class ResultadoRestauro {
  const ResultadoRestauro(this.plano, this.desfazer);
  final PlanoRestauro plano;
  final Future<void> Function() desfazer;
}

Lista _copiaLista(Lista l, {String? id, int? ordem}) => Lista(
    id: id ?? l.id, ordem: ordem ?? l.ordem, conta: l.conta, ultima: l.ultima,
    favoritos: Set.of(l.favoritos), nomeProprio: l.nomeProprio, gruposEscondidos: Set.of(l.gruposEscondidos),
    ordemCanais: l.ordemCanais, vistos: List.of(l.vistos), favorita: l.favorita);

/// Calcula as listas depois de restaurar `doFicheiro` sobre `atuais`, sem mexer em nenhuma.
/// - juntar: as da mesma conta (pela chave) ficam, com os favoritos e os grupos escondidos unidos,
///   o resultado mais recente, e o nome próprio e a ordem A–Z se não tinham; as novas entram no fim com o número de ordem seguinte;
/// - substituir: ficam só as do ficheiro (as repetidas dentro do ficheiro contam uma vez).
PlanoRestauro planearRestauro(List<Lista> atuais, List<Lista> doFicheiro, {required bool substituir}) {
  final vistas = <String>{};
  final deFicheiro = [for (final l in doFicheiro) if (vistas.add(chave(l.conta))) l];
  final ids = <String>{};
  String idLivre(String id) {
    var n = id;
    while (!ids.add(n)) {
      n = novoIdLista();
    }
    return n;
  }

  if (substituir) {
    final listas = [for (final l in deFicheiro) _copiaLista(l, id: idLivre(l.id))];
    final porId = {for (final l in listas) l.id: chave(l.conta)};
    final sem = {for (final l in atuais) if (porId[l.id] != chave(l.conta)) l.id};
    final removidas = atuais.where((a) => !vistas.contains(chave(a.conta))).length;
    return PlanoRestauro(listas, listas.length, 0, removidas, sem);
  }
  final porChave = {for (final l in atuais) chave(l.conta): l.id};
  final listas = [for (final l in atuais) _copiaLista(l)];
  for (final l in listas) {
    ids.add(l.id);
  }
  var proxima = atuais.fold<int>(0, (m, l) => max(m, l.ordem)) + 1;
  var novas = 0, atualizadas = 0;
  for (final f in [...deFicheiro]..sort((a, b) => a.ordem.compareTo(b.ordem))) {
    final idExistente = porChave[chave(f.conta)];
    if (idExistente == null) {
      listas.add(_copiaLista(f, id: idLivre(f.id), ordem: proxima++));
      novas++;
      continue;
    }
    final dest = listas.firstWhere((l) => l.id == idExistente);
    var mudou = false;
    final antes = dest.favoritos.length;
    dest.favoritos.addAll(f.favoritos);
    if (dest.favoritos.length != antes) mudou = true;
    final escondidosAntes = dest.gruposEscondidos.length;
    dest.gruposEscondidos.addAll(f.gruposEscondidos);
    if (dest.gruposEscondidos.length != escondidosAntes) mudou = true;
    if (dest.vistos.isEmpty && f.vistos.isNotEmpty) {
      dest.vistos.addAll(f.vistos);
      mudou = true;
    }
    if (f.favorita && !dest.favorita) {
      dest.favorita = true;
      mudou = true;
    }
    if (dest.ordemCanais == OrdemCanais.lista && f.ordemCanais != OrdemCanais.lista) {
      dest.ordemCanais = f.ordemCanais;
      mudou = true;
    }
    final u = f.ultima;
    if (u != null && (dest.ultima == null || u.data.isAfter(dest.ultima!.data))) {
      dest.ultima = u;
      mudou = true;
    }
    if (dest.nomeProprio.trim().isEmpty && f.nomeProprio.trim().isNotEmpty) {
      dest.nomeProprio = f.nomeProprio;
      mudou = true;
    }
    if (mudou) atualizadas++;
  }
  return PlanoRestauro(listas, novas, atualizadas, 0, const {});
}

/// Uma edição recusada (por exemplo, a conta nova já é outra lista do Player).
class ErroEdicao implements Exception {
  ErroEdicao(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}

/// Como juntar as listas enviadas pelo Gestor às do Player.
enum ModoEnvio {
  /// Junta (sem duplicar) e atualiza o resultado das que já existiam.
  adicionar,

  /// O Player fica com as enviadas e com o que [ManterAoSubstituir] pedir; o resto sai.
  substituir,
}

/// O que se mantém das listas que já estão no Player ao substituir (combina por «ou»).
/// Nenhum = o Player fica só com as enviadas.
enum ManterAoSubstituir { favoritas, funcionam, inconclusivas }

/// O que um envio para o Player mudou.
class ResumoEnvio {
  const ResumoEnvio({this.adicionadas = 0, this.atualizadas = 0, this.removidas = 0});
  final int adicionadas, atualizadas, removidas;
}

class Biblioteca extends ChangeNotifier implements ColecaoListas {
  Biblioteca._(this._pasta, this._listas);

  final Directory _pasta;
  final List<Lista> _listas;

  /// Os canais que a verificação testa ("rtp1", "sporttv1", "dazn1").
  List<String> canaisTeste = const ['rtp1'];

  UltimoVisto? _ultimoVisto;

  /// O último canal visto ("Continuar a ver"); null se não há ou se a lista já não existe.
  UltimoVisto? get ultimoVisto {
    final u = _ultimoVisto;
    return u != null && porId(u.lista) != null ? u : null;
  }

  @override
  List<Lista> get listas => List.unmodifiable(_listas);

  File get _ficheiro => File('${_pasta.path}${Platform.pathSeparator}biblioteca.json');
  Directory get _pastaCanais => Directory('${_pasta.path}${Platform.pathSeparator}canais');

  /// Abre (ou cria) a biblioteca em `pasta`. Um ficheiro estragado fica guardado como
  /// biblioteca.json.bak e a app começa vazia.
  /// Um erro ao *ler* (ficheiro bloqueado por outro processo ou pelo antivírus) é repetido e,
  /// se continuar, lançado: nunca se começa vazio por cima de uma biblioteca boa.
  static Future<Biblioteca> abrir(Directory pasta,
      {@visibleForTesting Future<String> Function(File f) ler = _lerTexto}) async {
    await pasta.create(recursive: true);
    final b = Biblioteca._(pasta, []);
    if (await b._ficheiro.exists()) {
      String? texto;
      for (var tentativa = 1; texto == null; tentativa++) {
        try {
          texto = await ler(b._ficheiro);
        } on FileSystemException {
          if (tentativa >= 5) rethrow;
          await Future<void>.delayed(Duration(milliseconds: 200 * tentativa));
        }
      }
      try {
        final dados = jsonDecode(texto);
        for (final j in (dados['listas'] as List)) {
          final l = Lista.deJson(j);
          if (l != null) b._listas.add(l);
        }
        final ct = dados['canais_teste'];
        if (ct is List && ct.isNotEmpty) b.canaisTeste = [for (final c in ct) '$c'];
        b._ultimoVisto = UltimoVisto.deJson(dados['ultimo_visto']);
      } catch (_) {
        // o texto leu-se bem mas não é uma biblioteca (JSON inválido ou outra forma): estragado
        await b._ficheiro.copy('${b._ficheiro.path}.bak');
      }
    }
    return b;
  }

  static Future<String> _lerTexto(File f) => f.readAsString();

  /// O nome do ficheiro temporário de uma gravação: com o pid e bytes aleatórios, para duas
  /// gravações (mesmo de dois processos) nunca escreverem no mesmo ficheiro.
  @visibleForTesting
  static String nomeTemporario(File f) => '${f.path}.$pid.${novoIdLista()}.tmp';

  /// Bloqueia a pasta de dados para esta instância da app (fica bloqueada enquanto o
  /// ficheiro devolvido estiver aberto). null = outra instância já a tem.
  static Future<RandomAccessFile?> bloquearInstancia(Directory pasta) async {
    await pasta.create(recursive: true);
    final raf = await File('${pasta.path}${Platform.pathSeparator}instancia.lock').open(mode: FileMode.append);
    try {
      await raf.lock(FileLock.exclusive);
      return raf;
    } on FileSystemException {
      await raf.close();
      return null;
    }
  }

  @override
  Lista? porId(String id) {
    for (final l in _listas) {
      if (l.id == id) return l;
    }
    return null;
  }

  /// Junta as listas novas (as repetidas, pela chave, só atualizam o resultado se este for
  /// mais recente). Devolve quantas eram novas.
  Future<int> adicionar(Iterable<Importada> importadas) async {
    final porChave = {for (final l in _listas) chave(l.conta): l};
    var novas = 0;
    var proxima = _listas.fold<int>(0, (m, l) => max(m, l.ordem)) + 1;
    for (final i in importadas) {
      final existente = porChave[chave(i.conta)];
      if (existente != null) {
        final u = i.ultima;
        if (u != null && (existente.ultima == null || u.data.isAfter(existente.ultima!.data))) {
          existente.ultima = u;
        }
        continue;
      }
      final l = Lista(id: _novoId(), ordem: proxima++, conta: i.conta, ultima: i.ultima);
      _listas.add(l);
      porChave[chave(i.conta)] = l;
      novas++;
    }
    await guardar();
    return novas;
  }

  Future<void> remover(String id) async {
    _listas.removeWhere((l) => l.id == id);
    if (_ultimoVisto?.lista == id) _ultimoVisto = null;
    final f = _ficheiroCanais(id);
    if (await f.exists()) await f.delete();
    await guardar();
  }

  /// Muda a conta e o nome próprio de uma lista ('' = o nome gerado). Se a chave da conta mudar
  /// (é outra conta), a cache de canais e o último resultado saem; com a mesma chave (por
  /// exemplo, só a password mudou) ficam. Devolve se a cache ficou. Lança [ErroEdicao] se a conta
  /// nova já for outra lista do Player (nada muda).
  Future<bool> editar(String id, Conta conta, {String nomeProprio = ''}) async {
    final l = porId(id);
    if (l == null) throw ErroEdicao('a lista já não existe');
    final k = chave(conta);
    final mesma = k == chave(l.conta);
    if (!mesma && _listas.any((o) => o.id != id && chave(o.conta) == k)) {
      throw ErroEdicao('já existe outra lista com esta conta');
    }
    final (contaAntes, nomeAntes, ultimaAntes) = (l.conta, l.nomeProprio, l.ultima);
    l
      ..conta = conta
      ..nomeProprio = nomeProprio.trim();
    if (!mesma) l.ultima = null;
    try {
      await guardar();
    } catch (_) {
      // o que se vê é sempre o que está no disco
      l
        ..conta = contaAntes
        ..nomeProprio = nomeAntes
        ..ultima = ultimaAntes;
      notifyListeners();
      rethrow;
    }
    if (!mesma) {
      try {
        final f = _ficheiroCanais(id);
        if (await f.exists()) await f.delete();
      } on FileSystemException {
        // ignora-se: o próximo "Atualizar" escreve por cima
      }
    }
    return mesma;
  }

  /// Recebe as listas enviadas pelo Gestor. Ao substituir, as listas do Player que não foram
  /// enviadas e não pertencem a nenhum dos filtros de [manter] saem (com os favoritos e a cache
  /// de canais). As enviadas que já existiam (pela chave) ficam com o resultado do Gestor e
  /// continuam favoritas se já o eram.
  Future<ResumoEnvio> receber(Iterable<Lista> doGestor, ModoEnvio modo,
      {Set<ManterAoSubstituir> manter = const {}}) async {
    final enviadas = {for (final l in doGestor) chave(l.conta): l};
    bool mantem(Lista l) => switch (modo) {
          ModoEnvio.adicionar => true,
          ModoEnvio.substituir => (manter.contains(ManterAoSubstituir.favoritas) && l.favorita) ||
              (manter.contains(ManterAoSubstituir.funcionam) && l.ultima?.estado == 'funciona') ||
              (manter.contains(ManterAoSubstituir.inconclusivas) && l.ultima?.estado == 'inconclusivo'),
        };
    // as listas mudam todas de uma vez (a interface nunca vê um envio a meio); a cache depois.
    // Se a gravação falhar, tudo volta a como estava (o que se vê é sempre o que está no disco)
    final antes = List.of(_listas);
    final ultimasAntes = {for (final l in _listas) l: l.ultima};
    final sair = [for (final l in _listas) if (!enviadas.containsKey(chave(l.conta)) && !mantem(l)) l];
    _listas.removeWhere(sair.contains);
    final porChave = {for (final l in _listas) chave(l.conta): l};
    var adicionadas = 0, atualizadas = 0;
    var proxima = _listas.fold<int>(0, (m, l) => max(m, l.ordem)) + 1;
    for (final MapEntry(key: k, value: g) in enviadas.entries) {
      final existente = porChave[k];
      if (existente == null) {
        _listas.add(Lista(id: _novoId(), ordem: proxima++, conta: g.conta, ultima: g.ultima));
        adicionadas++;
      } else if (g.ultima != null && !_mesmoResultado(existente.ultima, g.ultima!)) {
        existente.ultima = g.ultima;
        atualizadas++;
      }
    }
    try {
      await guardar();
    } catch (_) {
      _listas
        ..clear()
        ..addAll(antes);
      ultimasAntes.forEach((l, u) => l.ultima = u);
      notifyListeners();
      rethrow;
    }
    for (final l in sair) {
      try {
        final f = _ficheiroCanais(l.id);
        if (await f.exists()) await f.delete();
      } on FileSystemException {
        // uma cache que não se apaga já não é usada (o id não volta a existir)
      }
    }
    return ResumoEnvio(adicionadas: adicionadas, atualizadas: atualizadas, removidas: sair.length);
  }

  static bool _mesmoResultado(UltimaVerificacao? a, UltimaVerificacao b) =>
      a != null && a.estado == b.estado && a.data == b.data && a.validade == b.validade && a.motivo == b.motivo;

  @override
  Future<void> registarVerificacao(String id, UltimaVerificacao v) async {
    final l = porId(id);
    if (l == null) return;
    l.ultima = v;
    await guardar();
  }

  /// Aplica uma cópia de segurança (ver [planearRestauro]). Se a gravação falhar, tudo volta a
  /// como estava. `canaisTeste` só vale ao substituir. O `ultimoVisto` do ficheiro (que aponta para
  /// uma lista do ficheiro) passa para a lista restaurada da mesma conta; ao juntar só entra se não
  /// houver um local. O resultado traz como desfazer.
  Future<ResultadoRestauro> restaurar(List<Lista> doFicheiro,
      {required bool substituir, List<String>? canaisTeste, UltimoVisto? ultimoVisto}) async {
    final plano = planearRestauro(_listas, doFicheiro, substituir: substituir);
    final antes = List.of(_listas), testeAntes = this.canaisTeste, vistoAntes = _ultimoVisto;
    void repor() {
      _listas
        ..clear()
        ..addAll(antes);
      this.canaisTeste = testeAntes;
      _ultimoVisto = vistoAntes;
    }

    Future<void> desfazer() async {
      repor();
      await guardar();
    }

    UltimoVisto? visto;
    if (ultimoVisto != null) {
      final daLista = doFicheiro.where((l) => l.id == ultimoVisto.lista).firstOrNull;
      final destino = daLista == null
          ? null
          : plano.listas.where((l) => chave(l.conta) == chave(daLista.conta)).firstOrNull;
      if (destino != null) visto = ultimoVisto.comLista(destino.id);
    }
    final localValido = this.ultimoVisto;
    _listas
      ..clear()
      ..addAll(plano.listas);
    if (substituir && canaisTeste != null && canaisTeste.isNotEmpty) {
      this.canaisTeste = List.unmodifiable(canaisTeste);
    }
    if (substituir) {
      _ultimoVisto = visto;
    } else if (localValido == null && visto != null) {
      _ultimoVisto = visto;
    }
    try {
      await guardar();
    } catch (_) {
      repor();
      notifyListeners();
      rethrow;
    }
    return ResultadoRestauro(plano, desfazer);
  }

  /// Apaga a cache de canais de listas que já não existem (ou mudaram de conta).
  Future<void> apagarCaches(Iterable<String> ids) async {
    for (final id in ids) {
      try {
        final f = _ficheiroCanais(id);
        if (await f.exists()) await f.delete();
      } on FileSystemException {
        // uma cache que não se apaga já não é usada
      }
    }
  }

  Future<void> definirCanaisTeste(List<String> ids) async {
    if (ids.isEmpty) return;
    canaisTeste = List.unmodifiable(ids);
    await guardar();
  }

  /// Esconde (ou volta a mostrar) um grupo da lista `id`.
  Future<void> esconderGrupo(String id, String grupo, bool esconder) async {
    final l = porId(id);
    if (l == null) return;
    final mudou = esconder ? l.gruposEscondidos.add(grupo) : l.gruposEscondidos.remove(grupo);
    if (mudou) await guardar();
  }

  /// Muda a ordem dos canais da lista `id`.
  Future<void> definirOrdem(String id, OrdemCanais ordem) async {
    final l = porId(id);
    if (l == null || l.ordemCanais == ordem) return;
    l.ordemCanais = ordem;
    await guardar();
  }

  /// Regista o canal que abriu no player (para o "Continuar a ver"). Sem gravar se for o mesmo.
  Future<void> registarVisto(String listaId, Canal canal) async {
    final l = porId(listaId);
    if (l == null) return;
    var mudou = false;
    if (l.vistos.isEmpty || l.vistos.first != canal.id) {
      l.vistos
        ..remove(canal.id)
        ..insert(0, canal.id);
      if (l.vistos.length > maxVistos) l.vistos.removeRange(maxVistos, l.vistos.length);
      mudou = true;
    }
    final u = _ultimoVisto;
    if (!mudou && u != null && u.lista == listaId && u.canal == canal.id) return;
    _ultimoVisto = UltimoVisto(lista: listaId, canal: canal.id, nome: canal.nome, grupo: canal.grupo,
        logo: canal.logo, data: DateTime.now());
    await guardar();
  }

  Future<void> alternarFavorito(String id, String canalId) async {
    final l = porId(id);
    if (l == null) return;
    if (!l.favoritos.remove(canalId)) l.favoritos.add(canalId);
    await guardar();
  }

  /// Põe a lista nas favoritas, ou tira-a.
  Future<void> alternarFavorita(String id) async {
    final l = porId(id);
    if (l == null) return;
    l.favorita = !l.favorita;
    await guardar();
  }

  File _ficheiroCanais(String id) => File('${_pastaCanais.path}${Platform.pathSeparator}$id.json');

  /// Quantas vezes se leu a cache de cada lista (pelo id): os testes confirmam que o Início não
  /// relê caches que não mudaram.
  @visibleForTesting
  final leiturasCache = <String, int>{};

  Future<ConteudoLista?> canaisEmCache(String id) async {
    leiturasCache.update(id, (n) => n + 1, ifAbsent: () => 1);
    final f = _ficheiroCanais(id);
    if (!await f.exists()) return null;
    try {
      // uma lista grande (100 mil canais) lê-se fora da thread da interface
      if (await f.length() < limiteIsolate) return _lerCanais(await f.readAsString());
      return await _lerCanaisNumIsolate(f.path);
    } catch (_) {
      return null;
    }
  }

  /// Quando foi gravada a cache de canais (null = sem cache).
  Future<DateTime?> dataCache(String id) async {
    try {
      final f = _ficheiroCanais(id);
      return await f.exists() ? await f.lastModified() : null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> guardarCanais(String id, ConteudoLista c) async {
    await _pastaCanais.create(recursive: true);
    // o JSON de uma lista grande faz-se num isolate (só se mandam os mapas, já simples)
    final texto = c.canais.length < 2000
        ? jsonEncode(c.paraJson())
        : await _codificarNumIsolate(c);
    await _emFila(() => _escreverAtomico(_ficheiroCanais(id), texto));
  }

  /// As gravações fazem-se uma de cada vez (várias verificações podem acabar juntas).
  Future<void> _gravacoes = Future.value();

  Future<void> guardar() {
    // o texto é tirado agora (o estado deste momento); a escrita espera pela anterior
    final texto = const JsonEncoder.withIndent(' ').convert({
      'versao': 1, 'canais_teste': canaisTeste, 'listas': [for (final l in _listas) l.paraJson()],
      if (ultimoVisto != null) 'ultimo_visto': ultimoVisto!.paraJson(),
    });
    notifyListeners();
    return _emFila(() => _escreverAtomico(_ficheiro, texto));
  }

  Future<void> _emFila(Future<void> Function() f) {
    final r = _gravacoes.then((_) => f());
    _gravacoes = r.catchError((_) {});
    return r;
  }

  static Future<void> _escreverAtomico(File f, String texto) => escreverAtomico(f, texto);

  static String _novoId() => novoIdLista();
}

/// Escreve `texto` em `f` de forma atómica (ficheiro temporário + rename).
Future<void> escreverAtomico(File f, String texto) async {
  final tmp = File(Biblioteca.nomeTemporario(f));
  await tmp.writeAsString(texto, flush: true);
  await tmp.rename(f.path);
}

final _rnd = Random.secure();

/// Um id aleatório para uma lista nova.
String novoIdLista() => List.generate(6, (_) => _rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

ConteudoLista _lerCanais(String texto) => ConteudoLista.deJson(jsonDecode(texto) as Map<String, dynamic>);

// funções de topo: a closure mandada para o isolate não pode levar o `this` da Biblioteca
Future<ConteudoLista> _lerCanaisNumIsolate(String caminho) =>
    Isolate.run(() => _lerCanais(File(caminho).readAsStringSync()));

Future<String> _codificarNumIsolate(ConteudoLista c) => Isolate.run(() => jsonEncode(c.paraJson()));
