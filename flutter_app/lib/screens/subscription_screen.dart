import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _isYearly = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Plans & Pricing',
                    style: GoogleFonts.syne(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Billing Toggle ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _BillingToggle(
                isYearly: _isYearly,
                onChanged: (v) => setState(() => _isYearly = v),
              ),
            ),

            const SizedBox(height: 20),

            // ── Plan Cards ──
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _PlanCard(
                    name: 'Free',
                    description: 'Get started with basic features',
                    monthlyPrice: 0,
                    yearlyPrice: 0,
                    isYearly: _isYearly,
                    isCurrent: true,
                    isRecommended: false,
                    features: const [
                      _Feature('Basic video calls', true),
                      _Feature('Standard captions', true),
                      _Feature('5 avatar translations / day', true),
                      _Feature('Standard TTS voice', true),
                      _Feature('Enhanced sign detection', false),
                      _Feature('Custom avatar', false),
                      _Feature('Multi-language support', false),
                    ],
                    onUpgrade: () => _showComingSoon(),
                  ),
                  const SizedBox(height: 14),
                  _PlanCard(
                    name: 'Pro',
                    description: 'For daily communicators',
                    monthlyPrice: 9.99,
                    yearlyPrice: 89.99,
                    isYearly: _isYearly,
                    isCurrent: false,
                    isRecommended: true,
                    features: const [
                      _Feature('Unlimited video calls', true),
                      _Feature('Real-time captions', true),
                      _Feature('Unlimited avatar translations', true),
                      _Feature('Enhanced TTS voices', true),
                      _Feature('Priority sign detection', true),
                      _Feature('Custom avatar', false),
                      _Feature('Multi-language support', false),
                    ],
                    onUpgrade: () => _showComingSoon(),
                  ),
                  const SizedBox(height: 14),
                  _PlanCard(
                    name: 'Premium',
                    description: 'Complete accessibility suite',
                    monthlyPrice: 19.99,
                    yearlyPrice: 179.99,
                    isYearly: _isYearly,
                    isCurrent: false,
                    isRecommended: false,
                    features: const [
                      _Feature('Unlimited video calls', true),
                      _Feature('Real-time captions', true),
                      _Feature('Unlimited avatar translations', true),
                      _Feature('Premium natural TTS voices', true),
                      _Feature('Advanced sign detection', true),
                      _Feature('Custom avatar styles', true),
                      _Feature('Multi-language support', true),
                    ],
                    onUpgrade: () => _showComingSoon(),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Subscriptions coming soon!'),
        backgroundColor: AppTheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// DATA
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _Feature {
  final String name;
  final bool included;
  const _Feature(this.name, this.included);
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SUB-WIDGETS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _BillingToggle extends StatelessWidget {
  final bool isYearly;
  final ValueChanged<bool> onChanged;

  const _BillingToggle({required this.isYearly, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: !isYearly ? AppTheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    'Monthly',
                    style: TextStyle(
                      color: !isYearly ? Colors.white : AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isYearly ? AppTheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Yearly',
                        style: TextStyle(
                          color: isYearly ? Colors.white : AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withOpacity(isYearly ? 0.3 : 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Save 25%',
                          style: TextStyle(
                            color: isYearly ? Colors.white : AppTheme.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String name;
  final String description;
  final double monthlyPrice;
  final double yearlyPrice;
  final bool isYearly;
  final bool isCurrent;
  final bool isRecommended;
  final List<_Feature> features;
  final VoidCallback onUpgrade;

  const _PlanCard({
    required this.name,
    required this.description,
    required this.monthlyPrice,
    required this.yearlyPrice,
    required this.isYearly,
    required this.isCurrent,
    required this.isRecommended,
    required this.features,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final price = isYearly ? yearlyPrice : monthlyPrice;
    final period = isYearly ? '/yr' : '/mo';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRecommended ? AppTheme.primary : AppTheme.border,
          width: isRecommended ? 2 : 1,
        ),
        boxShadow: isRecommended
            ? [BoxShadow(color: AppTheme.primary.withOpacity(0.1), blurRadius: 20)]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plan header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.syne(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (isRecommended) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'RECOMMENDED',
                              style: TextStyle(
                                color: AppTheme.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Price
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (price == 0)
                Text(
                  'Free',
                  style: GoogleFonts.syne(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                )
              else ...[
                Text(
                  '\$${price.toStringAsFixed(2)}',
                  style: GoogleFonts.syne(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    period,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
              if (isYearly && monthlyPrice > 0) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Save \$${(monthlyPrice * 12 - yearlyPrice).toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),

          // Divider
          Container(height: 1, color: AppTheme.border),

          const SizedBox(height: 16),

          // Features
          ...features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(
                      f.included ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: f.included ? AppTheme.accent : AppTheme.textDim,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        f.name,
                        style: TextStyle(
                          color: f.included ? AppTheme.textPrimary : AppTheme.textDim,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              )),

          const SizedBox(height: 8),

          // CTA Button
          SizedBox(
            width: double.infinity,
            child: isCurrent
                ? OutlinedButton(
                    onPressed: null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Current Plan'),
                  )
                : ElevatedButton(
                    onPressed: onUpgrade,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isRecommended ? AppTheme.primary : AppTheme.surfaceLight,
                      foregroundColor: isRecommended ? Colors.white : AppTheme.textPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Upgrade'),
                  ),
          ),
        ],
      ),
    );
  }
}
