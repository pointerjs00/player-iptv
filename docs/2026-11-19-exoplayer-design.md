# Motor ExoPlayer no Android (fluidez como a IPTV Extreme) — design

## Porquê
O utilizador compara com a IPTV Extreme: lá os canais são mais fluidos. A análise (relatório
`fluidez-player.md` no espaço do plano compacto) mostrou que no Android o vídeo do mpv vai para uma
SurfaceTexture do Flutter (perde imagens sem as contar, ritmo do raster do Flutter), que os canais
entrelaçados ficam a 25 movimentos/s ou passam ao modo Compatível (cópias + bwdif no CPU), e que o ritmo das
imagens não segue o vsync. A IPTV Extreme usa ExoPlayer (Media3): descodificação MediaCodec para uma Surface
real, imagens libertadas alinhadas ao vsync, `Surface.setFrameRate`, desentrelaçamento do SoC e túnel opcional.
O utilizador pediu: «Faz com que a imagem seja a mais fluida possível… Replica esse sistema.»

## O que muda
- **Android: motor ExoPlayer por omissão.** Media3 1.5.1 (`media3-exoplayer`, `media3-exoplayer-hls`;
  download aprovado pelo utilizador). Fontes: HLS (`.m3u8`) e progressivo (MPEG-TS/MP4 por HTTP) com os
  cabeçalhos do canal (User-Agent, cookies/tokens do Stalker) — nunca registados.
- **Saída direta:** o vídeo desenha-se num `SurfaceView` real do Android. Abordagem: `SurfaceView` por baixo
  da `FlutterView` com a `FlutterView` transparente só enquanto o player ExoPlayer está aberto (a zona do vídeo
  na UI é transparente). Alternativa só se a primeira falhar: PlatformView em Hybrid Composition. Proibido:
  qualquer caminho por textura (é o que se quer evitar).
- **Ritmo e ecrã:** ExoPlayer liberta cada imagem com o tempo do vsync (o que faz por omissão com uma Surface);
  `setVideoChangeFrameRateStrategy`/`Surface.setFrameRate` com a taxa do canal, mais o pedido de modo de ecrã
  que já existe (`player_iptv/ecra`).
- **Modo túnel** (Definições, desligado por omissão): `setTunnelingEnabled(true)` quando o aparelho o suporta.
- **Recurso automático:** se o ExoPlayer falhar a abrir um canal por formato/descodificador não suportado, a
  app reabre o canal no mpv e mostra «Este canal abriu com o motor mpv». Erros de rede seguem a recuperação que
  já existe (não trocam de motor).
- **Definições › Imagem e som (só Android):** «Motor do player»: ExoPlayer (omissão) / mpv; «Modo túnel».
  Com ExoPlayer, as opções que só existem no mpv (desentrelaçamento, modo Compatível, descodificação por
  hardware) ficam escondidas ou com a nota «só no motor mpv».
- **Paridade no ExoPlayer:** abrir/parar, play/pausa, zapping e número do canal, faixas de áudio e legendas,
  buffering e percentagem, erro e recuperação, continuar a ver (posição), formato da imagem (ajustar,
  preencher, esticar, 16:9, 4:3, zoom), volume ao abrir, estatísticas (resolução, fps, codec, imagens
  perdidas/renderizadas, bitrate, buffer).
- **Melhorias rápidas no mpv** (continua no Windows e como recurso): `cache-on-disk=no`; limite de perdas do
  Compatível de 2/s para 0,5/s; canais já vistos progressivos não levam shader nem Compatível (memória por
  canal); estatísticas com imagens/s desenhadas pelo Flutter e tempo de raster.
- **Windows:** fica com o mpv.

## Fora do âmbito
Filmes/séries; a extensão ffmpeg do Media3 (não está no Maven; o recurso ao mpv cobre os áudios que o aparelho
não descodifica); mudar a UI do player além do necessário.

## Abordagens
(A) ExoPlayer com Surface real — o que a IPTV Extreme faz; (B) mpv com `vo=mediacodec_embed` numa Surface real
— resolve a saída mas não o desentrelaçamento do SoC nem o ritmo ao vsync; (C) afinar só o mpv atual — ganhos
pequenos. O utilizador pediu A; B/C ficam como recurso (mpv) e melhorias rápidas.

## Decisões minhas
- O ecrã do player passa a falar com um `MotorReproducao` (interface) com duas implementações (mpv e ExoPlayer),
  em vez de usar o `Player` do media_kit diretamente.
- O recurso ao mpv só por erro de formato/descodificador, uma vez por canal na sessão.
- Estatísticas do ExoPlayer pelos `DecoderCounters` (dropped/rendered/skipped) e `Format`.
