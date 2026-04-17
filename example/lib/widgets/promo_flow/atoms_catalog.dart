import 'package:flutter/material.dart';
import 'theme/promo_colors.dart';
import 'theme/promo_spacing.dart';
import 'atoms/card_shell.dart';
import 'atoms/card_header.dart';
import 'atoms/icon_badge.dart';
import 'atoms/status_badge.dart';
import 'atoms/metric_value.dart';
import 'atoms/delta_indicator.dart';
import 'atoms/gauge_arc.dart';
import 'atoms/progress_bar.dart';
import 'atoms/alert_item.dart';
import 'atoms/count_badge.dart';
import 'atoms/navigation_arrow_button.dart';
import 'atoms/filter_chip_row.dart';
import 'atoms/live_badge.dart';
import 'atoms/metric_pair.dart';

class AtomsCatalog extends StatelessWidget {
  const AtomsCatalog({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PromoColors.surfaceSecondary,
      child: SingleChildScrollView(
        padding: PromoSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('A1. CardShell'),
            const CardShell(child: Text('Basic card shell')),
            const SizedBox(height: PromoSpacing.lg),
            CardShell(
              borderColor: PromoColors.danger,
              borderWidth: 2,
              child: const Text('Card with colored border'),
            ),

            _sectionTitle('A2. CardHeader'),
            const CardShell(
              child: CardHeader(
                title: 'Faturamento',
                icon: Icons.attach_money,
                iconColor: PromoColors.primary,
                trailing: StatusBadge.neutral('vs meta'),
              ),
            ),
            const SizedBox(height: PromoSpacing.lg),
            CardShell(
              child: CardHeader(
                title: 'Calendário Comercial',
                subtitle: 'Abril 2026',
                icon: Icons.calendar_today_outlined,
                iconColor: PromoColors.primary,
                trailing: NavigationArrowButton(),
              ),
            ),

            _sectionTitle('A3. IconBadge'),
            Wrap(
              spacing: PromoSpacing.md,
              runSpacing: PromoSpacing.md,
              children: const [
                IconBadge(icon: Icons.attach_money, color: PromoColors.primary),
                IconBadge(icon: Icons.shield_outlined, color: PromoColors.danger),
                IconBadge(icon: Icons.warning_amber_rounded, color: PromoColors.warning),
                IconBadge(icon: Icons.store_outlined, color: PromoColors.brown),
                IconBadge(icon: Icons.gps_fixed, color: PromoColors.primary),
                IconBadge(icon: Icons.check_circle_outline, color: PromoColors.success),
              ],
            ),

            _sectionTitle('A4. StatusBadge'),
            Wrap(
              spacing: PromoSpacing.sm,
              runSpacing: PromoSpacing.sm,
              children: const [
                StatusBadge.positive('+8%'),
                StatusBadge.negative('-29%'),
                StatusBadge.neutral('vs meta'),
                StatusBadge(label: 'Semanal', variant: BadgeVariant.info),
              ],
            ),

            _sectionTitle('A5. GaugeArc'),
            Row(
              children: [
                Expanded(
                  child: CardShell(
                    child: Column(
                      children: [
                        GaugeArc(percentage: 72, label: 'Faltam R\$ 280k'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: PromoSpacing.md),
                Expanded(
                  child: CardShell(
                    child: Column(
                      children: [
                        GaugeArc(
                          percentage: 32,
                          label: 'Bloqueados',
                          color: PromoColors.gaugeRed,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            _sectionTitle('A6. ProgressBar'),
            CardShell(
              child: Column(
                children: [
                  ProgressBar(
                    progress: 0.72,
                    label: 'Faturamento',
                    trailingLabel: 'R\$ 720k / R\$ 1Mi',
                  ),
                  const SizedBox(height: PromoSpacing.lg),
                  ProgressBar(
                    progress: 0.32,
                    color: PromoColors.gaugeRed,
                    label: 'Bloqueados',
                    trailingLabel: '32%',
                  ),
                  const SizedBox(height: PromoSpacing.lg),
                  ProgressBar(progress: 0.89, color: PromoColors.gaugeGreen),
                ],
              ),
            ),

            _sectionTitle('A7. MetricValue'),
            Row(
              children: [
                Expanded(
                  child: CardShell(
                    child: MetricValue(
                      value: 'R\$ 720k',
                      unit: '/ R\$ 1Mi',
                      label: 'Faturamento',
                      size: MetricSize.large,
                    ),
                  ),
                ),
                const SizedBox(width: PromoSpacing.md),
                const Expanded(
                  child: CardShell(
                    child: MetricValue(
                      value: '68',
                      label: 'Pedidos bloqueados',
                      size: MetricSize.medium,
                    ),
                  ),
                ),
              ],
            ),

            _sectionTitle('A8. DeltaIndicator'),
            CardShell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  DeltaIndicator(
                    value: '15 pedidos',
                    isPositive: true,
                    percentage: '30.2%',
                    subtitle: 'vs mês anterior',
                  ),
                  SizedBox(height: PromoSpacing.lg),
                  DeltaIndicator(
                    value: 'R\$ 25.267',
                    isPositive: false,
                    percentage: '29%',
                    subtitle: 'vs ideal',
                  ),
                ],
              ),
            ),

            _sectionTitle('A9. MetricPair'),
            CardShell(
              child: MetricPair(
                items: const [
                  MetricPairItem(
                    label: 'Vendas',
                    value: '1.304',
                    delta: '3.5% ↗',
                    deltaPositive: true,
                  ),
                  MetricPairItem(
                    label: 'Receita',
                    value: 'R\$ 21.1k',
                    delta: '4.5% ↘',
                    deltaPositive: false,
                  ),
                ],
              ),
            ),

            _sectionTitle('A10. AlertItem'),
            CardShell(
              child: Column(
                children: const [
                  AlertItem(
                    message: '3 clientes inadimplentes com valor total de R\$ 33.249',
                    severity: AlertSeverity.critical,
                  ),
                  SizedBox(height: PromoSpacing.sm),
                  AlertItem(
                    message: '15 pedidos bloqueados aguardando liberação',
                    severity: AlertSeverity.warning,
                  ),
                  SizedBox(height: PromoSpacing.sm),
                  AlertItem(
                    message: 'Meta de positivação a 35% — faltam 322 lojas',
                    severity: AlertSeverity.success,
                  ),
                ],
              ),
            ),

            _sectionTitle('A23. FilterChipRow'),
            const FilterChipRow(
              labels: ['Todos os pedidos', 'Bloqueados', 'Processando', 'Pedidos atrasados', 'Entregue'],
              selectedIndex: 0,
            ),
            const SizedBox(height: PromoSpacing.md),
            const FilterChipRow(
              labels: ['Hoje', 'Semana', 'Mês'],
              selectedIndex: 2,
            ),

            _sectionTitle('A20. LiveBadge'),
            const LiveBadge(),

            _sectionTitle('A25. NavigationArrowButton + A26. CountBadge'),
            Row(
              children: const [
                NavigationArrowButton(),
                SizedBox(width: PromoSpacing.lg),
                CountBadge(count: 4, color: PromoColors.danger),
                SizedBox(width: PromoSpacing.sm),
                CountBadge(count: 2, color: PromoColors.primary),
              ],
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Text(
        title,
        style: PromoTypography.titleMedium.copyWith(
          color: PromoColors.textPrimary,
        ),
      ),
    );
  }
}
