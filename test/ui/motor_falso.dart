import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/player/motor_reproducao.dart';

/// Um motor sem rede nem mpv: regista o que o player lhe pede e deixa o teste mandar eventos.
class MotorFalso implements MotorReproducao {
  MotorFalso({this.nome = 'falso', this.registo, this.estatisticasFalsas = const EstatisticasMotor()});

  /// Onde ficam, por ordem, os pedidos de todos os motores do teste (`nome: pedido`).
  final List<String>? registo;
  final EstatisticasMotor estatisticasFalsas;
  final aberturas = <({String url, Map<String, String> cabecalhos, Duration? inicio})>[];
  final pedidos = <String>[];
  final audios = <FaixaMotor>[];
  bool descartado = false;

  /// Se dado, o `parar` só acaba quando isto acabar (um mpv lento a largar o descodificador).
  Future<void>? pararDemora;

  final _erros = StreamController<ErroMotor>.broadcast();
  final _aCarregar = StreamController<bool>.broadcast();
  final _percentagem = StreamController<double>.broadcast();
  final _tamanho = StreamController<Size?>.broadcast();
  final _posicao = StreamController<Duration>.broadcast();
  final _fim = StreamController<void>.broadcast();
  final _faixas = StreamController<FaixasMotor>.broadcast();
  final _faixaAtual = StreamController<FaixaAtual>.broadcast();
  final _fps = StreamController<double>.broadcast();
  final _primeiraImagem = StreamController<void>.broadcast();

  void erro(String e, {bool formato = false, bool rede = false}) =>
      _erros.add(ErroMotor(e, formato: formato, rede: rede));
  /// O stream acabou (num direto: o servidor fechou a ligação).
  void acabar() => _fim.add(null);
  void carregar(bool b) => _aCarregar.add(b);
  void percentagem(double p) => _percentagem.add(p);
  void tamanho(Size? s) => _tamanho.add(s);
  void tempo(Duration p) => _posicao.add(p);
  void mudarFaixas(FaixasMotor f) => _faixas.add(f);
  void mudarFaixaAtual(FaixaAtual f) => _faixaAtual.add(f);
  void medirFps(double v) => _fps.add(v);
  void mostrouPrimeiraImagem() => _primeiraImagem.add(null);

  @override
  final String nome;
  @override
  bool get suportaDesentrelacamento => false;
  @override
  Stream<ErroMotor> get erros => _erros.stream;
  @override
  Stream<bool> get aCarregar => _aCarregar.stream;
  @override
  Stream<double> get percentagemCarga => _percentagem.stream;
  @override
  Stream<Size?> get tamanhoVideo => _tamanho.stream;
  @override
  Stream<Duration> get posicao => _posicao.stream;
  @override
  Stream<void> get fim => _fim.stream;
  @override
  Stream<FaixasMotor> get faixas => _faixas.stream;
  @override
  Stream<FaixaAtual> get faixaAtual => _faixaAtual.stream;
  @override
  Stream<double> get fps => _fps.stream;
  @override
  bool? direto = true;
  @override
  Stream<void> get primeiraImagem => _primeiraImagem.stream;

  @override
  Future<void> abrir(String url, Map<String, String> cabecalhos, {Duration? inicio}) async {
    registo?.add('$nome: abrir');
    aberturas.add((url: url, cabecalhos: cabecalhos, inicio: inicio));
  }
  @override
  Future<void> play() async => pedidos.add('play');
  @override
  Future<void> pausar() async => pedidos.add('pausar');
  @override
  Future<void> parar() async {
    pedidos.add('parar');
    final espera = pararDemora;
    if (espera != null) await espera;
    registo?.add('$nome: parou');
  }
  @override
  Future<void> escolherAudio(FaixaMotor faixa) async => audios.add(faixa);
  @override
  Future<void> escolherLegenda(FaixaMotor? faixa) async => pedidos.add('legenda ${faixa?.id}');
  @override
  Future<void> velocidade(double v) async => pedidos.add('velocidade $v');
  @override
  Future<void> volume(double v) async => pedidos.add('volume $v');
  @override
  Future<EstatisticasMotor> estatisticas() async => estatisticasFalsas;
  @override
  Widget video({required BoxFit ajuste, double? proporcao}) => const ColoredBox(color: Colors.black);
  @override
  Future<void> descartar() async {
    registo?.add('$nome: descartar');
    descartado = true;
  }
}
