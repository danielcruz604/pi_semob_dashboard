import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/dashboard_models.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String? _token;

  String get baseUrl {
    if (kIsWeb) return 'http://localhost:8000/api';
    if (Platform.isAndroid) return 'http://10.0.2.2:8000/api';
    return 'http://127.0.0.1:8000/api';
  }

  void setToken(String token) => _token = token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<ResumoOperacional> buscarResumoOperacional({
    String? dataInicio,
    String? dataFim,
    String? linha,
  }) async {
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

  Future<AnomaliasResponse> buscarAnomalias({
    String? dataInicio,
    String? dataFim,
    String? linha,
    double toleranciaKm = 15.0,
    double limiarFcv = 0.98,
    double limiarImprod = 10.0,
  }) async {
    final queryParams = {
      if (dataInicio != null) 'data_inicio': dataInicio,
      if (dataFim != null) 'data_fim': dataFim,
      if (linha != null) 'linha': linha,
      'tolerancia_desvio_km_pct': toleranciaKm.toString(),
      'limiar_fcv': limiarFcv.toString(),
      'limiar_km_improd_pct': limiarImprod.toString(),
    };

    final uri = Uri.parse('$baseUrl/dashboard/anomalias')
        .replace(queryParameters: queryParams);

    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 200) {
      return AnomaliasResponse.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
    }
    throw Exception('Falha ao consultar anomalias: ${res.statusCode}');
  }

  Future<List<LinhaRanking>> buscarRankingLinhas({
    String? dataInicio,
    String? dataFim,
  }) async {
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
}