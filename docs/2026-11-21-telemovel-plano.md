# Telemóvel e pesquisa em Ver TV — plano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Corrigir a interface no telemóvel (nada cortado, escondido ou espremido) e o foco da pesquisa em Ver TV.

**Architecture:** Ramos de layout para ecrã estreito / sem TV (`!ecraTv(context)` e largura < 600 dp) nos ecrãs afetados; a TV e o Windows não mudam salvo nas tarefas 1 (foco da pesquisa, todas as plataformas).

**Tech Stack:** Flutter 3.50 / Dart 3.14, `package:material_ui/material_ui.dart`.

**Spec:** pedido do utilizador (capturas de um telemóvel ~412×915 dp) + relatório `.superpowers/sdd/auditoria-telemovel.md` (problemas e correções por ecrã, com ficheiro e linhas; PNGs na pasta de rascunho).

## Global Constraints

- Telemóvel = não TV e largura < 600 dp (vertical); testar a 360×800 e 412×915, escala de texto 1,0 e 1,3: **nenhum overflow**, nada cortado que importe (nomes de listas/canais podem ter reticências só depois de 2 linhas), alvos de toque ≥ 48 dp.
- TV e Windows: comportamento e testes existentes iguais (salvo Task 1).
- Dicas do comando (setas, OK, Menu) não aparecem fora da TV/Windows.
- Cores de `Tokens`; pt-PT; `mostrarMensagem`; `CampoTv` nos campos.
- `flutter analyze` sem avisos; `flutter test` verde; sem tempo de parede.

## Review Focus

1. Passo 2 a 360 dp com 300 listas: nomes visíveis, sem overflow, seleção e «Ações» alcançáveis. — Task 2.
2. Lista aberta no telemóvel: escolher um grupo entre 96 é fácil (pesquisa) e volta-se a «Todos». — Task 4.
3. Confirmar o filtro com zero resultados não tira o foco do campo. — Task 1.
4. A TV continua igual: os testes de D-pad e de «cabe N» passam sem mudanças. — todas.

---

### Task 1: Ver TV — foco depois de filtrar e caminho até à pesquisa de canais

**Files:** `lib/ui/conteudo/tela_conteudo.dart`; Tests `test/ui/conteudo_pesquisa_test.dart`, `test/ui/navegacao_conteudo_test.dart`.

- [ ] Testes que falham: no «Filtrar grupos», confirmar (Enter / OK / «Concluído» do teclado) com resultados → foco no 1.º grupo encontrado; sem resultados → foco fica no campo; idem na «Pesquisar canais ou número» → 1.º canal / fica no campo; escrever letra a letra não move o foco; → no «Filtrar grupos» (com o cursor no fim do texto ou campo vazio) vai à «Pesquisar canais ou número»; ← na pesquisa de canais (cursor no início ou vazio) volta ao filtro dos grupos.
- [ ] FALHAM → implementar → PASSAM; suite + analyze.
- [ ] Commit `fix(ver tv): foco no 1.º resultado ao confirmar o filtro; seta entre os dois campos`

### Task 2: Gestor no telemóvel

**Files:** `lib/ui/gestor/tela_gestor.dart`, `indicador_atividade.dart`, `passo_verificar.dart`, `passo_enviar.dart`, `tela_importar.dart`, `lib/ui/verificar/dialogos_gestor.dart`, `lib/ui/design/tokens.dart`; Tests novos `test/ui/gestor_telemovel_test.dart`.

- [ ] Testes que falham (360×800 e 412×915, 1,0 e 1,3, sem overflow): topo com «←» só ícone (Semantics «Voltar»), sem título dentro dos passos, indicador só ícone + número (Semantics com o texto completo); faixa com «Importar», «Verificar», «Enviar» inteiros; passo 2 com cada lista em duas linhas (nome inteiro até 2 linhas; estado + motivo + teste em baixo), sem cabeçalho de colunas, caixa de seleção ≥ 48 dp, linha ≥ 56 dp; a ☐ «selecionar visíveis» continua acessível (na barra de cima); passo 3 com os 6 chips visíveis (`Wrap`) e linhas ≥ 48 dp; dicas «OK: abrir →», «OK marca/desmarca…» escondidas fora da TV; diálogo de envio em ecrã inteiro no telemóvel com os chips «manter» visíveis sem deslizar; importar sem partir «.txt»; «Limpar o Gestor» como ação secundária/destrutiva (cor `Tokens.mau`, fim do ecrã).
- [ ] FALHAM → implementar → PASSAM; os testes de TV existentes continuam verdes; suite + analyze.
- [ ] Commit `fix(gestor): telemóvel — topo, faixa, linhas em duas linhas, chips visíveis e diálogo inteiro`

### Task 3: Início no telemóvel

**Files:** `lib/ui/inicio/tela_inicio.dart`, `cartao_continuar.dart`, `cartao_lista.dart`; Tests `test/ui/inicio_telemovel_test.dart`.

- [ ] Testes que falham: filtros todos visíveis (`Wrap`) com «Inconclusivas» em vez de «INC» (também na TV? — não: só o rótulo muda em todas as plataformas, o layout só no telemóvel); «Continuar a ver» com o rótulo «Continuar a ver», o nome do canal numa linha própria (até 2 linhas) e o botão ▶ só ícone (Semantics «Ver»); sem overflow a 360/1,3.
- [ ] FALHAM → implementar → PASSAM; suite + analyze.
- [ ] Commit `fix(ver tv): Início no telemóvel — filtros visíveis e Continuar a ver legível`

### Task 4: Lista aberta no telemóvel

**Files:** `lib/ui/conteudo/tela_conteudo.dart`; Tests `test/ui/conteudo_telemovel_test.dart`.

- [ ] Testes que falham: topo com o nome da lista (até 2 linhas) + «N canais», ⟳ e um menu ⋮ com «Ordem: A–Z / da lista», «Mostrar grupos escondidos (n)», «Atualizar»; os grupos num botão «Grupo: <nome> ▾» que abre um bottom sheet com pesquisa, «Todos os canais», Favoritos/Vistos e cada grupo com a contagem; escolher fecha e mostra os canais; nome do canal até 2 linhas; contador «1 de N» escondido fora da TV; sem overflow a 360/1,3; a TV continua com as duas colunas.
- [ ] FALHAM → implementar → PASSAM; suite + analyze.
- [ ] Commit `fix(ver tv): lista aberta no telemóvel — menu ⋮ e escolha de grupo com pesquisa`

### Task 5: Player e Definições no telemóvel

**Files:** `lib/ui/player/controlos_player.dart`, `lib/ui/player/painel_definicoes.dart`, `lib/ui/definicoes/tela_definicoes.dart`, `lib/ui/definicoes/linha_opcao.dart`; Tests.

- [ ] Testes que falham: player ao alto sem cortar o nome do canal de forma ilegível (2 linhas) e com ⚙ na mesma linha; ajustes rápidos sem partir palavras a meio; Definições sem a nota «← → mudam o valor» e sem «Ajustar a taxa do ecrã ao canal (Android TV)» fora da TV; linhas de opção sem overflow a 360/1,3 (o controlo passa para baixo do título quando não cabe).
- [ ] FALHAM → implementar → PASSAM; suite + analyze.
- [ ] Commit `fix(interface): player e Definições no telemóvel`
