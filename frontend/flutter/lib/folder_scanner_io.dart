import 'dart:io';

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

Future<List<ArquivoLido>> escanearPastaNativa(
  String caminhoEscolhido,
  bool Function(String nome) filtroNome,
) async {
  final resultado = <ArquivoLido>[];
  try {
    Directory? dirAlvo;
    final dirDireto = Directory(caminhoEscolhido);
    if (dirDireto.existsSync()) {
      dirAlvo = dirDireto;
    }

    if (dirAlvo == null && Platform.isAndroid) {
      dirAlvo = _resolverDiretorioAndroid(caminhoEscolhido, filtroNome);
    }

    if (dirAlvo == null || !dirAlvo.existsSync()) return resultado;

    final entidades = dirAlvo.listSync(recursive: true, followLinks: false);
    for (final entity in entidades) {
      if (entity is File) {
        try {
          final nome = entity.path.split(RegExp(r'[/\\]')).last;
          if (!filtroNome(nome)) continue;

          final bytes = await entity.readAsBytes();
          resultado.add(ArquivoLido(
            nome: nome,
            caminho: entity.path,
            bytes: bytes,
          ));
        } catch (_) {}
      }
    }
  } catch (_) {}
  return resultado;
}

Directory? _resolverDiretorioAndroid(
  String rawPath,
  bool Function(String nome) filtroNome,
) {
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

  Directory? fallbackComHtml;

  for (final r in raizes) {
    try {
      final rDir = Directory(r);
      if (!rDir.existsSync()) continue;
      for (final item in rDir.listSync(recursive: true, followLinks: false)) {
        if (item is Directory) {
          final n = item.path.split('/').last.toLowerCase();
          if (n == nomeAlvo) return item;
        } else if (item is File && fallbackComHtml == null) {
          final nomeArq = item.path.split('/').last;
          if (filtroNome(nomeArq)) {
            fallbackComHtml = item.parent.parent;
          }
        }
      }
    } catch (_) {}
  }
  return fallbackComHtml;
}