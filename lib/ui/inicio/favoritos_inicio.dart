import '../../dados/biblioteca.dart';
import '../../modelo/canal.dart';

/// Um canal favorito e a lista a que pertence (para a fila "Favoritos" do Início).
class FavoritoInicio {
  const FavoritoInicio({required this.lista, required this.canal});
  final Lista lista;
  final Canal canal;
}

/// O que o Início precisa de saber de cada lista com cache de canais: as contagens do cartão, os
/// favoritos e (só na lista do "Continuar a ver") o número do canal visto.
class ResumoLista {
  const ResumoLista({required this.canais, required this.grupos, required this.favoritos, this.numeroVisto});
  final int canais, grupos;
  final List<Canal> favoritos;
  final int? numeroVisto;
}

/// Lê a cache de cada lista, uma de cada vez (as grandes são pesadas), e guarda só o resumo, para
/// não ter todos os canais em memória. As listas sem cache ficam de fora. [visto] é o último
/// canal visto: o seu número (o do portal ou a posição na lista) vai no resumo da lista dele.
Future<Map<String, ResumoLista>> resumirListas(Biblioteca b, {UltimoVisto? visto}) async {
  final r = <String, ResumoLista>{};
  for (final l in List.of(b.listas)) {
    final c = await b.canaisEmCache(l.id);
    if (c == null) continue;
    r[l.id] = _resumir(l, c, visto?.lista == l.id ? visto!.canal : null);
  }
  return r;
}

ResumoLista _resumir(Lista l, ConteudoLista c, String? canalVisto) {
  int? numero;
  if (canalVisto != null) {
    final i = c.canais.indexWhere((x) => x.id == canalVisto);
    if (i >= 0) numero = c.canais[i].numero ?? i + 1;
  }
  final favoritos = l.favoritos.toSet();
  return ResumoLista(
    canais: c.canais.length,
    grupos: c.grupos.length,
    favoritos: [for (final x in c.canais) if (favoritos.contains(x.id)) x],
    numeroVisto: numero,
  );
}

/// Os resumos do Início, guardados por lista. Cada lista só se relê quando a cache dela (pela data
/// do ficheiro), os favoritos dela ou o canal visto nela mudam; as outras ficam como estavam. Assim
/// um favorito ou um canal visto numa lista não obriga a descodificar as caches de todas.
class ResumosInicio {
  ResumosInicio(this.biblioteca);
  final Biblioteca biblioteca;
  final _guardados = <String, ({DateTime data, int favoritos, String? visto, ResumoLista resumo})>{};

  static int _chaveFavoritos(Lista l) => Object.hash(l.favoritos.length, Object.hashAll(l.favoritos));

  /// Os resumos atuais de todas as listas com cache (as sem cache ficam de fora).
  Future<Map<String, ResumoLista>> atualizar({UltimoVisto? visto}) async {
    final b = biblioteca;
    final r = <String, ResumoLista>{};
    final listas = List.of(b.listas);
    final ids = {for (final l in listas) l.id};
    // as datas das caches pedem-se todas de uma vez (é só ver o ficheiro, sem o ler)
    final datas = await Future.wait([for (final l in listas) b.dataCache(l.id)]);
    for (final (i, l) in listas.indexed) {
      final data = datas[i];
      if (data == null) {
        _guardados.remove(l.id);
        continue;
      }
      // as chaves tiram-se antes de ler: se mudarem durante a leitura, a próxima volta relê
      final favoritos = _chaveFavoritos(l);
      final canalVisto = visto?.lista == l.id ? visto!.canal : null;
      final g = _guardados[l.id];
      if (g != null && g.data == data && g.favoritos == favoritos) {
        if (g.visto == canalVisto) {
          r[l.id] = g.resumo;
          continue;
        }
        if (canalVisto == null) {
          // o visto passou para outra lista: só sai o número, sem reler
          final semVisto = ResumoLista(canais: g.resumo.canais, grupos: g.resumo.grupos, favoritos: g.resumo.favoritos);
          _guardados[l.id] = (data: data, favoritos: favoritos, visto: null, resumo: semVisto);
          r[l.id] = semVisto;
          continue;
        }
      }
      final c = await b.canaisEmCache(l.id);
      if (c == null) {
        _guardados.remove(l.id);
        continue;
      }
      final resumo = _resumir(l, c, canalVisto);
      _guardados[l.id] = (data: data, favoritos: favoritos, visto: canalVisto, resumo: resumo);
      r[l.id] = resumo;
    }
    _guardados.removeWhere((id, _) => !ids.contains(id));
    return r;
  }
}

/// Os favoritos de todas as listas (pela ordem das listas e dos canais), até [maximo].
/// As listas sem cache de canais ficam de fora.
Future<List<FavoritoInicio>> favoritosInicio(Biblioteca b, {int maximo = 12}) async =>
    favoritosDeResumos(b.listas, await resumirListas(b), maximo: maximo);

/// Como [favoritosInicio], a partir de resumos já lidos.
List<FavoritoInicio> favoritosDeResumos(List<Lista> listas, Map<String, ResumoLista> resumos, {int maximo = 12}) {
  final f = <FavoritoInicio>[];
  for (final l in listas) {
    for (final c in resumos[l.id]?.favoritos ?? const <Canal>[]) {
      if (f.length >= maximo) return f;
      f.add(FavoritoInicio(lista: l, canal: c));
    }
  }
  return f;
}
