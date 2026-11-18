# Redesenho da app — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refazer a app (Windows, Android, Android TV/Fire TV) em azul, com três secções fixas, os ecrãs dos mockups aprovados e um Gestor que nunca obriga a esperar.

**Architecture:** Uma casca nova (`TelaPrincipal`) com as secções Ver TV / Gestor / Definições num `IndexedStack` (o estado fica ao trocar). Os ecrãs passam a ler o mesmo vocabulário de estados (`EstadoLista`). Todo o trabalho longo do Gestor passa para um `ServicoTarefas` criado em `AppPlayerIptv`, fora dos widgets; a UI só observa.

**Tech Stack:** Flutter 3.50 / Dart 3.14, `package:material_ui/material_ui.dart`, media_kit vendorizado, flutter_test.

**Spec:** docs/2026-11-19-redesenho-design.md (mockups: https://claude.ai/artifact/7BUwpd195zP4MpvFCsDw3F)

## Global Constraints

- Ramo `feature/redesenho`, criado a partir de `feature/v2` **depois** de a correção da barra verde / fluidez Android estar no ramo (mexe em lib/ui/player/).
- Todas as cores vêm de `Tokens` (lib/ui/design/tokens.dart); nenhum `Color(0x…)` novo fora desse ficheiro.
- Texto em pt-PT. Vocabulário de estados exato: `Funciona`, `Inconclusiva`, `Não funciona`, `Por verificar`.
- Secções exatas: `Ver TV`, `Gestor`, `Definições`. Barra lateral quando a largura ≥ 900 px; senão `NavigationBar` em baixo.
- O foco do comando vê-se sempre (anel `Tokens.anelFoco`, 4 px) e nunca fica preso; os testes de D-pad existentes continuam verdes.
- Nenhum botão do Gestor fica desligado por haver uma tarefa a decorrer. Só esperam: o seletor de ficheiros do sistema e as confirmações de remover/limpar/substituir.
- Sem EPG, sem pré-visualização ao vivo, sem filmes/séries.
- "Copiar link" só aparece quando `defaultTargetPlatform == TargetPlatform.windows`.
- Nunca mostrar credenciais, MACs, tokens ou links completos em mensagens, tarefas ou registos.
- Cada tarefa acaba com `flutter test` e `flutter analyze` sem erros; repor os ficheiros gerados (.flutter-plugins-dependencies, windows/flutter/generated_*) depois.

## Review Focus

1. Mudar de secção (ou sair do Gestor) a meio de uma pesquisa do stbstalker ou de uma importação → ao voltar, a tarefa continua ou já tem o resultado; nada se perde (teste na Task 9 e Task 12).
2. Remover no Gestor uma lista que está a ser verificada → só essa sai da fila, as outras continuam, contadores certos (Task 13).
3. Voltar (Android) em Gestor/Definições → vai para Ver TV, e só no Início o duplo Voltar sai da app (Task 3).
4. Uma lista sem cache de canais no Início (favoritos/contagem) → o cartão aparece sem números e sem erro, e a fila de favoritos ignora as que não têm cache (Task 5).
5. Migração das preferências: `desentrelacar: true` antigo → `automatico`, `false` → `desligado`; uma cópia de segurança antiga restaura sem perder a opção (Task 16).

---

### Task 1: Tokens azuis

**Files:**
- Modify: `lib/ui/design/tokens.dart`, `lib/ui/tema.dart`
- Test: `test/ui/design_test.dart`

**Interfaces:**
- Produces: `Tokens.fundo = 0xFF0A1628`, `Tokens.superficie = 0xFF0D1F3A`, `Tokens.superficie2 = 0xFF132B4D`, `Tokens.superficie3 = 0xFF1A3A66` (novo), `Tokens.acento = 0xFF2F7BF6`, `Tokens.anelFoco = 0xFF8EC5FF` (novo), `Tokens.texto = 0xFFEEF4FF`, `Tokens.texto2 = 0xFFA3B8D6` (opaco), `Tokens.ok = 0xFF5EE0A0`, `Tokens.aviso = 0xFFFFD27A`, `Tokens.mau = 0xFFFF9A9A`, `Tokens.neutro = 0xFFA3B8D6`; `Tokens.fundoOk = 0xFF123F33`, `Tokens.fundoAviso = 0xFF4A3A12`, `Tokens.fundoMau = 0xFF4A1E24`, `Tokens.fundoNeutro = 0xFF22324A` (novos). `acento2` e `gradienteAcento` passam a azul (`0xFF1E5BB8`); `sombraFoco` brilha em `0x738EC5FF`.
- Produces: `double contraste(Color a, Color b)` em tokens.dart (razão WCAG).

- [ ] **Step 1: Write the failing test** — em design_test.dart: `test('tokens azuis')` verifica os valores acima; `test('contraste do texto')` com `expect(contraste(Tokens.texto2, Tokens.fundo), greaterThanOrEqualTo(4.5))`, o mesmo para `Tokens.superficie2` e `Tokens.superficie3`; e para cada par (ok/fundoOk, aviso/fundoAviso, mau/fundoMau, neutro/fundoNeutro) ≥ 4.5.
- [ ] **Step 2: Run** `flutter test test/ui/design_test.dart` — Expected: FAIL (valores antigos / `contraste` não existe).
- [ ] **Step 3: Implement** os tokens e `contraste` (luminância relativa sRGB); em tema.dart o `ColorScheme` usa os tokens novos e o realce de foco usa `Tokens.anelFoco`.
- [ ] **Step 4: Run** `flutter test` — Expected: PASS (ajustar só testes que fixavam cores antigas, sem mudar o que testam).
- [ ] **Step 5: Commit** `feat(design): cores à volta do azul com contraste verificado`

### Task 2: Vocabulário de estados

**Files:**
- Create: `lib/ui/design/estado_lista.dart`
- Test: `test/ui/estado_lista_test.dart`

**Interfaces:**
- Consumes: `Lista.ultima?.estado` (`'funciona' | 'inconclusivo' | 'nao_funciona' | null`).
- Produces: `enum EstadoLista { funciona, inconclusiva, naoFunciona, porVerificar }`; `EstadoLista estadoDe(Lista l)`; `extension on EstadoLista { String get rotulo; Color get cor; Color get fundo; }`; `class PilulaEstado extends StatelessWidget { const PilulaEstado(this.estado, {this.detalhe}); final EstadoLista estado; final String? detalhe; }` (mostra "Funciona · verificada há 2 h" quando há detalhe).

- [ ] **Step 1: Write the failing test** — `estadoDe` para cada valor de `ultima.estado` e para `ultima == null` → `porVerificar`; rótulos exatos `Funciona`, `Inconclusiva`, `Não funciona`, `Por verificar`; `PilulaEstado(EstadoLista.naoFunciona, detalhe: 'ontem')` mostra `'Não funciona · ontem'`.
- [ ] **Step 2: Run** `flutter test test/ui/estado_lista_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement** (cores de Task 1: ok/fundoOk, aviso/fundoAviso, mau/fundoMau, neutro/fundoNeutro).
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat(design): os estados das listas com as mesmas palavras e cores em todo o lado`

### Task 3: Casca com três secções

**Files:**
- Create: `lib/ui/principal/tela_principal.dart`, `lib/ui/principal/barra_seccoes.dart`
- Modify: `lib/main.dart:105-140` (home passa a `TelaPrincipal`), `lib/ui/inicio/tela_inicio.dart` (sai o `TabBar`/`DefaultTabController`, o "+" e a roda dentada; fica só o conteúdo de Ver TV)
- Test: `test/ui/principal_test.dart`; atualizar `test/ui/navegacao_inicio_test.dart`, `test/ui/telas_test.dart`

**Interfaces:**
- Produces: `enum Seccao { verTv, gestor, definicoes }`; `class TelaPrincipal extends StatefulWidget { const TelaPrincipal({required Widget verTv, required Widget gestor, required Widget definicoes, Seccao inicial = Seccao.verTv, VoidCallback sair = SystemNavigator.pop}); }`; `static void irPara(BuildContext c, Seccao s)` (via `InheritedWidget` `SeccaoAtual`); `class BarraSeccoes extends StatelessWidget` (lateral, 220 px, rótulos `Ver TV`/`Gestor`/`Definições`).
- As três secções vivem num `IndexedStack` (o estado de cada uma fica).

- [ ] **Step 1: Write the failing tests** —
  `testWidgets('largura 1280: barra lateral com as 3 secções')`: encontra `BarraSeccoes` e os 3 rótulos;
  `testWidgets('largura 400: NavigationBar em baixo')`;
  `testWidgets('trocar de secção guarda o estado')`: escreve num `TextField` em Gestor, vai a Ver TV e volta → o texto continua;
  `testWidgets('Voltar em Gestor vai para Ver TV')` e `testWidgets('duplo Voltar em Ver TV chama sair')` (o comportamento atual de 2 s passa para a casca);
  `testWidgets('D-pad: ESQUERDA no conteúdo chega à barra; DIREITA volta ao conteúdo')` com `ajuda_dpad.dart`.
- [ ] **Step 2: Run** `flutter test test/ui/principal_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement** a casca; `main.dart` monta `TelaPrincipal(verTv: TelaInicio(...), gestor: TelaGestor(...) /* Task 11; até lá TelaVerificar */, definicoes: TelaDefinicoes(...))`. "Ir para o Gestor" do ecrã vazio usa `TelaPrincipal.irPara(context, Seccao.gestor)`.
- [ ] **Step 4: Run** `flutter test` — Expected: PASS (incluindo dpad_regressoes_test.dart).
- [ ] **Step 5: Commit** `feat(ui): três secções fixas (Ver TV, Gestor, Definições) que guardam o estado`

### Task 4: Mensagens e barra de teclas

**Files:**
- Create: `lib/ui/design/mensagens.dart`, `lib/ui/design/barra_teclas.dart`
- Modify: os `ScaffoldMessenger…showSnackBar` de lib/ui (substituir por `mostrarMensagem`)
- Test: `test/ui/mensagens_test.dart`

**Interfaces:**
- Produces: `void mostrarMensagem(BuildContext context, String texto, {MensagemTipo tipo = MensagemTipo.info, String? acao, VoidCallback? aoAcao, Duration duracao = const Duration(seconds: 4)})`; `enum MensagemTipo { info, sucesso, erro, progresso }`. Aparece no canto superior direito (sobreposição na `TelaPrincipal`), uma de cada vez (a nova substitui), com `Semantics(liveRegion: true)`; com `acao`, a duração passa a 8 s e a mensagem mostra a dica `Menu: <acao>`; enquanto está visível, a tecla Menu do comando (`LogicalKeyboardKey.contextMenu`) ativa a ação sem tirar o foco de onde está; no Windows/telemóvel também com clique/toque. A mensagem nunca rouba o foco.
- Produces: `class BarraTeclas extends StatelessWidget { const BarraTeclas(this.itens); final List<(String tecla, String acao)> itens; }` — só aparece em TV (`ecraTv(context)`, já existente) e no Windows.

- [ ] **Step 1: Write the failing tests** — mostra o texto; a segunda mensagem substitui a primeira; `aoAcao` é chamado com a tecla Menu (e com toque) e o foco não muda; desaparece após `duracao`; `BarraTeclas([('OK','ver')])` mostra `OK` e `ver`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** e trocar as SnackBars existentes (mesmos textos).
- [ ] **Step 4: Run** `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(ui): mensagens no canto com Desfazer e a barra de teclas`

### Task 5: Início

**Files:**
- Modify: `lib/ui/inicio/tela_inicio.dart`, `lib/ui/inicio/cartao_lista.dart`, `lib/ui/inicio/cartao_continuar.dart`
- Create: `lib/ui/inicio/favoritos_inicio.dart`
- Test: `test/ui/inicio_test.dart`

**Interfaces:**
- Consumes: `Biblioteca.listas`, `Lista.favoritos`, `Biblioteca.canaisEmCache(id)`, `Biblioteca.ultimoVisto`, `PilulaEstado`, `BarraTeclas`.
- Produces: `class FavoritoInicio { final Lista lista; final Canal canal; }`; `Future<List<FavoritoInicio>> favoritosInicio(Biblioteca b, {int maximo = 12})` (pela ordem das listas e dos canais; listas sem cache ignoradas).

- [ ] **Step 1: Write the failing tests** — `favoritosInicio` junta favoritos de 2 listas, respeita `maximo`, ignora lista sem cache; o Início mostra "Continuar a ver" com o nome do canal e da lista, a fila `Favoritos · n` e os cartões das listas com `PilulaEstado`; cartão sem cache não mostra contagem; OK num favorito abre esse canal da lista certa (`abrirCanal` de teste); com 0 listas mostra o ecrã "Ainda não há listas para ver" com os 3 passos e "Ir para o Gestor".
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** conforme ecrãs 1 e 11 dos mockups (sem miniatura de vídeo; logótipo ou iniciais).
- [ ] **Step 4: Run** `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(início): continuar a ver, favoritos de todas as listas e listas com estado`

### Task 6: "Vistos há pouco"

**Files:**
- Modify: `lib/dados/biblioteca.dart` (`Lista`, `registarVisto`, `paraJson`/`deJson`, `planearRestauro` copia o campo), `lib/ui/conteudo/tela_conteudo.dart` (grupo virtual)
- Test: `test/dados/biblioteca_test.dart`, `test/ui/navegacao_conteudo_test.dart`

**Interfaces:**
- Produces: `final List<String> Lista.vistos` (ids de canal, mais recente primeiro, sem repetidos, no máximo 20), gravado como `"vistos"`; `registarVisto` atualiza-o.

- [ ] **Step 1: Write the failing tests** — 25 `registarVisto` → 20 guardados, mais recente primeiro, sem repetidos; reabrir a Biblioteca mantém-nos; JSON antigo sem `vistos` abre com lista vazia; na lista aberta aparece o grupo `Vistos há pouco` com esses canais (só os que ainda existem).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(listas): grupo "Vistos há pouco" que fica guardado`

### Task 7: Lista aberta

**Files:**
- Modify: `lib/ui/conteudo/tela_conteudo.dart`, `lib/ui/conteudo/opcoes_conteudo.dart`
- Test: `test/ui/conteudo_carregar_test.dart`, `test/ui/navegacao_conteudo_test.dart`

**Interfaces:**
- Consumes: `BarraTeclas`, `mostrarMensagem`, `Biblioteca.alternarFavorito`, `Biblioteca.esconderGrupo`.
- Layout (ecrã 2): topo com `‹ Início`, nome da lista, nº de canais, pesquisa ("Pesquisar canais ou escrever o número"), `Ordem: …`, `Grupos escondidos: n`; grupos à esquerda (Favoritos, Vistos há pouco, depois os da lista, `Filtrar grupos…`); canais **um por linha** (número, logótipo, nome, estrela); por cima "<grupo>" e "i de n"; **sem** painel à direita.

- [ ] **Step 1: Write the failing tests** — cada canal ocupa uma linha inteira (a 1280 px, dois canais seguidos têm o mesmo `dx` e `dy` diferentes); o cabeçalho mostra `2 de 54` com o foco no 2.º; OK mantido alterna o favorito e mostra mensagem com `Desfazer` que o repõe; esconder grupo mostra mensagem com `Desfazer`; os testes de D-pad atuais da lista continuam.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(lista): canais um por linha, contador e mensagens com desfazer`

### Task 8: Opções da lista

**Files:**
- Modify: `lib/ui/inicio/acoes_lista.dart`, `lib/main.dart` (segundo serviço de verificação para o Player)
- Test: `test/ui/menu_lista_test.dart`, `test/ui/acoes_lista_test.dart`

**Interfaces:**
- Consumes: `ServicoVerificacao(biblioteca)` (colecao = Biblioteca, partilha o `RitmoHost` do do Gestor), `AreaGestor.adicionar`.
- Produces: `enum AcaoLista` ganha `verificar` e `enviarGestor`; ordem do menu: `Atualizar canais`, `Verificar agora`, `Editar lista`, `Copiar link` (só Windows), `Enviar para o Gestor`, `Remover lista`, cada um com uma linha de explicação (ecrã 3).

- [ ] **Step 1: Write the failing tests** — em Android o menu não tem `Copiar link`, em Windows tem; `Verificar agora` atualiza o estado da lista no Início e mostra mensagem de fim; `Enviar para o Gestor` acrescenta 1 lista ao Gestor (ou diz `Já estava no Gestor`); `Atualizar canais` mostra mensagem de progresso e depois de fim sem bloquear a navegação.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(listas): opções da lista com verificar agora e enviar para o Gestor`

### Task 9: Serviço de tarefas

**Files:**
- Create: `lib/tarefas/servico_tarefas.dart`, `lib/tarefas/segredos.dart`
- Modify: `lib/main.dart` (criado em `_AppPlayerIptvState`, `dispose` cancela)
- Test: `test/tarefas/servico_tarefas_test.dart`

**Interfaces:**
- Produces:
  - `enum EstadoTarefa { aDecorrer, terminada, falhou, cancelada }`
  - `class Tarefa { final String id; final String titulo; EstadoTarefa estado; double? progresso; String detalhe; String? resultado; final DateTime inicio; DateTime? fim; final Future<void> Function()? repetir; }`
  - `class ServicoTarefas extends ChangeNotifier { Tarefa iniciar(String titulo, Future<String> Function(Progresso p) trabalho, {Future<void> Function()? repetir}); void cancelar(String id); List<Tarefa> get emCurso; List<Tarefa> get recentes /* terminadas, mais recente primeiro, no máximo 10 */; Stream<Tarefa> get acabadas; }`
  - `class Progresso { void call(double? fracao, String detalhe); bool get cancelado; }`
  - `String mascararSegredos(String t)` (novo, em `lib/tarefas/segredos.dart`): troca MACs (`XX:XX:XX:XX:XX:XX` → `••:••:••:••:••:••`), o caminho e a query de qualquer URL (`http://host/…` → `http://host/…`) e pares `username=`/`password=`/`token=` → `=•••`. O texto de `resultado`/`detalhe` passa por ela antes de guardar.

- [ ] **Step 1: Write the failing tests** — `iniciar` devolve logo (`estado == aDecorrer`) e o trabalho corre sem `await` do chamador; o progresso notifica; ao terminar vai para `recentes` com `resultado` e emite em `acabadas`; exceção → `falhou` com a mensagem; `cancelar` põe `cancelado` a true e acaba em `cancelada`; 12 tarefas terminadas → só 10 em `recentes`; um `resultado` com `http://h/c?mac=00:1A:79:AA:BB:CC` fica mascarado.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat(tarefas): o trabalho longo corre fora dos ecrãs`

### Task 10: Fila e cancelamento por lista na verificação

**Files:**
- Modify: `lib/verificar/servico.dart`
- Test: `test/verificar/servico_test.dart`

**Interfaces:**
- Produces: `void cancelar(String id)` (tira da fila ou cancela só essa; `feitas/total` certos); `verificarVarias` aceita ser chamado com o serviço ocupado (junta à fila, `total` cresce); `Duration? get estimativaRestante` (média das terminadas × por fazer, `null` antes da primeira).

- [ ] **Step 1: Write the failing tests** — com 3 a correr, `verificarVarias` de mais 2 → `total == 5` e todas acabam; `cancelar` da 2.ª na fila → não é verificada, `total == 4`, as outras acabam; `cancelar` da que está a correr → o resultado dela não é gravado; `estimativaRestante` com 2 feitas de 10 s e 3 por fazer → 30 s.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/verificar` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(verificação): juntar à fila a meio e cancelar uma lista só`

### Task 11: Gestor — ecrã principal

**Files:**
- Create: `lib/ui/gestor/tela_gestor.dart`, `lib/ui/gestor/indicador_atividade.dart`
- Modify: `lib/main.dart` (secção Gestor passa a `TelaGestor`); `lib/ui/verificar/tela_verificar.dart` deixa de ser usado e sai no fim desta tarefa (os testes migram)
- Test: `test/ui/gestor_test.dart`, `test/ui/gestor_passos_test.dart` (migrar)

**Interfaces:**
- Consumes: `AreaGestor`, `ServicoVerificacao` (Task 10), `ServicoTarefas` (Task 9), `EstadoLista`, `PilulaEstado`.
- Produces: `class TelaGestor extends StatefulWidget { const TelaGestor({required Biblioteca biblioteca, required AreaGestor area, required ServicoVerificacao servico, required ServicoTarefas tarefas, String baseStb = stbBase}); }`; sub-ecrãs internos `enum EcraGestor { principal, importar, verificacao }` num `IndexedStack` (o estado de cada um fica); `class IndicadorAtividade` (ex.: `A verificar 11/17 · stbstalker: 24 encontradas`; abre o painel da Task 15).
- Layout (ecrã 7): passos `1 Importar` / `2 Verificar` / `3 Enviar ou exportar` com o estado de cada um; filtros `Todas · n`, `Funcionam · n`, `Inconclusivas · n`, `Não funcionam · n`, `Por verificar · n`; tabela LISTA / ESTADO / CANAIS / VALIDADE; caixas de seleção; barra das selecionadas `Verificar (entra na fila)` · `Enviar para o Player` · `Exportar` · `Remover`.

- [ ] **Step 1: Write the failing tests** — com uma verificação a decorrer, **nenhum** botão está desligado (`onPressed != null` em todos); `Verificar (entra na fila)` com seleção junta à fila; uma lista a ser verificada mostra `A verificar · canal 2/3`; remover selecionadas inclui uma a ser verificada → pede confirmação e cancela só essa; o foco não se perde quando a linha focada muda de estado com filtro ativo (migrar o teste atual); trocar para `importar` e voltar mantém filtro e seleção.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(gestor): ecrã principal sem esperas, com passos, filtros e atividade`

### Task 12: Gestor — importar

**Files:**
- Create: `lib/ui/gestor/tela_importar.dart`
- Modify: `lib/ui/adicionar.dart` (as funções de importar passam a devolver `ResumoImportacao` em vez de texto), `lib/importar/importar.dart` se preciso
- Test: `test/ui/importar_test.dart`, `test/ui/verificar_stb_test.dart` (migrar)

**Interfaces:**
- Consumes: `ServicoTarefas.iniciar`, `importarFicheiros`, `importarTexto`, `importarEntre`, `AreaGestor.importarDoPlayer`.
- Produces: `class ResumoImportacao { final int encontradas, novas, repetidas; final List<String> erros; List<String> idsNovas; String get texto; }`; ecrã 8: 4 origens (`Ficheiros`, `Colar texto`, `Listas do stbstalker`, `Do Player`), painel da origem escolhida, painel `Resultado` (Encontradas / Novas no Gestor / Já estavam no Gestor / Com erro) e botão `Verificar as n novas`.

- [ ] **Step 1: Write the failing tests** — `Procurar e juntar` (stbstalker com servidor falso) cria uma tarefa e devolve o foco logo; sair para Ver TV e voltar com a tarefa ainda a correr → o painel mostra o progresso; quando acaba, `Resultado` mostra os números e há mensagem global; carregar outra vez em `Procurar e juntar` durante a pesquisa inicia outra tarefa (não é ignorado); `Verificar as n novas` junta só as novas à fila.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** (o estado da pesquisa vive na `Tarefa`, não no widget).
- [ ] **Step 4: Run** `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(gestor): importar em segundo plano com o resumo do que entrou`

### Task 13: Gestor — verificação

**Files:**
- Create: `lib/ui/gestor/tela_verificacao.dart`
- Modify: `lib/ui/definicoes/tela_definicoes.dart:176-205` (sai o bloqueio "Não se mudam durante uma verificação."; passa a dizer `Vale para as próximas listas.` quando há verificação)
- Test: `test/ui/verificacao_test.dart`, `test/ui/definicoes_test.dart`

**Interfaces:**
- Consumes: `ServicoVerificacao` (Task 10: `passos`, `feitas`, `total`, `estimativaRestante`, `cancelar`), `EstadoLista`.
- Produces (ecrã 9): título `A verificar n listas`; barra de progresso por cor (funcionam/inconclusivas/não funcionam); contagens; uma linha por lista com o motivo (`Funciona · 3 de 3 canais com imagem`, `Não funciona · <motivo>`); a que está a correr com `A testar canal i de 3`; botões `Verificar mais (fila)` e `Parar`; texto `podes sair, continua sozinha`.

- [ ] **Step 1: Write the failing tests** — com o serviço a correr mostra `11 de 17 verificadas` e a estimativa; a linha de uma lista `nao_funciona` mostra o `motivo` do resultado; `Parar` pára e mostra mensagem; mudar o tempo limite nas Definições durante uma verificação é aceite e mostra `Vale para as próximas listas.`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(gestor): ver a verificação a decorrer, com motivo por lista`

### Task 14: Gestor — enviar e exportar

**Files:**
- Modify: `lib/ui/verificar/dialogos_gestor.dart` (diálogos novos do ecrã 10), `lib/ui/gestor/tela_gestor.dart`
- Test: `test/ui/gestor_test.dart`

**Interfaces:**
- Consumes: `Biblioteca.receber(listas, ModoEnvio)`, `exportarAccountsJson`, `exportarZipIni`, `guardarFicheiro`, `ServicoTarefas`.
- Produces: `Future<(ModoEnvio, bool incluirInc)?> perguntarEnvio(BuildContext, {required int funcionam, required int inconclusivas})` (opções `Adicionar às listas do Player` / `Substituir as listas do Player`, `Só as que funcionam (n)` / `Funcionam + inconclusivas (n)`, botão `Enviar n listas`); `Future<String?> perguntarExportacao(BuildContext, int n)` (`Accounts.json` / `Ficheiros .ini num zip`, aviso `O ficheiro leva os dados de acesso das listas. Guarda-o num sítio seguro.`).
- Depois de escolher, o envio e a exportação correm como `Tarefa`; no fim: mensagem `n listas enviadas para o Player` com ação `Ir para Ver TV` (`TelaPrincipal.irPara`).

- [ ] **Step 1: Write the failing tests** — enviar a meio de uma verificação envia só as já verificadas e a mensagem diz quantas ficaram a decorrer; `Ir para Ver TV` troca de secção; exportar com erro de escrita → tarefa `falhou` com `Tentar de novo`; os textos acima aparecem exatos.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(gestor): enviar e exportar em segundo plano, com as escolhas explicadas`

### Task 15: Painel de atividade

**Files:**
- Create: `lib/ui/gestor/painel_atividade.dart`
- Modify: `lib/ui/principal/tela_principal.dart` (ouve `ServicoTarefas.acabadas` e mostra a mensagem de fim em qualquer secção)
- Test: `test/ui/atividade_test.dart`

**Interfaces:**
- Consumes: `ServicoTarefas`, `ServicoVerificacao`, `IndicadorAtividade`.
- Produces (ecrã 10b): painel lateral `Atividade` com `n a decorrer · n terminadas`; cartão por tarefa (progresso ou resultado; `Ver detalhe`, `Parar`, `Tentar de novo` quando falhou); fecha com Voltar e devolve o foco ao indicador.

- [ ] **Step 1: Write the failing tests** — com 1 verificação e 1 stbstalker a correr mostra 2 cartões a decorrer; uma tarefa que falhou mostra `Tentar de novo` e chama `repetir`; estando em Ver TV, uma tarefa que acaba mostra a mensagem `Verificação terminada: …` com ação `Ver resultados` que leva ao Gestor; Voltar fecha o painel e o foco volta ao indicador.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(gestor): painel de atividade e aviso quando cada tarefa acaba`

### Task 16: Player — topo, ajustes rápidos e erro

**Files:**
- Modify: `lib/ui/player/controlos_player.dart`, `lib/ui/player/painel_definicoes.dart`, `lib/ui/player/cartao_erro.dart`, `lib/dados/preferencias.dart`, `lib/dados/copia_seguranca.dart`, `lib/ui/player/aplicar_preferencias.dart`
- Test: `test/ui/player/controlos_test.dart` (ou o existente equivalente), `test/dados/preferencias_test.dart`, `test/dados/copia_seguranca_test.dart`

**Interfaces:**
- Produces: `enum ModoDesentrelacamento { automatico, ligado, desligado }`; `Preferencias.modoDesentrelacamento` gravado como `"modo_desentrelacamento"`; leitura antiga `desentrelacar: true → automatico`, `false → desligado`; `automatico` = comportamento atual de `desentrelacar == true` (o mpv só desentrelaça o que vem entrelaçado); `ligado` força; `desligado` desliga.
- Topo: número grande + nome + `<lista> › <grupo> · em direto`. Painel → `Ajustes rápidos` com a nota `Áudio e legendas: só este canal · o resto vale para todos`. Cartão de erro: `Tentar de novo` (foco) · `Abrir em modo compatível` · `Canal visto antes` (só se houver) · `Voltar à lista`.

- [ ] **Step 1: Write the failing tests** — migração das preferências (Review Focus 5) incluindo cópia de segurança antiga; `ligado` passa `deinterlace=yes` ao mpv, `desligado` `no`, `automatico` mantém o atual (testes de aplicar_preferencias); o topo mostra `Casa › Desporto · em direto`; o cartão de erro tem as 4 ações e sem canal anterior só 3; os testes atuais de D-pad do player continuam.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(player): topo com lista e grupo, desentrelaçamento automático e erro com mais saídas`

### Task 17: Definições por categorias

**Files:**
- Modify: `lib/ui/definicoes/tela_definicoes.dart`
- Test: `test/ui/definicoes_test.dart`

**Interfaces:**
- Consumes: `Preferencias`, `mostrarMensagem`, `ModoDesentrelacamento`.
- Produces (ecrã 12): categorias à esquerda `Imagem e som`, `Verificação`, `Ligação`, `Cópia de segurança`, `Sobre e licenças` (no telemóvel: lista que abre cada categoria); cada opção com título e explicação; cada mudança mostra `Guardado · vale a partir do próximo canal` (Imagem e som) ou `Guardado` (resto).

- [ ] **Step 1: Write the failing tests** — as 5 categorias existem e cada opção atual está numa delas (nenhuma se perde: canais de teste, tempo limite, desentrelaçamento, hardware, taxa do ecrã, formato, volume, user-agent, cópia de segurança, licenças); mudar uma opção mostra a mensagem certa; D-pad: ESQUERDA da opção vai à categoria, DIREITA volta.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(definições): organizadas por categorias e com confirmação ao mudar`

### Task 18: Pacotes

**Files:** nenhum de código.

- [ ] **Step 1:** `flutter analyze` → `No issues found!`; `flutter test` → tudo verde; `pytest ferramentas` → verde.
- [ ] **Step 2:** No worktree `../player-iptv-dist` (destacado no HEAD do ramo): `python ferramentas/empacotar.py` → gera `dist/PlayerIPTV-android-arm64.apk`, `dist/PlayerIPTV-android-armv7.apk`, `dist/PlayerIPTV-windows.zip`.
- [ ] **Step 3:** Confirmar com zipfile que nenhum pacote contém `test.json`, `Accounts*.json`, `export.json`, `gestor.json`, `biblioteca.json`.
- [ ] **Step 4:** Entregar ao utilizador para testar nos aparelhos.
