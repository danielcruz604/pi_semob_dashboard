import 'dart:io';
import 'package:flutter/foundation.dart';

class ArquivoLido {
  final String nome;
  final String caminho;
  final List<int> bytes;

  ArquivoLido({
    required this.nome,
    required this.caminho,
    required this.bytes,
  });
}

/// Resolve e normaliza qualquer caminho de diretório no Windows, Linux, macOS e Android,
/// tratando URIs (file://), percent-encoding (%20), aspas e separadores de barra.
Directory? resolverDiretorioNativo(String caminhoEscolhido) {
  String limpo = caminhoEscolhido.trim();
  if ((limpo.startsWith('"') && limpo.endsWith('"')) ||
      (limpo.startsWith("'") && limpo.endsWith("'"))) {
    limpo = limpo.substring(1, limpo.length - 1).trim();
  }

  // Se for URI com file:// ou percent-encoded
  if (limpo.startsWith('file://') || limpo.startsWith('file:')) {
    try {
      limpo = Uri.parse(limpo).toFilePath();
    } catch (_) {
      try {
        limpo = Uri.decodeFull(limpo.replaceFirst(RegExp(r'^file:/{0,3}'), ''));
      } catch (_) {}
    }
  }

  try {
    limpo = Uri.decodeFull(limpo);
  } catch (_) {}

  // 1. Testa diretamente o caminho limpo
  var d = Directory(limpo);
  if (d.existsSync()) return d;

  // 2. Normaliza separadores de barra para o SO atual
  final barraSo = Platform.isWindows ? '\\' : '/';
  final comSeparadorSo = limpo.replaceAll(RegExp(r'[/\\]'), barraSo);
  d = Directory(comSeparadorSo);
  if (d.existsSync()) return d;

  // 3. Remove barra final se houver
  if (limpo.endsWith('/') || limpo.endsWith('\\')) {
    final semBarra = limpo.substring(0, limpo.length - 1);
    d = Directory(semBarra);
    if (d.existsSync()) return d;
  }

  // 4. Resolução específica para permissões e content URIs no Android
  if (Platform.isAndroid) {
    final resolvidoAndroid = _resolverDiretorioAndroid(caminhoEscolhido);
    if (resolvidoAndroid != null && resolvidoAndroid.existsSync()) {
      return resolvidoAndroid;
    }
  }

  return null;
}

/// Escaneia recursivamente todos os arquivos da pasta utilizando busca iterativa em fila (BFS),
/// garantindo que arquivos bloqueados, restritos ou subdiretórios com exceções de sistema não
/// abortem o processamento dos demais arquivos HTML.
Future<List<ArquivoLido>> escanearPastaNativa(
  String caminhoEscolhido,
  bool Function(String nome) filtroNome,
) async {
  final resultado = <ArquivoLido>[];

  try {
    final dirAlvo = resolverDiretorioNativo(caminhoEscolhido);
    if (dirAlvo == null || !dirAlvo.existsSync()) {
      debugPrint('Diretório não encontrado ou inacessível: $caminhoEscolhido');
      return resultado;
    }

    final filaDiretorios = <Directory>[dirAlvo];
    final caminhosVisitados = <String>{};

    while (filaDiretorios.isNotEmpty) {
      final dirAtual = filaDiretorios.removeAt(0);
      final pathNorm = dirAtual.path.toLowerCase();
      if (caminhosVisitados.contains(pathNorm)) continue;
      caminhosVisitados.add(pathNorm);

      List<FileSystemEntity> entidades = [];
      try {
        entidades = dirAtual.listSync(followLinks: false);
      } catch (e) {
        debugPrint('Aviso: Subdiretório inacessível ignorado (${dirAtual.path}): $e');
        continue;
      }

      for (final entity in entidades) {
        if (entity is Directory) {
          final nomeDir = entity.path.split(RegExp(r'[/\\]')).last.toLowerCase();
          // Ignora pastas internas do sistema/git
          if (!nomeDir.startsWith('.') && nomeDir != '\$recycle.bin') {
            filaDiretorios.add(entity);
          }
        } else if (entity is File) {
          try {
            final nome = entity.path.split(RegExp(r'[/\\]')).last;
            if (!filtroNome(nome)) continue;

            final bytes = await entity.readAsBytes();
            if (bytes.isNotEmpty) {
              resultado.add(ArquivoLido(
                nome: nome,
                caminho: entity.path,
                bytes: bytes,
              ));
            }
          } catch (e) {
            debugPrint('Aviso: Falha ao ler arquivo ${entity.path}: $e');
          }
        }
      }
    }
  } catch (e) {
    debugPrint('Erro geral ao escanear pasta nativa: $e');
  }

  return resultado;
}

Directory? _resolverDiretorioAndroid(String rawPath) {
  String decodificado = rawPath;
  try {
    decodificado = Uri.decodeFull(rawPath);
  } catch (_) {}

  final candidatos = <String>[
    decodificado,
    if (decodificado.contains('primary:'))
      '/storage/emulated/0/${decodificado.split('primary:').last}',
    if (decodificado.startsWith('/tree/raw:'))
      decodificado.replaceFirst('/tree/raw:', ''),
    if (decodificado.startsWith('raw:'))
      decodificado.replaceFirst('raw:', ''),
  ];

  for (final c in candidatos) {
    final d = Directory(c);
    if (d.existsSync()) return d;
  }

  String limpo = decodificado;
  if (limpo.contains(':')) {
    final apos = limpo.split(':').last;
    if (apos.isNotEmpty) limpo = apos;
  }
  final partes = limpo.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
  final nomeAlvo = (partes.isNotEmpty ? partes.last : '').toLowerCase();

  final raizes = [
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Downloads',
    '/storage/emulated/0/Documents',
  ];

  for (final r in raizes) {
    try {
      final rDir = Directory(r);
      if (!rDir.existsSync()) continue;
      for (final item in rDir.listSync(recursive: true, followLinks: false)) {
        if (item is Directory) {
          final n = item.path.split('/').last.toLowerCase();
          if (n == nomeAlvo) return item;
        }
      }
    } catch (_) {}
  }
  return null;
}

Future<void> salvarBytesNoCaminho(String caminho, List<int> bytes) async {
  try {
    final file = File(caminho);
    if (!file.existsSync() || file.lengthSync() == 0) {
      await file.writeAsBytes(bytes);
    }
  } catch (_) {}
}
