import 'package:flutter/material.dart';
import 'dashboard_page.dart';

class UsuarioCadastrado {
  final String nome;
  final String email;
  final String senha;
  final String cargo;
  final IconData icone;

  const UsuarioCadastrado({
    required this.nome,
    required this.email,
    required this.senha,
    required this.cargo,
    required this.icone,
  });
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();

  bool _senhaVisivel = false;
  bool _lembrarMe = true;
  bool _autenticando = false;
  String? _mensagemErro;

  /// Base de dados pré-cadastrada da SEMOB
  static const List<UsuarioCadastrado> _bancoDeUsuarios = [
    UsuarioCadastrado(
      nome: 'Diretoria Geral',
      email: 'gestor@semob.sp.gov.br',
      senha: 'semob2026',
      cargo: 'Gestor Operacional',
      icone: Icons.admin_panel_settings_rounded,
    ),
    UsuarioCadastrado(
      nome: 'Engenharia de Tráfego',
      email: 'analista@semob.sp.gov.br',
      senha: 'transporte123',
      cargo: 'Analista de Planejamento',
      icone: Icons.insights_rounded,
    ),
    UsuarioCadastrado(
      nome: 'Fiscalização de Frota',
      email: 'fiscal@semob.sp.gov.br',
      senha: 'fiscal2026',
      cargo: 'Fiscal de Campo',
      icone: Icons.fact_check_rounded,
    ),
  ];

  void _preencherCredenciaisRapidas(UsuarioCadastrado user) {
    setState(() {
      _emailController.text = user.email;
      _senhaController.text = user.senha;
      _mensagemErro = null;
    });
  }

  Future<void> _efetuarLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _autenticando = true;
      _mensagemErro = null;
    });

    await Future.delayed(const Duration(milliseconds: 500));

    final emailDigitado = _emailController.text.trim().toLowerCase();
    final senhaDigitada = _senhaController.text.trim();

    final usuarioEncontrado = _bancoDeUsuarios.cast<UsuarioCadastrado?>().firstWhere(
          (u) => u?.email.toLowerCase() == emailDigitado && u?.senha == senhaDigitada,
          orElse: () => null,
        );

    if (!mounted) return;

    if (usuarioEncontrado != null) {
      setState(() => _autenticando = false);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardPage()),
      );
    } else {
      setState(() {
        _autenticando = false;
        _mensagemErro = 'E-mail ou senha incorretos. Utilize uma credencial válida.';
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Fundo Dark Slate alinhado à AppBar
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo e Título
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0284C7).withOpacity(0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.directions_bus_filled_rounded,
                  size: 36,
                  color: Color(0xFF38BDF8),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'SEMOB • SÃO CAETANO DO SUL',
                style: TextStyle(
                  color: Color(0xFF38BDF8),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Central de Inteligência Operacional',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              // Card de Login
              Container(
                constraints: const BoxConstraints(maxWidth: 440),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Autenticação do Operador',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Insira suas credenciais corporativas para acessar o painel.',
                        style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                      ),
                      const SizedBox(height: 20),

                      // Alerta de Erro
                      if (_mensagemErro != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded, size: 18, color: Colors.red.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _mensagemErro!,
                                  style: TextStyle(fontSize: 12, color: Colors.red.shade800, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Campo E-mail
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          labelText: 'E-mail Corporativo',
                          labelStyle: const TextStyle(fontSize: 13, color: Colors.blueGrey),
                          prefixIcon: const Icon(Icons.email_outlined, size: 20, color: Color(0xFF0284C7)),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Informe o e-mail.';
                          if (!v.contains('@')) return 'E-mail inválido.';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Campo Senha
                      TextFormField(
                        controller: _senhaController,
                        obscureText: !_senhaVisivel,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          labelText: 'Senha de Acesso',
                          labelStyle: const TextStyle(fontSize: 13, color: Colors.blueGrey),
                          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: Color(0xFF0284C7)),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _senhaVisivel ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              size: 19,
                              color: Colors.blueGrey,
                            ),
                            onPressed: () => setState(() => _senhaVisivel = !_senhaVisivel),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Informe a senha.';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Lembrar-me
                      Row(
                        children: [
                          Checkbox(
                            value: _lembrarMe,
                            activeColor: const Color(0xFF0284C7),
                            visualDensity: VisualDensity.compact,
                            onChanged: (val) => setState(() => _lembrarMe = val ?? true),
                          ),
                          const Text('Lembrar neste dispositivo', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Botão Entrar
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _autenticando ? null : _efetuarLogin,
                        child: _autenticando
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Acessar Painel Operacional', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      ),

                      const SizedBox(height: 24),
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      const SizedBox(height: 18),

                      // Atalhos Rápidos para Demonstração / TV
                      const Text(
                        'Acesso Rápido para Apresentação / Demonstração:',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _bancoDeUsuarios.map((user) {
                          return ActionChip(
                            avatar: Icon(user.icone, size: 15, color: const Color(0xFF0284C7)),
                            label: Text('${user.nome} (${user.cargo})', style: const TextStyle(fontSize: 11)),
                            backgroundColor: const Color(0xFFF1F5F9),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            onPressed: () => _preencherCredenciaisRapidas(user),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
              const Text(
                'Secretaria Municipal de Mobilidade Urbana • Versão 1.0.0',
                style: TextStyle(color: Colors.blueGrey, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}