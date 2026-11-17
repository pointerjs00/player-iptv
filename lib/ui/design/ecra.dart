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
