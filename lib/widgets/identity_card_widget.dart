import 'package:flutter/material.dart';
import 'package:wallet/models/identity_card.dart';
import 'package:wallet/models/card_color_data.dart';

class IdentityCardWidget extends StatelessWidget {
  final IdentityCard card;
  final VoidCallback onTap;

  const IdentityCardWidget({
    super.key,
    required this.card,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorKey = card.color ?? (isDark ? '#0F0F0F' : '#1E293B');
    final colorData = CardColorData.fromHexOrKey(colorKey, isDark: isDark);
    
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 1.586, // Standard ID card ratio
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorData.accent,
                colorData.secondary,
                colorData.primary,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.05),
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                // Minimal Watermark Icon
                Positioned(
                  right: -20,
                  bottom: -20,
                  child: Icon(
                    Icons.security_rounded,
                    size: 140,
                    color: Colors.white.withValues(alpha: 0.03),
                  ),
                ),
                
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Elegant Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                card.cardType.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(
                            Icons.nfc_rounded,
                            size: 20,
                            color: Colors.white24,
                          ),
                        ],
                      ),

                      // Name and document number, aligned to the bottom of
                      // the card. The card has a fixed ID-card shape, so if
                      // this section doesn't fit (long name, small screen or
                      // large system font) it is scaled down to fit instead
                      // of being cut off.
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) => Align(
                            alignment: Alignment.bottomLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.bottomLeft,
                              child: SizedBox(
                                width: constraints.maxWidth,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Cardholder Name
                                    const Text(
                                      'NAME',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                        color: Colors.white38,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    // At most two lines; the full name is
                                    // shown on the details screen.
                                    Text(
                                      card.name.toUpperCase(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w300,
                                        letterSpacing: 0.5,
                                        color: Colors.white,
                                      ),
                                    ),

                                    const SizedBox(height: 24),

                                    // ID Number
                                    const Text(
                                      'DOCUMENT NUMBER',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                        color: Colors.white38,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    // Always shown in full on one line (never
                                    // cut off); long numbers are scaled down.
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        card.value,
                                        maxLines: 1,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w500,
                                          fontFamily: 'Courier',
                                          letterSpacing: 1.5,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
