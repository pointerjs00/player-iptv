# Listas favoritas, envio com filtros a manter, marcação por estado e «Ver TV» — design

## Pedido do utilizador
1. Em «Ver TV», poder marcar listas como favoritas.
2. No Gestor, ao enviar com «Substituir», escolher o que manter com filtros que se ligam/desligam:
   «Nenhuma», «Favoritas», «As que funcionam», «As inconclusivas»; «Favoritas» ligado por omissão.
3. No passo 3 do Gestor, os filtros de marcação ligam/desligam-se um a um: um por cada estado das listas,
   mais «Todas» e «Nenhuma».
4. No Gestor, todas as referências a «Player» (o antigo nome de «Ver TV») passam a «Ver TV».

## O que muda
- **Lista favorita:** `Lista.favorita` (guardada com a lista; listas antigas sem o campo = não favoritas;
  entra na cópia de segurança). No Início: estrela no cartão da lista favorita; «Pôr nas favoritas» /
  «Tirar das favoritas» no menu da lista (OK mantido / toque longo / clique direito); chip de filtro
  «Favoritas» junto aos filtros por estado. A ordem das listas não muda.
- **Envio com «Substituir»:** em vez dos três modos de «manter», uma fila de chips de escolha múltipla
  «Nenhuma», «Favoritas», «As que funcionam», «As inconclusivas». «Favoritas» ligado ao abrir. «Nenhuma» é
  exclusivo: ligá-lo desliga os outros; ligar outro desliga «Nenhuma»; desligar o último liga «Nenhuma».
  Uma lista de Ver TV fica se cumprir **qualquer** dos filtros ligados. O texto por baixo diz o que fica
  (ex.: «Ver TV fica com estas e com as favoritas e as que funcionam.»). O resumo final mantém as contagens.
- **Passo 3 — marcar:** chips que se ligam/desligam: «Funcionam (N)», «Inconclusivas (N)», «Não funcionam
  (N)», «Por verificar (N)», «Todas (N)», «Nenhuma». Ligar um estado marca todas as listas desse estado;
  desligar desmarca-as. Um estado aparece ligado quando tem listas e estão todas marcadas. «Todas» marca
  tudo (e fica ligado quando tudo está marcado); «Nenhuma» desmarca tudo. Marcar/desmarcar à mão uma lista
  atualiza os chips.
- **«Ver TV» em vez de «Player»** em todos os textos do Gestor (e mensagens que daí saem): «Enviar para Ver
  TV», «Adicionar às listas de Ver TV», «Substituir as listas de Ver TV», «Em Ver TV: N listas», «De Ver
  TV» / «Importar de Ver TV», «As listas de Ver TV não mudam», «N listas enviadas para Ver TV», etc. Fica o
  nome da app «Player IPTV» e nomes de produtos externos (ex.: «Stalker Portal Player»).

## Decisões minhas
- A estrela fica no canto do cartão (só nas favoritas); o chip «Favoritas» filtra como os outros.
- Os filtros a manter combinam por «ou».
- O chip de estado sem listas fica desativado.
