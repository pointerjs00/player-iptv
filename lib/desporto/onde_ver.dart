/// As fontes de um canal nas listas e a ordem em que se mostram e experimentam (spec §8).
library;

import 'package:flutter/foundation.dart' show Listenable;

import '../dados/biblioteca.dart';
import '../modelo/canal.dart';
import '../ui/design/estado_lista.dart' show EstadoLista, estadoDe;
import 'modelo.dart';
import 'preferencias_jogos.dart';

/// Um canal de uma lista (uma fonte para o player).
class FonteCanal {
  const FonteCanal(this.lista, this.canal, {this.qualidade = Qualidade.hd, this.confianca = 1, this.canalTv});
  final Lista lista;
  final Canal canal;
  final Qualidade qualidade;

  /// < 1 para nomes antigos (Eleven → DAZN).
  final double confianca;

  /// O canal português de que é fonte (para guardar «funcionou da última vez»).
  final String? canalTv;
}

/// De onde o ecrã «Jogos» tira as fontes de cada canal (o [IndiceCanais]; nos testes, um falso).
abstract interface class FontesDosCanais implements Listenable {
  /// As fontes do canal `canalTv` em todas as listas (sem ordem).
  List<FonteCanal> fontes(String canalTv);

  /// Listas que ainda não têm canais em cache (não entram no «Onde ver»).
  int get listasSemCache;

  /// Relê as listas cuja cache de canais mudou.
  Future<void> atualizar();
}

int _estado(Lista l) => switch (estadoDe(l)) {
      EstadoLista.funciona => 0,
      EstadoLista.inconclusiva => 1,
      EstadoLista.porVerificar => 2,
      EstadoLista.naoFunciona => 3,
    };

/// Pela probabilidade de funcionar: a que funcionou da última vez; depois as listas que
/// funcionam (a verificação mais recente primeiro), a qualidade preferida, as inconclusivas e
/// por verificar; as que não funcionam no fim.
List<FonteCanal> ordenarFontes(List<FonteCanal> fontes, {UltimaFonte? ultima, Qualidade preferida = Qualidade.fhd}) {
  bool eUltima(FonteCanal f) => ultima != null && f.lista.id == ultima.listaId && f.canal.id == ultima.canalId;
  int qualidade(FonteCanal f) {
    final d = f.qualidade.index - preferida.index;
    return d == 0 ? 0 : (d > 0 ? d : 10 - d); // acima da preferida antes de abaixo
  }

  final r = [...fontes];
  r.sort((a, b) {
    final u = (eUltima(a) ? 0 : 1) - (eUltima(b) ? 0 : 1);
    if (u != 0) return u;
    final e = _estado(a.lista) - _estado(b.lista);
    if (e != 0) return e;
    final da = a.lista.ultima?.data, db = b.lista.ultima?.data;
    if (da != null && db != null && da != db) return db.compareTo(da);
    final q = qualidade(a) - qualidade(b);
    if (q != 0) return q;
    return b.confianca.compareTo(a.confianca);
  });
  return r;
}

/// A lista não funciona (mostra-se esbatida no fim).
bool fonteNaoFunciona(FonteCanal f) => estadoDe(f.lista) == EstadoLista.naoFunciona;

/// O logótipo de um canal do catálogo: o primeiro que as listas trazem para ele ('' sem nenhum).
/// A MEO tem os logótipos, mas recusa a app (ver a memória do projeto): ficam os das listas.
String logoDoCanal(String canalTv, FontesDosCanais fontes) {
  for (final f in fontes.fontes(canalTv)) {
    if (f.canal.logo.isNotEmpty) return f.canal.logo;
  }
  return '';
}
