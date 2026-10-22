import 'package:flutter/material.dart';
import 'dashboard_page.dart';
import 'login_page.dart';
import 'sessao_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SemobApp());
}

class SemobApp extends StatelessWidget {
  const SemobApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SEMOB • Monitoramento de Transporte',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0284C7),
          primary: const Color(0xFF0284C7),
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const InicializacaoSessao(),
    );
  }
}

/// Decide a tela inicial: se houver uma sessão salva e válida, abre o
/// dashboard direto; caso contrário, abre o login.
class InicializacaoSessao extends StatefulWidget {
  const InicializacaoSessao({super.key});

  @override
  State<InicializacaoSessao> createState() => _InicializacaoSessaoState();
}

class _InicializacaoSessaoState extends State<InicializacaoSessao> {
  @override
  void initState() {
    super.initState();
    _verificarSessao();
  }

  Future<void> _verificarSessao() async {
    final resultado = await SessaoService.restaurar();
    if (!mounted) return;

    final Widget destino = switch (resultado) {
      ResultadoRestauracao.restaurada => const DashboardPage(),
      ResultadoRestauracao.expirada => const LoginPage(
          mensagemInicial: 'Sua sessão expirou. Faça login novamente.',
        ),
      ResultadoRestauracao.servidorIndisponivel => const LoginPage(
          mensagemInicial: 'Não foi possível validar sua sessão: servidor indisponível.',
        ),
      ResultadoRestauracao.semSessao => const LoginPage(),
    };

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => destino),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0F172A),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
      ),
    );
  }
}
