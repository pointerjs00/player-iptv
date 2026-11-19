# Ajustes 1 ao redesenho — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aplicar ao redesenho as variantes escolhidas na página «Ajustes 1» e os dois bugs reportados.

**Architecture:** Flutter, ramo feature/redesenho. O Gestor passa a ter um resumo (sem passo aberto) e cinco
ecrãs no `IndexedStack` (resumo, importar, verificar, enviar, progresso). Os passos 2 e 3 ficam em widgets
próprios, testáveis sozinhos, e a `TelaGestor` liga-os às ações que já tem. As novas definições vivem em
`Preferencias` e o `ServicoVerificacao` lê-as a cada arranque de lista.

**Tech Stack:** Flutter 3.50 / Dart 3.14, `package:material_ui/material_ui.dart`, flutter_test.

**Spec:** docs/2026-11-19-ajustes1-design.md (os mockups escolhidos estão em
`.superpowers/sdd/2026-11-19-ajustes1-plano/mockups/`).

## Global Constraints

- Cores só de `Tokens` (lib/ui/design/tokens.dart); nada de `Color(0x…)` novo fora desse ficheiro.
- Texto da interface em pt-PT, com os textos exatos do spec/mockups; nomes de listas nos testes fictícios (001ALFA…).
- Foco sempre visível (o anel `Tokens.anelFoco` dos componentes existentes); tudo alcançável só com setas + OK + Voltar.
- Mensagens só com `mostrarMensagem`; teclas no fundo só com `BarraTeclas`.
- Nada de credenciais, MACs, tokens ou links completos em código, testes, logs ou commits.
- `flutter analyze` sem avisos novos e `flutter test` verde antes de cada commit.

## Review Focus

1. Listas enormes (100 mil canais) na pesquisa única: a coluna dos canais continua virtualizada (`itemExtent` fixo) e a pesquisa dos grupos não bloqueia a interface. — teste na Task 3.
2. Baixar «Listas ao mesmo tempo» com uma verificação a correr: as que já correm acabam, não arrancam novas acima do novo número. — teste na Task 1.
3. Calendário na mudança de mês e nos dias depois de hoje: as setas atravessam meses e saltam os dias futuros; 2.º OK antes do 1.º troca as datas. — teste na Task 4.
4. Uma lista removida do Gestor enquanto está marcada no passo 3 ou selecionada no passo 2: sai das contagens e dos botões. — testes nas Tasks 5 e 6.
5. Voltar no ecrã de progresso volta ao passo 2, e no passo 2/3/importar volta ao resumo, sem perder o foco. — teste na Task 7.

---

### Task 1: Preferências e serviço — listas em simultâneo e tempo limite por lista

**Files:**
- Modify: `lib/dados/preferencias.dart`, `lib/verificar/servico.dart`, `lib/verificar/verificador.dart`
- Test: `test/dados/preferencias_test.dart`, `test/verificar/servico_test.dart` (ou o ficheiro de testes do serviço que já existe)

**Interfaces:**
- Produces: `Preferencias.listasEmSimultaneo` (int, get/set, clamp 1–20, omissão 8; consts `padraoListasEmSimultaneo = 8, minListasEmSimultaneo = 1, maxListasEmSimultaneo = 20`); `Preferencias.tempoLimiteLista` (int segundos, get/set, clamp 10–300, omissão 30; consts `padraoTempoLimiteLista = 30, minTempoLimiteLista = 10, maxTempoLimiteLista = 300`). Ambas persistem no JSON como as outras (`_mudar`), com chaves `listasEmSimultaneo` e `tempoLimiteLista`.
- Produces: `ServicoVerificacao.workers` passa a getter `int get workers` — o valor do construtor se for dado (`int? workers`), senão `(preferencias ?? Preferencias.atual).listasEmSimultaneo`; lido em cada `_servir`.
- Produces: `Verificador.verificarComLimite(..., {Duration? limite})` — quando dado, substitui `limiteConta × perfis`. O serviço passa `Duration(seconds: prefs.tempoLimiteLista)` em todas as voltas (1.ª e reteste). Ao esgotar, o motivo é `tempo esgotado (limite de 30s por lista)` (com o valor real).

- [ ] **Step 1: testes que falham**
  - `preferencias_test`: omissões 8 e 30; `listasEmSimultaneo = 25` → 20, `= 0` → 1; `tempoLimiteLista = 5` → 10, `= 999` → 300; valores sobrevivem a gravar/reler.
  - `servico_test` `'workers vem das definições'`: sem `workers` no construtor e prefs com 2, 5 listas com verificador falso que só acaba quando se manda → 2 a correr.
  - `servico_test` `'baixar as listas em simultâneo não cancela as que correm'`: começa com 4 a correr, muda para 1, acaba uma → nenhuma nova arranca até só restar 0 a correr; depois arranca 1 de cada vez.
  - `servico_test` `'o tempo limite por lista torna-a inconclusiva'`: prefs `tempoLimiteLista = 10`, verificador cujo `lerStream` nunca acaba, `fakeAsync` 11 s → resultado inconclusivo com motivo que contém `por lista`, e a seguinte arranca.
- [ ] **Step 2:** correr os testes focados → FALHAM.
- [ ] **Step 3:** implementar como nas Interfaces. `main.dart` deixa de precisar de passar `workers` (confirmar que não passa; o do Player também usa as prefs).
- [ ] **Step 4:** testes focados → PASSAM; `flutter test` + `flutter analyze`.
- [ ] **Step 5:** commit `feat(verificação): listas em simultâneo e tempo limite por lista nas definições`

### Task 2: Definições › Verificação (variante A)

**Files:**
- Create: `lib/ui/definicoes/seletor_numero.dart`
- Modify: `lib/ui/definicoes/tela_definicoes.dart`
- Test: `test/ui/definicoes_verificacao_test.dart`

**Interfaces:**
- Consumes: Task 1 (`listasEmSimultaneo`, `tempoLimiteLista` e consts).
- Produces: `SeletorNumero({required String titulo, required String descricao, required int valor, required int min, required int max, int passo = 1, String Function(int)? formatar, required ValueChanged<int> aoMudar, FocusNode? focusNode, bool autofocus = false})` — uma linha focável inteira (título + descrição à esquerda, `− valor +` à direita, `Semantics` de valor ajustável com `increasedValue`/`decreasedValue`); ← → mudam o valor em `passo`, sem sair dos limites (os botões − / + ficam desativados nos extremos e também respondem ao toque/rato, sem serem paragens do foco); ↑ ↓ seguem o percurso normal do foco.

- [ ] **Step 1: testes que falham** (em `definicoes_verificacao_test`):
  - a categoria Verificação mostra, por esta ordem, «Listas ao mesmo tempo», «Tempo limite por lista», «Tempo por canal», «Canais de teste», com as descrições do mockup A5-DefVer-1 tal como estão.
  - com o foco em «Listas ao mesmo tempo» (8): → três vezes → `prefs.listasEmSimultaneo == 11` e aparece «Guardado · vale para as próximas listas»; ← até ao fim → pára em 1.
  - «Tempo limite por lista» mostra `30 s`; → → `50 s`; nunca passa de 300.
  - ↓ a partir de «Listas ao mesmo tempo» leva o foco a «Tempo limite por lista».
- [ ] **Step 2:** correr → FALHAM.
- [ ] **Step 3:** implementar `SeletorNumero` e trocar o deslizador atual do tempo por canal pelas três linhas; manter a nota de rodapé do mockup («Com uma verificação a decorrer, as mudanças valem para as próximas listas. ← → mudam o valor; ↑ ↓ mudam de opção.») e a linha dos canais de teste como está hoje. A mensagem sai em cada mudança (`mostrarMensagem` já substitui a anterior).
- [ ] **Step 4:** PASSAM; suite + analyze.
- [ ] **Step 5:** commit `feat(definições): verificação com listas em simultâneo, tempo limite por lista e setas`

### Task 3: Ver TV — foco em «Por verificar» e pesquisa única na lista aberta (variante C)

**Files:**
- Modify: `lib/ui/inicio/tela_inicio.dart`, `lib/ui/conteudo/tela_conteudo.dart`
- Test: `test/ui/inicio_filtros_test.dart`, `test/ui/conteudo_pesquisa_test.dart` (ou juntar aos testes existentes destes ecrãs)

**Interfaces:**
- Produces: nada consumido por outras tarefas.

- [ ] **Step 1: testes que falham**
  - `'o filtro Por verificar recebe o foco e escolhe-se com OK'`: no Início com listas, a partir da pesquisa, com setas (as que a pessoa usaria: → / ↓) chega-se a «Por verificar» e OK filtra. Primeiro reproduzir o bug no teste e encontrar a causa (não tapar o sintoma).
  - `'a pesquisa encontra grupos e canais'`: lista com grupos «Desporto», «Desporto Internacional», «Notícias» e 31 canais com «Desp» no nome; escrever `desp` → cabeçalhos `Grupos · 2` e `Canais · 31`; o último canal encontrado é alcançável com scroll (não há texto «+ N canais»).
  - `'Canais / Grupos limitam a pesquisa'`: com «Grupos», a coluna dos canais mostra o grupo escolhido como sem pesquisa; com «Canais», a coluna dos grupos mostra todos.
  - `'OK num grupo encontrado limpa a pesquisa e abre o grupo'`.
  - `'Voltar com texto limpa a pesquisa; sem texto sai'`.
  - `'↑ no primeiro grupo ou no primeiro canal vai à pesquisa'`.
  - `'já não existe o campo filtro-grupos'` (`find.byKey(Key('filtro-grupos'))` → nada).
  - `'pesquisa numa lista de 100 mil canais'`: escrever não bloqueia (a lista de canais continua um `ListView` com `itemExtent`).
- [ ] **Step 2:** correr → FALHAM.
- [ ] **Step 3:** implementar. Campo de pesquisa com dica «Pesquisar canais, grupos ou o número»; ao lado a escolha «Tudo · Canais · Grupos» (chips de escolha única, focáveis); destacar a parte encontrada em `Tokens.acento`. Grupos encontrados = nome sem acentos contém a pesquisa (usar `semAcentos` já existente). No ecrã estreito (sem coluna dos grupos) os grupos encontrados vão numa fila de chips por cima dos canais. A barra de teclas mostra `('↑', 'pesquisa')`, `('OK', 'abrir')`, `('Voltar', 'limpar')` com texto na pesquisa.
- [ ] **Step 4:** PASSAM; suite + analyze.
- [ ] **Step 5:** commit `feat(ver tv): uma pesquisa para canais e grupos; foco no filtro Por verificar`

### Task 4: Importar · calendário do stbstalker no ecrã (variante C)

**Files:**
- Create: `lib/ui/gestor/calendario_intervalo.dart`
- Modify: `lib/ui/gestor/tela_importar.dart`
- Test: `test/ui/calendario_intervalo_test.dart`

**Interfaces:**
- Produces: `Future<DateTimeRange?> escolherIntervalo(BuildContext context, {required DateTime inicio, required DateTime fim, required DateTime hoje, DateTime? primeiro})` — abre um ecrã inteiro (rota) com o calendário; devolve o intervalo ao carregar em «Procurar e juntar», ou `null` com Voltar.
- Produces: `CalendarioIntervalo` (o widget do ecrã, testável sozinho).

- [ ] **Step 1: testes que falham**
  - abre no mês de `fim`, foco no dia de `fim`; título do mês em pt-PT (`novembro 2026`), semana a começar à segunda (`S T Q Q S S D`).
  - → / ← / ↑ / ↓ mudam o dia (±1 / ±7) e mudam de mês ao passar o limite; não se vai para depois de `hoje`.
  - 1.º OK marca «De», 2.º OK marca «Até» (textos `De` / `Até` com datas `10 nov. 2026`); se o 2.º for antes do 1.º, as datas trocam; um 3.º OK recomeça com esse dia como início.
  - «Recomeçar» limpa as marcas; «Procurar e juntar» fica desativado até haver as duas datas e devolve o intervalo.
  - Voltar devolve `null`.
  - (regressão do bug) OK num dia marca-o — o OK do comando funciona.
- [ ] **Step 2:** correr → FALHAM.
- [ ] **Step 3:** implementar com os textos do mockup A2-Datas-3 tal como estão (título «Escolhe o início e o fim», ajuda «1.º OK marca o início, 2.º OK marca o fim. Os dias depois de hoje não se escolhem.», teclas `←↑↓→ dias`, `OK marcar`, `Voltar sair sem mudar`). Em `tela_importar.dart`, os dois botões de data do stbstalker dão lugar a um botão «Escolher datas · <De> – <Até>» que abre `escolherIntervalo`; ao voltar com intervalo, guarda-o e inicia a mesma pesquisa que o botão de procurar inicia hoje. `showDatePicker` deixa de ser usado.
- [ ] **Step 4:** PASSAM; suite + analyze.
- [ ] **Step 5:** commit `feat(importar): calendário do stbstalker no próprio ecrã, com OK a marcar início e fim`

### Task 5: Passo 2 Verificar (variante A, barra nos azuis da app)

**Files:**
- Create: `lib/ui/gestor/passo_verificar.dart`
- Test: `test/ui/passo_verificar_test.dart`

**Interfaces:**
- Consumes: `AreaGestor`, `ServicoVerificacao` (`ocupado`, `feitas`, `total`, `passos`), `EstadoLista`/`estadoDe`/`PilulaEstado`.
- Produces: `PassoVerificar({required AreaGestor area, required ServicoVerificacao servico, required ValueChanged<List<Lista>> aoVerificar, required VoidCallback aoVerificarTodas, required VoidCallback aoVerVerificacao, required Future<void> Function(List<Lista>) aoRemover, FocusNode? focoInicial})`. Guarda a pesquisa, o filtro e a seleção (ids; ids que saem do Gestor saem da seleção).
- Produces: `bool ServicoVerificacao.houveVerificacao` se ainda não existir nada equivalente (true depois da 1.ª lista posta na fila nesta sessão) — se acrescentares, teste no `servico_test`.

- [ ] **Step 1: testes que falham**
  - mostra a pesquisa «Pesquisar listas…», os filtros `Todas · N`, `Funcionam · N`, `Inconclusivas · N`, `Não funcionam · N`, `Por verificar · N`, a linha `Selecionar:` com `Todas as visíveis`, `Por verificar`, `Nenhuma`, e o cabeçalho `LISTA ESTADO MOTIVO TESTE`.
  - pesquisa `delta` + filtro mostram só as linhas certas; «Todas as visíveis» seleciona só essas.
  - OK numa linha alterna a caixa; a barra diz `2 selecionadas` / `Nenhuma selecionada`.
  - a barra tem exatamente os botões «Verificar selecionadas», «Verificar todas», «Ver verificação», «Remover do gestor»; «Verificar selecionadas» e «Remover do gestor» desativados sem seleção; o fundo da barra é `Tokens.superficie3`.
  - «Ver verificação» desativado com o texto `nenhuma verificação` antes de qualquer verificação; com o serviço a correr mostra `Ver verificação · 2/5` e chama `aoVerVerificacao`.
  - «Verificar selecionadas» chama `aoVerificar` com as selecionadas e mantém o foco na barra.
  - uma lista selecionada que sai do Gestor sai da contagem.
  - TESTE mostra `nunca`, `há 2 h`, `ontem` (relógio injetável ou datas fixas relativas a `DateTime.now`).
- [ ] **Step 2:** correr → FALHAM.
- [ ] **Step 3:** implementar, reaproveitando a tabela/linhas que hoje estão em `_principal()` da `TelaGestor` (copiar para este widget; a remoção do código antigo é na Task 7). Linhas preguiçosas (`SliverList.builder`). ↓ da última linha vai à barra; ↑ da barra volta à última linha focada.
- [ ] **Step 4:** PASSAM; suite + analyze.
- [ ] **Step 5:** commit `feat(gestor): passo 2 só com a verificação — pesquisa, estados, seleção e barra de ações`

### Task 6: Passo 3 Enviar ou exportar (variante A)

**Files:**
- Create: `lib/ui/gestor/passo_enviar.dart`
- Test: `test/ui/passo_enviar_test.dart`

**Interfaces:**
- Consumes: `AreaGestor`, `Biblioteca` (n.º de listas no Player), `estadoDe`, `PilulaEstado`.
- Produces: `PassoEnviar({required AreaGestor area, required Set<String> marcadas, required VoidCallback aoMudarMarcadas, required ValueChanged<List<Lista>> aoEnviar, required ValueChanged<List<Lista>> aoExportar, FocusNode? focoInicial})` — o conjunto `marcadas` pertence à `TelaGestor` (sobrevive a mudar de passo); o widget mexe nele e chama `aoMudarMarcadas`.

- [ ] **Step 1: testes que falham**
  - `Marcar:` com `As que funcionam (12)`, `+ inconclusivas (15)`, `Todas (24)`, `Nenhuma` (contagens reais); cada um substitui a marcação.
  - OK numa linha marca/desmarca; rodapé `12 marcadas · OK marca/desmarca uma lista`.
  - cartões com os textos do mockup A4-Enviar-1 tal como estão; botões `Enviar 12 listas` / `Exportar 12 listas` (singular `Enviar 1 lista`); desativados com 0.
  - os botões chamam `aoEnviar`/`aoExportar` com as marcadas pela ordem da lista.
  - uma marcada que sai do Gestor deixa de contar.
  - → a partir da lista leva aos cartões; ← volta.
- [ ] **Step 2:** correr → FALHAM.
- [ ] **Step 3:** implementar (duas colunas; no ecrã estreito os cartões vão por baixo da lista).
- [ ] **Step 4:** PASSAM; suite + analyze.
- [ ] **Step 5:** commit `feat(gestor): passo 3 com a marcação e os destinos lado a lado`

### Task 7: Gestor — resumo ao entrar (variante A), faixa de passos e ligações

**Files:**
- Modify: `lib/ui/gestor/tela_gestor.dart`, `lib/ui/verificar/dialogos_gestor.dart`, quem usa `EcraGestor` (procurar com grep, p. ex. `lib/ui/principal/tela_principal.dart`, `painel_atividade.dart`)
- Test: os testes existentes do Gestor (atualizar) + `test/ui/gestor_resumo_test.dart`

**Interfaces:**
- Consumes: `PassoVerificar` (Task 5), `PassoEnviar` (Task 6), `ServicoVerificacao.estimativaRestante`, `RegistoImportacoes`.
- Produces: `enum EcraGestor { resumo, importar, verificar, enviar, verificacao }` (substitui `principal`; `pedido` continua a aceitar qualquer um).
- Produces: `perguntarEnvio(context, {required int n})` devolve só o `ModoEnvio` escolhido (adicionar, ou substituir com o que manter) — o «quais» sai do diálogo; atualizar os testes do diálogo.

- [ ] **Step 1: testes que falham** (em `gestor_resumo_test`):
  - ao entrar: título «Gestor de listas», `24 listas no Gestor · escolhe por onde começar`, três cartões (1 Importar, 2 Verificar com o número por verificar, 3 Enviar ou exportar com o número das que funcionam e `prontas a enviar`), cada um com `OK: abrir →`; o foco começa no cartão 1.
  - Gestor vazio: os cartões 2 e 3 dizem `Importe listas primeiro`.
  - com o serviço ocupado aparece a barra `A verificar 2/5` com `faltam cerca de N s` (só quando há estimativa); OK nela abre o progresso.
  - OK no cartão 2 abre o passo 2 com a faixa de passos no topo e o passo 2 realçado; → na faixa muda para o passo 3.
  - Voltar no passo 2 → resumo com o foco no cartão 2; «Ver verificação» → progresso; Voltar no progresso → passo 2.
  - enviar do passo 3 com 3 marcadas pergunta só o modo e envia as 3.
  - a barra de teclas: no resumo `('OK', 'abrir o passo')`; num passo `('Voltar', 'resumo do Gestor')`.
- [ ] **Step 2:** correr → FALHAM.
- [ ] **Step 3:** implementar. O texto de rodapé do resumo: «Nenhum passo está aberto: o Gestor abre sempre neste resumo. Voltar dentro de um passo volta aqui.». Linhas do cartão 1: `Última importação` (do `RegistoImportacoes`, «há 3 min») e `Entraram` («17 novas») só quando há importação nesta sessão; cartão 2: `Funcionam`, `Não funcionam`; cartão 3: `No Player` (n.º de listas da biblioteca). Remover da `TelaGestor` o código antigo da tabela, da marcação e dos filtros que passou para as Tasks 5–6 (e os `FocusNode` que ficam sem uso). As ações (`_verificarSelecionadas`, `_verificarTodas`, `_enviar`, `_exportar`, `_removerSelecionadas`) passam a receber as listas dos passos.
- [ ] **Step 4:** PASSAM; suite inteira (incluindo os testes de D-pad existentes) + analyze.
- [ ] **Step 5:** commit `feat(gestor): resumo ao entrar, faixa de passos e passos 2 e 3 ligados`
