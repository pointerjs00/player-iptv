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
    int? numero;
    if (visto != null && visto.lista == l.id) {
      final i = c.canais.indexWhere((x) => x.id == visto.canal);
      if (i >= 0) numero = c.canais[i].numero ?? i + 1;
    }
    r[l.id] = ResumoLista(
      canais: c.canais.length,
      grupos: c.grupos.length,
      favoritos: [for (final x in c.canais) if (l.favoritos.contains(x.id)) x],
      numeroVisto: numero,
    );
  }
  return r;
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
