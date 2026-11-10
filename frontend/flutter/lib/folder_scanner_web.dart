//ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

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
  return [];
}

Future<List<int>> lerArquivoNativoPorCaminho(String caminho) async {
  return [];
}

/// Abre o seletor nativo de pastas do navegador (`webkitdirectory`) na Web,
/// permitindo anexar uma pasta inteira cheia de HTMLs (incluindo subpastas) de uma só vez.
Future<List<ArquivoLido>> selecionarPastaWeb(
  bool Function(String nome) filtroNome,
) async {
  final completer = Completer<List<ArquivoLido>>();
  final input = html.FileUploadInputElement()..multiple = true;
  input.setAttribute('webkitdirectory', '');
  input.setAttribute('directory', '');
  input.setAttribute('mozdirectory', '');
  input.style.display = 'none';
  html.document.body?.append(input);

  bool finalizado = false;

  Future<void> processarSelecao() async {
    if (finalizado) return;
    finalizado = true;
    final files = input.files;
    final resultado = <ArquivoLido>[];
    if (files != null && files.isNotEmpty) {
      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final nome = file.name;
        if (!filtroNome(nome)) continue;

        final bytes = await _lerBytesHtmlFile(file);
        if (bytes.isNotEmpty) {
          final relPath = (file.relativePath != null && file.relativePath!.isNotEmpty)
              ? file.relativePath!
              : nome;
          resultado.add(ArquivoLido(
            nome: nome,
            caminho: relPath,
            bytes: bytes,
          ));
        }
      }
    }
    input.remove();
    if (!completer.isCompleted) {
      completer.complete(resultado);
    }
  }

  input.onChange.listen((_) => processarSelecao());
  input.addEventListener('cancel', (_) {
    if (!finalizado) {
      finalizado = true;
      input.remove();
      if (!completer.isCompleted) {
        completer.complete(<ArquivoLido>[]);
      }
    }
  });

  input.click();
  return completer.future;
}

Future<List<int>> _lerBytesHtmlFile(html.File file) {
  final completer = Completer<List<int>>();
  final reader = html.FileReader();
  reader.onLoadEnd.listen((_) {
    final result = reader.result;
    if (result is ByteBuffer) {
      completer.complete(result.asUint8List());
    } else if (result is Uint8List) {
      completer.complete(result);
    } else if (result is List<int>) {
      completer.complete(result);
    } else {
      completer.complete(<int>[]);
    }
  });
  reader.onError.listen((_) {
    if (!completer.isCompleted) completer.complete(<int>[]);
  });
  reader.readAsArrayBuffer(file);
  return completer.future;
}

Future<void> salvarBytesNoCaminho(String caminho, List<int> bytes) async {
  // Na Web o salvamento é gerenciado diretamente pelo FilePicker.saveFile
}
