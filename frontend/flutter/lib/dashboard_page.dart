import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'folder_scanner_io.dart' if (dart.library.html) 'folder_scanner_web.dart';
import 'local_data_loader.dart';
import 'login_page.dart';
import 'services/api_service.dart';
import 'utils/export_service.dart';

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
    final discrepanciasAntes = _dataset.discrepanciasDetectadas.length;
    for (int i = 0; i < arquivos.length; i++) {
      final arq = arquivos[i];
      if (mounted) {
        setState(() {
          _statusUpload = 'Salvando no MongoDB (${i + 1}/${arquivos.length})...';
        });
      }
      final ok = await _api.enviarHtmlParaBanco(
        arq.nome,
        arq.bytes,
        datasetParaAlertas: _dataset,
      );
      if (ok) salvos++;
    }

    // Sincroniza com os dados consolidados do MongoDB para integrar todos os tipos de relatórios
    if (salvos > 0) {
      final datasetDoBanco = await _api.carregarDatasetDoBanco();
      if (datasetDoBanco != null && !datasetDoBanco.isEmpty) {
        _mesclarDatasets(_dataset, datasetDoBanco);
        _aplicarDatasetCarregado(_dataset);
      }
    }

    if (mounted) {
      final novasDiscrepancias = _dataset.discrepanciasDetectadas.length - discrepanciasAntes;
      setState(() {
        _statusUpload = null;
        if (novasDiscrepancias > 0) _alertasExpandidos = true;
        if (_origemCarregada != null && !_origemCarregada!.contains('(MongoDB)')) {
          _origemCarregada = '$_origemCarregada (MongoDB)';
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _dataset.discrepanciasDetectadas.isNotEmpty
                ? '⚠ $salvos relatórios sincronizados. ${_dataset.discrepanciasDetectadas.length} discrepância(s) detectada(s) na consolidação!'
                : '✓ $salvos relatórios processados e sincronizados com o MongoDB!',
          ),
          backgroundColor:
              _dataset.discrepanciasDetectadas.isNotEmpty ? const Color(0xFFDC2626) : const Color(0xFF059669),
        ),
      );
    }
  }

  void _mesclarDatasets(SemobDataset base, SemobDataset novos) {
    for (final r in novos.resumos) {
      final idx = base.resumos.indexWhere((e) => e.data == r.data && e.periodicidade == r.periodicidade);
      if (idx < 0) {
        base.resumos.add(r);
      } else if (base.resumos[idx].calculadoViaDiario && !r.calculadoViaDiario) {
        base.resumos[idx] = r;
      }
    }
    for (final p in novos.passageiros) {
      final idx = base.passageiros.indexWhere((e) => e.data == p.data && e.periodicidade == p.periodicidade);
      if (idx < 0) {
        base.passageiros.add(p);
      } else if (base.passageiros[idx].calculadoViaDiario && !p.calculadoViaDiario) {
        base.passageiros[idx] = p;
      }
    }
    for (final f in novos.fcv) {
      final idx = base.fcv.indexWhere((e) => e.data == f.data && e.periodicidade == f.periodicidade);
      if (idx < 0) {
        base.fcv.add(f);
      } else if (base.fcv[idx].calculadoViaDiario && !f.calculadoViaDiario) {
        base.fcv[idx] = f;
      }
    }
    for (final fh in novos.faixasHorarias) {
      if (!base.faixasHorarias.any((e) =>
          e.data == fh.data && e.linha == fh.linha && e.hora == fh.hora && e.periodicidade == fh.periodicidade)) {
        base.faixasHorarias.add(fh);
      }
    }
    for (final l in novos.linhas) {
      if (!base.linhas.any((e) => e.data == l.data && e.linha == l.linha && e.periodicidade == l.periodicidade)) {
        base.linhas.add(l);
      }
    }
    for (final a in novos.arquivosHtmlCarregados) {
      if (!base.arquivosHtmlCarregados.any((e) => e.nome.toLowerCase() == a.nome.toLowerCase())) {
        base.arquivosHtmlCarregados.add(a);
      }
    }
    for (final d in novos.discrepanciasDetectadas) {
      if (!base.discrepanciasDetectadas.any((e) => e.data == d.data && e.descricao == d.descricao)) {
        base.discrepanciasDetectadas.add(d);
      }
    }
  }

  /// Abre o seletor nativo de pastas no Windows, macOS, Linux, iOS e Android.
  /// Na Web (Chrome/Edge), abre diretamente o seletor de múltiplos arquivos com dica de seleção total.
  Future<void> _selecionarPastaUnificada() async {
    if (kIsWeb) {
      await _selecionarMultiplosArquivos();
      return;
    }

    try {
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
        dialogTitle: 'Selecione a pasta com os relatórios HTML da SEMOB',
      );
      if (path == null) return;

      final nomeCurto = LocalDataLoader.extrairNomeCurtoPasta(path);

      setState(() {
        _carregando = true;
        _origemCarregada = nomeCurto;
        _statusUpload = 'Lendo e escaneando arquivos da pasta...';
      });

      final ds = await LocalDataLoader.carregarPasta(
        path,
        datasetExistente: _dataset.isEmpty ? null : _dataset,
      );

      if (ds.arquivosHtmlCarregados.isEmpty) {
        if (mounted) {
          setState(() {
            _carregando = false;
            _statusUpload = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nenhum arquivo .HTML ou .HTM encontrado na pasta selecionada.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (ds.discrepanciasDetectadas.isNotEmpty) _alertasExpandidos = true;
      _aplicarDatasetCarregado(ds);

      await _enviarArquivosParaOBanco(ds.arquivosHtmlCarregados);
    } catch (e) {
      debugPrint('Falha ao processar pasta selecionada: $e');
      if (mounted) {
        setState(() {
          _carregando = false;
          _statusUpload = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao abrir pasta: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  /// Seleção direta de múltiplos arquivos .HTML (Funciona em todas as 6 plataformas)
  Future<void> _selecionarMultiplosArquivos() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['html', 'htm'],
        dialogTitle: 'Selecione os arquivos HTML da SEMOB (pressione Ctrl+A para selecionar todos)',
      );

      if (result.isEmpty) return;

      final nomesNovos = result.map((f) => f.name.toLowerCase()).toSet();

      setState(() {
        _carregando = true;
        _origemCarregada = result.length == 1
            ? result.first.name
            : '${_dataset.arquivosHtmlCarregados.length + result.length} arq.';
        _statusUpload = 'Processando ${result.length} arquivo(s)...';
      });

      final ds = await LocalDataLoader.carregarArquivosSelecionados(
        result,
        datasetExistente: _dataset.isEmpty ? null : _dataset,
      );
      if (ds.discrepanciasDetectadas.isNotEmpty) _alertasExpandidos = true;
      _aplicarDatasetCarregado(ds);

      final apenasNovos = ds.arquivosHtmlCarregados
          .where((a) => nomesNovos.contains(a.nome.toLowerCase()))
          .toList();
      await _enviarArquivosParaOBanco(apenasNovos);
    } catch (e) {
      debugPrint('Erro ao selecionar múltiplos arquivos: $e');
      if (mounted) {
        setState(() {
          _carregando = false;
          _statusUpload = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar arquivos selecionados: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
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

    if (!mounted) return;
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
        ds.fcv.any((e) => e.mesAno == mesAlvo && e.periodicidade == preferida) ||
        ds.faixasHorarias.any((e) => e.mesAno == mesAlvo && e.periodicidade == preferida) ||
        ds.linhas.any((e) => e.mesAno == mesAlvo && e.periodicidade == preferida);

    if (temPreferida) return preferida;

    final outra = preferida == 'Mensal' ? 'Quinzenal' : 'Mensal';
    final temOutra = ds.resumos.any((e) => e.mesAno == mesAlvo && e.periodicidade == outra) ||
        ds.passageiros.any((e) => e.mesAno == mesAlvo && e.periodicidade == outra) ||
        ds.fcv.any((e) => e.mesAno == mesAlvo && e.periodicidade == outra) ||
        ds.faixasHorarias.any((e) => e.mesAno == mesAlvo && e.periodicidade == outra) ||
        ds.linhas.any((e) => e.mesAno == mesAlvo && e.periodicidade == outra);

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
      ..._dataset.fcv.map((e) => e.dateTime),
      ..._dataset.faixasHorarias.map((e) => e.dateTime),
      ..._dataset.linhas.map((e) => e.dateTime),
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
      ..._dataset.fcv
          .where((e) => e.mesAno == _mesSelecionado && e.periodicidade == _periodicidade)
          .map((e) => e.dateTime),
      ..._dataset.faixasHorarias
          .where((e) => e.mesAno == _mesSelecionado && e.periodicidade == _periodicidade)
          .map((e) => e.dateTime),
      ..._dataset.linhas
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

  static DateTime _parseStrToDate(String s) => LocalDataLoader.parseDataBR(s) ?? DateTime(2026);

  late final RelatorioIntegrationController relatorioController = RelatorioIntegrationController();

  @override
  void dispose() {
    relatorioController.dispose();
    super.dispose();
  }

  bool _gerandoRelatorio = false;
  RelatorioConsolidado? _ultimoRelatorioConsolidado;
  String? _ultimoRelatorioTexto;
  String? _erroRelatorio;

  bool get gerandoRelatorio => _gerandoRelatorio;
  RelatorioConsolidado? get ultimoRelatorioConsolidado => _ultimoRelatorioConsolidado;
  String? get ultimoRelatorioTexto => _ultimoRelatorioTexto;
  String? get erroRelatorio => _erroRelatorio;

  static String _fmtDataISO(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  ///Retorna os filtros ativos no estado do painel já convertidos para o contrato da API
  Map<String, String?> obterFiltrosAtivosParaApi({String agrupamento = 'diario'}) {
    DateTime? inicio = _dataInicio;
    DateTime? fim = _dataFim;

    if (_modoAtivo == ModoAnalise.compararDiasSemana && _datasMarcadasComparacao.isNotEmpty) {
      final datas = _datasMarcadasComparacao.map(_parseStrToDate).toList()..sort();
      inicio = datas.first;
      fim = datas.last;
    } else if (inicio == null || fim == null) {
      final globais = _todasAsDatasGlobal();
      if (globais.isNotEmpty) {
        inicio ??= globais.first;
        fim ??= globais.last;
      }
    }

    return {
      'agrupamento': agrupamento,
      'data_inicio': inicio != null ? _fmtDataISO(inicio) : null,
      'data_fim': fim != null ? _fmtDataISO(fim) : null,
      'linha': _linhaSelecionada,
    };
  }

  ///Ponto de acoplamento pronto para o botão de geração de relatório (onPressed: gerarRelatorioIntegrado).
  ///Envia os HTMLs carregados e solicita o relatório consolidado ao backend FastAPI
  Future<RelatorioConsolidado?> gerarRelatorioIntegrado({
    String agrupamento = 'diario',
    bool sincronizarArquivosLocais = true,
    double toleranciaDesvioKmPct = 15.0,
    double limiarFcv = 0.98,
    double limiarKmImprodPct = 10.0,
    bool exibirFeedbackSnackBar = true,
  }) async {
    if (_gerandoRelatorio) return _ultimoRelatorioConsolidado;

    final filtros = obterFiltrosAtivosParaApi(agrupamento: agrupamento);
    setState(() {
      _gerandoRelatorio = true;
      _erroRelatorio = null;
    });

    try {
      final relatorio = await LocalDataLoader.sincronizarEGerarRelatorio(
        dataset: _dataset,
        agrupamento: filtros['agrupamento'] ?? 'diario',
        dataInicio: filtros['data_inicio'],
        dataFim: filtros['data_fim'],
        linha: filtros['linha'],
        toleranciaDesvioKmPct: toleranciaDesvioKmPct,
        limiarFcv: limiarFcv,
        limiarKmImprodPct: limiarKmImprodPct,
        enviarArquivosEmMemoria: sincronizarArquivosLocais,
      );
      final resumoTexto = RelatorioApiService.formatarResumoRelatorio(relatorio);

      if (mounted) {
        setState(() {
          _gerandoRelatorio = false;
          _ultimoRelatorioConsolidado = relatorio;
          _ultimoRelatorioTexto = resumoTexto;
        });
        if (exibirFeedbackSnackBar) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Relatório consolidado gerado com sucesso (${relatorio.serieTemporal.totalPontos} períodos analisados).',
              ),
              backgroundColor: const Color(0xFF059669),
            ),
          );
        }
      }
      return relatorio;
    } catch (e) {
      final msgErro = e.toString();
      if (mounted) {
        setState(() {
          _gerandoRelatorio = false;
          _erroRelatorio = msgErro;
        });
        if (exibirFeedbackSnackBar) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msgErro),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
      return null;
    }
  }

  ///Gera o relatório consolidado via API e devolve diretamente o texto estruturado para exportação/exibição
  Future<String?> gerarTextoRelatorioConsolidado({
    String agrupamento = 'diario',
    bool sincronizarArquivosLocais = true,
  }) async {
    final relatorio = await gerarRelatorioIntegrado(
      agrupamento: agrupamento,
      sincronizarArquivosLocais: sincronizarArquivosLocais,
    );
    if (relatorio == null) return null;
    return _ultimoRelatorioTexto ?? RelatorioApiService.formatarResumoRelatorio(relatorio);
  }

  void _sairParaTelaDeLogin() {
    RelatorioApiService.limparSessao();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  String _obterDescricaoIntervaloFiltro() {
    if (_modoAtivo == ModoAnalise.extratoPeriodo) {
      if (_dataInicio != null && _dataFim != null) {
        return '${_fmtDataBR(_dataInicio!)} a ${_fmtDataBR(_dataFim!)} ($_presetPeriodo)';
      }
      return _presetPeriodo;
    } else {
      final nomeDia = _nomesLongoDia[_diaSemanaComparar] ?? 'Dia selecionado';
      return 'Comparação de $nomeDia (${_datasMarcadasComparacao.length} datas)';
    }
  }

  Future<void> _exportarRelatorioExecutivoPdf({
    required List<ResumoDiario> resumos,
    required List<PassageiroDiario> passageiros,
    required List<FcvDiario> fcvs,
    required List<FaixaHorariaItem> faixasHorarias,
    required List<LinhaDiaria> linhas,
    required List<AlertaOutlier> outliers,
  }) async {
    try {
      final alertasPdf = outliers
          .map((o) => AlertaExecutivoPdf(
                titulo: o.titulo,
                descricao: o.descricao,
                critico: o.critico,
              ))
          .toList();

      final bytes = await ExportService.gerarBytesRelatorioPdf(
        mesSelecionado: _mesSelecionado,
        periodicidade: _periodicidade,
        linhaSelecionada: _linhaSelecionada,
        intervaloTexto: _obterDescricaoIntervaloFiltro(),
        origemDados: _origemCarregada ?? 'Memória Local',
        resumos: resumos,
        passageiros: passageiros,
        fcv: fcvs,
        faixasHorarias: faixasHorarias,
        linhas: linhas,
        alertas: alertasPdf,
      );

      final nomeSugerido =
          'relatorio_executivo_semob_${_mesSelecionado.replaceAll('/', '_')}_${_periodicidade.toLowerCase()}.pdf';

      final caminhoSalvo = await FilePicker.saveFile(
        dialogTitle: 'Exportar Relatório Executivo SEMOB (PDF)',
        fileName: nomeSugerido,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        mimeType: 'application/pdf',
        bytes: bytes,
      );

      if (!kIsWeb && caminhoSalvo != null && caminhoSalvo.scheme == 'file') {
        await salvarBytesNoCaminho(caminhoSalvo.toFilePath(), bytes);
      }

      if (mounted && (kIsWeb || caminhoSalvo != null)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Relatório Executivo em PDF gerado e salvo com sucesso!'),
            backgroundColor: Color(0xFF059669),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar relatório PDF: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  List<AlertaOutlier> _calcularOutliers(List<ResumoDiario> resumos, List<PassageiroDiario> passageiros) {
    final alertas = <AlertaOutlier>[];

    // 1. Discrepâncias de consolidação entre cálculo via diários e HTMLs Mensal/Quinzenal anexados:
    for (final d in _dataset.discrepanciasDetectadas) {
      alertas.add(AlertaOutlier(
        titulo: 'Discrepância de Consolidação (${d.categoria} • ${d.data})',
        descricao: d.descricao,
        critico: true,
      ));
    }

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
        final desvio = mediaKm > 0 ? ((r.kmTotal - mediaKm) / mediaKm).abs() : 0.0;
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

  @override
  Widget build(BuildContext context) {
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
        toolbarHeight: 54,
        title: Row(
          children: [
            const Icon(Icons.directions_bus_filled_rounded, color: Color(0xFF38BDF8), size: 22),
            const SizedBox(width: 8),
            const Text(
              'SEMOB • Monitoramento',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _backendOnline ? const Color(0xFF065F46) : const Color(0xFF475569),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 7, color: _backendOnline ? const Color(0xFF34D399) : Colors.amberAccent),
                  const SizedBox(width: 5),
                  Text(
                    _backendOnline ? 'MongoDB Online' : 'Modo Local',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sincronizar com MongoDB',
            icon: const Icon(Icons.sync_rounded, color: Color(0xFF38BDF8), size: 20),
            onPressed: _carregando ? null : _inicializarDadosDoBanco,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 2.0),
            child: Tooltip(
              message: 'Ajusta fontes e contraste para leitura em telas de 32" ou à distância',
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: _modoTV ? const Color(0xFF0284C7) : Colors.transparent,
                  foregroundColor: Colors.white,
                  side: BorderSide(color: _modoTV ? const Color(0xFF38BDF8) : Colors.white30),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: () => setState(() => _modoTV = !_modoTV),
                icon: Icon(Icons.tv_rounded, size: 15, color: _modoTV ? Colors.white : const Color(0xFF38BDF8)),
                label: Text(
                  _modoTV ? 'Modo TV: ON' : 'Modo TV 32"',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            child: Tooltip(
              message: 'Exporta Relatório Executivo em PDF com síntese, indicadores e glossário para superiores',
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                ),
                onPressed: _dataset.isEmpty
                    ? null
                    : () => _exportarRelatorioExecutivoPdf(
                          resumos: resumosFiltrados,
                          passageiros: passageirosFiltrados,
                          fcvs: fcvFiltrados,
                          faixasHorarias: fxHrFiltrados,
                          linhas: linhasFiltradas,
                          outliers: outliersDetectados,
                        ),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                label: const Text('Exportar PDF', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            child: Tooltip(
              message: kIsWeb
                  ? 'Selecionar múltiplos arquivos da pasta (selecione todos com Ctrl+A)'
                  : 'Abre e escaneia recursivamente todos os relatórios HTML da pasta selecionada',
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: _carregando ? null : _selecionarPastaUnificada,
                icon: const Icon(Icons.folder_open_rounded, size: 16),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
                  child: Text(
                    _origemCarregada == null
                        ? (kIsWeb ? 'Carregar Pasta' : 'Abrir Pasta')
                        : _origemCarregada!,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF38BDF8)),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              onPressed: _carregando ? null : _selecionarMultiplosArquivos,
              icon: const Icon(Icons.file_present_rounded, size: 15, color: Color(0xFF38BDF8)),
              label: const Text('HTMLs', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
          IconButton(
            tooltip: 'Sair / Trocar Operador',
            icon: const Icon(Icons.logout_rounded, color: Colors.white70, size: 20),
            onPressed: _sairParaTelaDeLogin,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _dataset.isEmpty
              ? _buildEmptyState()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 850;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(14),
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
                                  Text(
                                    _statusUpload!,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8)),
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
    );
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
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                  onPressed: _selecionarPastaUnificada,
                  icon: const Icon(Icons.folder_open),
                  label: Text(kIsWeb ? 'Carregar Pasta (Lote)' : 'Selecionar Pasta'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey.shade700,
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
    if (alertas.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Operação Regular: Nenhum outlier crítico ou déficit de cumprimento detectado em SCS no recorte atual.',
                style: TextStyle(
                  fontSize: _modoTV ? 13 : 11,
                  fontWeight: FontWeight.w600,
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
      padding: const EdgeInsets.all(12),
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
              Icon(Icons.warning_amber_rounded, color: corBase, size: _modoTV ? 22 : 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ALERTAS DE IMPACTO NA MOBILIDADE (SÃO CAETANO DO SUL)',
                  style: TextStyle(
                    fontSize: _modoTV ? 13 : 11,
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: corBase,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${alertas.length} Ocorrências',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _alertasExpandidos ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 16,
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
              children: alertas.take(3).map((a) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: corBase.withOpacity(0.3)),
                  ),
                  child: Text(
                    '${a.titulo}: ${a.descricao}',
                    style: TextStyle(fontSize: _modoTV ? 12 : 11, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)),
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
                      Icon(Icons.arrow_right_rounded, color: corBase, size: 20),
                      const SizedBox(width: 4),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: _modoTV ? 13 : 11,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: Colors.blueGrey),
          const SizedBox(width: 5),
          Text('$label: ', style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w600)),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: valorSeguro,
              isDense: true,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: ativo ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: ativo ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 3)] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 14, color: ativo ? const Color(0xFF0284C7) : Colors.blueGrey),
            const SizedBox(width: 5),
            Text(
              titulo,
              style: TextStyle(
                fontSize: 12,
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

    // Fallback: se a frota estiver zerada nos resumos, busca o pico real nas faixas horárias
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

    final fcvPercent = prog > 0 ? (realiz / prog) * 100 : 0.0;
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
            if (i < cards.length - 1) const SizedBox(width: 12),
          ]
        ],
      );
    }

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
    return Container(
      padding: EdgeInsets.all(_modoTV ? 14 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: cor, width: _modoTV ? 5 : 4)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4)],
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
                    fontSize: _modoTV ? 11 : 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.blueGrey,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icone, size: _modoTV ? 17 : 15, color: cor),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              style: TextStyle(
                fontSize: _modoTV ? 24 : 18,
                fontWeight: FontWeight.w900,
                color: cor,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitulo,
            style: TextStyle(
              fontSize: _modoTV ? 12 : 11,
              fontWeight: _modoTV ? FontWeight.w600 : FontWeight.normal,
              color: Colors.grey.shade600,
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
        ],
      ),
      child: datas.isEmpty
          ? const Center(child: Text('Sem dados para os dias selecionados.'))
          : _barChartDuplo(
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
        ],
      ),
      child: passageiros.isEmpty
          ? const Center(child: Text('Sem dados de passageiros para este filtro.'))
          : _barChartDuplo(
              labels: labels,
              valoresA: pagantes,
              valoresB: gratuitos,
              corA: const Color(0xFF0284C7),
              corB: const Color(0xFFF97316),
            ),
    );
  }

  Widget _buildGraficoFaixaHoraria(List<FaixaHorariaItem> fxHr) {
    final Map<int, double> viagensPorHora = {};
    for (final item in fxHr) {
      viagensPorHora[item.hora] = (viagensPorHora[item.hora] ?? 0) + item.viagens;
    }

    final horas = viagensPorHora.keys.toList()..sort();
    final maxVal = viagensPorHora.values.isEmpty ? 10.0 : viagensPorHora.values.reduce((a, b) => a > b ? a : b);
    final interval = _calcularIntervalo(maxVal);
    final maxY = (((maxVal * 1.2) / interval).ceil() * interval).toDouble();

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
          : BarChart(
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
                        width: 12,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ],
                  );
                }).toList(),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: interval,
                      reservedSize: 44,
                      getTitlesWidget: (v, m) => Text(
                        _fmtMilhar(v),
                        style: TextStyle(fontSize: _modoTV ? 11 : 10, color: Colors.blueGrey, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (v, m) {
                        final h = v.toInt();
                        if (h % 2 != 0 && horas.length > 12) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${h}h',
                            style: TextStyle(fontSize: _modoTV ? 11 : 10, fontWeight: FontWeight.w700),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildGraficoTurnosERanking(
    List<FcvDiario> fcv,
    List<FaixaHorariaItem> fxHr,
    List<ResumoDiario> resumos,
  ) {
    int manhaP = 0, manhaR = 0, tardeP = 0, tardeR = 0, noiteP = 0, noiteR = 0;
    for (final item in fcv) {
      manhaP += item.manhaProg;
      manhaR += item.manhaRealiz;
      tardeP += item.tardeProg;
      tardeR += item.tardeRealiz;
      noiteP += item.noiteProg;
      noiteR += item.noiteRealiz;
    }

    // Se a coleção de FCV não contiver divisões de turnos, calcula a partir das faixas horárias reais:
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
      for (final r in resumos) {
        totalProg += r.viagensProg;
        totalReal += r.viagensRealiz;
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

    return _boxGrafico(
      titulo: 'Turnos (FCV) & Linhas Mais Ativas',
      subtitulo: 'Cumprimento Manhã/Tarde/Noite + Top Linhas',
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _barraProgressoTurno('Manhã', manhaR, manhaP, const Color(0xFFF59E0B)),
                const SizedBox(height: 14),
                _barraProgressoTurno('Tarde', tardeR, tardeP, const Color(0xFFEA580C)),
                const SizedBox(height: 14),
                _barraProgressoTurno('Noite', noiteR, noiteP, const Color(0xFF312E81)),
              ],
            ),
          ),
          const VerticalDivider(width: 24),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Top Linhas (Partidas)',
                  style: TextStyle(fontSize: _modoTV ? 12 : 11, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: topLinhas.isEmpty
                      ? const Center(child: Text('Sem dados'))
                      : ListView.builder(
                          itemCount: topLinhas.take(5).length,
                          itemBuilder: (ctx, i) {
                            final item = topLinhas[i];
                            final maxLinha = topLinhas.first.value;
                            final ratio = maxLinha > 0 ? item.value / maxLinha : 0.0;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Linha ${item.key}',
                                        style: TextStyle(fontSize: _modoTV ? 12 : 11, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        '${item.value} viag.',
                                        style: TextStyle(fontSize: _modoTV ? 11 : 10, color: Colors.blueGrey, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: ratio,
                                      minHeight: _modoTV ? 8 : 6,
                                      backgroundColor: const Color(0xFFE2E8F0),
                                      color: const Color(0xFF0284C7),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _barraProgressoTurno(String turno, int realiz, int prog, Color cor) {
    final perc = prog > 0 ? (realiz / prog) * 100 : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(turno, style: TextStyle(fontWeight: FontWeight.bold, fontSize: _modoTV ? 13 : 12)),
            Text('${perc.toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.bold, fontSize: _modoTV ? 12 : 11, color: cor)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (perc / 100).clamp(0.0, 1.0),
            minHeight: _modoTV ? 12 : 10,
            backgroundColor: const Color(0xFFE2E8F0),
            color: cor,
          ),
        ),
      ],
    );
  }

  Widget _barChartDuplo({
    required List<String> labels,
    required List<double> valoresA,
    required List<double> valoresB,
    required Color corA,
    required Color corB,
  }) {
    double maxVal = 10;
    for (final v in [...valoresA, ...valoresB]) {
      if (v > maxVal) maxVal = v;
    }
    final interval = _calcularIntervalo(maxVal);
    final maxY = (((maxVal * 1.22) / interval).ceil() * interval).toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final larguraMin = constraints.maxWidth;
        final larguraCalculada = (labels.length * 52.0).clamp(larguraMin, 3000.0);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: larguraCalculada,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(drawVerticalLine: false),
                barTouchData: _tooltipPadrao(),
                barGroups: List.generate(labels.length, (i) {
                  return BarChartGroupData(
                    x: i,
                    barsSpace: 4,
                    barRods: [
                      BarChartRodData(
                        toY: valoresA[i],
                        color: corA,
                        width: labels.length <= 7 ? 16 : 10,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      BarChartRodData(
                        toY: valoresB[i],
                        color: corB,
                        width: labels.length <= 7 ? 16 : 10,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ],
                  );
                }),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: interval,
                      reservedSize: 44,
                      getTitlesWidget: (v, m) => Text(
                        _fmtMilhar(v),
                        style: TextStyle(fontSize: _modoTV ? 11 : 10, color: Colors.blueGrey, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (v, m) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            labels[idx],
                            style: TextStyle(fontSize: _modoTV ? 11 : 10, fontWeight: FontWeight.w700),
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
      },
    );
  }

  BarTouchData _tooltipPadrao() {
    return BarTouchData(
      touchTooltipData: BarTouchTooltipData(
        fitInsideHorizontally: true,
        fitInsideVertically: true,
        getTooltipColor: (_) => const Color(0xFF0F172A),
        tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        getTooltipItem: (group, groupIndex, rod, rodIndex) {
          return BarTooltipItem(
            _fmtInt(rod.toY.round()),
            const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
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
  }) {
    return Container(
      height: _modoTV ? 320 : 300,
      padding: const EdgeInsets.all(14),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: _modoTV ? 14 : 13,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitulo, style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                  ],
                ),
              ),
              if (legenda != null) legenda,
            ],
          ),
          const SizedBox(height: 14),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _bolinhaLegenda(Color cor, String texto) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(texto, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.blueGrey)),
      ],
    );
  }

  Widget _buildTabelaResumo(List<ResumoDiario> resumos, List<PassageiroDiario> passageiros) {
    final mapPass = {for (var p in passageiros) p.data: p};

    return Container(
      padding: const EdgeInsets.all(14),
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
                'Espelho Diário Consolidado (Operação + Bilhetagem)',
                style: TextStyle(
                  fontSize: _modoTV ? 14 : 13,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              Text(
                '${resumos.length} registros',
                style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
              columns: const [
                DataColumn(label: Text('Data', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Dia da Semana', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Frota', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Viagens Prog.', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Viagens Realiz.', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Dif.', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('KM Total', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Catraca', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Gratuitos', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Total Passageiros', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: resumos.map((r) {
                final p = mapPass[r.data];
                return DataRow(
                  cells: [
                    DataCell(Text(r.data, style: const TextStyle(fontWeight: FontWeight.w600))),
                    DataCell(Text(_nomesLongoDia[r.weekday] ?? '')),
                    DataCell(Text('${r.veiculos} veíc.')),
                    DataCell(Text(_fmtInt(r.viagensProg))),
                    DataCell(Text(_fmtInt(r.viagensRealiz))),
                    DataCell(Text(
                      r.difViagens == 0 ? '0' : '-${r.difViagens}',
                      style: TextStyle(
                        color: r.difViagens == 0 ? Colors.green.shade700 : Colors.red.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    )),
                    DataCell(Text('${r.kmTotal.toStringAsFixed(1)} km')),
                    DataCell(Text(p != null ? _fmtInt(p.catraca) : '-')),
                    DataCell(Text(p != null ? _fmtInt(p.naoPagantes) : '-')),
                    DataCell(Text(
                      p != null ? _fmtInt(p.totalPassageiros) : '-',
                      style: const TextStyle(fontWeight: FontWeight.bold),
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