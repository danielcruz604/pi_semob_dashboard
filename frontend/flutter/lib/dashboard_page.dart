import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'cadastro_usuario_page.dart';
import 'folder_scanner_io.dart' if (dart.library.html) 'folder_scanner_web.dart';
import 'local_data_loader.dart';
import 'login_page.dart';
import 'services/api_service.dart';
import 'utils/export_service.dart';
import 'sessao_service.dart';

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
  bool _verMesTodo = true;

  final ScrollController _scrollViagens = ScrollController();
  final ScrollController _scrollPassageiros = ScrollController();
  late final RelatorioIntegrationController relatorioController = RelatorioIntegrationController();

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
    relatorioController.dispose();
    super.dispose();
  }

  Future<void> _inicializarDadosDoBanco() async {
    setState(() => _carregando = true);

    final online = await _api.verificarServidorOnline();
    _backendOnline = online;

    if (online) {
      final datasetDoBanco = await _api.carregarDatasetDoBanco();
      if (datasetDoBanco != null && !datasetDoBanco.isEmpty) {
        _origemCarregada = 'Importar Dados';
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

  Future<void> _selecionarPastaUnificada() async {
    if (kIsWeb) {
      try {
        final arquivosDaPasta = await LocalDataLoader.selecionarArquivosDaPastaWeb();
        if (arquivosDaPasta.isEmpty) return;

        final primeiroCaminho = arquivosDaPasta.first.caminho.replaceAll('\\', '/');
        final partesCaminho = primeiroCaminho.split('/').where((p) => p.isNotEmpty).toList();
        final nomePasta = partesCaminho.length > 1 ? partesCaminho.first : 'Pasta (${arquivosDaPasta.length} arq.)';

        setState(() {
          _carregando = true;
          _origemCarregada = nomePasta;
          _statusUpload = 'Processando ${arquivosDaPasta.length} arquivo(s) da pasta...';
        });

        final ds = LocalDataLoader.carregarListaArquivosLidos(
          arquivosDaPasta,
          datasetExistente: _dataset.isEmpty ? null : _dataset,
        );

        if (ds.discrepanciasDetectadas.isNotEmpty) _alertasExpandidos = true;
        _aplicarDatasetCarregado(ds);

        await _enviarArquivosParaOBanco(arquivosDaPasta);
      } catch (e) {
        debugPrint('Falha ao carregar pasta na Web: $e');
        if (mounted) {
          setState(() {
            _carregando = false;
            _statusUpload = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao carregar pasta: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
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
      final caminhosAntes = _dataset.arquivosHtmlCarregados.map((a) => a.caminho.toLowerCase()).toSet();

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

      final novosDaPasta = ds.arquivosHtmlCarregados
          .where((a) => !caminhosAntes.contains(a.caminho.toLowerCase()))
          .toList();
      await _enviarArquivosParaOBanco(
        novosDaPasta.isNotEmpty ? novosDaPasta : ds.arquivosHtmlCarregados,
      );
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

  String? get _nomeUsuarioLogado {
    final nome = RelatorioApiService.usuarioLogado?['nome']?.toString().trim();
    return (nome == null || nome.isEmpty) ? null : nome;
  }

  bool get _usuarioEhAdmin {
    final papel = (RelatorioApiService.usuarioLogado?['papel'] ?? '').toString().trim().toLowerCase();
    return papel == 'gestor' || papel == 'admin';
  }

  void _abrirTelaCadastroUsuario() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CadastroUsuarioPage()),
    );
  }

  Future<void> _sairParaTelaDeLogin() async {
    await SessaoService.sair();
    if (!mounted) return;
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

  static Widget _emptyAxisTitle(double value, TitleMeta meta) => const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;

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
        actions: _construirAcoesAppBar(
          isTelaLarga: isTelaLarga,
          resumos: resumosFiltrados,
          passageiros: passageirosFiltrados,
          fcvs: fcvFiltrados,
          faixasHorarias: fxHrFiltrados,
          linhas: linhasFiltradas,
          outliers: outliersDetectados,
        ),
      ),
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
                      final isWide = constraints.maxWidth >= 950 && !isPhoneLandscape;
                      return SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          _modoTV ? 18 : (isMobile ? 12 : 14),
                          _modoTV ? 18 : (isMobile ? 10 : 14),
                          _modoTV ? 18 : (isMobile ? 12 : 14),
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

  List<Widget> _construirAcoesAppBar({
    required bool isTelaLarga,
    required List<ResumoDiario> resumos,
    required List<PassageiroDiario> passageiros,
    required List<FcvDiario> fcvs,
    required List<FaixaHorariaItem> faixasHorarias,
    required List<LinhaDiaria> linhas,
    required List<AlertaOutlier> outliers,
  }) {
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
            if (val == 'pdf' && !_dataset.isEmpty) {
              _exportarRelatorioExecutivoPdf(
                resumos: resumos,
                passageiros: passageiros,
                fcvs: fcvs,
                faixasHorarias: faixasHorarias,
                linhas: linhas,
                outliers: outliers,
              );
            }
            if (val == 'pasta') _selecionarPastaUnificada();
            if (val == 'htmls') _selecionarMultiplosArquivos();
            if (val == 'cadastro') _abrirTelaCadastroUsuario();
            if (val == 'sair') _sairParaTelaDeLogin();
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'pdf',
              enabled: !_dataset.isEmpty,
              child: const Row(
                children: [
                  Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF059669), size: 18),
                  SizedBox(width: 8),
                  Text('Exportar PDF'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'pasta',
              child: Row(
                children: [
                  Icon(Icons.folder_open_rounded, color: Color(0xFF0284C7), size: 18),
                  SizedBox(width: 8),
                  Text('Importar Pasta Completa'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'htmls',
              child: Row(
                children: [
                  Icon(Icons.file_present_rounded, color: Color(0xFF38BDF8), size: 18),
                  SizedBox(width: 8),
                  Text('Selecionar Arquivos .HTML'),
                ],
              ),
            ),
            if (_usuarioEhAdmin) ...[
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'cadastro',
                child: Row(
                  children: [
                    Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF7C3AED), size: 18),
                    SizedBox(width: 8),
                    Text('Gerenciar Usuários'),
                  ],
                ),
              ),
            ],
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
          message: 'Ajusta fontes e contraste para leitura em telas menores',
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
        child: Tooltip(
          message: 'Exporta Relatório Executivo em PDF com síntese, indicadores e glossário para superiores',
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(horizontal: _modoTV ? 14 : 11),
            ),
            onPressed: _dataset.isEmpty
                ? null
                : () => _exportarRelatorioExecutivoPdf(
                      resumos: resumos,
                      passageiros: passageiros,
                      fcvs: fcvs,
                      faixasHorarias: faixasHorarias,
                      linhas: linhas,
                      outliers: outliers,
                    ),
            icon: Icon(Icons.picture_as_pdf_rounded, size: _modoTV ? 18 : 16),
            label: Text('Exportar PDF', style: TextStyle(fontSize: _modoTV ? 13 : 12, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
      // Botão unificado de importação de relatórios HTML (Pasta completa ou arquivos soltos)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: PopupMenuButton<String>(
          enabled: !_carregando,
          tooltip: 'Importar relatórios HTML por pasta completa ou arquivos individuais',
          onSelected: (opcao) {
            if (opcao == 'pasta') _selecionarPastaUnificada();
            if (opcao == 'arquivos') _selecionarMultiplosArquivos();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'pasta',
              child: Row(
                children: [
                  Icon(Icons.folder_open_rounded, color: Color(0xFF0284C7), size: 18),
                  SizedBox(width: 10),
                  Text('Importar Pasta Completa', style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'arquivos',
              child: Row(
                children: [
                  Icon(Icons.file_present_rounded, color: Color(0xFF0284C7), size: 18),
                  SizedBox(width: 10),
                  Text('Selecionar Arquivos .HTML', style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: _modoTV ? 14 : 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.upload_file_rounded, size: _modoTV ? 18 : 16, color: Colors.white),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    _origemCarregada == null ? 'Importar Dados' : _origemCarregada!,
                    style: TextStyle(
                      fontSize: _modoTV ? 13 : 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down_rounded, size: 18, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
      if (_usuarioEhAdmin)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          child: Tooltip(
            message: 'Cadastrar novos usuários operadores (restrito ao administrador)',
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: _modoTV ? 14 : 11),
              ),
              onPressed: _abrirTelaCadastroUsuario,
              icon: Icon(Icons.manage_accounts_rounded, size: _modoTV ? 18 : 16),
              label: Text('Cadastrar Usuários', style: TextStyle(fontSize: _modoTV ? 13 : 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      if (_nomeUsuarioLogado != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_circle_rounded, color: Color(0xFF38BDF8), size: 18),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  _nomeUsuarioLogado!,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      IconButton(
        tooltip: _nomeUsuarioLogado == null
            ? 'Sair / Trocar Operador'
            : 'Sair ($_nomeUsuarioLogado)',
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
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12)],
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
    final isMobile = MediaQuery.of(context).size.width < 700 || MediaQuery.of(context).size.height < 550;

    if (alertas.isEmpty) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: _modoTV ? 12 : 9),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
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
        border: Border.all(color: corBase.withValues(alpha: 0.6), width: 1.5),
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
                    border: Border.all(color: corBase.withValues(alpha: 0.3)),
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
          boxShadow: ativo ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 3)] : null,
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
            if (i < cards.length - 1) SizedBox(width: _modoTV ? 14 : 12),
          ]
        ],
      );
    }

    if (isPhoneLandscape) {
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
            color: Colors.black.withValues(alpha: _modoTV ? 0.06 : 0.03),
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
                    fontSize: _modoTV ? 13 : (isMobile ? 9 : 10),
                    fontWeight: FontWeight.w800,
                    color: _modoTV ? const Color(0xFF1E293B) : Colors.blueGrey,
                    letterSpacing: _modoTV ? 0.4 : 0.0,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icone, size: _modoTV ? 21 : (isMobile ? 14 : 15), color: cor),
            ],
          ),
          SizedBox(height: _modoTV ? 8 : (isMobile ? 4 : 6)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              style: TextStyle(
                fontSize: _modoTV ? 34 : (isMobile ? 18 : 20),
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
              fontSize: _modoTV ? 14 : (isMobile ? 10 : 11),
              fontWeight: _modoTV ? FontWeight.w700 : FontWeight.normal,
              color: _modoTV ? const Color(0xFF334155) : Colors.grey.shade600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Gráfico 1: Série Diária de Viagens em Linha + Área (melhor leitura à distância sem barras finas)
  Widget _buildGraficoViagensEQuilometragem(
    List<ResumoDiario> resumos,
    List<FaixaHorariaItem> fxHr,
    List<LinhaDiaria> linhas,
  ) {
    final Map<String, double> mapProg = {};
    final Map<String, double> mapReal = {};
    final Map<String, int> mapWeekday = {};

    if (_linhaSelecionada == null && resumos.isNotEmpty) {
      for (final r in resumos) {
        mapProg[r.data] = r.viagensProg.toDouble();
        mapReal[r.data] = r.viagensRealiz.toDouble();
        mapWeekday[r.data] = r.weekday;
      }
    } else if (linhas.isNotEmpty) {
      for (final l in linhas) {
        mapProg[l.data] = (mapProg[l.data] ?? 0) + l.viagensProg;
        mapReal[l.data] = (mapReal[l.data] ?? 0) + l.viagensRealiz;
        mapWeekday[l.data] = l.weekday;
      }
    } else {
      for (final f in fxHr) {
        mapReal[f.data] = (mapReal[f.data] ?? 0) + f.viagens;
        mapProg[f.data] = mapReal[f.data]!;
        mapWeekday[f.data] = f.weekday;
      }
    }

    final datas = mapReal.keys.toList();

    return _boxGrafico(
      titulo: _linhaSelecionada == null
          ? 'Execução Diária de Viagens (Prog. vs. Realiz.)'
          : 'Viagens Diárias Realizadas • Linha $_linhaSelecionada',
      subtitulo: 'Linha tracejada = média diária • Faixas cinzas = fins de semana',
      legenda: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _bolinhaLegenda(const Color(0xFF64748B), 'Prog.'),
          _bolinhaLegenda(const Color(0xFF0284C7), 'Realiz.'),
          _botaoAlternarAjuste(),
        ],
      ),
      child: datas.isEmpty
          ? const Center(child: Text('Sem dados para os dias selecionados.'))
          : _lineChartDuplo(
              controller: _scrollViagens,
              labels: datas.map(_fmtCurto).toList(),
              weekdays: datas.map((d) => mapWeekday[d] ?? 1).toList(),
              valoresA: datas.map((d) => mapProg[d] ?? 0).toList(),
              valoresB: datas.map((d) => mapReal[d] ?? 0).toList(),
              nomeSerieA: 'Prog.',
              nomeSerieB: 'Realiz.',
              corA: const Color(0xFF64748B),
              corB: const Color(0xFF0284C7),
            ),
    );
  }

  /// Gráfico 2: Série Diária de Passageiros em Linha + Área (contraste claro entre Pagantes e Gratuidade)
  Widget _buildGraficoPassageiros(List<PassageiroDiario> passageiros) {
    final labels = passageiros.map((e) => _fmtCurto(e.data)).toList();
    final weekdays = passageiros.map((e) => e.weekday).toList();
    final pagantes = passageiros.map((e) => (e.catraca + e.antecipados).toDouble()).toList();
    final gratuitos = passageiros.map((e) => e.naoPagantes.toDouble()).toList();

    return _boxGrafico(
      titulo: 'Passageiros por Dia (Pagantes vs. Gratuidade)',
      subtitulo: 'Linha tracejada = média de gratuidade • Faixas cinzas = fins de semana',
      legenda: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _bolinhaLegenda(const Color(0xFF0284C7), 'Pagantes'),
          _bolinhaLegenda(const Color(0xFFEA580C), 'Gratuidade'),
          _botaoAlternarAjuste(),
        ],
      ),
      child: passageiros.isEmpty
          ? const Center(child: Text('Sem dados de passageiros para este filtro.'))
          : _lineChartDuplo(
              controller: _scrollPassageiros,
              labels: labels,
              weekdays: weekdays,
              valoresA: pagantes,
              valoresB: gratuitos,
              nomeSerieA: 'Pagantes',
              nomeSerieB: 'Gratuidade',
              corA: const Color(0xFF0284C7),
              corB: const Color(0xFFEA580C),
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

  /// Gráfico 3: Distribuição por Faixa Horária (mantido em Barras Verticais para contraste visual)
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
      final leftReserved = isMobile ? 46.0 : (_modoTV ? 66.0 : 52.0);
      final rightReserved = isMobile ? 12.0 : (_modoTV ? 18.0 : 14.0);
      final areaUtil = (constraints.maxWidth - (leftReserved + rightReserved + 16)).clamp(150.0, 5000.0);
      final slotWidth = areaUtil / (horas.isEmpty ? 1 : horas.length);
      final rodWidth = (slotWidth * (isMobile ? 0.62 : 0.64)).clamp(4.0, _modoTV ? 20.0 : 14.0);

      return _boxGrafico(
        titulo: 'Viagens por Faixa Horária (0h às 23h)',
        subtitulo: _linhaSelecionada == null ? 'Soma de todas as linhas' : 'Operação da Linha $_linhaSelecionada',
        legenda: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _bolinhaLegenda(const Color(0xFFE11D48), 'Pico'),
            const SizedBox(width: 8),
            _bolinhaLegenda(const Color(0xFF334155), 'Normal'),
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
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: const Color(0xFFE2E8F0),
                        strokeWidth: _modoTV ? 1.2 : 0.8,
                      ),
                    ),
                    barTouchData: _tooltipPadrao(),
                    barGroups: horas.map((h) {
                      final pico = (h >= 6 && h <= 8) || (h >= 17 && h <= 19);
                      return BarChartGroupData(
                        x: h,
                        barRods: [
                          BarChartRodData(
                            toY: viagensPorHora[h]!,
                            color: pico ? const Color(0xFFE11D48) : const Color(0xFF334155),
                            width: rodWidth,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(3.0)),
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
                                  fontSize: isMobile ? 9 : (_modoTV ? 13 : 10),
                                  color: _modoTV ? const Color(0xFF1E293B) : Colors.blueGrey,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: isMobile ? 26 : (_modoTV ? 34 : 26),
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
                                  fontSize: isMobile ? 10 : (_modoTV ? 13 : 10),
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
    List<FaixaHorariaItem> fxHr,
    List<ResumoDiario> resumos,
  ) {
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

    final turnosWidget = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _barraProgressoTurno('Manhã', manhaR, manhaP, const Color(0xFFD97706)),
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
            fontSize: _modoTV ? 15 : 11,
            fontWeight: FontWeight.w800,
            color: _modoTV ? const Color(0xFF1E293B) : Colors.blueGrey,
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
                        style: TextStyle(fontSize: _modoTV ? 15 : 11, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${_fmtInt(item.value)} viag.',
                        style: TextStyle(
                          fontSize: _modoTV ? 14 : 10,
                          color: _modoTV ? const Color(0xFF334155) : Colors.blueGrey,
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
                      minHeight: _modoTV ? 12 : 6,
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
      height: isMobile ? 480 : (_modoTV ? 380 : 315),
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
            Text(turno, style: TextStyle(fontWeight: FontWeight.w800, fontSize: _modoTV ? 16 : (isMobile ? 12 : 12))),
            Text('${perc.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: _modoTV ? 16 : (isMobile ? 12 : 11),
                  color: cor,
                )),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (perc / 100).clamp(0.0, 1.0),
            minHeight: _modoTV ? 18 : 10,
            backgroundColor: const Color(0xFFE2E8F0),
            color: cor,
          ),
        ),
      ],
    );
  }

  /// Gráfico de Linha + Área preenchida para séries diárias:
  /// elimina o efeito de "palitinhos" finos, destaca fins de semana e mostra linha de média.
  Widget _lineChartDuplo({
    required ScrollController controller,
    required List<String> labels,
    required List<int> weekdays,
    required List<double> valoresA,
    required List<double> valoresB,
    required String nomeSerieA,
    required String nomeSerieB,
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

    final double mediaB = valoresB.isNotEmpty
        ? valoresB.reduce((a, b) => a + b) / valoresB.length
        : 0.0;

    // Faixas verticais sutis para destacar sábados e domingos
    final weekendRanges = <VerticalRangeAnnotation>[];
    for (int i = 0; i < weekdays.length; i++) {
      if (weekdays[i] == 6 || weekdays[i] == 7) {
        weekendRanges.add(
          VerticalRangeAnnotation(
            x1: (i - 0.45).clamp(0.0, (labels.length - 1).toDouble()),
            x2: (i + 0.45).clamp(0.0, (labels.length - 1).toDouble()),
            color: const Color(0xFFE2E8F0).withValues(alpha: 0.55),
          ),
        );
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final larguraMin = constraints.maxWidth;
        final leftReserved = isMobile ? 46.0 : (_modoTV ? 66.0 : 52.0);
        final rightReserved = isMobile ? 12.0 : (_modoTV ? 18.0 : 14.0);

        if (_verMesTodo && controller.hasClients && controller.offset != 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (controller.hasClients) controller.jumpTo(0);
          });
        }

        final double larguraCalculada = _verMesTodo
            ? larguraMin
            : (labels.length * (isMobile ? 48.0 : (_modoTV ? 64.0 : 54.0)) + 60.0)
                .clamp(larguraMin, 4000.0);

        final larguraAreaLabels = larguraCalculada - (leftReserved + rightReserved + 16);
        final maxLabelsQueCabem = (larguraAreaLabels / (isMobile ? 42.0 : (_modoTV ? 62.0 : 52.0))).floor().clamp(2, 35);
        final stepDatas = (labels.length / maxLabelsQueCabem).ceil().clamp(1, 15);

        final spotsA = List.generate(labels.length, (i) => FlSpot(i.toDouble(), valoresA[i]));
        final spotsB = List.generate(labels.length, (i) => FlSpot(i.toDouble(), valoresB[i]));
        final mostrarPontos = labels.length <= 16 || !_verMesTodo;

        final chartWidget = LineChart(
          LineChartData(
            minX: 0,
            maxX: labels.length > 1 ? (labels.length - 1).toDouble() : 1.0,
            minY: 0,
            maxY: maxY,
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(
                color: const Color(0xFFE2E8F0),
                strokeWidth: _modoTV ? 1.2 : 0.8,
              ),
            ),
            rangeAnnotations: RangeAnnotations(
              verticalRangeAnnotations: weekendRanges,
            ),
            extraLinesData: ExtraLinesData(
              horizontalLines: [
                if (mediaB > 0)
                  HorizontalLine(
                    y: mediaB,
                    color: corB.withValues(alpha: 0.65),
                    strokeWidth: _modoTV ? 2.0 : 1.4,
                    dashArray: [6, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      padding: const EdgeInsets.only(right: 4, bottom: 2),
                      style: TextStyle(
                        fontSize: _modoTV ? 11 : 9,
                        fontWeight: FontWeight.w800,
                        color: corB,
                      ),
                      labelResolver: (_) => 'Média: ${_fmtMilhar(mediaB)}',
                    ),
                  ),
              ],
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipColor: (_) => const Color(0xFF0F172A),
                tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((spot) {
                    final idx = spot.x.toInt();
                    final dataLabel = (idx >= 0 && idx < labels.length) ? '${labels[idx]} • ' : '';
                    final serieNome = spot.barIndex == 0 ? nomeSerieA : nomeSerieB;
                    return LineTooltipItem(
                      '$dataLabel$serieNome: ${_fmtInt(spot.y.round())}',
                      TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: _modoTV ? 14 : (isMobile ? 11 : 12),
                      ),
                    );
                  }).toList();
                },
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spotsA,
                isCurved: true,
                curveSmoothness: 0.22,
                color: corA,
                barWidth: _modoTV ? 3.0 : 2.2,
                dashArray: nomeSerieA == 'Prog.' ? [6, 4] : null,
                dotData: FlDotData(
                  show: mostrarPontos,
                  getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                    radius: _modoTV ? 3.5 : 2.5,
                    color: corA,
                    strokeWidth: 1,
                    strokeColor: Colors.white,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: nomeSerieA != 'Prog.',
                  color: corA.withValues(alpha: 0.14),
                ),
              ),
              LineChartBarData(
                spots: spotsB,
                isCurved: true,
                curveSmoothness: 0.22,
                color: corB,
                barWidth: _modoTV ? 3.6 : 2.6,
                dotData: FlDotData(
                  show: mostrarPontos,
                  getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                    radius: _modoTV ? 4.2 : 3.0,
                    color: corB,
                    strokeWidth: 1.5,
                    strokeColor: Colors.white,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: corB.withValues(alpha: 0.16),
                ),
              ),
            ],
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
                          fontSize: isMobile ? 9 : (_modoTV ? 13 : 10),
                          color: _modoTV ? const Color(0xFF1E293B) : Colors.blueGrey,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 1,
                  reservedSize: isMobile ? 26 : (_modoTV ? 34 : 26),
                  getTitlesWidget: (v, m) {
                    if ((v - v.roundToDouble()).abs() > 0.01) return const SizedBox.shrink();
                    final idx = v.round();
                    if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();

                    if (stepDatas > 1 && idx % stepDatas != 0 && idx != labels.length - 1) {
                      return const SizedBox.shrink();
                    }

                    return SideTitleWidget(
                      meta: m,
                      space: 4,
                      child: Text(
                        labels[idx],
                        style: TextStyle(
                          fontSize: isMobile ? 9 : (_modoTV ? 13 : 10),
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
      height: height ?? (_modoTV ? 380 : (isMobile ? 330 : 315)),
      padding: EdgeInsets.all(_modoTV ? 16 : (isMobile ? 12 : 14)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _modoTV ? 0.04 : 0.02),
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
                          fontSize: _modoTV ? 17 : 13,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitulo,
                        style: TextStyle(
                          fontSize: _modoTV ? 13 : 11,
                          color: _modoTV ? const Color(0xFF334155) : Colors.blueGrey,
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
          width: _modoTV ? 13 : 10,
          height: _modoTV ? 13 : 10,
          decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 5),
        Text(
          texto,
          style: TextStyle(
            fontSize: _modoTV ? 13 : 10,
            fontWeight: FontWeight.w700,
            color: _modoTV ? const Color(0xFF1E293B) : Colors.blueGrey,
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
                  fontSize: _modoTV ? 17 : 13,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              Text(
                '${resumos.length} reg.',
                style: TextStyle(
                  fontSize: _modoTV ? 14 : 11,
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
                  fontSize: _modoTV ? 14 : 12,
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
                        fontSize: _modoTV ? 14 : 12,
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
          fontSize: _modoTV ? 14 : 12,
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