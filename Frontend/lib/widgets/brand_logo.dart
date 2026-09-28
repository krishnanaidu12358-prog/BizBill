import 'package:flutter/material.dart';

/// The BizBill logo. It sits on a white card so the navy/green artwork stays
/// readable in dark mode too.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.height = 150, this.markOnly = false});

  final double height;

  /// Just the "B" mark (no name / tagline) - for small places.
  final bool markOnly;

  static const full = 'assets/branding/logo_full.png';
  static const mark = 'assets/branding/logo_mark.png';

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final image = Image.asset(
      markOnly ? mark : full,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'BizBill',
    );
    if (!dark) return image;
    return Container(
      padding: EdgeInsets.all(height * 0.08),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(height * 0.14),
      ),
      child: image,
    );
  }
}
