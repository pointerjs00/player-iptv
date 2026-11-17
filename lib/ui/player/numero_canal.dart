/// O número do canal escrito com os algarismos do comando e o "canal visto antes".
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../modelo/canal.dart';
import '../design/componentes.dart';
import '../design/ecra.dart';
import '../design/tokens.dart';

/// Quanto se espera pelo algarismo seguinte antes de saltar para o canal escrito.
const tempoNumero = Duration(seconds: 2);

/// Quantos algarismos cabem num número de canal.
const maxAlgarismos = 4;

final _algarismos = {
  for (var i = 0; i < 10; i++) ...{
    LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + i): i,
    LogicalKeyboardKey(LogicalKeyboardKey.numpad0.keyId + i): i,
  },
};

/// O algarismo de uma tecla (0–9 em cima ou no teclado numérico); null = não é algarismo.
int? algarismoDe(LogicalKeyboardKey k) => _algarismos[k];

/// O índice do canal número `n` em `canais`: o número do portal ([Canal.numero]) quando a lista
/// os tem; senão a posição na lista (1 = o primeiro). null = não existe.
int? indicePorNumero(List<Canal> canais, int n) {
  if (n < 1) return null;
  if (canais.any((c) => c.numero != null)) {
    final i = canais.indexWhere((c) => c.numero == n);
    return i < 0 ? null : i;
  }
  return n <= canais.length ? n - 1 : null;
}

/// O canal a tocar e o anterior (para alternar entre os dois últimos).
class HistoricoCanais {
  HistoricoCanais(this.atual);

  int atual;
  int? anterior;

  /// Vai para `i` (o atual passa a anterior). null = já estava nele.
  int? irPara(int i) {
    if (i == atual) return null;
    anterior = atual;
    atual = i;
    return i;
  }

  /// Troca o atual com o anterior. null = não há anterior.
  int? alternar() {
    final a = anterior;
    return a == null ? null : irPara(a);
  }

  /// Outra lista de canais: os índices antigos já não servem.
  void novaLista(int i) {
    atual = i;
    anterior = null;
  }
}

/// O número a ser escrito, grande no canto do vídeo.
class MostradorNumero extends StatelessWidget {
  const MostradorNumero({super.key, required this.numero});
  final String numero;

  @override
  Widget build(BuildContext context) {
    final tv = ecraTv(context);
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(Tokens.e32),
        child: Semantics(
          liveRegion: true,
          label: 'Canal $numero',
          child: SuperficieVidro(
            key: const Key('numero-canal'),
            cor: const Color(0xD90B0F17),
            raio: Tokens.raioBotao,
            elevacao: 2,
            padding: EdgeInsets.symmetric(horizontal: tv ? 28 : 20, vertical: tv ? 12 : 8),
            child: ExcludeSemantics(
              child: Text(numero,
                  style: TextStyle(
                      fontSize: tv ? 56 : 40,
                      fontWeight: FontWeight.w700,
                      color: Tokens.texto,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ),
        ),
      ),
    );
  }
}
