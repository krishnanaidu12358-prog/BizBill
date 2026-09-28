import 'dart:math' as math;

import 'package:flutter/material.dart';

/// BizBill's loading spinner: a gold coin that flips, a Flutter copy of this CSS:
///
///   .loader:after { content:'$'; 48px circle; background #ffd700; color #daa520;
///                   4px double border; box-shadow 2px 2px 2px 1px rgba(0,0,0,.1);
///                   animation: coin-flip 4s infinite }
///   @keyframes coin-flip { 0% rotateY(0) -> 50% rotateY(1800deg) -> 100% rotateY(3600deg) }
///
/// [size] is the coin's diameter (48 = the CSS size); everything scales with it,
/// so the same coin works full-page (48-64) and inside a button (18-22).
class CoinLoader extends StatefulWidget {
  const CoinLoader({super.key, this.size = 48, this.symbol = r'$'});

  final double size;

  /// The character on the coin.
  final String symbol;

  static const color1 = Color(0xFFFFD700); // --color-1  gold face
  static const color2 = Color(0xFFDAA520); // --color-2  goldenrod rim + symbol
  static const color3 = Color(0x1A000000); // --color-3  rgba(0,0,0,.1) shadow

  @override
  State<CoinLoader> createState() => _CoinLoaderState();
}

class _CoinLoaderState extends State<CoinLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  // Keyframe timing functions from the CSS.
  static const _firstHalf = Cubic(0.5, 0, 1, 0.5); // 0% -> 50%: speeds up
  static const _secondHalf = Cubic(0, 0.5, 0.5, 1); // 50% -> 100%: slows down
  static const _halfTurns = 1800 * math.pi / 180; // 1800deg

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _angle(double t) => t < 0.5
      ? _halfTurns * _firstHalf.transform(t / 0.5)
      : _halfTurns + _halfTurns * _secondHalf.transform((t - 0.5) / 0.5);

  @override
  Widget build(BuildContext context) {
    final u = widget.size / 48; // CSS --size unit
    final line = 4 * u / 3; // "4px double" = line, gap, line

    final coin = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: CoinLoader.color1,
        border: Border.all(color: CoinLoader.color2, width: line),
        boxShadow: [
          BoxShadow(
            color: CoinLoader.color3,
            offset: Offset(2 * u, 2 * u),
            blurRadius: 2 * u,
            spreadRadius: 1 * u,
          ),
        ],
      ),
      padding: EdgeInsets.all(line),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: CoinLoader.color2, width: line),
        ),
        alignment: Alignment.center,
        child: Text(
          widget.symbol,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: 32 * u,
            height: 1,
            fontWeight: FontWeight.bold,
            color: CoinLoader.color2,
          ),
        ),
      ),
    );

    return Semantics(
      label: 'Loading',
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          child: coin,
          builder: (_, child) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(_angle(_c.value)),
            child: child,
          ),
        ),
      ),
    );
  }
}
