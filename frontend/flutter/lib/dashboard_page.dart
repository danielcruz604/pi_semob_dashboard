import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/api_service.dart';
import 'folder_scanner_io.dart' if (dart.library.html) 'folder_scanner_web.dart';
import 'local_data_loader.dart';
import 'login_page.dart';

enum ModoAnalise { extratoPeriodo, compararDiasSemana }

class AlertaOutlier {
  final String titulo;
  final String descricao;
  final bool critico;

  AlertaOutlier({
    required this.titulo,
    required this.descricao,
    this.critico = false,
  });
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _api = ApiService();
  SemobDataset _dataset = SemobDataset();
  bool _carregando = false;
  String? _origemCarregada;
  bool _backendOnline = false;
  String? _statusUpload;

  String _mesSelecionado = 'Agosto/2026';
  String _periodicidade = 'Quinzenal';
  String? _linhaSelecionada;

  ModoAnalise _modoAtivo = ModoAnalise.extratoPeriodo;

  DateTime? _dataInicio;
  DateTime? _dataFim;
  String _presetPeriodo = 'Mês Todo';

  int _diaSemanaComparar = 1;
  Set<String> _datasMarcadasComparacao = {};

  bool _modoTV = false;
  bool _alertasExpandidos = false;

  // Ajusta todos os 31 dias para caberem perfeitamente no card
  bool _verMesTodo = true;

  final ScrollController _scrollViagens = ScrollController();
  final ScrollController _scrollPassageiros = ScrollController();

  static const Map<int, String> _nomesCurtoDia = {
    1: 'Seg',
    2: 'Ter',
    3: 'Qua',
    4: 'Qui',
    5: 'Sex',
    6: 'Sáb',
    7: 'Dom',
  };

  static const Map<int, String> _nomesLongoDia = {
    1: 'Segunda-feira',
    2: 'Terça-feira',
    3: 'Quarta-feira',
    4: 'Quinta-feira',
    5: 'Sexta-feira',
    6: 'Sábado',
    7: 'Domingo',
  };

  static const Map<int, String> _mapaMesNumeroParaNome = {
    1: 'Janeiro',
    2: 'Fevereiro',
    3: 'Março',
    4: 'Abril',
    5: 'Maio',
    6: 'Junho',
    7: 'Julho',
    8: 'Agosto',
    9: 'Setembro',
    10: 'Outubro',
    11: 'Novembro',
    12: 'Dezembro',
  };

  @override
  void initState() {
    super.initState();
    _inicializarDadosDoBanco();
  }

  @override
  void dispose() {
    _scrollViagens.dispose();
    _scrollPassageiros.dispose();
    super.dispose();
  }

  Future<void> _inicializarDadosDoBanco() async {
    setState(() => _carregando = true);

    final online = await _api.verificarServidorOnline();
    _backendOnline = online;

    if (online) {
      final datasetDoBanco = await _api.carregarDatasetDoBanco();
      if (datasetDoBanco != null && !datasetDoBanco.isEmpty) {
        _origemCarregada = 'MongoDB';
        _aplicarDatasetCarregado(datasetDoBanco);
        return;
      }
    }

    if (mounted) {
      setState(() => _carregando = false);
    }
  }

  Future<void> _enviarArquivosParaOBanco(List<ArquivoLido> arquivos) async {
    if (arquivos.isEmpty) return;

    if (!_backendOnline) {
      _backendOnline = await _api.verificarServidorOnline();
    }

    if (!_backendOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Servidor FastAPI offline. Dados exibidos apenas na memória local.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    int salvos = 0;
    for (int i = 0; i < arquivos.length; i++) {
      final arq = arquivos[i];
      if (mounted) {
        setState(() {
          _statusUpload = 'Salvando no MongoDB (${i + 1}/${arquivos.length})...';
        });
      }
      final ok = await _api.enviarHtmlParaBanco(arq.nome, arq.bytes);
      if (ok) salvos++;
    }

    if (mounted) {
      setState(() {
        _statusUpload = null;
        _origemCarregada = '$_origemCarregada (MongoDB)';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ $salvos relatórios salvos e atualizados no MongoDB!'),
          backgroundColor: const Color(0xFF059669),
        ),
      );
    }
  }

  Future<void> _selecionarPastaUnificada() async {
    if (kIsWeb) {
      await _selecionarMultiplosArquivos();
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      var status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        status = await Permission.manageExternalStorage.request();
      }
      if (!status.isGranted) {
        await Permission.storage.request();
      }
    }

    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Selecione a pasta de relatórios da SEMOB',
    );
    if (path == null) return;

    final nomeCurto = LocalDataLoader.extrairNomeCurtoPasta(path);

    setState(() {
      _carregando = true;
      _origemCarregada = nomeCurto;
    });

    final arquivosLidos = await escanearPastaNativa(
      path,
      (nome) => nome.toLowerCase().endsWith('.html') || nome.toLowerCase().endsWith('.htm'),
    );

    final ds = await LocalDataLoader.carregarPasta(path);
    _aplicarDatasetCarregado(ds);

    await _enviarArquivosParaOBanco(arquivosLidos);
  }

  Future<void> _selecionarMultiplosArquivos() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['html', 'htm'],
      dialogTitle: 'Selecione os arquivos HTML da SEMOB',
    );

    if (result.isEmpty) return;

    setState(() {
      _carregando = true;
      _origemCarregada = '${result.length} arq.';
    });

    final arquivosLidos = <ArquivoLido>[];
    for (final f in result) {
      final bytes = await f.readAsBytes();
      arquivosLidos.add(ArquivoLido(
        nome: f.name,
        caminho: f.path ?? f.name,
        bytes: bytes,
      ));
    }

    final ds = await LocalDataLoader.carregarArquivosSelecionados(result);
    _aplicarDatasetCarregado(ds);

    await _enviarArquivosParaOBanco(arquivosLidos);
  }

  void _aplicarDatasetCarregado(SemobDataset ds) {
    if (ds.isEmpty && mounted) {
      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum relatório válido encontrado. Tente selecionar os arquivos .HTML diretamente.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final mesInicial = ds.mesesDisponiveis.isNotEmpty ? ds.mesesDisponiveis.first : 'Agosto/2026';
    final perInicial = _obterPeriodicidadeValida(ds, mesInicial, 'Mensal');

    setState(() {
      _dataset = ds;
      _carregando = false;
      _mesSelecionado = mesInicial;
      _periodicidade = perInicial;
      _linhaSelecionada = null;
      _recalcularLimitesData();
      _atualizarChipsDiaSemana(_diaSemanaComparar, mudarModo: false);
    });
  }

  String _obterPeriodicidadeValida(SemobDataset ds, String mesAlvo, String preferida) {
    final temPreferida = ds.resumos.any((e) => e.mesAno == mesAlvo && e.periodicidade == preferida) ||
        ds.passageiros.any((e) => e.mesAno == mesAlvo && e.periodicidade == preferida) ||
        ds.faixasHorarias.any((e) => e.mesAno == mesAlvo && e.periodicidade == preferida);

    if (temPreferida) return preferida;

    final outra = preferida == 'Mensal' ? 'Quinzenal' : 'Mensal';
    final temOutra = ds.resumos.any((e) => e.mesAno == mesAlvo && e.periodicidade == outra) ||
        ds.passageiros.any((e) => e.mesAno == mesAlvo && e.periodicidade == outra) ||
        ds.faixasHorarias.any((e) => e.mesAno == mesAlvo && e.periodicidade == outra);

    return temOutra ? outra : preferida;
  }

  void _sincronizarMesPelaData(DateTime dtEscolhida) {
    final nomeMes = '${_mapaMesNumeroParaNome[dtEscolhida.month]}/${dtEscolhida.year}';
    if (_dataset.mesesDisponiveis.contains(nomeMes)) {
      _mesSelecionado = nomeMes;
      _periodicidade = _obterPeriodicidadeValida(_dataset, _mesSelecionado, _periodicidade);
    }
  }

  List<DateTime> _todasAsDatasGlobal() {
    final setDt = <DateTime>{
      ..._dataset.resumos.map((e) => e.dateTime),
      ..._dataset.passageiros.map((e) => e.dateTime),
      ..._dataset.faixasHorarias.map((e) => e.dateTime),
    };
    final lista = setDt.toList()..sort();
    return lista;
  }

  List<DateTime> _todasAsDatasDoEscopo() {
    final setDt = <DateTime>{
      ..._dataset.resumos
          .where((e) => e.mesAno == _mesSelecionado && e.periodicidade == _periodicidade)
          .map((e) => e.dateTime),
      ..._dataset.passageiros
          .where((e) => e.mesAno == _mesSelecionado && e.periodicidade == _periodicidade)
          .map((e) => e.dateTime),
      ..._dataset.faixasHorarias
          .where((e) => e.mesAno == _mesSelecionado && e.periodicidade == _periodicidade)
          .map((e) => e.dateTime),
    };
    final lista = setDt.toList()..sort();
    return lista;
  }

  void _recalcularLimitesData() {
    final dts = _todasAsDatasDoEscopo();
    if (dts.isNotEmpty) {
      _dataInicio = dts.first;
      _dataFim = dts.last;
    }
    _presetPeriodo = 'Mês Todo';
  }

  void _atualizarChipsDiaSemana(int weekday, {bool mudarModo = true}) {
    final dts = _todasAsDatasDoEscopo().where((dt) => dt.weekday == weekday).toList();
    setState(() {
      _diaSemanaComparar = weekday;
      if (mudarModo) _modoAtivo = ModoAnalise.compararDiasSemana;
      _datasMarcadasComparacao = dts.map(_fmtDataBR).toSet();
    });
  }

  bool _dataPassaNoFiltro(String dataStr, DateTime dt) {
    if (_modoAtivo == ModoAnalise.extratoPeriodo) {
      if (_dataInicio != null) {
        final inicioLimpo = DateTime(_dataInicio!.year, _dataInicio!.month, _dataInicio!.day);
        if (dt.isBefore(inicioLimpo)) return false;
      }
      if (_dataFim != null) {
        final fimLimpo = DateTime(_dataFim!.year, _dataFim!.month, _dataFim!.day, 23, 59, 59);
        if (dt.isAfter(fimLimpo)) return false;
      }
      return true;
    } else {
      return _datasMarcadasComparacao.contains(dataStr);
    }
  }

  static String _fmtDataBR(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _fmtCurto(String dataBR) => dataBR.length >= 5 ? dataBR.substring(0, 5) : dataBR;

  static DateTime _parseStrToDate(String s) {
    final p = s.split('/');
    if (p.length != 3) return DateTime(2026);
    return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
  }

  void _sairParaTelaDeLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  Future<void> _exportarRelatorioCsv(
    List<ResumoDiario> resumos,
    List<PassageiroDiario> passageiros,
  ) async {
    final mapPass = {for (var p in passageiros) p.data: p};
    final buffer = StringBuffer();

    buffer.write('\uFEFF');
    buffer.writeln('=== RELATÓRIO OPERACIONAL SEMOB • SÃO CAETANO DO SUL ===');
    buffer.writeln('Escopo:;$_mesSelecionado - $_periodicidade;Linha:;${_linhaSelecionada ?? "Todas as Linhas"}');
    buffer.writeln('Data de Extração:;${_fmtDataBR(DateTime.now())}');
    buffer.writeln('Origem dos Dados:;${_origemCarregada ?? "Local"}');
    buffer.writeln();
    buffer.writeln(
      'Data;Dia da Semana;Frota (Veíc.);Viagens Programadas;Viagens Realizadas;Diferença;FCV (%);KM Total;KM Improdutivo;Passageiros Catraca;Passageiros Gratuitos;Total Passageiros',
    );

    for (final r in resumos) {
      final p = mapPass[r.data];
      final fcv = r.viagensProg > 0 ? ((r.viagensRealiz / r.viagensProg) * 100).toStringAsFixed(2) : '100.00';
      buffer.writeln(
        '${r.data};${_nomesLongoDia[r.weekday] ?? ''};${r.veiculos};${r.viagensProg};${r.viagensRealiz};${r.difViagens};$fcv%;${r.kmTotal.toStringAsFixed(2)};${r.kmImprod.toStringAsFixed(2)};${p?.catraca ?? 0};${p?.naoPagantes ?? 0};${p?.totalPassageiros ?? 0}',
      );
    }

    try {
      final bytes = Uint8List.fromList(utf8.encode(buffer.toString()));
      final nomeSugerido = 'relatorio_semob_${_mesSelecionado.replaceAll('/', '_')}_${_periodicidade.toLowerCase()}.csv';

      final caminhoSalvo = await FilePicker.saveFile(
        dialogTitle: 'Exportar Relatório Operacional SEMOB (CSV)',
        fileName: nomeSugerido,
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: bytes,
      );

      if (!kIsWeb && caminhoSalvo != null) {
        final f = File(caminhoSalvo.toFilePath());
        if (!f.existsSync() || f.lengthSync() == 0) {
          await f.writeAsBytes(bytes);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(caminhoSalvo != null ? 'Relatório exportado com sucesso!' : 'Exportação concluída.'),
            backgroundColor: const Color(0xFF059669),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao exportar relatório: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  List<AlertaOutlier> _calcularOutliers(List<ResumoDiario> resumos, List<PassageiroDiario> passageiros) {
    final alertas = <AlertaOutlier>[];
    if (resumos.isEmpty) return alertas;

    for (final r in resumos) {
      final fcv = r.viagensProg > 0 ? (r.viagensRealiz / r.viagensProg) * 100 : 100.0;
      if (fcv < 98.0) {
        alertas.add(AlertaOutlier(
          titulo: 'Descumprimento de FCV em ${r.data} (${_nomesCurtoDia[r.weekday]})',
          descricao:
              'FCV atingiu ${fcv.toStringAsFixed(1)}% (${r.difViagens} viagens não realizadas). Impacto direto no intervalo de espera em SCS.',
          critico: fcv < 95.0,
        ));
      }
    }

    final diasUteis = resumos.where((r) => r.weekday >= 1 && r.weekday <= 5).toList();
    if (diasUteis.length >= 3) {
      final mediaKm = diasUteis.map((e) => e.kmTotal).reduce((a, b) => a + b) / diasUteis.length;
      for (final r in diasUteis) {
        final desvio = ((r.kmTotal - mediaKm) / mediaKm).abs();
        if (desvio > 0.25) {
          alertas.add(AlertaOutlier(
            titulo: 'Anomalia de Quilometragem em ${r.data}',
            descricao:
                'KM total (${r.kmTotal.toStringAsFixed(0)} km) desviou ${(desvio * 100).toStringAsFixed(0)}% da média dos dias úteis (${mediaKm.toStringAsFixed(0)} km).',
            critico: false,
          ));
        }
      }
    }

    if (diasUteis.isNotEmpty) {
      final maxFrota = diasUteis.map((e) => e.veiculos).reduce((a, b) => a > b ? a : b);
      for (final r in diasUteis) {
        if (maxFrota > 0 && r.veiculos < (maxFrota * 0.75).round()) {
          alertas.add(AlertaOutlier(
            titulo: 'Déficit de Frota Operacional em ${r.data}',
            descricao: 'Operando com apenas ${r.veiculos} ônibus (${maxFrota - r.veiculos} a menos que a frota de pico).',
            critico: true,
          ));
        }
      }
    }

    return alertas;
  }

  static Widget _emptyAxisTitle(double value, TitleMeta meta) => const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;

    // Detecta se é celular deitado (landscape em smartphone)
    final isPhoneLandscape = screenHeight < 550 && screenWidth < 1050;
    final isTelaLarga = screenWidth >= 1050 && !isPhoneLandscape;
    final isMobile = screenWidth < 700 || isPhoneLandscape;

    final resumosFiltrados = _dataset.resumos
        .where((e) => e.periodicidade == _periodicidade && _dataPassaNoFiltro(e.data, e.dateTime))
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    final passageirosFiltrados = _dataset.passageiros
        .where((e) => e.periodicidade == _periodicidade && _dataPassaNoFiltro(e.data, e.dateTime))
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    final fcvFiltrados = _dataset.fcv
        .where((e) => e.periodicidade == _periodicidade && _dataPassaNoFiltro(e.data, e.dateTime))
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    final fxHrFiltrados = _dataset.faixasHorarias
        .where((e) =>
            e.periodicidade == _periodicidade &&
            (_linhaSelecionada == null || e.linha == _linhaSelecionada) &&
            _dataPassaNoFiltro(e.data, e.dateTime))
        .toList();

    final linhasFiltradas = _dataset.linhas
        .where((e) =>
            e.periodicidade == _periodicidade &&
            (_linhaSelecionada == null || e.linha == _linhaSelecionada) &&
            _dataPassaNoFiltro(e.data, e.dateTime))
        .toList();

    final outliersDetectados = _calcularOutliers(resumosFiltrados, passageirosFiltrados);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: _modoTV ? 62 : (isPhoneLandscape ? 48 : 54),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_bus_filled_rounded, color: const Color(0xFF38BDF8), size: _modoTV ? 26 : 22),
            const SizedBox(width: 8),
            Text(
              isTelaLarga ? 'SEMOB • Monitoramento' : 'SEMOB',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: _modoTV ? 18 : 15),
            ),
            const SizedBox(width: 10),
            Container(
              padding: EdgeInsets.symmetric(horizontal: _modoTV ? 8 : 6, vertical: _modoTV ? 3 : 2),
              decoration: BoxDecoration(
                color: _backendOnline ? const Color(0xFF065F46) : const Color(0xFF475569),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: _modoTV ? 7 : 6, color: _backendOnline ? const Color(0xFF34D399) : Colors.amberAccent),
                  if (isTelaLarga) ...[
                    const SizedBox(width: 5),
                    Text(
                      _backendOnline ? 'MongoDB Online' : 'Modo Local',
                      style: TextStyle(fontSize: _modoTV ? 11 : 10, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: _construirAcoesAppBar(isTelaLarga, resumosFiltrados, passageirosFiltrados),
      ),
      // SafeArea protege contra a câmera punch hole na lateral e a barra de navegação/gestos do Android no rodapé
      body: SafeArea(
        left: true,
        right: true,
        bottom: true,
        top: false,
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _dataset.isEmpty
                ? _buildEmptyState()
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // Em celulares deitados (landscape), mantém 1 coluna para não esmagar os gráficos
                      final isWide = constraints.maxWidth >= 950 && !isPhoneLandscape;
                      return SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          _modoTV ? 18 : (isMobile ? 12 : 14),
                          _modoTV ? 18 : (isMobile ? 10 : 14),
                          _modoTV ? 18 : (isMobile ? 12 : 14),
                          // Respiro extra para garantir que a barra do Android nunca sobreponha o conteúdo
                          _modoTV ? 24 : 32,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_statusUpload != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF3B82F6)),
                                ),
                                child: Row(
                                  children: [
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _statusUpload!,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            _buildBarraTopoSlim(),
                            const SizedBox(height: 12),
                            _buildAvisoOutliers(outliersDetectados),
                            const SizedBox(height: 12),
                            _buildKPIsResponsivo(
                              isWide,
                              isPhoneLandscape,
                              resumosFiltrados,
                              passageirosFiltrados,
                              fxHrFiltrados,
                              linhasFiltradas,
                            ),
                            const SizedBox(height: 14),
                            if (isWide) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _buildGraficoViagensEQuilometragem(
                                      resumosFiltrados,
                                      fxHrFiltrados,
                                      linhasFiltradas,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: _buildGraficoPassageiros(passageirosFiltrados),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _buildGraficoFaixaHoraria(fxHrFiltrados),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: _buildGraficoTurnosERanking(fcvFiltrados, fxHrFiltrados, resumosFiltrados),
                                  ),
                                ],
                              ),
                            ] else ...[
                              _buildGraficoViagensEQuilometragem(resumosFiltrados, fxHrFiltrados, linhasFiltradas),
                              const SizedBox(height: 14),
                              _buildGraficoPassageiros(passageirosFiltrados),
                              const SizedBox(height: 14),
                              _buildGraficoFaixaHoraria(fxHrFiltrados),
                              const SizedBox(height: 14),
                              _buildGraficoTurnosERanking(fcvFiltrados, fxHrFiltrados, resumosFiltrados),
                            ],
                            const SizedBox(height: 14),
                            _buildTabelaResumo(resumosFiltrados, passageirosFiltrados),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  List<Widget> _construirAcoesAppBar(
    bool isTelaLarga,
    List<ResumoDiario> resumos,
    List<PassageiroDiario> passageiros,
  ) {
    if (!isTelaLarga) {
      return [
        IconButton(
          tooltip: 'Sincronizar com MongoDB',
          icon: Icon(Icons.sync_rounded, color: const Color(0xFF38BDF8), size: _modoTV ? 24 : 20),
          onPressed: _carregando ? null : _inicializarDadosDoBanco,
        ),
        IconButton(
          tooltip: _modoTV ? 'Modo TV: ON' : 'Modo TV',
          icon: Icon(Icons.tv_rounded, color: _modoTV ? Colors.cyanAccent : Colors.white70, size: 20),
          onPressed: () => setState(() => _modoTV = !_modoTV),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
          onSelected: (val) {
            if (val == 'csv') _exportarRelatorioCsv(resumos, passageiros);
            if (val == 'pasta') _selecionarPastaUnificada();
            if (val == 'htmls') _selecionarMultiplosArquivos();
            if (val == 'sair') _sairParaTelaDeLogin();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'csv',
              child: Row(
                children: [
                  Icon(Icons.download_rounded, color: Color(0xFF059669), size: 18),
                  SizedBox(width: 8),
                  Text('Exportar CSV'),
                ],
              ),
            ),
            if (!kIsWeb)
              const PopupMenuItem(
                value: 'pasta',
                child: Row(
                  children: [
                    Icon(Icons.folder_open_rounded, color: Color(0xFF0284C7), size: 18),
                    SizedBox(width: 8),
                    Text('Abrir Pasta'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'htmls',
              child: Row(
                children: [
                  Icon(Icons.file_present_rounded, color: Color(0xFF38BDF8), size: 18),
                  SizedBox(width: 8),
                  Text('Selecionar HTMLs'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'sair',
              child: Row(
                children: [
                  Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18),
                  SizedBox(width: 8),
                  Text('Sair do Sistema'),
                ],
              ),
            ),
          ],
        ),
      ];
    }

    return [
      IconButton(
        tooltip: 'Sincronizar com MongoDB',
        icon: Icon(Icons.sync_rounded, color: const Color(0xFF38BDF8), size: _modoTV ? 24 : 20),
        onPressed: _carregando ? null : _inicializarDadosDoBanco,
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 2.0),
        child: Tooltip(
          message: 'Ajusta fontes e contraste para leitura à distância ou telas grandes',
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              backgroundColor: _modoTV ? const Color(0xFF0284C7) : Colors.transparent,
              foregroundColor: Colors.white,
              side: BorderSide(color: _modoTV ? const Color(0xFF38BDF8) : Colors.white30, width: 1.5),
              padding: EdgeInsets.symmetric(horizontal: _modoTV ? 14 : 10),
            ),
            onPressed: () => setState(() => _modoTV = !_modoTV),
            icon: Icon(Icons.tv_rounded, size: _modoTV ? 18 : 15, color: _modoTV ? Colors.white : const Color(0xFF38BDF8)),
            label: Text(
              _modoTV ? 'Modo TV: ON' : 'Modo TV',
              style: TextStyle(fontSize: _modoTV ? 13 : 12, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF059669),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: EdgeInsets.symmetric(horizontal: _modoTV ? 14 : 11),
          ),
          onPressed: _dataset.isEmpty ? null : () => _exportarRelatorioCsv(resumos, passageiros),
          icon: Icon(Icons.download_rounded, size: _modoTV ? 18 : 16),
          label: Text('Exportar CSV', style: TextStyle(fontSize: _modoTV ? 13 : 12, fontWeight: FontWeight.bold)),
        ),
      ),
      if (!kIsWeb)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(horizontal: _modoTV ? 14 : 12),
            ),
            onPressed: _carregando ? null : _selecionarPastaUnificada,
            icon: Icon(Icons.folder_open_rounded, size: _modoTV ? 18 : 16),
            label: Text(
              'Abrir Pasta',
              style: TextStyle(fontSize: _modoTV ? 13 : 12, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF38BDF8)),
            padding: EdgeInsets.symmetric(horizontal: _modoTV ? 12 : 10),
          ),
          onPressed: _carregando ? null : _selecionarMultiplosArquivos,
          icon: Icon(Icons.file_present_rounded, size: _modoTV ? 17 : 15, color: const Color(0xFF38BDF8)),
          label: Text('HTMLs', style: TextStyle(fontSize: _modoTV ? 13 : 12, fontWeight: FontWeight.bold)),
        ),
      ),
      IconButton(
        tooltip: 'Sair / Trocar Operador',
        icon: Icon(Icons.logout_rounded, color: Colors.white70, size: _modoTV ? 22 : 20),
        onPressed: _sairParaTelaDeLogin,
      ),
      const SizedBox(width: 6),
    ];
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(28),
        constraints: const BoxConstraints(maxWidth: 460),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.analytics_outlined, size: 64, color: Color(0xFF0284C7)),
            const SizedBox(height: 16),
            const Text(
              'Painel de Mobilidade SEMOB',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _backendOnline
                  ? 'MongoDB conectado! Ao selecionar relatórios, eles serão salvos no banco. Se já houver dados gravados, clique no botão de sincronizar no topo.'
                  : 'Servidor FastAPI offline. Conecte o backend para salvar no banco ou abra os arquivos para análise local temporária.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.blueGrey, fontSize: 13),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                if (!kIsWeb)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    onPressed: _selecionarPastaUnificada,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Selecionar Pasta'),
                  ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kIsWeb ? const Color(0xFF0284C7) : Colors.blueGrey.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                  onPressed: _selecionarMultiplosArquivos,
                  icon: const Icon(Icons.file_present_rounded),
                  label: const Text('Selecionar Arquivos .HTML'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvisoOutliers(List<AlertaOutlier> alertas) {
    final isMobile = MediaQuery.of(context).size.width < 700 || MediaQuery.of(context).size.height < 550;

    if (alertas.isEmpty) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: _modoTV ? 12 : 9),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: const Color(0xFF059669), size: _modoTV ? 22 : 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Operação Regular: Nenhum outlier crítico detectado em SCS.',
                style: TextStyle(
                  fontSize: _modoTV ? 14 : 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF065F46),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final temCritico = alertas.any((a) => a.critico);
    final corBase = temCritico ? const Color(0xFFDC2626) : const Color(0xFFD97706);
    final corFundo = temCritico ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB);

    return Container(
      padding: EdgeInsets.all(_modoTV ? 16 : 12),
      decoration: BoxDecoration(
        color: corFundo,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: corBase.withOpacity(0.6), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: corBase, size: _modoTV ? 26 : 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isMobile ? 'ALERTAS DE MOBILIDADE' : 'ALERTAS DE IMPACTO NA MOBILIDADE (SÃO CAETANO DO SUL)',
                  style: TextStyle(
                    fontSize: _modoTV ? 14 : 11,
                    fontWeight: FontWeight.w900,
                    color: corBase,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              InkWell(
                onTap: () => setState(() => _alertasExpandidos = !_alertasExpandidos),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: _modoTV ? 12 : 8, vertical: _modoTV ? 6 : 4),
                  decoration: BoxDecoration(
                    color: corBase,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${alertas.length} Ocorrências',
                        style: TextStyle(fontSize: _modoTV ? 13 : 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _alertasExpandidos ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 18,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!_alertasExpandidos)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: alertas.take(isMobile ? 2 : 3).map((a) {
                return Container(
                  padding: EdgeInsets.symmetric(horizontal: _modoTV ? 12 : 10, vertical: _modoTV ? 7 : 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: corBase.withOpacity(0.3)),
                  ),
                  child: Text(
                    '${a.titulo}: ${a.descricao}',
                    style: TextStyle(
                      fontSize: _modoTV ? 13 : 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                );
              }).toList(),
            )
          else
            Column(
              children: alertas.map((a) {
                return Padding(
                  padding: const EdgeInsets.only(top: 6.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.arrow_right_rounded, color: corBase, size: 24),
                      const SizedBox(width: 4),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: _modoTV ? 14 : 11,
                              color: const Color(0xFF1E293B),
                            ),
                            children: [
                              TextSpan(text: '${a.titulo} • ', style: TextStyle(fontWeight: FontWeight.bold, color: corBase)),
                              TextSpan(text: a.descricao),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildBarraTopoSlim() {
    final todasDatasEscopo = _todasAsDatasDoEscopo();
    final datasDoDiaSemana = todasDatasEscopo.where((d) => d.weekday == _diaSemanaComparar).map(_fmtDataBR).toSet();

    final chipsParaExibir = <String>{
      ...datasDoDiaSemana,
      ..._datasMarcadasComparacao,
    }.toList()
      ..sort((a, b) => _parseStrToDate(a).compareTo(_parseStrToDate(b)));

    final labelIntervalo = (_dataInicio != null && _dataFim != null)
        ? (_dataInicio == _dataFim
            ? 'Dia: ${_fmtDataBR(_dataInicio!)}'
            : '${_fmtCurto(_fmtDataBR(_dataInicio!))} a ${_fmtDataBR(_dataFim!)}')
        : 'Período';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: _modoTV ? 12 : 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _pillSelect(
            icone: Icons.calendar_today_rounded,
            label: 'Mês',
            value: _mesSelecionado,
            items: _dataset.mesesDisponiveis.isEmpty ? ['Agosto/2026'] : _dataset.mesesDisponiveis,
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _mesSelecionado = v;
                _periodicidade = _obterPeriodicidadeValida(_dataset, v, _periodicidade);
                _recalcularLimitesData();
                _atualizarChipsDiaSemana(_diaSemanaComparar, mudarModo: false);
              });
            },
          ),
          _pillSelect(
            icone: Icons.layers_outlined,
            label: 'Visão',
            value: _periodicidade,
            items: const ['Mensal', 'Quinzenal'],
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _periodicidade = v;
                _recalcularLimitesData();
                _atualizarChipsDiaSemana(_diaSemanaComparar, mudarModo: false);
              });
            },
          ),
          _pillSelect(
            icone: Icons.directions_bus_outlined,
            label: 'Linha',
            value: _linhaSelecionada ?? 'Todas',
            items: ['Todas', ..._dataset.linhasDisponiveis],
            onChanged: (v) => setState(() => _linhaSelecionada = (v == 'Todas') ? null : v),
          ),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _tabModoButton(
                  titulo: 'Por Período',
                  icone: Icons.date_range_rounded,
                  ativo: _modoAtivo == ModoAnalise.extratoPeriodo,
                  onTap: () => setState(() => _modoAtivo = ModoAnalise.extratoPeriodo),
                ),
                _tabModoButton(
                  titulo: 'Comparar Dias',
                  icone: Icons.compare_arrows_rounded,
                  ativo: _modoAtivo == ModoAnalise.compararDiasSemana,
                  onTap: () => setState(() => _modoAtivo = ModoAnalise.compararDiasSemana),
                ),
              ],
            ),
          ),
          if (_modoAtivo == ModoAnalise.extratoPeriodo) ...[
            _pillSelect(
              icone: Icons.bolt_rounded,
              label: 'Recorte',
              value: _presetPeriodo,
              items: const ['Mês Todo', '1ª Quinzena', '2ª Quinzena', 'Dia Único', 'Personalizado'],
              onChanged: (val) async {
                if (val == null) return;
                final dts = _todasAsDatasDoEscopo();
                final base = dts.isNotEmpty ? dts.first : DateTime(2026, 8, 1);
                final fimMes = dts.isNotEmpty ? dts.last : DateTime(2026, 8, 31);

                if (val == 'Mês Todo') {
                  setState(() {
                    _presetPeriodo = val;
                    _dataInicio = base;
                    _dataFim = fimMes;
                  });
                } else if (val == '1ª Quinzena') {
                  setState(() {
                    _presetPeriodo = val;
                    _dataInicio = DateTime(base.year, base.month, 1);
                    _dataFim = DateTime(base.year, base.month, 15);
                  });
                } else if (val == '2ª Quinzena') {
                  setState(() {
                    _presetPeriodo = val;
                    _dataInicio = DateTime(base.year, base.month, 16);
                    _dataFim = DateTime(base.year, base.month, fimMes.day);
                  });
                } else if (val == 'Dia Único') {
                  await _abrirSingleDatePicker();
                } else if (val == 'Personalizado') {
                  await _abrirRangePicker();
                }
              },
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.edit_calendar_rounded, size: 16, color: Color(0xFF0284C7)),
              label: Text(
                labelIntervalo,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              onPressed: () {
                if (_presetPeriodo == 'Dia Único') {
                  _abrirSingleDatePicker();
                } else {
                  _abrirRangePicker();
                }
              },
            ),
          ] else ...[
            Wrap(
              spacing: 4,
              children: _nomesCurtoDia.entries.map((e) {
                final sel = _diaSemanaComparar == e.key;
                return InkWell(
                  onTap: () => _atualizarChipsDiaSemana(e.key),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFF7C3AED) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      e.value,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: sel ? Colors.white : const Color(0xFF475569),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            ...chipsParaExibir.map((dataStr) {
              final marcado = _datasMarcadasComparacao.contains(dataStr);
              final ehExtra = !datasDoDiaSemana.contains(dataStr);
              return FilterChip(
                visualDensity: VisualDensity.compact,
                label: Text(
                  _fmtCurto(dataStr),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: ehExtra ? const Color(0xFF0284C7) : null,
                  ),
                ),
                selected: marcado,
                selectedColor: ehExtra ? const Color(0xFFE0F2FE) : const Color(0xFFDDD6FE),
                checkmarkColor: ehExtra ? const Color(0xFF0369A1) : const Color(0xFF5B21B6),
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _datasMarcadasComparacao.add(dataStr);
                    } else {
                      _datasMarcadasComparacao.remove(dataStr);
                    }
                  });
                },
              );
            }),
            ActionChip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.calendar_month_rounded, size: 14, color: Color(0xFF7C3AED)),
              label: Text('+ Datas (${_datasMarcadasComparacao.length})', style: const TextStyle(fontSize: 11)),
              onPressed: _abrirSeletorMultiplasDatas,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _abrirSingleDatePicker() async {
    final todasGlobal = _todasAsDatasGlobal();
    final minDate = todasGlobal.isNotEmpty ? todasGlobal.first : DateTime(2026, 1, 1);
    final maxDate = todasGlobal.isNotEmpty ? todasGlobal.last : DateTime(2026, 12, 31);
    final initial = _dataInicio ?? minDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(minDate) ? minDate : (initial.isAfter(maxDate) ? maxDate : initial),
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime(2026, 12, 31),
      helpText: 'SELECIONE O DIA ÚNICO (QUALQUER MÊS)',
    );
    if (picked != null) {
      setState(() {
        _sincronizarMesPelaData(picked);
        _presetPeriodo = 'Dia Único';
        _dataInicio = picked;
        _dataFim = picked;
      });
    }
  }

  Future<void> _abrirRangePicker() async {
    final todasGlobal = _todasAsDatasGlobal();
    final minDate = todasGlobal.isNotEmpty ? todasGlobal.first : DateTime(2026, 1, 1);
    final maxDate = todasGlobal.isNotEmpty ? todasGlobal.last : DateTime(2026, 12, 31);

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime(2026, 12, 31),
      initialDateRange: DateTimeRange(
        start: _dataInicio ?? minDate,
        end: _dataFim ?? maxDate,
      ),
      helpText: 'SELECIONE O PERÍODO OU DIA ÚNICO',
    );
    if (picked != null) {
      setState(() {
        _sincronizarMesPelaData(picked.start);
        _presetPeriodo = picked.start == picked.end ? 'Dia Único' : 'Personalizado';
        _dataInicio = picked.start;
        _dataFim = picked.end;
      });
    }
  }

  Widget _pillSelect({
    required IconData icone,
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final valorSeguro = items.contains(value) ? value : items.first;
    return Container(
      height: _modoTV ? 38 : 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: _modoTV ? 16 : 14, color: Colors.blueGrey),
          const SizedBox(width: 5),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: _modoTV ? 12 : 11,
              color: Colors.blueGrey,
              fontWeight: FontWeight.w700,
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: valorSeguro,
              isDense: true,
              style: TextStyle(
                fontSize: _modoTV ? 13 : 12,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F172A),
              ),
              items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabModoButton({
    required String titulo,
    required IconData icone,
    required bool ativo,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: _modoTV ? 12 : 10, vertical: _modoTV ? 7 : 6),
        decoration: BoxDecoration(
          color: ativo ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: ativo ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 3)] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: _modoTV ? 16 : 14, color: ativo ? const Color(0xFF0284C7) : Colors.blueGrey),
            const SizedBox(width: 6),
            Text(
              titulo,
              style: TextStyle(
                fontSize: _modoTV ? 13 : 12,
                fontWeight: FontWeight.bold,
                color: ativo ? const Color(0xFF0F172A) : Colors.blueGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirSeletorMultiplasDatas() {
    final todasDatas = _todasAsDatasDoEscopo().map(_fmtDataBR).toList();
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return AlertDialog(
              title: const Text('Escolher Datas para Comparar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Marque quaisquer dias do mês para adicioná-los à barra de comparação:',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: todasDatas.map((dtStr) {
                          final sel = _datasMarcadasComparacao.contains(dtStr);
                          return FilterChip(
                            label: Text(dtStr),
                            selected: sel,
                            selectedColor: const Color(0xFFDDD6FE),
                            onSelected: (v) {
                              setModal(() {
                                if (v) {
                                  _datasMarcadasComparacao.add(dtStr);
                                } else {
                                  _datasMarcadasComparacao.remove(dtStr);
                                }
                              });
                              setState(() {});
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setModal(() => _datasMarcadasComparacao.clear());
                    setState(() {});
                  },
                  child: const Text('Desmarcar Tudo', style: TextStyle(color: Colors.red)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Concluído'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildKPIsResponsivo(
    bool isWide,
    bool isPhoneLandscape,
    List<ResumoDiario> resumos,
    List<PassageiroDiario> passageiros,
    List<FaixaHorariaItem> fxHr,
    List<LinhaDiaria> linhas,
  ) {
    int prog = 0;
    int realiz = 0;
    double kmTotal = 0;
    double kmImprod = 0;
    int maxFrota = 0;

    if (_linhaSelecionada == null && resumos.isNotEmpty) {
      for (final r in resumos) {
        prog += r.viagensProg;
        realiz += r.viagensRealiz;
        kmTotal += r.kmTotal;
        kmImprod += r.kmImprod;
        if (r.veiculos > maxFrota) maxFrota = r.veiculos;
      }
    } else if (linhas.isNotEmpty) {
      for (final l in linhas) {
        prog += l.viagensProg;
        realiz += l.viagensRealiz;
        kmTotal += l.kmTotal;
      }
    } else {
      for (final f in fxHr) {
        realiz += f.viagens;
        prog += f.viagens;
        if (f.veiculos > maxFrota) maxFrota = f.veiculos;
      }
    }

    if (maxFrota == 0 && fxHr.isNotEmpty) {
      for (final f in fxHr) {
        if (f.veiculos > maxFrota) maxFrota = f.veiculos;
      }
    }

    int totalPass = 0;
    int totalCatraca = 0;
    int totalGratuitos = 0;
    for (final p in passageiros) {
      totalPass += p.totalPassageiros;
      totalCatraca += p.catraca;
      totalGratuitos += p.naoPagantes;
    }

    final fcvPercent = prog > 0 ? (realiz / prog) * 100 : 100.0;
    final ipk = kmTotal > 0 ? totalPass / kmTotal : 0.0;
    final percGratuidade = totalPass > 0 ? (totalGratuitos / totalPass) * 100 : 0.0;

    final cards = [
      _cardKpi(
        titulo: 'VIAGENS REALIZADAS',
        valor: _fmtInt(realiz),
        subtitulo: 'Prog: ${_fmtInt(prog)} (${realiz - prog >= 0 ? "+${realiz - prog}" : "${realiz - prog}"})',
        cor: const Color(0xFF0284C7),
        icone: Icons.route_rounded,
      ),
      _cardKpi(
        titulo: 'CUMPRIMENTO (FCV)',
        valor: '${fcvPercent.toStringAsFixed(2)}%',
        subtitulo: fcvPercent >= 98 ? '✓ Meta Atingida' : 'Abaixo de 98%',
        cor: fcvPercent >= 98 ? const Color(0xFF059669) : const Color(0xFFD97706),
        icone: Icons.verified_rounded,
      ),
      _cardKpi(
        titulo: 'QUILOMETRAGEM TOTAL',
        valor: '${_fmtMilhar(kmTotal)} km',
        subtitulo: 'Improd: ${kmImprod.toStringAsFixed(0)} km',
        cor: const Color(0xFF7C3AED),
        icone: Icons.speed_rounded,
      ),
      _cardKpi(
        titulo: 'TOTAL PASSAGEIROS',
        valor: _fmtInt(totalPass),
        subtitulo: 'Catraca: ${_fmtInt(totalCatraca)}',
        cor: const Color(0xFFEA580C),
        icone: Icons.groups_rounded,
      ),
      _cardKpi(
        titulo: 'TAXA DE GRATUIDADE',
        valor: '${percGratuidade.toStringAsFixed(1)}%',
        subtitulo: 'Gratuitos: ${_fmtInt(totalGratuitos)}',
        cor: const Color(0xFFE11D48),
        icone: Icons.volunteer_activism_rounded,
      ),
      _cardKpi(
        titulo: 'FROTA PICO / IPK',
        valor: '$maxFrota ônibus',
        subtitulo: 'IPK: ${ipk.toStringAsFixed(2)} pass/km',
        cor: const Color(0xFF0F172A),
        icone: Icons.directions_bus_rounded,
      ),
    ];

    if (isWide) {
      return Row(
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            Expanded(child: cards[i]),
            if (i < cards.length - 1) SizedBox(width: _modoTV ? 14 : 12),
          ]
        ],
      );
    }

    if (isPhoneLandscape) {
      // 3 cards em 2 linhas para celular em modo horizontal
      return Column(
        children: [
          Row(children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 8),
            Expanded(child: cards[1]),
            const SizedBox(width: 8),
            Expanded(child: cards[2]),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: cards[3]),
            const SizedBox(width: 8),
            Expanded(child: cards[4]),
            const SizedBox(width: 8),
            Expanded(child: cards[5]),
          ]),
        ],
      );
    }

    // Celular em modo vertical (retrato): 2 cards por linha
    return Column(
      children: [
        Row(children: [Expanded(child: cards[0]), const SizedBox(width: 10), Expanded(child: cards[1])]),
        const SizedBox(height: 10),
        Row(children: [Expanded(child: cards[2]), const SizedBox(width: 10), Expanded(child: cards[3])]),
        const SizedBox(height: 10),
        Row(children: [Expanded(child: cards[4]), const SizedBox(width: 10), Expanded(child: cards[5])]),
      ],
    );
  }

  Widget _cardKpi({
    required String titulo,
    required String valor,
    required String subtitulo,
    required Color cor,
    required IconData icone,
  }) {
    final isMobile = MediaQuery.of(context).size.width < 700 || MediaQuery.of(context).size.height < 550;

    return Container(
      padding: EdgeInsets.all(_modoTV ? 16 : (isMobile ? 10 : 12)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: cor, width: _modoTV ? 6 : 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(_modoTV ? 0.06 : 0.03),
            blurRadius: _modoTV ? 8 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                    fontSize: _modoTV ? 12 : (isMobile ? 9 : 10),
                    fontWeight: FontWeight.w800,
                    color: _modoTV ? const Color(0xFF334155) : Colors.blueGrey,
                    letterSpacing: _modoTV ? 0.4 : 0.0,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icone, size: _modoTV ? 20 : (isMobile ? 14 : 15), color: cor),
            ],
          ),
          SizedBox(height: _modoTV ? 8 : (isMobile ? 4 : 6)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              style: TextStyle(
                fontSize: _modoTV ? 32 : (isMobile ? 18 : 20),
                fontWeight: FontWeight.w900,
                color: cor,
                letterSpacing: -0.5,
              ),
            ),
          ),
          SizedBox(height: _modoTV ? 6 : 4),
          Text(
            subtitulo,
            style: TextStyle(
              fontSize: _modoTV ? 13 : (isMobile ? 10 : 11),
              fontWeight: _modoTV ? FontWeight.w700 : FontWeight.normal,
              color: _modoTV ? const Color(0xFF475569) : Colors.grey.shade600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildGraficoViagensEQuilometragem(
    List<ResumoDiario> resumos,
    List<FaixaHorariaItem> fxHr,
    List<LinhaDiaria> linhas,
  ) {
    final Map<String, double> mapProg = {};
    final Map<String, double> mapReal = {};

    if (_linhaSelecionada == null && resumos.isNotEmpty) {
      for (final r in resumos) {
        mapProg[r.data] = r.viagensProg.toDouble();
        mapReal[r.data] = r.viagensRealiz.toDouble();
      }
    } else if (linhas.isNotEmpty) {
      for (final l in linhas) {
        mapProg[l.data] = (mapProg[l.data] ?? 0) + l.viagensProg;
        mapReal[l.data] = (mapReal[l.data] ?? 0) + l.viagensRealiz;
      }
    } else {
      for (final f in fxHr) {
        mapReal[f.data] = (mapReal[f.data] ?? 0) + f.viagens;
        mapProg[f.data] = mapReal[f.data]!;
      }
    }

    final datas = mapReal.keys.toList();

    return _boxGrafico(
      titulo: _linhaSelecionada == null
          ? 'Execução Diária de Viagens (Prog. vs. Realiz.)'
          : 'Viagens Diárias Realizadas • Linha $_linhaSelecionada',
      subtitulo: 'Comparativo direto dos dias selecionados',
      legenda: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _bolinhaLegenda(const Color(0xFFCBD5E1), 'Prog.'),
          const SizedBox(width: 8),
          _bolinhaLegenda(const Color(0xFF0284C7), 'Realiz.'),
          const SizedBox(width: 12),
          _botaoAlternarAjuste(),
        ],
      ),
      child: datas.isEmpty
          ? const Center(child: Text('Sem dados para os dias selecionados.'))
          : _barChartDuplo(
              controller: _scrollViagens,
              labels: datas.map(_fmtCurto).toList(),
              valoresA: datas.map((d) => mapProg[d] ?? 0).toList(),
              valoresB: datas.map((d) => mapReal[d] ?? 0).toList(),
              corA: const Color(0xFFCBD5E1),
              corB: const Color(0xFF0284C7),
            ),
    );
  }

  Widget _buildGraficoPassageiros(List<PassageiroDiario> passageiros) {
    final labels = passageiros.map((e) => _fmtCurto(e.data)).toList();
    final pagantes = passageiros.map((e) => (e.catraca + e.antecipados).toDouble()).toList();
    final gratuitos = passageiros.map((e) => e.naoPagantes.toDouble()).toList();

    return _boxGrafico(
      titulo: 'Passageiros por Dia (Pagantes vs. Gratuidade)',
      subtitulo: 'Evolução diária do sistema de bilhetagem',
      legenda: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _bolinhaLegenda(const Color(0xFF0284C7), 'Pagantes'),
          const SizedBox(width: 8),
          _bolinhaLegenda(const Color(0xFFF97316), 'Gratuidade'),
          const SizedBox(width: 12),
          _botaoAlternarAjuste(),
        ],
      ),
      child: passageiros.isEmpty
          ? const Center(child: Text('Sem dados de passageiros para este filtro.'))
          : _barChartDuplo(
              controller: _scrollPassageiros,
              labels: labels,
              valoresA: pagantes,
              valoresB: gratuitos,
              corA: const Color(0xFF0284C7),
              corB: const Color(0xFFF97316),
            ),
    );
  }

  Widget _botaoAlternarAjuste() {
    return InkWell(
      onTap: () {
        setState(() => _verMesTodo = !_verMesTodo);
        if (_verMesTodo) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollViagens.hasClients) _scrollViagens.jumpTo(0);
            if (_scrollPassageiros.hasClients) _scrollPassageiros.jumpTo(0);
          });
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _verMesTodo ? const Color(0xFFE0F2FE) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _verMesTodo ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _verMesTodo ? Icons.fit_screen_rounded : Icons.view_week_rounded,
              size: 13,
              color: _verMesTodo ? const Color(0xFF0369A1) : Colors.blueGrey,
            ),
            const SizedBox(width: 4),
            Text(
              _verMesTodo ? 'Mês Todo' : 'Expandido',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: _verMesTodo ? const Color(0xFF0369A1) : Colors.blueGrey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGraficoFaixaHoraria(List<FaixaHorariaItem> fxHr) {
    final isMobile = MediaQuery.of(context).size.width < 700 || MediaQuery.of(context).size.height < 550;

    final Map<int, double> viagensPorHora = {};
    for (final item in fxHr) {
      viagensPorHora[item.hora] = (viagensPorHora[item.hora] ?? 0) + item.viagens;
    }

    final horas = viagensPorHora.keys.toList()..sort();
    final maxVal = viagensPorHora.values.isEmpty ? 10.0 : viagensPorHora.values.reduce((a, b) => a > b ? a : b);
    final interval = _calcularIntervalo(maxVal);

    final maxComMargem = maxVal * 1.15;
    final tetoTicks = ((maxComMargem / interval).ceil() * interval).toDouble();
    final maxY = tetoTicks + (interval * 0.12);

    return LayoutBuilder(builder: (context, constraints) {
      final leftReserved = isMobile ? 46.0 : (_modoTV ? 62.0 : 52.0);
      final rightReserved = isMobile ? 12.0 : (_modoTV ? 18.0 : 14.0);
      final areaUtil = (constraints.maxWidth - (leftReserved + rightReserved + 16)).clamp(150.0, 5000.0);
      final slotWidth = areaUtil / (horas.isEmpty ? 1 : horas.length);
      final rodWidth = (slotWidth * (isMobile ? 0.60 : 0.60)).clamp(3.5, _modoTV ? 16.0 : 13.0);

      return _boxGrafico(
        titulo: 'Viagens por Faixa Horária (0h às 23h)',
        subtitulo: _linhaSelecionada == null ? 'Soma de todas as linhas' : 'Operação da Linha $_linhaSelecionada',
        legenda: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _bolinhaLegenda(const Color(0xFFE11D48), 'Pico'),
            const SizedBox(width: 8),
            _bolinhaLegenda(const Color(0xFF475569), 'Normal'),
          ],
        ),
        child: horas.isEmpty
            ? const Center(child: Text('Sem dados de faixa horária.'))
            : Padding(
                padding: const EdgeInsets.only(top: 8.0, left: 4, right: 6),
                child: BarChart(
                  BarChartData(
                    maxY: maxY,
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(drawVerticalLine: false),
                    barTouchData: _tooltipPadrao(),
                    barGroups: horas.map((h) {
                      final pico = (h >= 6 && h <= 8) || (h >= 17 && h <= 19);
                      return BarChartGroupData(
                        x: h,
                        barRods: [
                          BarChartRodData(
                            toY: viagensPorHora[h]!,
                            color: pico ? const Color(0xFFE11D48) : const Color(0xFF475569),
                            width: rodWidth,
                            borderRadius: BorderRadius.circular(2.0),
                          ),
                        ],
                      );
                    }).toList(),
                    titlesData: FlTitlesData(
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: rightReserved,
                          getTitlesWidget: _emptyAxisTitle,
                        ),
                      ),
                      topTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: _modoTV ? 20 : 16,
                          getTitlesWidget: _emptyAxisTitle,
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: interval,
                          reservedSize: leftReserved,
                          getTitlesWidget: (v, m) {
                            if (v > tetoTicks + 0.001) return const SizedBox.shrink();
                            return SideTitleWidget(
                              meta: m,
                              space: isMobile ? 3 : 6,
                              child: Text(
                                _fmtMilhar(v),
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  fontSize: isMobile ? 9 : (_modoTV ? 12 : 10),
                                  color: _modoTV ? const Color(0xFF334155) : Colors.blueGrey,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: isMobile ? 26 : (_modoTV ? 32 : 26),
                          getTitlesWidget: (v, m) {
                            final h = v.toInt();
                            if (isMobile && h % 4 != 0) return const SizedBox.shrink();
                            if (!isMobile && h % 2 != 0 && horas.length > 12) return const SizedBox.shrink();

                            return SideTitleWidget(
                              meta: m,
                              space: 4,
                              child: Text(
                                '${h}h',
                                style: TextStyle(
                                  fontSize: isMobile ? 10 : (_modoTV ? 12 : 10),
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      );
    });
  }

  Widget _buildGraficoTurnosERanking(
    List<FcvDiario> fcv,
    List<FaixaHorariaItem> fxHr, [
    List<ResumoDiario>? resumos,
  ]) {
    final isMobile = MediaQuery.of(context).size.width < 700;

    int manhaP = 0, manhaR = 0, tardeP = 0, tardeR = 0, noiteP = 0, noiteR = 0;
    for (final item in fcv) {
      manhaP += item.manhaProg;
      manhaR += item.manhaRealiz;
      tardeP += item.tardeProg;
      tardeR += item.tardeRealiz;
      noiteP += item.noiteProg;
      noiteR += item.noiteRealiz;
    }

    if (manhaR == 0 && tardeR == 0 && noiteR == 0 && fxHr.isNotEmpty) {
      for (final item in fxHr) {
        if (item.hora >= 5 && item.hora < 12) {
          manhaR += item.viagens;
        } else if (item.hora >= 12 && item.hora < 18) {
          tardeR += item.viagens;
        } else {
          noiteR += item.viagens;
        }
      }

      int totalProg = 0;
      int totalReal = 0;
      if (resumos != null) {
        for (final r in resumos) {
          totalProg += r.viagensProg;
          totalReal += r.viagensRealiz;
        }
      }
      final ratio = totalProg > 0 ? (totalReal / totalProg) : 0.9984;
      manhaP = (manhaR / ratio).round();
      tardeP = (tardeR / ratio).round();
      noiteP = (noiteR / ratio).round();
    }

    final Map<String, int> viagensPorLinha = {};
    for (final f in fxHr) {
      viagensPorLinha[f.linha] = (viagensPorLinha[f.linha] ?? 0) + f.viagens;
    }
    final topLinhas = viagensPorLinha.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final turnosWidget = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _barraProgressoTurno('Manhã', manhaR, manhaP, const Color(0xFFF59E0B)),
        SizedBox(height: _modoTV ? 18 : 14),
        _barraProgressoTurno('Tarde', tardeR, tardeP, const Color(0xFFEA580C)),
        SizedBox(height: _modoTV ? 18 : 14),
        _barraProgressoTurno('Noite', noiteR, noiteP, const Color(0xFF312E81)),
      ],
    );

    final rankingWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Top Linhas (Partidas)',
          style: TextStyle(
            fontSize: _modoTV ? 14 : 11,
            fontWeight: FontWeight.w800,
            color: _modoTV ? const Color(0xFF334155) : Colors.blueGrey,
          ),
        ),
        SizedBox(height: _modoTV ? 10 : 8),
        if (topLinhas.isEmpty)
          const Center(child: Text('Sem dados'))
        else
          ...topLinhas.take(5).map((item) {
            final maxLinha = topLinhas.first.value;
            final ratio = maxLinha > 0 ? item.value / maxLinha : 0.0;
            return Padding(
              padding: EdgeInsets.only(bottom: _modoTV ? 10.0 : 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Linha ${item.key}',
                        style: TextStyle(fontSize: _modoTV ? 14 : 11, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${item.value} viag.',
                        style: TextStyle(
                          fontSize: _modoTV ? 13 : 10,
                          color: _modoTV ? const Color(0xFF475569) : Colors.blueGrey,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: _modoTV ? 10 : 6,
                      backgroundColor: const Color(0xFFE2E8F0),
                      color: const Color(0xFF0284C7),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );

    return _boxGrafico(
      titulo: 'Turnos (FCV) & Linhas Mais Ativas',
      subtitulo: 'Cumprimento Manhã/Tarde/Noite + Top Linhas',
      height: isMobile ? 480 : (_modoTV ? 370 : 310),
      child: isMobile
          ? Column(
              children: [
                turnosWidget,
                const Divider(height: 28),
                rankingWidget,
              ],
            )
          : Row(
              children: [
                Expanded(flex: 5, child: turnosWidget),
                const VerticalDivider(width: 24),
                Expanded(flex: 5, child: rankingWidget),
              ],
            ),
    );
  }

  Widget _barraProgressoTurno(String turno, int realiz, int prog, Color cor) {
    final isMobile = MediaQuery.of(context).size.width < 700 || MediaQuery.of(context).size.height < 550;
    final perc = prog > 0 ? (realiz / prog) * 100 : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(turno, style: TextStyle(fontWeight: FontWeight.bold, fontSize: _modoTV ? 15 : (isMobile ? 12 : 12))),
            Text('${perc.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: _modoTV ? 15 : (isMobile ? 12 : 11),
                  color: cor,
                )),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (perc / 100).clamp(0.0, 1.0),
            minHeight: _modoTV ? 16 : 10,
            backgroundColor: const Color(0xFFE2E8F0),
            color: cor,
          ),
        ),
      ],
    );
  }

  Widget _barChartDuplo({
    required ScrollController controller,
    required List<String> labels,
    required List<double> valoresA,
    required List<double> valoresB,
    required Color corA,
    required Color corB,
  }) {
    final isMobile = MediaQuery.of(context).size.width < 700 || MediaQuery.of(context).size.height < 550;

    double maxVal = 10;
    for (final v in [...valoresA, ...valoresB]) {
      if (v > maxVal) maxVal = v;
    }
    final interval = _calcularIntervalo(maxVal);

    final maxComMargem = maxVal * 1.15;
    final tetoTicks = ((maxComMargem / interval).ceil() * interval).toDouble();
    final maxY = tetoTicks + (interval * 0.12);

    return LayoutBuilder(
      builder: (context, constraints) {
        final larguraMin = constraints.maxWidth;
        final leftReserved = isMobile ? 46.0 : (_modoTV ? 62.0 : 52.0);
        final rightReserved = isMobile ? 12.0 : (_modoTV ? 18.0 : 14.0);

        if (_verMesTodo && controller.hasClients && controller.offset != 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (controller.hasClients) controller.jumpTo(0);
          });
        }

        double larguraCalculada;
        double rodWidth;
        double barsSpace;

        if (_verMesTodo) {
          larguraCalculada = larguraMin;
          final areaUtil = (larguraMin - (leftReserved + rightReserved + 16)).clamp(150.0, 5000.0);
          final espacoPorItem = areaUtil / (labels.isEmpty ? 1 : labels.length);
          rodWidth = (espacoPorItem * 0.30).clamp(2.5, 14.0);
          barsSpace = (espacoPorItem * 0.08).clamp(1.0, 4.0);
        } else {
          larguraCalculada = (labels.length * (isMobile ? 48.0 : (_modoTV ? 62.0 : 54.0)) + 60.0)
              .clamp(larguraMin, 4000.0);
          rodWidth = isMobile ? 10.0 : (_modoTV ? 18.0 : 13.0);
          barsSpace = isMobile ? 2.5 : 4.0;
        }

        // Cálculo dinâmico de passo para as datas nunca encavalarem em nenhuma resolução
        final larguraAreaLabels = larguraCalculada - (leftReserved + rightReserved + 16);
        final maxLabelsQueCabem = (larguraAreaLabels / (isMobile ? 38.0 : 52.0)).floor().clamp(2, 35);
        final stepDatas = (labels.length / maxLabelsQueCabem).ceil().clamp(1, 15);

        final chartWidget = BarChart(
          BarChartData(
            maxY: maxY,
            borderData: FlBorderData(show: false),
            gridData: const FlGridData(drawVerticalLine: false),
            barTouchData: _tooltipPadrao(),
            barGroups: List.generate(labels.length, (i) {
              return BarChartGroupData(
                x: i,
                barsSpace: barsSpace,
                barRods: [
                  BarChartRodData(
                    toY: valoresA[i],
                    color: corA,
                    width: rodWidth,
                    borderRadius: BorderRadius.circular(2.0),
                  ),
                  BarChartRodData(
                    toY: valoresB[i],
                    color: corB,
                    width: rodWidth,
                    borderRadius: BorderRadius.circular(2.0),
                  ),
                ],
              );
            }),
            titlesData: FlTitlesData(
              topTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: _modoTV ? 20 : 16,
                  getTitlesWidget: _emptyAxisTitle,
                ),
              ),
              rightTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: rightReserved,
                  getTitlesWidget: _emptyAxisTitle,
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: interval,
                  reservedSize: leftReserved,
                  getTitlesWidget: (v, m) {
                    if (v > tetoTicks + 0.001) return const SizedBox.shrink();
                    return SideTitleWidget(
                      meta: m,
                      space: isMobile ? 3 : 6,
                      child: Text(
                        _fmtMilhar(v),
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: isMobile ? 9 : (_modoTV ? 12 : 10),
                          color: _modoTV ? const Color(0xFF334155) : Colors.blueGrey,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: isMobile ? 26 : (_modoTV ? 32 : 26),
                  getTitlesWidget: (v, m) {
                    final idx = v.toInt();
                    if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();

                    // Evita encavalar mostrando as datas proporcionalmente ao espaço disponível
                    if (stepDatas > 1 && idx % stepDatas != 0 && idx != labels.length - 1) {
                      return const SizedBox.shrink();
                    }

                    return SideTitleWidget(
                      meta: m,
                      space: 4,
                      child: Text(
                        labels[idx],
                        style: TextStyle(
                          fontSize: isMobile ? 9 : (_modoTV ? 12 : 10),
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );

        if (_verMesTodo) {
          return Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 4, right: 6),
            child: chartWidget,
          );
        }

        return Listener(
          onPointerSignal: (pointerSignal) {
            if (pointerSignal is PointerScrollEvent) {
              final delta = pointerSignal.scrollDelta.dy != 0
                  ? pointerSignal.scrollDelta.dy
                  : pointerSignal.scrollDelta.dx;
              final novoOffset = (controller.offset + delta).clamp(
                0.0,
                controller.position.maxScrollExtent,
              );
              controller.jumpTo(novoOffset);
            }
          },
          child: Scrollbar(
            controller: controller,
            thumbVisibility: larguraCalculada > larguraMin,
            interactive: true,
            thickness: 5,
            radius: const Radius.circular(3),
            // Padding na base impede que a barra de rolagem cubra os números e datas
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 6, right: 12),
                child: SizedBox(
                  width: larguraCalculada,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: chartWidget,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  BarTouchData _tooltipPadrao() {
    final isMobile = MediaQuery.of(context).size.width < 700 || MediaQuery.of(context).size.height < 550;

    return BarTouchData(
      touchTooltipData: BarTouchTooltipData(
        fitInsideHorizontally: true,
        fitInsideVertically: true,
        getTooltipColor: (_) => const Color(0xFF0F172A),
        tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        getTooltipItem: (group, groupIndex, rod, rodIndex) {
          return BarTooltipItem(
            _fmtInt(rod.toY.round()),
            TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: _modoTV ? 14 : (isMobile ? 11 : 12),
            ),
          );
        },
      ),
    );
  }

  Widget _boxGrafico({
    required String titulo,
    required String subtitulo,
    Widget? legenda,
    required Widget child,
    double? height,
  }) {
    final isMobile = MediaQuery.of(context).size.width < 700 || MediaQuery.of(context).size.height < 550;

    return Container(
      height: height ?? (_modoTV ? 370 : (isMobile ? 330 : 310)),
      padding: EdgeInsets.all(_modoTV ? 16 : (isMobile ? 12 : 14)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(_modoTV ? 0.04 : 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile) ...[
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitulo,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.blueGrey,
              ),
            ),
            if (legenda != null) ...[
              const SizedBox(height: 8),
              legenda,
            ],
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TextStyle(
                          fontSize: _modoTV ? 16 : 13,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitulo,
                        style: TextStyle(
                          fontSize: _modoTV ? 13 : 11,
                          color: _modoTV ? const Color(0xFF475569) : Colors.blueGrey,
                          fontWeight: _modoTV ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                if (legenda != null) legenda,
              ],
            ),
          ],
          SizedBox(height: _modoTV ? 16 : (isMobile ? 8 : 12)),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _bolinhaLegenda(Color cor, String texto) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _modoTV ? 12 : 10,
          height: _modoTV ? 12 : 10,
          decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 5),
        Text(
          texto,
          style: TextStyle(
            fontSize: _modoTV ? 12 : 10,
            fontWeight: FontWeight.w700,
            color: _modoTV ? const Color(0xFF334155) : Colors.blueGrey,
          ),
        ),
      ],
    );
  }

  Widget _buildTabelaResumo(List<ResumoDiario> resumos, List<PassageiroDiario> passageiros) {
    final isMobile = MediaQuery.of(context).size.width < 700 || MediaQuery.of(context).size.height < 550;
    final mapPass = {for (var p in passageiros) p.data: p};

    return Container(
      padding: EdgeInsets.all(_modoTV ? 16 : (isMobile ? 12 : 14)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Espelho Diário Consolidado',
                style: TextStyle(
                  fontSize: _modoTV ? 16 : 13,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              Text(
                '${resumos.length} reg.',
                style: TextStyle(
                  fontSize: _modoTV ? 13 : 11,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: _modoTV ? 14 : 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              dataRowMinHeight: _modoTV ? 46 : 38,
              dataRowMaxHeight: _modoTV ? 54 : 44,
              headingRowHeight: _modoTV ? 48 : 42,
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
              columns: [
                _colunaHeader('Data'),
                _colunaHeader('Dia da Semana'),
                _colunaHeader('Frota'),
                _colunaHeader('Viagens Prog.'),
                _colunaHeader('Viagens Realiz.'),
                _colunaHeader('Dif.'),
                _colunaHeader('KM Total'),
                _colunaHeader('Catraca'),
                _colunaHeader('Gratuitos'),
                _colunaHeader('Total Passageiros'),
              ],
              rows: resumos.map((r) {
                final p = mapPass[r.data];
                final cellStyle = TextStyle(
                  fontSize: _modoTV ? 13 : 12,
                  fontWeight: _modoTV ? FontWeight.w600 : FontWeight.normal,
                );

                return DataRow(
                  cells: [
                    DataCell(Text(r.data, style: cellStyle.copyWith(fontWeight: FontWeight.w700))),
                    DataCell(Text(_nomesLongoDia[r.weekday] ?? '', style: cellStyle)),
                    DataCell(Text('${r.veiculos} veíc.', style: cellStyle)),
                    DataCell(Text(_fmtInt(r.viagensProg), style: cellStyle)),
                    DataCell(Text(_fmtInt(r.viagensRealiz), style: cellStyle)),
                    DataCell(Text(
                      r.difViagens == 0 ? '0' : '-${r.difViagens}',
                      style: TextStyle(
                        fontSize: _modoTV ? 13 : 12,
                        color: r.difViagens == 0 ? Colors.green.shade700 : Colors.red.shade700,
                        fontWeight: FontWeight.w800,
                      ),
                    )),
                    DataCell(Text('${r.kmTotal.toStringAsFixed(1)} km', style: cellStyle)),
                    DataCell(Text(p != null ? _fmtInt(p.catraca) : '-', style: cellStyle)),
                    DataCell(Text(p != null ? _fmtInt(p.naoPagantes) : '-', style: cellStyle)),
                    DataCell(Text(
                      p != null ? _fmtInt(p.totalPassageiros) : '-',
                      style: cellStyle.copyWith(fontWeight: FontWeight.w800),
                    )),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  DataColumn _colunaHeader(String rotulo) {
    return DataColumn(
      label: Text(
        rotulo,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: _modoTV ? 13 : 12,
          color: const Color(0xFF1E293B),
        ),
      ),
    );
  }

  static double _calcularIntervalo(double max) {
    if (max <= 10) return 2;
    if (max <= 50) return 10;
    if (max <= 200) return 50;
    if (max <= 500) return 100;
    if (max <= 1500) return 300;
    if (max <= 5000) return 1000;
    if (max <= 25000) return 5000;
    if (max <= 60000) return 10000;
    return (max / 4).ceilToDouble();
  }

  static String _fmtMilhar(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toInt().toString();
  }

  static String _fmtInt(int v) {
    final s = v.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}