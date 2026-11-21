import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// O nome com que o libmpv e o ffmpeg aparecem na página de licenças (Definições -> Licenças).
const pacoteLicencasLibmpv = 'libmpv (mpv) e ffmpeg';

/// Os ficheiros de `third_party/libmpv_completo/` que vão na app (assets: dentro do APK e na pasta
/// da app no Windows): o aviso (versões, origem, onde está o código-fonte) e os textos das licenças.
const assetsLicencasLibmpv = [
  'third_party/libmpv_completo/AVISOS-LICENCAS.txt',
  'third_party/libmpv_completo/licencas/GPL-3.0.txt',
  'third_party/libmpv_completo/licencas/LGPL-2.1.txt',
];

/// Junta o libmpv e o ffmpeg (GPLv3) às licenças que a página de licenças do Flutter mostra.
void registarLicencasLibmpv() {
  LicenseRegistry.addLicense(() async* {
    for (final a in assetsLicencasLibmpv) {
      yield LicenseEntryWithLineBreaks(const [pacoteLicencasLibmpv], await rootBundle.loadString(a));
    }
  });
}
