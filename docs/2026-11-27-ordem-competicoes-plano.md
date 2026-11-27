# Ordem das competições — plano de implementação

> **Para agentes:** executar com superpowers:executing-plans (tarefa a tarefa, checkboxes `- [ ]`).

**Objetivo:** um ecrã «Competições» (aberto dos Jogos) com as competições seguidas, um modo
«Reordenar» (comando, toque e rato), e os blocos dos Jogos pela ordem escolhida.

**Arquitetura:** a ordem vive em `PreferenciasJogos` (chave `ordem` no `preferencias.json`);
`agruparPorCompeticao` recebe-a; o ecrã novo é uma rota por cima dos Jogos.

**Tecnologia:** Flutter (`material_ui`), testes de widgets com `flutter_test`
(`C:\flutter\bin\flutter.bat`).

**Design:** `docs/2026-11-27-ordem-competicoes-design.md`

## Restrições globais
- Textos novos em português, com `tr()`, e a tradução em `lib/idioma/ingles.dart`.
- Na TV nenhum controlo pode ficar desligado com o foco (ver o fix do foco nos Jogos, `db86d0a`).
- A edição de partilha não tem Jogos: nada fora de `lib/desporto` e `lib/ui/jogos` muda.

## Focos de revisão
1. Quem já tem `preferencias.json` sem `ordem`: a ordem do catálogo (teste na Tarefa 1).
2. `ordem` com ids que já não existem no catálogo: ignorados (teste na Tarefa 1).
3. Seguir uma competição nova: entra no fim (teste na Tarefa 1).
4. Mover a primeira para cima / a última para baixo: não faz nada, o foco fica (teste na Tarefa 2).
5. Voltar com uma competição pegada: larga-a e não fecha o ecrã (teste na Tarefa 2).

---

### Task 1: a ordem nas preferências e nos blocos dos Jogos

**Ficheiros:**
- Modificar: `lib/desporto/preferencias_jogos.dart`, `lib/desporto/servico_jogos.dart:57-72`,
  `lib/ui/jogos/tela_jogos.dart` (as duas chamadas de `agruparPorCompeticao`)
- Testes: `test/desporto/preferencias_jogos_test.dart` (ou o ficheiro de testes das preferências
  que já existir), `test/desporto/servico_jogos_test.dart`

**Interfaces (produz):**
- `List<String> get PreferenciasJogos.ordemCompeticoes` — as seguidas, pela ordem guardada; as
  seguidas fora da lista guardada no fim, pela ordem do catálogo.
- `set PreferenciasJogos.ordemCompeticoes(List<String> ids)` — guarda (notifica e grava). Mantém,
  depois das dadas, as posições das não seguidas que já estavam na lista guardada.
- `void PreferenciasJogos.moverCompeticao(String id, int novaPosicao)` — `novaPosicao` é o índice
  em `ordemCompeticoes`, limitado a `0..length-1`.
- `List<GrupoJogos> agruparPorCompeticao(List<JogoComCanais> jogos, {List<String> ordem = const []})`
  — competições em `ordem` primeiro, por essa ordem; as restantes depois, pela ordem do catálogo.

- [ ] Testes que falham: sem `ordem` no ficheiro → `ordemCompeticoes` segue o catálogo; `ordem`
  `['champions','liga-portugal']` gravada e reaberta → começa por essas duas; id desconhecido na
  `ordem` → ignorado; `alternarCompeticao` de uma nova → fica no fim; deixar de seguir e voltar a
  seguir → volta ao mesmo sítio relativo; `agruparPorCompeticao(jogos, ordem: ['eredivisie'])` →
  o bloco Eredivisie é o primeiro.
- [ ] Correr: `flutter test test/desporto` → falham.
- [ ] Implementar (lista `_ordem` guardada como `'ordem'`; lida filtrando com `competicaoPorId`).
  Em `tela_jogos.dart` passar `ordem: widget.preferencias.ordemCompeticoes`.
- [ ] Correr: `flutter test test/desporto test/ui/jogos_test.dart` → passam.
- [ ] Commit `feat(jogos): a ordem das competições nas preferências e nos blocos`.

### Task 2: o ecrã «Competições» com o modo «Reordenar»

**Ficheiros:**
- Criar: `lib/ui/jogos/tela_competicoes.dart`
- Mover: `CabecalhoCompeticao`/logótipo — reutilizar `logoCompeticaoFotmob` para o logótipo.
- Teste: `test/ui/competicoes_test.dart` (TV com `ecraTvTeste` + `teclaDpad`; telemóvel com
  `noTelemovel`)

**Interfaces:**
- Consome: `ordemCompeticoes`, `moverCompeticao` (Tarefa 1).
- Produz: `class TelaCompeticoes extends StatefulWidget { const TelaCompeticoes({required PreferenciasJogos preferencias}); }`

Comportamento:
- Lista: logótipo (24 px; ícone de taça sem logo), nome, desporto (`nomeDesporto`). Cabeçalho
  `CabecalhoSeccao(titulo: tr('Competições'), acoes: [botão «Reordenar» / «Concluído»])`.
  Sem seguidas: texto `tr('Não segues nenhuma competição. Escolhe-as em Definições › Jogos.')`.
- Fora do modo: as linhas recebem o foco (para se ver a lista com o comando) e OK não faz nada.
- No modo: `ReorderableListView` com pega (`ReorderableDragStartListener`) para toque/rato; com o
  foco numa linha, OK pega (linha com `destaque`), CIMA/BAIXO chamam `moverCompeticao(id, i∓1)`
  e o foco segue a linha; OK ou Voltar largam; Voltar sem nada pegado sai do modo; Voltar fora do
  modo fecha o ecrã. Rótulo para leitores: `tr('A mover: {0}')`.

- [ ] Testes que falham (TV): abrir, «Reordenar», BAIXO até à 2.ª, OK, CIMA → a 2.ª passa a 1.ª
  em `prefs.ordemCompeticoes` e o foco continua nela; CIMA na 1.ª → nada muda, foco fica;
  Voltar com pegada → larga, o ecrã continua aberto; «Concluído» → sai do modo.
  (Telemóvel): nada transborda a 360×800 com letra 1,3; no modo veem-se as pegas.
- [ ] Correr → falham.
- [ ] Implementar `TelaCompeticoes`.
- [ ] Correr `flutter test test/ui/competicoes_test.dart` → passam.
- [ ] Commit `feat(jogos): ecrã das competições seguidas com «Reordenar»`.

### Task 3: o botão «Competições» nos Jogos

**Ficheiros:** modificar `lib/ui/jogos/tela_jogos.dart`; testes em `test/ui/jogos_test.dart` e
`test/ui/jogos_dpad_test.dart`.

- [ ] Testes que falham: no cabeçalho há `IconButton(tooltip: tr('Competições'))` (ícone
  `Icons.emoji_events_outlined`), antes de «Atualizar»; tocar abre `TelaCompeticoes`; depois de
  reordenar e voltar, o primeiro `CabecalhoCompeticao` é o da competição movida para o topo. Na TV,
  DIREITA a partir da pesquisa chega a «Competições» e, a seguir, a «Atualizar».
- [ ] Correr → falham.
- [ ] Implementar (push de `MaterialPageRoute` com `Scaffold(body: SafeArea(child: TelaCompeticoes(...)))`).
- [ ] Correr o conjunto todo `flutter test` e `flutter analyze` → sem falhas.
- [ ] Commit `feat(jogos): botão «Competições» nos Jogos`.

## Estado
- Concluído (Tasks 1–3 e revisão final), 27/11/2026. Testes: 1790 a passar; `flutter analyze` sem problemas.
