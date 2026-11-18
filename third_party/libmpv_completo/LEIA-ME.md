# libmpv completo (com filtros do ffmpeg)

O libmpv que o `media_kit_libs_*_video` traz é um build mínimo: o ffmpeg foi compilado com
`--disable-filters`, por isso não há `bwdif`/`yadif` e o vídeo entrelaçado (1080i/576i) não se
desentrelaça por campo (25i -> 25 imagens/s com riscas, em vez de 50). O player usa por isso um
libmpv **completo**, o mesmo tipo de build que o "sfvip player" usa.

Nada disto está no repositório (a DLL tem ~120 MB, as libs Android ~30 MB por ABI): são descarregadas
no build, com o SHA-256 fixado, e o build falha se não bater.

## Windows

- Origem: <https://github.com/shinchiro/mpv-winbuild-cmake/releases/tag/20261111>
- Ficheiro: `mpv-dev-x86_64-20261111-git-bcde6b93cc.7z`
  - SHA-256 do `.7z`: `273c079b11ea5575822f972756f4c9a71149a5c10130353abeb8586738938452`
  - SHA-256 do `libmpv-2.dll` (121 789 952 bytes): `ver SHA256.txt`
- mpv `v0.42.0-38-gbcde6b93c`, ffmpeg `N-128766-gcd4e96eb3`, API do cliente 2.6 (o media_kit usava mpv 0.36).
- `windows/libmpv_completo.cmake` descarrega e extrai para `build/windows/x64/libmpv-completo/`;
  `windows/CMakeLists.txt` instala essa DLL no lugar da `libmpv-2.dll` do media_kit (que se
  continua a extrair, mas já não se instala; os `.h` e o `libmpv.dll.a` dela servem para compilar o
  plugin de vídeo e têm os mesmos símbolos).
- O pacote (`python ferramentas/empacotar.py`) leva a DLL e a pasta `licencas-libmpv/`.

## Android

- Origem: <https://github.com/mpv-android/mpv-android/releases/tag/2026-09-17>
- Ficheiros (de cada APK tiram-se as `lib/<abi>/*.so` listadas em `SHA256.txt`; o `libplayer.so`, o JNI da
  app do mpv-android, não):
  `app-default-arm64-v8a-release.apk`, `app-default-armeabi-v7a-release.apk`,
  `app-default-x86_64-release.apk` (SHA-256 em `SHA256.txt`).
- Ver `android/libmpv_completo.gradle`.

## Licenças

Estes builds do mpv e do ffmpeg estão compilados com `--enable-gpl --enable-version3` (o ffmpeg do
mpv-android di-lo na própria configuração), por isso estão sob a **GPLv3**. O código-fonte
correspondente obtém-se nos projetos de origem (mpv, ffmpeg), nas versões indicadas em
`AVISOS-LICENCAS.txt`; os repositórios da shinchiro e do mpv-android têm os scripts de build, não
esse código. Os textos da GPLv3 e da LGPLv2.1 estão em `licencas/` e vão com a app: no Windows em
`licencas-libmpv/` ao lado do executável, no Android dentro do APK (assets da app) e nas duas em
Definições -> Licenças.

## Voltar ao libmpv mínimo do media_kit (só Android)

`libmpvMinimo=1` (ou `true`) em `android/gradle.properties` (ou `-PlibmpvMinimo=1`) desliga o
`libmpv_completo.gradle`; a app volta ao shader (o mpv recusa o `vf`, ver `FiltrosNaSessao`). Outro
valor (`0`, `false`) não desliga nada. Um APK assim não passa no `ferramentas/empacotar.py` (o
SHA-256 do `libmpv.so` não é o fixado). No Windows não há interruptor: o `windows/CMakeLists.txt`
instala sempre o libmpv completo.

## Estado da verificação

- Windows: testado com a DLL no caminho da app (render API sobre o ANGLE) e na app empacotada (arranca e carrega a DLL).
- Android: o APK leva os `.so` do mpv-android (mpv 0.41, `bwdif` existe; SHA-256 do `libmpv.so` verificado no
  build e no `empacotar.py`). Ver o relatório da ronda 1 sobre o emulador.
