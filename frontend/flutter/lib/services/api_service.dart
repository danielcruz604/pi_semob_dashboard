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

  String get baseUrl {
    if (kIsWeb) return 'http://localhost:8000/api';
    if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:8000/api';
    return 'http://127.0.0.1:8000/api';
  }

  void setToken(String token) => _token = token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  /// Testa conexão com a API FastAPI
  Future<bool> verificarServidorOnline() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/')).timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Realiza login e armazena o token JWT
  Future<bool> login(String email, String senha) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/usuarios/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'senha': senha}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _token = data['access_token'];
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Envia relatório HTML para persistência no MongoDB (upsert)
  Future<bool> enviarHtmlParaBanco(String nomeArquivo, List<int> bytes) async {
    try {
      final uri = Uri.parse('$baseUrl/transporte/processar-e-salvar');
      final req = http.MultipartRequest('POST', uri);
      if (_token != null) {
        req.headers['Authorization'] = 'Bearer $_token';
      }
      req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: nomeArquivo));

      final streamed = await req.send().timeout(const Duration(seconds: 40));
      final res = await http.Response.fromStream(streamed);
      return res.statusCode == 200;
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
      final List serie = bodySerie['serie'] ?? [];

      // 3. Busca faixas horárias
      final resHorarios = await http.get(Uri.parse('$baseUrl/dashboard/horarios'), headers: _headers);
      final List horariosRaw = resHorarios.statusCode == 200 ? jsonDecode(utf8.decode(resHorarios.bodyBytes)) : [];

      // Mapeia o pico de veículos por data a partir das faixas horárias
      final Map<String, int> veiculosPorDataIso = {};
      for (final h in horariosRaw) {
        final dIso = h['data']?.toString() ?? '';
        final veic = (h['numero_veiculos'] as num?)?.toInt() ?? 0;
        if (veic > (veiculosPorDataIso[dIso] ?? 0)) {
          veiculosPorDataIso[dIso] = veic;
        }
      }

      final resumos = <ResumoDiario>[];
      final passageiros = <PassageiroDiario>[];
      final setMeses = <String>{};

      for (final item in serie) {
        final refIso = item['referencia'] as String; // YYYY-MM-DD
        final p = refIso.split('-');
        if (p.length != 3) continue;

        final dt = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
        final dataBR = '${p[2]}/${p[1]}/${p[0]}';
        final mesAno = '${_nomeMes(dt.month)}/${dt.year}';
        setMeses.add(mesAno);

        final viagProg = (item['viagens_programadas'] as num?)?.toInt() ?? 0;
        final viagReal = (item['viagens_realizadas'] as num?)?.toInt() ?? 0;
        final kmTotal = (item['km_total'] as num?)?.toDouble() ?? 0.0;
        final kmImprod = (item['km_improdutivo'] as num?)?.toDouble() ?? 0.0;
        final kmProd = (item['km_produtivo'] as num?)?.toDouble() ?? (kmTotal - kmImprod);
        final veiculosDia = veiculosPorDataIso[refIso] ?? 0;

        resumos.add(ResumoDiario(
          data: dataBR,
          weekday: dt.weekday,
          veiculos: veiculosDia,
          maxVeicFaixa: veiculosDia,
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

        final passPag = (item['passageiros_pagantes'] as num?)?.toInt() ?? 0;
        final passNaoPag = (item['passageiros_nao_pagantes'] as num?)?.toInt() ?? 0;
        final passTot = (item['total_passageiros'] as num?)?.toInt() ?? (passPag + passNaoPag);

        passageiros.add(PassageiroDiario(
          data: dataBR,
          weekday: dt.weekday,
          catraca: passPag,
          antecipados: 0,
          naoPagantes: passNaoPag,
          totalPassageiros: passTot,
          mesAno: mesAno,
          periodicidade: 'Mensal',
          dateTime: dt,
        ));
      }

      final faixasHorarias = <FaixaHorariaItem>[];
      for (final h in horariosRaw) {
        final refIso = h['data']?.toString() ?? '';
        final p = refIso.split('-');
        final dt = p.length == 3 ? DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2])) : DateTime(2026, 8, 1);
        final dataBR = p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : refIso;

        faixasHorarias.add(FaixaHorariaItem(
          data: dataBR,
          weekday: dt.weekday,
          linha: h['linha']?.toString() ?? '',
          hora: (h['hora'] as num?)?.toInt() ?? 0,
          faixaTexto: h['faixa']?.toString() ?? '',
          veiculos: (h['numero_veiculos'] as num?)?.toInt() ?? 0,
          viagens: (h['viagens'] as num?)?.toInt() ?? 0,
          partidas: h['partidas']?.toString() ?? '',
          mesAno: '${_nomeMes(dt.month)}/${dt.year}',
          periodicidade: 'Mensal',
          dateTime: dt,
        ));
      }

      final ds = SemobDataset()
        ..resumos.addAll(resumos)
        ..passageiros.addAll(passageiros)
        ..faixasHorarias.addAll(faixasHorarias);

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
    final uri = Uri.parse('$baseUrl/dashboard/resumo-operacional').replace(queryParameters: queryParams.isEmpty ? null : queryParams);
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
    final uri = Uri.parse('$baseUrl/dashboard/anomalias').replace(queryParameters: queryParams.isEmpty ? null : queryParams);
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
    final uri = Uri.parse('$baseUrl/dashboard/linhas-ranking').replace(queryParameters: queryParams.isEmpty ? null : queryParams);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 200) {
      final List data = jsonDecode(utf8.decode(res.bodyBytes));
      return data.map((e) => LinhaRanking.fromJson(e)).toList();
    }
    throw Exception('Falha ao carregar ranking de linhas: ${res.statusCode}');
  }

  static String _nomeMes(int m) {
    const meses = ['', 'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'];
    return m >= 1 && m <= 12 ? meses[m] : 'Agosto';
  }

  static String _diaSemanaSigla(int w) {
    const sig = ['', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
    return w >= 1 && w <= 7 ? sig[w] : 'Seg';
  }
}