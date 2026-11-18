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
- Ficheiros (de cada APK tiram-se só as `lib/<abi>/*.so`):
  `app-default-arm64-v8a-release.apk`, `app-default-armeabi-v7a-release.apk`,
  `app-default-x86_64-release.apk` (SHA-256 em `SHA256.txt`).
- Ver `android/libmpv_completo.gradle`.

## Licenças

O mpv é GPLv2+ (LGPLv2.1+ se compilado sem as partes GPL) e o ffmpeg é LGPLv2.1+, **mas estes builds
estão compilados com `--enable-gpl --enable-version3`** (o ffmpeg do mpv-android di-lo na própria
configuração), portanto o conjunto distribuído é **GPLv3**. Quem distribuir o pacote tem de oferecer
o código-fonte correspondente (mpv, ffmpeg e as bibliotecas ligadas): ver `AVISOS-LICENCAS.txt`
para os links dos projetos e dos scripts de build usados. O código da app não é alterado por isto
(o libmpv é carregado como biblioteca dinâmica), mas confirme com quem distribui se a GPLv3 serve.

## Voltar ao libmpv mínimo do media_kit (Android)

`libmpvMinimo=1` em `android/gradle.properties` (ou `-PlibmpvMinimo=1`) desliga o `libmpv_completo.gradle`;
a app volta ao shader (o código deteta a falta de filtros pelo `mpv-version`, ver `filtrosDoMpv`).

## Estado da verificação

- Windows: testado com a DLL no caminho da app (render API sobre o ANGLE) e na app empacotada (arranca e carrega a DLL).
- Android: o APK leva os `.so` do mpv-android (mpv 0.41, `bwdif` existe) e o canal abre no modo direto no emulador;
  falta testá-lo num aparelho real (o emulador usado deixa o mpv sem responder ~3 s depois de abrir, também com o libmpv de antes).
