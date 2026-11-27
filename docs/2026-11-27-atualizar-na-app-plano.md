# Atualizar a app dentro da app — plano de implementação

> **Para agentes:** usar superpowers:executing-plans (ou subagent-driven-development), tarefa a
> tarefa. Passos com `- [ ]`. No fim de cada tarefa: commit e atualizar a secção «Estado».

**Objetivo:** «Procurar atualizações» nas Definições e «Atualizar» (também no aviso ao abrir) que
descarrega o pacote da edição/plataforma e instala-o: Android pelo instalador do sistema, Windows
por um script que troca os ficheiros depois de a app fechar.

**Arquitetura:** a leitura das releases (lib/dados/nova_versao.dart) passa a trazer os pacotes;
um módulo novo lib/atualizar/ escolhe o pacote, descarrega-o para ficheiro (com verificação) e
instala-o por plataforma; a UI (lib/ui/atualizar/) junta tudo num diálogo de progresso.

**Tecnologia:** Flutter/Dart (`material_ui`), `dart:io` HttpClient, `archive` (já existe),
Kotlin (canal `player_iptv/atualizar` em MainActivity.kt), PowerShell (Windows).

**Design:** docs/2026-11-27-atualizar-na-app-design.md

## Restrições globais

- Sem dependências novas no pubspec.
- Edição: `edicaoPartilha` (lib/edicao.dart). Prefixos `prefixoCompleta = 'v'`, `prefixoPartilha = 'partilha-v'`.
- Nomes dos pacotes: `TVIntel-<versão>-[partilha-]android-arm64.apk`, `…-android-armv7.apk`, `…-windows.zip`.
  Um pacote da completa **não** tem `-partilha-`.
- O zip do Windows tem tudo dentro da pasta `TVIntel/` (exe: `TVIntel/TVIntel.exe`).
- Textos em português de Portugal, todos com `tr(...)` e tradução em lib/idioma/ingles.dart.
- Tudo usável com o comando (foco inicial no botão principal de cada diálogo; Voltar fecha/cancela).
- O aviso ao abrir mantém as regras atuais (uma vez por versão, nada em dados móveis com poupança).

## Pontos de atenção (testes em cada tarefa)

1. Release sem pacote para este aparelho/edição (ABI x86_64, ou falta o ficheiro) → «Não há pacote
   desta versão para este aparelho» e, se possível, oferecer a página da release. (Tarefa 2, 5)
2. Download truncado, interrompido ou com SHA-256 diferente → erro claro, ficheiro apagado, nada
   instalado. (Tarefa 3)
3. «Cancelar» a meio → o ficheiro parcial é apagado e o diálogo fecha sem erro. (Tarefa 3, 5)
4. Android sem o ecrã de «apps desconhecidas» (algumas TVs: ActivityNotFound) → mensagem a dizer
   onde se dá a autorização, sem rebentar. (Tarefa 4)
5. Windows: pasta do exe não gravável → oferecer a página no browser; caminhos com espaços e
   apóstrofos no script. (Tarefa 6)

---

### Tarefa 1: Releases com pacotes e a procura manual

**Ficheiros:** Modificar lib/dados/nova_versao.dart; Teste test/dados/nova_versao_test.dart

**Interfaces (produz):**
- `class Pacote { const Pacote(this.nome, this.url, this.tamanho, this.sha256); final String nome, url; final int tamanho; final String? sha256; }`
  (`url` = `browser_download_url`; `sha256` = o `digest` sem o `sha256:`, ou null)
- `NovaVersao(versao, pagina, {this.pacotes = const []})` com `final List<Pacote> pacotes`.
- `lerUltimaRelease` preenche `pacotes` a partir de `assets`.
- `sealed class Procura`: `EmDia(String versao)`, `HaNova(NovaVersao v)`, `SemResposta()`.
- `Future<Procura> procurarVersao({required String atual, String prefixo = prefixoCompleta, Future<String> Function(Uri) obter = _obterDaRede})`
  — ignora a «versão avisada» e os dados móveis; erro de rede → `SemResposta`.

- [ ] Teste: `lerUltimaRelease` lê os pacotes (nome, url, tamanho, sha256 de `"digest":"sha256:ab12…"`; sem digest → null).
- [ ] Teste: `procurarVersao` → `HaNova` com 1.0.29 vs atual 1.0.28; `EmDia('1.0.28')` quando a última é 1.0.28; `SemResposta` quando `obter` lança.
- [ ] Ver a falhar, implementar, ver a passar; `flutter analyze` limpo.
- [ ] Commit `feat(atualizar): as releases trazem os pacotes; procura manual`.

### Tarefa 2: O pacote certo para este aparelho

**Ficheiros:** Criar lib/atualizar/pacote_certo.dart; Teste test/atualizar/pacote_certo_test.dart

**Interfaces (produz):**
- `enum Plataforma { android, windows, outra }`
- `Pacote? pacoteDaApp(List<Pacote> pacotes, {required Plataforma plataforma, List<String> abis = const [], required bool partilha})`
  Android: percorre `abis` pela ordem (as do aparelho, a preferida primeiro): `arm64-v8a` → sufixo
  `-android-arm64.apk`, `armeabi-v7a` → `-android-armv7.apk`; Windows → `-windows.zip`. Com
  `partilha` só nomes com `-partilha-`; sem, só sem `-partilha-`.

- [ ] Testes: arm64 completa → `TVIntel-1.0.28-android-arm64.apk`; `['arm64-v8a','armeabi-v7a']` partilha → o arm64 da partilha; só `armeabi-v7a` → armv7; `['x86_64']` → null; windows completa nunca devolve o zip da partilha; `outra` → null.
- [ ] Falhar → implementar → passar. Commit `feat(atualizar): escolher o pacote da edição e do processador`.

### Tarefa 3: Descarregar para ficheiro com verificação

**Ficheiros:** Criar lib/atualizar/descarregar.dart; Teste test/atualizar/descarregar_test.dart

**Interfaces (produz):**
- `class ErroPacote implements Exception { ErroPacote(this.mensagem); final String mensagem; }`
- `typedef AbrirDownload = Future<(Stream<List<int>>, int?)> Function(Uri uri, Cancelamento? c);` (corpo e Content-Length)
- `Future<File> descarregarPacote(Pacote p, Directory pasta, {void Function(int recebidos, int total)? progresso, Cancelamento? cancelamento, AbrirDownload abrir = abrirDownloadHttp})`
  Escreve para `<pasta>/<nome>.parcial`, calcula SHA-256 em streaming (`package:crypto`, já existe),
  no fim confirma tamanho == `p.tamanho` e sha256 (se houver), renomeia para `<pasta>/<nome>`.
  Qualquer falha ou `Cancelado` apaga o `.parcial` e relança (`ErroPacote` para tamanho/sha).
- `abrirDownloadHttp`: HttpClient próprio (segue redireções do GitHub), User-Agent `TVIntel`,
  status ≥ 400 → `ErroHttp` (lib/rede/http.dart), 30 s sem dados → TimeoutException, cancelamento aborta o pedido.

- [ ] Testes (com `abrir` falso): sucesso escreve o ficheiro e chama `progresso` até `(t,t)`; tamanho errado → `ErroPacote` e nenhum ficheiro na pasta; sha256 errado → idem; sem sha256 só o tamanho conta; cancelar a meio → `Cancelado` e pasta vazia; stream com erro → relança e pasta vazia.
- [ ] Falhar → implementar → passar. Commit `feat(atualizar): descarregar o pacote com verificação`.

### Tarefa 4: Instalar no Android

**Ficheiros:**
- Criar lib/atualizar/instalar_android.dart; Teste test/atualizar/instalar_android_test.dart
- Modificar android/app/src/main/AndroidManifest.xml (permissão `android.permission.REQUEST_INSTALL_PACKAGES`; `<provider android:name="androidx.core.content.FileProvider" android:authorities="${applicationId}.atualizar" android:exported="false" android:grantUriPermissions="true">` com `android.support.FILE_PROVIDER_PATHS` → `@xml/caminhos_atualizar`)
- Criar android/app/src/main/res/xml/caminhos_atualizar.xml (`<cache-path name="atualizar" path="atualizar/"/>`)
- Modificar android/app/src/main/kotlin/pt/playeriptv/player_iptv/MainActivity.kt (canal novo)

**Interfaces (produz):**
- Canal `MethodChannel('player_iptv/atualizar')`: `abis` → `List<String>` (Build.SUPPORTED_ABIS);
  `podeInstalar` → bool (`packageManager.canRequestPackageInstalls()`, true abaixo do API 26);
  `pedirAutorizacao` → bool (abre `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES` com `package:`; false se ActivityNotFound);
  `instalar {caminho}` → abre `ACTION_VIEW` com o URI do FileProvider, tipo `application/vnd.android.package-archive`, `FLAG_GRANT_READ_URI_PERMISSION | FLAG_ACTIVITY_NEW_TASK`.
- Dart: `class InstaladorAndroid { const InstaladorAndroid([MethodChannel canal]); Future<List<String>> abis(); Future<bool> podeInstalar(); Future<bool> pedirAutorizacao(); Future<void> instalar(File apk); }`
- A pasta do download no Android: `<getTemporaryDirectory()>/atualizar` (bate com `cache-path`).

- [ ] Teste Dart com o canal simulado (`TestDefaultBinaryMessengerBinding…setMockMethodCallHandler`): nomes dos métodos e argumentos; `pedirAutorizacao` false passa por.
- [ ] Implementar Dart + Kotlin + manifesto. `flutter build apk --debug --target-platform android-arm64` compila.
- [ ] Commit `feat(atualizar): instalar o APK pelo instalador do Android`.

### Tarefa 5: O fluxo «Atualizar» e o botão nas Definições

**Ficheiros:**
- Criar lib/ui/atualizar/fluxo_atualizar.dart; Teste test/ui/atualizar_test.dart
- Modificar lib/ui/definicoes/tela_definicoes.dart (categoria «Sobre», depois de «Novidades»)
- Modificar lib/ui/principal/tela_principal.dart (`_avisarNovaVersao`: `acao: tr('Atualizar')`)
- Modificar lib/idioma/ingles.dart

**Interfaces:**
- Consome: Tarefas 1–4 e `instalarWindows` da Tarefa 6 (até lá, Windows abre a página).
- Produz: `class Atualizador` com as dependências injetáveis (procura, plataforma, abis, pasta,
  descarregar, instalador Android, instalador Windows, abrir página) e
  `Future<void> procurarAtualizacoes(BuildContext c, {Atualizador? a})` e
  `Future<void> atualizarApp(BuildContext c, NovaVersao v, {Atualizador? a})`.

Comportamento:
- Procurar: diálogo curto «A procurar…»; `EmDia` → «Estás na versão mais recente ({0}).»; `SemResposta` → «Não foi possível ver se há versão nova. Tenta mais tarde.»; `HaNova` → «Há uma versão nova: {0}.» com «Atualizar» (foco) e «Agora não».
- Atualizar: sem pacote → «Não há pacote desta versão para este aparelho.» (+ «Abrir a página» se a plataforma abre URLs); Android sem autorização → explicação + «Dar autorização» (chama `pedirAutorizacao`; false → «Abre as definições do Android › Apps › TVIntel › Instalar apps desconhecidas.»); diálogo de progresso «A descarregar a versão {0}» com barra, «{0} de {1} MB» e «Cancelar» (foco; Voltar cancela); erro → «O download falhou: {0}»; fim → instalar.

- [ ] Testes de widgets com `Atualizador` falso: em dia; nova → Atualizar → progresso → instalar chamado com o ficheiro; Cancelar a meio não instala; sem pacote mostra a mensagem; Android sem autorização chama `pedirAutorizacao`; o botão «Procurar atualizações» existe em Definições › Sobre e o foco começa nos botões principais.
- [ ] Implementar, traduções, `flutter analyze` e testes. Commit `feat(atualizar): procurar e atualizar nas Definições e no aviso`.

### Tarefa 6: Instalar no Windows

**Ficheiros:** Criar lib/atualizar/instalar_windows.dart; Teste test/atualizar/instalar_windows_test.dart; ligar em fluxo_atualizar.dart

**Interfaces (produz):**
- `bool pastaGravavel(Directory d)` (cria e apaga um ficheiro de teste; false em FileSystemException).
- `Future<Directory> extrairZip(File zip, Directory destino)` → devolve `destino/TVIntel` (lança `ErroPacote` se não tiver `TVIntel/TVIntel.exe`).
- `String scriptTroca({required int pid, required String origem, required String destino, required String exe})`
  PowerShell: `Wait-Process -Id pid -Timeout 60` (ignora erro), `robocopy origem destino /E /R:10 /W:1 /NFL /NDL /NJH /NJS` (código ≥ 8 = falha → não apaga nada e abre a mesma app antiga), `Start-Process exe`, apaga a pasta temporária. Strings entre aspas simples com `'` duplicado.
- `Future<void> instalarWindows(File zip, {required Future<void> Function() fechar})`: extrai para `%TEMP%\TVIntel-atualizar`, escreve o script, `Process.start('powershell', ['-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File', script], mode: ProcessStartMode.detached)`, depois `fechar()` (sai da app).
- No fluxo: antes de descarregar, se `!pastaGravavel(pasta do exe)` → «Não é possível atualizar nesta pasta…» + «Abrir a página»; depois de descarregar, «Fechar e atualizar agora?» (foco em «Atualizar agora»).

- [ ] Testes: `scriptTroca` com caminhos com espaços e `'` (aspas duplicadas, todos os passos presentes); `extrairZip` de um zip feito no teste (com e sem `TVIntel/TVIntel.exe`); `pastaGravavel` true numa pasta temporária.
- [ ] Teste manual no Windows: 1.0.28 instalada numa pasta, publicar/simular 1.0.29 (release local num `obter` falso não serve — ver «Estado»).
- [ ] Commit `feat(atualizar): atualizar no Windows (troca dos ficheiros depois de fechar)`.

### Tarefa 7: Versão 1.0.28, pacotes e publicação

- [ ] pubspec 1.0.28+29; novidades 1.0.28 (para as duas edições: «Definições › Sobre: «Procurar atualizações»…» e «Atualizar» no aviso) + inglês.
- [ ] `python ferramentas/empacotar.py --tudo` (verifica e assina); push do `main` e do `feature/redesenho`; releases `v1.0.28` (6, latest) e `partilha-v1.0.28` (3) com o script do scratchpad (SHA completo).
- [ ] Confirmar pela API que os assets têm `digest`.

## Estado

- 2026-11-27: design e plano escritos. Nenhuma tarefa começada.
- 2026-11-27: Tarefas 1–6 feitas e com commit (33b37d1..0055a52), suite inteira verde (1861+). Ledger:
  .superpowers/sdd/2026-11-27-atualizar-na-app-plano/progress.md (com as decisões «Ruling:»).
  A troca do Windows foi ensaiada a sério (pasta com acentos e apóstrofo). Em curso: revisão
  independente do ramo; depois corrigir o que for Critical/Important e fazer a Tarefa 7 (1.0.28,
  pacotes, push e releases). Falta o ensaio real no Android/Windows com uma 1.0.29 de teste.
- 2026-11-27: revisão independente (3 Important corrigidos em 0f4dcdd: troca do Windows espera por
  todos os processos e repõe a versão anterior — ensaiado a sério; Cancelar interrompe um download
  parado; pacotes antigos apagados). 7 Minor adiados (lista no ledger). Tarefa 7 feita: 1.0.28
  publicada — releases v1.0.28 (6, latest) e partilha-v1.0.28 (3), com digest SHA-256; main e
  feature/redesenho em 938d318. **Próximo passo:** ensaio real com uma 1.0.29 (Android TV/telemóvel
  e Windows) a partir da 1.0.28 instalada.
- 2026-11-27: os 7 Minor da revisão corrigidos (c4a1ade) e 1.0.29 publicada (v1.0.29 + partilha-v1.0.29,
  com digest); main e feature/redesenho em 523ea8f. **Próximo passo:** o utilizador experimenta
  «Procurar atualizações» a partir da 1.0.28 instalada (Android e Windows).

- 27/11 (noite): a atualização no Windows a partir da 1.0.28 fechou a app e não reabriu. Causa: `Process.start(mode: detached)` cria o PowerShell com DETACHED_PROCESS e ele morre antes da 1.ª linha (reproduzido também fora da sandbox; o modo normal funciona). Na 1.0.29 o efeito seria o erro «o Windows não deixou correr a atualização». Corrigido em ad9832d: `_iniciar` usa `CreateProcessW` por FFI com CREATE_NO_WINDOW (+ CREATE_BREAKAWAY_FROM_JOB, com nova tentativa sem ele), com teste de ponta a ponta com o PowerShell real. Ainda por publicar: falta a 1.0.30. Quem tem a 1.0.28 ou a 1.0.29 no Windows tem de instalar a 1.0.30 à mão, uma vez.
