# Atualizar a app dentro da app (1.0.28) — design

## Porquê

Hoje a app só avisa ao abrir (15 s, uma vez por versão) e o download/instalação é à mão. O
utilizador quer um botão nas Definições para procurar atualizações e, havendo, atualizar sem sair
da app — no Android e no Windows.

## Objetivos

- «Procurar atualizações» nas Definições (junto a «Novidades»): diz «Estás na versão mais recente
  ({versão})» ou «Há uma versão nova: {versão}» com «Atualizar».
- O aviso ao abrir ganha a ação «Atualizar» (o mesmo fluxo).
- Cada edição só vê e só descarrega as suas releases (completa `v…`, partilha `partilha-v…`) e os
  seus pacotes (os da partilha têm `-partilha-` no nome).
- **Android:** descarrega o APK da edição e do processador (arm64-v8a → `android-arm64`;
  armeabi-v7a → `android-armv7`), com progresso e «Cancelar», confirma o tamanho e o SHA-256 (o
  `digest` do GitHub, quando existe) e abre o instalador do sistema. Sem autorização para
  «instalar apps desconhecidas», explica e abre o ecrã do Android onde se dá; ao voltar,
  carrega-se outra vez em «Atualizar».
- **Windows:** descarrega o zip da edição (mesma verificação), descompacta para uma pasta
  temporária, pergunta «Fechar e atualizar agora?», fecha-se e deixa um script (PowerShell) que
  espera o processo terminar, copia os ficheiros para a pasta do `TVIntel.exe` e volta a abrir a
  app. Os dados ficam em `AppData\Roaming` e não são tocados.

## Não-objetivos

- Atualizações automáticas/silenciosas; agendamento; delta updates.
- Versões anteriores à 1.0.28 continuam só com o aviso (não têm o código).
- Outras plataformas (Linux/macOS/iOS): «Atualizar» abre a página da release, se houver forma; senão
  só diz que há versão nova.

## Restrições

- O aviso ao abrir continua a não procurar em dados móveis (poupança ligada); o botão procura sempre.
- Os APK são sempre assinados com a mesma chave (SHA-256 11f1a4d8…ca9e): instalar por cima mantém
  os dados. O Android recusa se a assinatura não bater — não há nada a fazer na app.
- Windows: se a pasta do executável não for gravável (ex.: `C:\Program Files`), avisa e oferece a
  página da release no browser.
- Sem dependências novas: Android por canal nativo (`player_iptv/atualizar`) em `MainActivity.kt`,
  com `REQUEST_INSTALL_PACKAGES` e um `FileProvider`; Windows com `Process.start` e o
  `archive` que já existe.
- Tudo controlável pelo comando (D-pad) e traduzido (lib/idioma/ingles.dart).

## Abordagens

1. **Instalador do sistema via `ACTION_VIEW` + `FileProvider` (escolhida).** Simples, funciona em
   Android TV/Fire TV, o utilizador confirma no ecrã do sistema.
2. `PackageInstaller` com sessão: mais controlo (progresso da instalação), mais código nativo, sem
   ganho visível para o utilizador.
3. Abrir a página no browser: não serve na TV (sem browser) e foi o que o utilizador quis evitar.

No Windows: script PowerShell que troca os ficheiros depois de a app fechar (escolhida) vs. abrir
o browser (só como recurso quando a pasta não é gravável).

## Decidido pelo utilizador

- Botão nas Definições + atualização dentro da app nas duas plataformas; no Windows tudo na app.
- Duas releases por versão (`v…` com os 6 pacotes; `partilha-v…` com os 3 da partilha).

## Chamadas minhas (a rever)

- A procura manual ignora a «versão já avisada» e os dados móveis.
- Verificação do download: tamanho sempre; SHA-256 quando o GitHub dá `digest` (`sha256:…`).
- O APK/zip fica na cache da app e apaga-se no fim (ou na próxima abertura).
- O ecrã do progresso é um diálogo com a barra, o tamanho descarregado e «Cancelar» (foco).
