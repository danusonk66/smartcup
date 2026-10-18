import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// พื้นหลังแสงน้ำ (ฟ้า + มิ้นต์) ใช้เป็นลูกแรกของ Stack เสมอ
/// เช่น Stack(children: [const AuraBackground(), ...])
class AuraBackground extends StatelessWidget {
  const AuraBackground({super.key});

  Widget _blob(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              top: -90,
              left: -70,
              child: _blob(cyanLight.withValues(alpha: 0.45), 360),
            ),
            Positioned(
              top: 360,
              right: -120,
              child: _blob(mint.withValues(alpha: 0.30), 340),
            ),
            Positioned(
              bottom: -120,
              left: -80,
              child: _blob(cyanLight.withValues(alpha: 0.25), 320),
            ),
          ],
        ),
      ),
    );
  }
}

/// สไตล์การ์ดกระจกฝ้าแบบเบา (ไม่ใช้ BackdropFilter เพื่อให้ลิสต์ยาวๆ ลื่น)
BoxDecoration glassDecoration({double radius = 24}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withValues(alpha: 0.84),
        Colors.white.withValues(alpha: 0.60),
      ],
    ),
    border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
    boxShadow: [
      BoxShadow(
        color: oceanBlue.withValues(alpha: 0.10),
        blurRadius: 24,
        offset: const Offset(0, 10),
      ),
    ],
  );
}

/// หัวข้อส่วน: จุดไล่สีฟ้า-มิ้นต์ + ข้อความ (+ ตัวท้ายถ้ามี)
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [cyanLight, mint]),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: textDark,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// ชิปไอคอนพื้นไล่สีอ่อน
class GradientIconChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
  const GradientIconChip({
    super.key,
    required this.icon,
    this.color = oceanBlue,
    this.size = 46,
    this.iconSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.24),
            color.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Icon(icon, color: color, size: iconSize),
    );
  }
}

/// ปุ่มไล่สีน้ำทะเล (onPressed เป็น null = ปิดการใช้งาน)
class GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget label;
  final Widget? icon;
  final EdgeInsetsGeometry padding;
  final bool expand;
  const GradientButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final BorderRadius br = BorderRadius.circular(16);
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: br,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [oceanBlue, Color(0xFF0A5F85)],
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: oceanBlue.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : const [],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: br,
            onTap: onPressed,
            child: Padding(
              padding: padding,
              child: IconTheme(
                data: const IconThemeData(color: Colors.white, size: 18),
                child: DefaultTextStyle(
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  child: Row(
                    mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[icon!, const SizedBox(width: 8)],
                      label,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// การ์ดน้ำทะเลลึก พร้อมคลื่นไหวเบาๆ ด้านล่าง (ใช้เป็นการ์ดหลักของแต่ละหน้า)
class DeepSeaCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  const DeepSeaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.radius = 28,
  });

  @override
  State<DeepSeaCard> createState() => _DeepSeaCardState();
}

class _DeepSeaCardState extends State<DeepSeaCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduce = MediaQuery.of(context).disableAnimations;
    final BorderRadius br = BorderRadius.circular(widget.radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: [
          BoxShadow(
            color: primaryDark.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: br,
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [oceanBlue, primaryDark],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => CustomPaint(
                    painter: _WavesPainter(reduce ? 0 : _c.value * 2 * math.pi),
                  ),
                ),
              ),
            ),
            Padding(padding: widget.padding, child: widget.child),
          ],
        ),
      ),
    );
  }
}

class _WavesPainter extends CustomPainter {
  final double phase;
  const _WavesPainter(this.phase);

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    void wave(double base, double amp, double ph, double alpha) {
      final Path p = Path()..moveTo(0, h);
      for (double x = 0; x <= w; x += 4) {
        p.lineTo(x, base + amp * math.sin(x / w * 2 * math.pi * 1.3 + ph));
      }
      p
        ..lineTo(w, h)
        ..close();
      canvas.drawPath(
        p,
        Paint()..color = Colors.white.withValues(alpha: alpha),
      );
    }

    wave(h * 0.80, 7, phase, 0.07);
    wave(h * 0.88, 6, phase + 2.1, 0.09);

    final Paint bubble = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.18);
    canvas.drawCircle(Offset(w * 0.88, h * 0.18), 14, bubble);
    canvas.drawCircle(Offset(w * 0.94, h * 0.32), 6, bubble);
    canvas.drawCircle(Offset(w * 0.82, h * 0.40), 4, bubble);
  }

  @override
  bool shouldRepaint(covariant _WavesPainter old) => old.phase != phase;
}

/// วงกลมแสดงคะแนน 0..1 ไล่สี มีแอนิเมชันตอนแสดงผล
class RingGauge extends StatelessWidget {
  final double value;
  final double size;
  final double stroke;
  final List<Color> colors;
  final Widget? child;
  const RingGauge({
    super.key,
    required this.value,
    required this.colors,
    this.size = 100,
    this.stroke = 10,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final double target = value.clamp(0.0, 1.0).toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(v, stroke, colors),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  final double stroke;
  final List<Color> colors;
  const _RingPainter(this.v, this.stroke, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = (size.width - stroke) / 2;
    final Rect rect = Rect.fromCircle(center: c, radius: r);

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = oceanBlue.withValues(alpha: 0.12),
    );
    if (v <= 0.005) return;

    final double sweep = 2 * math.pi * v;
    final List<Color> cs = colors.length > 1
        ? colors
        : [colors.first, colors.first];
    final Shader shader = SweepGradient(
      startAngle: 0,
      endAngle: 2 * math.pi,
      colors: cs,
      transform: GradientRotation(-math.pi / 2),
    ).createShader(rect);

    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 4
        ..strokeCap = StrokeCap.round
        ..color = cs.last.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.v != v || old.stroke != stroke || old.colors != colors;
}

/// วงแหวนขีด 72 ขีด สว่างไล่สีตามค่า 0..1 (ใช้กับหน้าแบตเตอรี่)
class TickRing extends StatelessWidget {
  final double value;
  final double size;
  final Color start;
  final Color end;
  final Widget? child;
  const TickRing({
    super.key,
    required this.value,
    required this.start,
    required this.end,
    this.size = 260,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final double target = value.clamp(0.0, 1.0).toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        return RepaintBoundary(
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _TickPainter(v, start, end),
              child: Center(child: child),
            ),
          ),
        );
      },
    );
  }
}

class _TickPainter extends CustomPainter {
  final double v;
  final Color start;
  final Color end;
  const _TickPainter(this.v, this.start, this.end);

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double ringR = size.width / 2 - 8;

    // แสงเรืองด้านหลัง
    canvas.drawCircle(
      c,
      ringR * 0.62,
      Paint()
        ..color = start.withValues(alpha: 0.14 + 0.16 * v)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 34),
    );
    // พื้นกระจกกลางวง
    canvas.drawCircle(
      c,
      ringR - 26,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
    canvas.drawCircle(
      c,
      ringR - 26,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.95),
    );

    const int n = 72;
    final double lit = v * n;
    final Paint off = Paint()
      ..color = oceanBlue.withValues(alpha: 0.16)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final Path glow = Path();
    for (int i = 0; i < n; i++) {
      final double a = -math.pi / 2 + i / n * 2 * math.pi;
      final Offset dir = Offset(math.cos(a), math.sin(a));
      final double inner = ringR - (i % 6 == 0 ? 17 : 11);
      final Offset p1 = c + dir * inner;
      final Offset p2 = c + dir * ringR;
      if (i < lit) {
        glow
          ..moveTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy);
        canvas.drawLine(
          p1,
          p2,
          Paint()
            ..color = Color.lerp(start, end, i / n)!
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
      } else {
        canvas.drawLine(p1, p2, off);
      }
    }
    canvas.drawPath(
      glow,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..color = start.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
  }

  @override
  bool shouldRepaint(covariant _TickPainter old) =>
      old.v != v || old.start != start || old.end != end;
}
