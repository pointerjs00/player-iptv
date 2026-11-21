import 'package:material_ui/material_ui.dart';

/// O que se sabe do ecrã para lá do MediaQuery.
abstract final class EcraTv {
  /// O Android disse que é uma TV (ou um aparelho sem ecrã tátil): ver `configurarRealceFoco`.
  static bool nativo = false;
}

/// É uma TV (vista de longe)? Então canais, logótipos e cartões ficam maiores.
/// Sim se o Android o disse (canal nativo), ou num ecrã de ≥ 1200 lógicos sem toque
/// (navegação direcional). Uma TV 1080p Android tem só 960 lógicos: aí vale o canal nativo.
bool ecraTv(BuildContext context) {
  if (EcraTv.nativo) return true;
  return MediaQuery.navigationModeOf(context) == NavigationMode.directional &&
      MediaQuery.sizeOf(context).width >= 1200;
}

/// Abaixo desta largura (em lógicos), um ecrã que não é TV é um telemóvel ao alto.
const larguraTelemovel = 600.0;

/// É um telemóvel (ao alto)? Não é TV e o ecrã tem menos de [larguraTelemovel] de largura. Aí
/// as filas únicas do D-pad passam a `Wrap`, os alvos de toque têm 48 e as dicas do comando
/// saem; a TV e o Windows (largos) ficam como estão.
bool ecraTelemovel(BuildContext context) =>
    !ecraTv(context) && MediaQuery.sizeOf(context).width < larguraTelemovel;

/// O maior fator da letra do sistema que as alturas fixas acompanham: acima dele, a letra
/// dessas peças fica presa ([letraPresa]).
const limiteEscalaTexto = 2.0;

/// O fator da letra do sistema (1 = normal), preso a [limiteEscalaTexto]. As peças de altura
/// fixa (os cartões do Início, por exemplo) multiplicam a altura por ele.
double fatorTexto(BuildContext context) =>
    MediaQuery.textScalerOf(context).clamp(maxScaleFactor: limiteEscalaTexto).scale(1);

/// [child] com a letra do sistema presa a [limiteEscalaTexto], para caber nas alturas que
/// crescem com [fatorTexto].
Widget letraPresa(Widget child) =>
    MediaQuery.withClampedTextScaling(maxScaleFactor: limiteEscalaTexto, child: child);
