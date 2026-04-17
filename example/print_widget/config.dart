import 'package:flutter/material.dart';
import 'package:print_widget_flutter/print_widget.dart';
import 'package:print_widget_example/theme.dart';
import 'package:print_widget_example/widgets/promo_flow/atoms_catalog.dart';
import 'package:print_widget_example/widgets/promo_flow/theme/promo_colors.dart';
import 'package:print_widget_example/widgets/promo_flow/atoms/card_header.dart';
import 'package:print_widget_example/widgets/promo_flow/atoms/icon_badge.dart';
import 'package:print_widget_example/widgets/promo_flow/atoms/status_badge.dart';
import 'package:print_widget_example/widgets/promo_flow/atoms/metric_value.dart';
import 'package:print_widget_example/widgets/promo_flow/atoms/delta_indicator.dart';
import 'package:print_widget_example/widgets/promo_flow/atoms/gauge_arc.dart';
import 'package:print_widget_example/widgets/promo_flow/atoms/progress_bar.dart';
import 'package:print_widget_example/widgets/promo_flow/atoms/alert_item.dart';
import 'package:print_widget_example/widgets/promo_flow/atoms/count_badge.dart';
import 'package:print_widget_example/widgets/promo_flow/atoms/navigation_arrow_button.dart';
import 'package:print_widget_example/widgets/promo_flow/atoms/filter_chip_row.dart';
import 'package:print_widget_example/widgets/promo_flow/atoms/live_badge.dart';
import 'package:print_widget_example/widgets/promo_flow/atoms/metric_pair.dart';

final printSession = PrintSession(
  appWrapper: (child) => MaterialApp(
    theme: AppTheme.light,
    debugShowCheckedModeBanner: false,
    home: child,
  ),
  defaultDevice: DeviceFrame.iPhone15Pro,
  // How state names appear in output files:
  // StateOutputMode.prefix  → empty_iphone_15_pro.png  (default)
  // StateOutputMode.suffix  → iphone_15_pro_empty.png
  // StateOutputMode.folder  → empty/iphone_15_pro.png
  // stateOutputMode: StateOutputMode.prefix,
);

final printList = <PrintEntry>[
  page('promo_atoms_catalog', const AtomsCatalog()),

  widget(
    'atom_icon_badge',
    const Material(
      type: MaterialType.transparency,
      child: Wrap(
        spacing: 12,
        children: [
          IconBadge(icon: Icons.attach_money, color: PromoColors.primary),
          IconBadge(icon: Icons.shield_outlined, color: PromoColors.danger),
          IconBadge(icon: Icons.warning_amber_rounded, color: PromoColors.warning),
          IconBadge(icon: Icons.store_outlined, color: PromoColors.brown),
          IconBadge(icon: Icons.gps_fixed, color: PromoColors.primary),
          IconBadge(icon: Icons.check_circle_outline, color: PromoColors.success),
        ],
      ),
    ),
    size: const Size(320, 50),
    devices: [DeviceFrame(name: 'compact', size: Size(350, 70), pixelRatio: 2.0)],
  ),

  widget(
    'atom_status_badge',
    const Material(
      type: MaterialType.transparency,
      child: Wrap(
        spacing: 8,
        children: [
          StatusBadge.positive('+8%'),
          StatusBadge.negative('-29%'),
          StatusBadge.neutral('vs meta'),
          StatusBadge(label: 'Semanal', variant: BadgeVariant.info),
        ],
      ),
    ),
    size: const Size(380, 40),
    devices: [DeviceFrame(name: 'compact', size: Size(400, 60), pixelRatio: 2.0)],
  ),

  widget(
    'atom_gauge_arc',
    Material(
      type: MaterialType.transparency,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GaugeArc(percentage: 72, size: 120),
          SizedBox(width: 16),
          GaugeArc(percentage: 32, size: 120, color: PromoColors.gaugeRed),
          SizedBox(width: 16),
          GaugeArc(percentage: 89, size: 120, color: PromoColors.gaugeGreen),
        ],
      ),
    ),
    size: const Size(410, 90),
    devices: [DeviceFrame(name: 'compact', size: Size(430, 110), pixelRatio: 2.0)],
  ),

  widget(
    'atom_progress_bar',
    Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProgressBar(progress: 0.72, label: 'Faturamento', trailingLabel: '72%'),
            SizedBox(height: 16),
            ProgressBar(progress: 0.32, color: PromoColors.gaugeRed, label: 'Bloqueados'),
            SizedBox(height: 16),
            ProgressBar(progress: 0.89, color: PromoColors.gaugeGreen),
          ],
        ),
      ),
    ),
    size: const Size(380, 110),
    devices: [DeviceFrame(name: 'compact', size: Size(400, 130), pixelRatio: 2.0)],
  ),

  widget(
    'atom_alert_item',
    Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AlertItem(
              message: '3 clientes inadimplentes com valor total de R\$ 33.249',
              severity: AlertSeverity.critical,
            ),
            SizedBox(height: 8),
            AlertItem(
              message: '15 pedidos bloqueados aguardando liberação',
              severity: AlertSeverity.warning,
            ),
            SizedBox(height: 8),
            AlertItem(
              message: 'Meta de positivação a 35% — faltam 322 lojas',
              severity: AlertSeverity.success,
            ),
          ],
        ),
      ),
    ),
    size: const Size(440, 180),
    devices: [DeviceFrame(name: 'compact', size: Size(460, 200), pixelRatio: 2.0)],
  ),

  widget(
    'atom_delta_indicator',
    const Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          DeltaIndicator(
            value: '15 pedidos',
            isPositive: true,
            percentage: '30.2%',
            subtitle: 'vs mês anterior',
          ),
          SizedBox(height: 16),
          DeltaIndicator(
            value: 'R\$ 25.267',
            isPositive: false,
            percentage: '29%',
            subtitle: 'vs ideal',
          ),
        ],
      ),
    ),
    size: const Size(280, 120),
    devices: [DeviceFrame(name: 'compact', size: Size(310, 150), pixelRatio: 2.0)],
  ),

  widget(
    'atom_metric_pair',
    Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: 400,
        child: MetricPair(
          items: const [
            MetricPairItem(label: 'Vendas', value: '1.304', delta: '3.5% ↗', deltaPositive: true),
            MetricPairItem(label: 'Receita', value: 'R\$ 21.1k', delta: '4.5% ↘', deltaPositive: false),
          ],
        ),
      ),
    ),
    size: const Size(420, 90),
    devices: [DeviceFrame(name: 'compact', size: Size(440, 110), pixelRatio: 2.0)],
  ),

  widget(
    'atom_filter_chip_row',
    const Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilterChipRow(
            labels: ['Todos os pedidos', 'Bloqueados', 'Processando', 'Entregue'],
            selectedIndex: 0,
          ),
          SizedBox(height: 12),
          FilterChipRow(labels: ['Hoje', 'Semana', 'Mês'], selectedIndex: 2),
        ],
      ),
    ),
    size: const Size(450, 80),
    devices: [DeviceFrame(name: 'compact', size: Size(470, 110), pixelRatio: 2.0)],
  ),

  widget(
    'atom_live_badge',
    const Material(
      type: MaterialType.transparency,
      child: LiveBadge(),
    ),
    size: const Size(110, 30),
    devices: [DeviceFrame(name: 'compact', size: Size(140, 50), pixelRatio: 2.0)],
  ),

  widget(
    'atom_count_badge',
    const Material(
      type: MaterialType.transparency,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CountBadge(count: 4, color: PromoColors.danger),
          SizedBox(width: 8),
          CountBadge(count: 2, color: PromoColors.primary),
          SizedBox(width: 8),
          CountBadge(count: 15, color: PromoColors.warning),
        ],
      ),
    ),
    size: const Size(120, 30),
    devices: [DeviceFrame(name: 'compact', size: Size(150, 50), pixelRatio: 2.0)],
  ),

  widget(
    'atom_card_header',
    Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CardHeader(
              title: 'Faturamento',
              icon: Icons.attach_money,
              iconColor: PromoColors.primary,
              trailing: StatusBadge.neutral('vs meta'),
            ),
            SizedBox(height: 16),
            CardHeader(
              title: 'Calendário Comercial',
              subtitle: 'Abril 2026',
              icon: Icons.calendar_today_outlined,
              iconColor: PromoColors.primary,
              trailing: NavigationArrowButton(),
            ),
          ],
        ),
      ),
    ),
    size: const Size(420, 130),
    devices: [DeviceFrame(name: 'compact', size: Size(440, 160), pixelRatio: 2.0)],
  ),

  widget(
    'atom_metric_value',
    const Material(
      type: MaterialType.transparency,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MetricValue(value: 'R\$ 720k', unit: '/ R\$ 1Mi', label: 'Faturamento'),
          SizedBox(width: 32),
          MetricValue(value: '68', label: 'Pedidos', size: MetricSize.medium),
          SizedBox(width: 32),
          MetricValue(value: '72%', label: 'Meta', size: MetricSize.small),
        ],
      ),
    ),
    size: const Size(450, 80),
    devices: [DeviceFrame(name: 'compact', size: Size(470, 100), pixelRatio: 2.0)],
  ),
];
