import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../local_data_loader.dart';
import '../models/dashboard_models.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String? _token;

  String get rootUrl {
    if (kIsWeb) return 'http://localhost:8000';
    if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:8000';
    return 'http://127.0.0.1:8000';
  }

  String get baseUrl => '$rootUrl/api';

  void setToken(String token) {
    _token = token;
    RelatorioApiService.definirToken(token);
  }

  String? get _tokenEfetivo => _token ?? RelatorioApiService.tokenJwt;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_tokenEfetivo != null && _tokenEfetivo!.isNotEmpty)
          'Authorization': 'Bearer $_tokenEfetivo',
      };

  /// Testa conexão com a API FastAPI (verifica a raiz `/` e `/api/dashboard/filtros`)
  Future<bool> verificarServidorOnline() async {
    try {
      final resRoot = await http
          .get(Uri.parse('$rootUrl/'))
          .timeout(const Duration(seconds: 3));
      if (resRoot.statusCode == 200) return true;

      final resFiltros = await http
          .get(Uri.parse('$baseUrl/dashboard/filtros'), headers: _headers)
          .timeout(const Duration(seconds: 3));
      return resFiltros.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Realiza login e armazena o token JWT compartilhado
  Future<bool> login(String email, String senha) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/usuarios/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'senha': senha}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final token = data['access_token']?.toString();
        if (token != null && token.isNotEmpty) {
          setToken(token);
        }
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Envia relatório HTML para persistência no MongoDB (upsert).
  /// Caso o HTML seja um relatório auxiliar sem coleção dedicada (ex.: `Mensal_Viagens` ou `Resumo_FxHr`),
  /// processa-o via `/transporte/processar-html` para validar a integridade sem erro.
  Future<bool> enviarHtmlParaBanco(
    String nomeArquivo,
    List<int> bytes, {
    SemobDataset? datasetParaAlertas,
  }) async {
    try {
      final uriSalvar = Uri.parse('$baseUrl/transporte/processar-e-salvar');
      final req = http.MultipartRequest('POST', uriSalvar);
      if (_tokenEfetivo != null && _tokenEfetivo!.isNotEmpty) {
        req.headers['Authorization'] = 'Bearer $_tokenEfetivo';
      }
      req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: nomeArquivo));

      final streamed = await req.send().timeout(const Duration(seconds: 40));
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode == 200) {
        if (datasetParaAlertas != null) {
          try {
            final Map<String, dynamic> body = jsonDecode(utf8.decode(res.bodyBytes));
            final List? discrepancias = body['discrepancias_detectadas'] as List?;
            if (discrepancias != null) {
              for (final raw in discrepancias.whereType<Map>()) {
                final dataIso = raw['data']?.toString() ?? '';
                final partes = dataIso.split('-');
                final dataBR = partes.length == 3 ? '${partes[2]}/${partes[1]}/${partes[0]}' : dataIso;
                final campo = raw['campo']?.toString() ?? '';
                final ant = raw['valor_anterior'];
                final novo = raw['valor_novo'];
                final colecao = raw['colecao']?.toString() ?? 'MongoDB';
                final desc =
                    'O arquivo $nomeArquivo divergiu do registro já salvo em $colecao ($dataBR • $campo: anterior=$ant vs novo=$novo).';
                final jaTem = datasetParaAlertas.discrepanciasDetectadas.any(
                  (d) => d.data == dataBR && d.descricao == desc,
                );
                if (!jaTem) {
                  datasetParaAlertas.discrepanciasDetectadas.add(
                    DiscrepanciaConsolidacao(
                      data: dataBR,
                      categoria: colecao,
                      periodicidadeNova: nomeArquivo,
                      periodicidadeBase: 'MongoDB',
                      descricao: desc,
                    ),
                  );
                }
              }
            }
          } catch (_) {}
        }
        return true;
      }

      // Fallback para relatórios válidos que apenas são higienizados (sem coleção de destino)
      if (res.statusCode == 422) {
        final bodyStr = utf8.decode(res.bodyBytes, allowMalformed: true);
        if (bodyStr.contains('/processar-html')) {
          final uriProc = Uri.parse('$baseUrl/transporte/processar-html');
          final reqProc = http.MultipartRequest('POST', uriProc);
          if (_tokenEfetivo != null && _tokenEfetivo!.isNotEmpty) {
            reqProc.headers['Authorization'] = 'Bearer $_tokenEfetivo';
          }
          reqProc.files.add(http.MultipartFile.fromBytes('file', bytes, filename: nomeArquivo));
          final streamedProc = await reqProc.send().timeout(const Duration(seconds: 40));
          final resProc = await http.Response.fromStream(streamedProc);
          return resProc.statusCode == 200;
        }
      }

      return false;
    } catch (e) {
      debugPrint('Falha ao enviar $nomeArquivo para o backend: $e');
      return false;
    }
  }

  /// Consulta dados salvos no MongoDB e remonta o SemobDataset
  Future<SemobDataset?> carregarDatasetDoBanco() async {
    try {
      // 1. Verifica filtros disponíveis
      final resFiltros = await http.get(Uri.parse('$baseUrl/dashboard/filtros'), headers: _headers);
      if (resFiltros.statusCode != 200) return null;
      final Map<String, dynamic> filtros = jsonDecode(utf8.decode(resFiltros.bodyBytes));
      if (filtros['data_minima'] == null) return null;

      // 2. Busca série diária consolidada
      final resSerie = await http.get(
        Uri.parse('$baseUrl/dashboard/serie-temporal?agrupamento=diario'),
        headers: _headers,
      );
      if (resSerie.statusCode != 200) return null;
      final Map<String, dynamic> bodySerie = jsonDecode(utf8.decode(resSerie.bodyBytes));
      final List serie = bodySerie['serie'] as List? ?? [];

      // 3. Busca faixas horárias
      final resHorarios = await http.get(Uri.parse('$baseUrl/dashboard/horarios'), headers: _headers);
      final List horariosRaw =
          resHorarios.statusCode == 200 ? (jsonDecode(utf8.decode(resHorarios.bodyBytes)) as List? ?? []) : [];

      // 4. Busca resumo operacional para recuperar FCV por turno (manhã, tarde, noite) se disponível
      Map<String, dynamic>? resumoRaw;
      try {
        final resResumo = await http.get(
          Uri.parse('$baseUrl/dashboard/resumo-operacional'),
          headers: _headers,
        );
        if (resResumo.statusCode == 200) {
          resumoRaw = jsonDecode(utf8.decode(resResumo.bodyBytes)) as Map<String, dynamic>?;
        }
      } catch (_) {}

      final resumos = <ResumoDiario>[];
      final passageiros = <PassageiroDiario>[];
      final fcvList = <FcvDiario>[];

      for (final item in serie) {
        final refIso = item['referencia']?.toString() ?? ''; // YYYY-MM-DD
        final p = refIso.split('-');
        if (p.length != 3) continue;

        final dt = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
        final dataBR = '${p[2]}/${p[1]}/${p[0]}';
        final mesAno = '${_nomeMes(dt.month)}/${dt.year}';

        final viagProg = (item['viagens_programadas'] as num?)?.toInt() ?? 0;
        final viagReal = (item['viagens_realizadas'] as num?)?.toInt() ?? 0;
        final kmTotal = (item['km_total'] as num?)?.toDouble() ?? 0.0;
        final kmImprod = (item['km_improdutivo'] as num?)?.toDouble() ?? 0.0;
        final kmProd = (item['km_produtivo'] as num?)?.toDouble() ?? (kmTotal - kmImprod);
        // Frota diária do sistema vem exclusivamente de `viagensSistema` (nunca de `viagensHorario`, que é por linha/hora)
        final veiculosDia = (item['numero_veiculos'] as num?)?.toInt() ?? 0;
        final maxVeicFaixaDia = (item['numero_max_veiculos_faixa'] as num?)?.toInt() ?? veiculosDia;

        if (kmTotal > 0 || (viagProg > 0 && item['fcv_por_periodo'] == null)) {
          resumos.add(ResumoDiario(
            data: dataBR,
            weekday: dt.weekday,
            veiculos: veiculosDia,
            maxVeicFaixa: maxVeicFaixaDia,
            viagensProg: viagProg,
            viagensRealiz: viagReal,
            difViagens: (viagProg - viagReal).abs(),
            kmProd: kmProd,
            kmImprod: kmImprod,
            kmTotal: kmTotal,
            mesAno: mesAno,
            periodicidade: 'Mensal',
            dateTime: dt,
          ));
        }

        final fcvDiaMap = item['fcv_por_periodo'] as Map?;
        if (fcvDiaMap != null) {
          final manha = fcvDiaMap['manha'] as Map? ?? {};
          final tarde = fcvDiaMap['tarde'] as Map? ?? {};
          final noite = fcvDiaMap['noite'] as Map? ?? {};
          final manhaP = (manha['prog'] as num?)?.toInt() ?? 0;
          final manhaR = (manha['real'] as num?)?.toInt() ?? 0;
          final tardeP = (tarde['prog'] as num?)?.toInt() ?? 0;
          final tardeR = (tarde['real'] as num?)?.toInt() ?? 0;
          final noiteP = (noite['prog'] as num?)?.toInt() ?? 0;
          final noiteR = (noite['real'] as num?)?.toInt() ?? 0;
          final somaProgTurnos = manhaP + tardeP + noiteP;
          final somaRealTurnos = manhaR + tardeR + noiteR;

          if (somaProgTurnos > 0 || somaRealTurnos > 0) {
            fcvList.add(FcvDiario(
              mesAno: mesAno,
              periodicidade: 'Mensal',
              data: dataBR,
              dateTime: dt,
              weekday: dt.weekday,
              manhaProg: manhaP,
              manhaRealiz: manhaR,
              tardeProg: tardeP,
              tardeRealiz: tardeR,
              noiteProg: noiteP,
              noiteRealiz: noiteR,
              totalProg: viagProg > 0 ? viagProg : somaProgTurnos,
              totalRealiz: viagReal > 0 ? viagReal : somaRealTurnos,
            ));
          }
        }

        final passPag = (item['passageiros_pagantes'] as num?)?.toInt() ?? 0;
        final passCatraca = (item['catraca'] as num?)?.toInt() ?? 0;
        final passAntecipados = (item['antecipados'] as num?)?.toInt() ?? 0;
        final passNaoPag = (item['passageiros_nao_pagantes'] as num?)?.toInt() ?? 0;
        final passTot = (item['total_passageiros'] as num?)?.toInt() ?? (passPag + passNaoPag);

        if (passTot > 0 || passPag > 0 || passNaoPag > 0) {
          final temDecomposicao = passCatraca > 0 || passAntecipados > 0;
          passageiros.add(PassageiroDiario(
            data: dataBR,
            weekday: dt.weekday,
            catraca: temDecomposicao ? passCatraca : passPag,
            antecipados: temDecomposicao ? passAntecipados : 0,
            naoPagantes: passNaoPag,
            totalPassageiros: passTot,
            mesAno: mesAno,
            periodicidade: 'Mensal',
            dateTime: dt,
          ));
        }
      }

      // Fallback caso o servidor esteja em versão anterior que não envie fcv_por_periodo na série diária
      final fcvPorPeriodo = ((resumoRaw?['viagens'] as Map?)?['por_periodo'] ??
          (resumoRaw?['viagens'] as Map?)?['fcv_por_periodo']) as Map?;
      if (fcvList.isEmpty && fcvPorPeriodo != null) {
        final manha = fcvPorPeriodo['manha'] as Map? ?? {};
        final tarde = fcvPorPeriodo['tarde'] as Map? ?? {};
        final noite = fcvPorPeriodo['noite'] as Map? ?? {};
        final manhaP = (manha['prog'] as num?)?.toInt() ?? 0;
        final manhaR = (manha['real'] as num?)?.toInt() ?? 0;
        final tardeP = (tarde['prog'] as num?)?.toInt() ?? 0;
        final tardeR = (tarde['real'] as num?)?.toInt() ?? 0;
        final noiteP = (noite['prog'] as num?)?.toInt() ?? 0;
        final noiteR = (noite['real'] as num?)?.toInt() ?? 0;

        if (manhaP + tardeP + noiteP > 0) {
          final dtRef = resumos.isNotEmpty ? resumos.first.dateTime : DateTime(2026, 8, 1);
          final dataBR = '${dtRef.day.toString().padLeft(2, '0')}/${dtRef.month.toString().padLeft(2, '0')}/${dtRef.year}';
          fcvList.add(FcvDiario(
            mesAno: '${_nomeMes(dtRef.month)}/${dtRef.year}',
            periodicidade: 'Mensal',
            data: dataBR,
            dateTime: dtRef,
            weekday: dtRef.weekday,
            manhaProg: manhaP,
            manhaRealiz: manhaR,
            tardeProg: tardeP,
            tardeRealiz: tardeR,
            noiteProg: noiteP,
            noiteRealiz: noiteR,
            totalProg: manhaP + tardeP + noiteP,
            totalRealiz: manhaR + tardeR + noiteR,
          ));
        }
      }

      final faixasHorarias = <FaixaHorariaItem>[];
      for (final h in horariosRaw) {
        final refIso = h['data']?.toString() ?? '';
        final p = refIso.split('-');
        final dt = p.length == 3 ? DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2])) : DateTime(2026, 8, 1);
        final dataBR = p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : refIso;
        final horaInt = (h['hora'] as num?)?.toInt() ?? 0;
        final linhaNorm = (h['linha']?.toString() ?? '').trim().padLeft(2, '0');
        final partidasRaw = h['partidas'];
        final partidasStr = partidasRaw is List
            ? partidasRaw.join(' > ')
            : (partidasRaw?.toString() ?? '');

        faixasHorarias.add(FaixaHorariaItem(
          data: dataBR,
          weekday: dt.weekday,
          linha: linhaNorm,
          hora: horaInt,
          faixaTexto: h['faixa']?.toString() ?? '${horaInt}hs',
          veiculos: (h['numero_veiculos'] as num?)?.toInt() ?? 0,
          viagens: (h['viagens'] as num?)?.toInt() ?? 0,
          partidas: partidasStr,
          mesAno: '${_nomeMes(dt.month)}/${dt.year}',
          periodicidade: 'Mensal',
          dateTime: dt,
        ));
      }

      final ds = SemobDataset()
        ..resumos.addAll(resumos)
        ..passageiros.addAll(passageiros)
        ..fcv.addAll(fcvList)
        ..faixasHorarias.addAll(faixasHorarias);

      LocalDataLoader.reconciliarDerivacoesDiarias(ds);
      return ds;
    } catch (e) {
      debugPrint('Erro ao reconstruir dataset a partir do MongoDB: $e');
      return null;
    }
  }

  Future<ResumoOperacional> buscarResumoOperacional({String? dataInicio, String? dataFim, String? linha}) async {
    final queryParams = {
      if (dataInicio != null) 'data_inicio': dataInicio,
      if (dataFim != null) 'data_fim': dataFim,
      if (linha != null) 'linha': linha,
    };
    final uri = Uri.parse('$baseUrl/dashboard/resumo-operacional')
        .replace(queryParameters: queryParams.isEmpty ? null : queryParams);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 200) {
      return ResumoOperacional.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
    }
    throw Exception('Falha ao obter resumo operacional: ${res.statusCode}');
  }

  Future<AnomaliasResponse> buscarAnomalias({String? dataInicio, String? dataFim, String? linha}) async {
    final queryParams = {
      if (dataInicio != null) 'data_inicio': dataInicio,
      if (dataFim != null) 'data_fim': dataFim,
      if (linha != null) 'linha': linha,
    };
    final uri = Uri.parse('$baseUrl/dashboard/anomalias')
        .replace(queryParameters: queryParams.isEmpty ? null : queryParams);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 200) {
      return AnomaliasResponse.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
    }
    throw Exception('Falha ao consultar anomalias: ${res.statusCode}');
  }

  Future<List<LinhaRanking>> buscarRankingLinhas({String? dataInicio, String? dataFim}) async {
    final queryParams = {
      if (dataInicio != null) 'data_inicio': dataInicio,
      if (dataFim != null) 'data_fim': dataFim,
    };
    final uri = Uri.parse('$baseUrl/dashboard/linhas-ranking')
        .replace(queryParameters: queryParams.isEmpty ? null : queryParams);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 200) {
      final List data = jsonDecode(utf8.decode(res.bodyBytes));
      return data.map((e) => LinhaRanking.fromJson(e)).toList();
    }
    throw Exception('Falha ao carregar ranking de linhas: ${res.statusCode}');
  }

  static String _nomeMes(int m) {
    const meses = [
      '',
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    return m >= 1 && m <= 12 ? meses[m] : 'Agosto';
  }
}
