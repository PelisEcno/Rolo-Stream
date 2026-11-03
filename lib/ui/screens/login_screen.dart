import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.signInWithGoogle();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = AuthService.instance.firebaseReady;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.7),
            radius: 1.1,
            colors: [Color(0x55E50914), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text.rich(
                      TextSpan(children: [
                        TextSpan(text: 'ROLO', style: TextStyle(color: AppColors.primary)),
                        TextSpan(text: 'STREAM'),
                      ]),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 12),
                    const Text('Tus series, películas y canales en un solo lugar.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 15, height: 1.35)),
                    const SizedBox(height: 40),
                    if (ready)
                      _GoogleButton(busy: _busy, onPressed: _google)
                    else ...[
                      const Text(
                        'El inicio de sesión aún no está disponible en esta versión. '
                        'Tus datos se guardarán solo en este dispositivo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted, height: 1.35),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: AuthService.instance.continueWithoutAccount,
                        child: const Text('CONTINUAR SIN CUENTA'),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.accentRed, height: 1.35)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onPressed;
  const _GoogleButton({required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.button),
        boxShadow: AppShadows.soft,
      ),
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F1F1F),
          disabledBackgroundColor: Colors.white70,
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5))
            else
              const CustomPaint(size: Size.square(22), painter: _GoogleLogoPainter()),
            const SizedBox(width: 12),
            const Text('Continuar con Google'),
          ],
        ),
      ),
    );
  }
}

/// La "G" de cuatro colores de Google.
class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.2;
    final rect = Rect.fromCircle(
        center: size.center(Offset.zero), radius: (size.width - stroke) / 2);
    Paint color(int c) => Paint()
      ..color = Color(c)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    double deg(double d) => d * math.pi / 180;

    canvas.drawArc(rect, deg(-45), deg(-90), false, color(0xFFEA4335));
    canvas.drawArc(rect, deg(-135), deg(-90), false, color(0xFFFBBC05));
    canvas.drawArc(rect, deg(135), deg(-90), false, color(0xFF34A853));
    canvas.drawArc(rect, deg(45), deg(-45), false, color(0xFF4285F4));
    canvas.drawRect(
      Rect.fromLTWH(size.width / 2, size.height / 2 - stroke / 2, size.width / 2, stroke),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
