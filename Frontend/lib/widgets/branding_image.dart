import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/branding_images.dart';

/// Shows a shop's logo or signature from the API (cached), or [placeholder].
class BrandingImage extends StatelessWidget {
  const BrandingImage({
    super.key,
    required this.url,
    this.width = 56,
    this.height = 56,
    this.placeholder,
    this.background = Colors.white,
  });

  final String? url;
  final double width;
  final double height;
  final Widget? placeholder;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return placeholder ?? const SizedBox.shrink();
    return FutureBuilder<Uint8List?>(
      future: BrandingImages.load(url),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) {
          return snap.connectionState == ConnectionState.done
              ? (placeholder ?? const SizedBox.shrink())
              : SizedBox(width: width, height: height);
        }
        return Container(
          width: width,
          height: height,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(10)),
          child: Image.memory(bytes, fit: BoxFit.contain),
        );
      },
    );
  }
}
