# PromoFlow Component Library — Atom Analysis

Source: `https://promo-flow-pro-78.lovable.app/` → Edit → + → Biblioteca de componentes
Captured: 2026-04-12 | 45 widgets | 6 tabs (Todos, Performance, Alertas, Operação, Clientes, IA)

## Identified Atoms

These are the reusable atomic building blocks shared across multiple molecules/widgets.

### A1. CardShell
- White rounded card container with subtle shadow/border
- `border-radius: 16px`, `padding: 20px`
- Used by: ALL 45 widgets as their outer wrapper
- DS status: Exists as `Card` in theme, needs custom shape/padding

### A2. CardHeader
- Row: [IconBadge] [Title text] [trailing widget]
- Title: semibold, ~16px, dark foreground
- Trailing: optional badge, arrow button, or dropdown
- Used by: KPI Individual, Meta do Mês, Sales Overview, Alertas, Calendário, Loja Perfeita, etc.

### A3. IconBadge
- Colored circle (40x40) with centered icon (20x20)
- Background: icon color at 10-15% opacity
- Icon colors: green (primary), red (danger), orange (warning), blue (info), brown (neutral)
- Used by: Every CardHeader, alert items, timeline items
- Variants: green/$, red/shield, orange/warning, green/target, brown/store, green/check

### A4. StatusBadge (Pill)
- Small rounded pill with text
- Variants:
  - Green bg + white text → positive delta (`+8%`, `+30%`)
  - Red bg + white text → negative delta (`-29%`, `-18%`)
  - Gray bg + dark text → neutral label (`vs meta`, `Semanal`)
  - Green outline → status (`Aprovado`)
- `border-radius: 20px`, `padding: 4px 10px`, `font-size: 12px`
- Used by: KPI cards, gauge cards, Insights, approval flow

### A5. GaugeArc
- Semi-circular arc (180°) showing progress percentage
- Center text: large bold percentage
- Colors: green (>70%), orange/yellow (40-70%), red (<40%)
- Arc track: light gray
- Used by: Meta do Mês, Sales Overview, Bloqueados, Processando, Faturados, Entregues, Ruptura, Inadimplentes, Loja Perfeita

### A6. ProgressBar (Linear)
- Horizontal bar showing current vs target
- Fill color matches status (green/orange/red)
- Track: light gray
- Used by: KPI Individual (Faturamento), Verbas progress bars, Metas bars

### A7. MetricValue
- Large bold number (24-32px) + optional unit/currency
- Variants:
  - Currency: `R$ 720k`, `R$ 85.4k`
  - Count: `68`, `25`, `1.304`
  - Percentage: `72%`, `67.2%`
- Often paired with a label below
- Used by: ALL KPI and gauge widgets

### A8. DeltaIndicator
- Shows change vs previous period
- Format: `+15 pedidos` or `- R$ 25.267`
- Color: green (positive), red (negative)
- Optional percentage pill next to it
- Used by: KPI cards, Pedidos status cards, Bloqueados gauge

### A9. MetricPair (Stat Box)
- Gray rounded box with label + value
- Used in pairs side-by-side
- Labels: "Vendas", "Receita", "pedidos", "retido"
- Used by: Sales Overview, Bloqueados gauge, Faturados gauge

### A10. AlertItem
- Colored left border (red=critical, orange=warning, green=info)
- Background tint matching severity
- Icon (warning triangle) + description text
- Used by: Alertas widget (4 severity levels)

### A11. TimelineItem
- Vertical timeline with dot connector
- Icon + title + timestamp
- Optional action button (e.g., "Criar campanha relâmpago")
- Color-coded by type (red=critical, green=success, orange=warning)
- Used by: Timeline em tempo real

### A12. TaskItem (Checklist)
- Row: [checkbox/status icon] [title] [subtitle] [trailing info]
- Checkbox states: unchecked, checked (green circle), in-progress
- Optional points badge (`+50`, `+80`)
- Used by: Missões do Dia, Pendências de hoje

### A13. ListRow
- Horizontal row with multiple columns
- Used for table-like data without formal table structure
- Columns: name, address, value, status
- Optional status badge at end
- Used by: Últimos Pedidos, Top Clientes, Roteiro inteligente

### A14. ApprovalItem
- Card with title + subtitle (person, value, time)
- Two action buttons: "Aprovar" (green) + "Reprovar" (red outline)
- Used by: Fluxo de Aprovação

### A15. VerbaProgressRow
- Label + progress bar + percentage
- Optional status text below
- Used by: Verbas (Consumo), Comprovações

### A16. GanttBar
- Horizontal timeline bar with date labels
- Color-coded by campaign
- Used by: Calendário Comercial

### A17. PlanningRow
- Label + status badge (Em execução, Em aprovação, Rascunho)
- Optional progress percentage
- Used by: Planejamentos Ativos

### A18. NetworkProgressRow
- Logo/avatar + network name + percentage + progress bar
- Used by: Metas por Rede (GPA, Carrefour, Atacadão)

### A19. LeaderboardRow
- Rank badge + avatar + name + tier badge + points
- Highlighted row for "you" (current user)
- Used by: Ranking Vendedor

### A20. LiveBadge
- Green pill with "AO VIVO" text and pulse dot
- Used by: Pedido Sugerido, Oportunidades, Roteiro, Queda

### A21. ProductLineItem
- Product icon + name + quantity + price
- Used by: Pedido Sugerido (Shampoo, Cond., Body Splash)

### A22. ActionButton
- Full-width rounded button with icon + label
- Variants: primary (green bg), outline, ghost
- Used by: "Montar pedido", "Iniciar rota", "Ver plano de ação"

### A23. FilterChipRow
- Horizontal scrollable row of filter pills
- Active pill: dark bg + white text
- Inactive pill: light bg + dark text
- Used by: time filters (Hoje/Semana/Mês), order filters (Todos/Bloqueados/Processando)

### A24. SectionDivider
- Light gray horizontal line between sections
- Sometimes with padding variation
- Used by: internal section separation in cards

### A25. NavigationArrowButton
- Circular button with right-arrow icon
- Used at top-right of cards for navigation
- Used by: Loja Perfeita, Calendário Comercial, and other drill-down cards

### A26. CountBadge
- Small colored circle with number
- Red for alerts/notifications, green for counts
- Used by: Alertas (4), Timeline (2), notification bell

### A27. SparklineChart
- Small inline trend line (no axes)
- Used by: Insights, Tendência Faturamento

### A28. RankBadge
- Circular badge with rank number (1st, 2nd, 3rd, etc.)
- Gold/silver/bronze colors for top 3
- Used by: Ranking Vendedor, Top Clientes

### A29. TierBadge
- Label pill showing tier: "Diamante", "Ouro"
- Color-coded by tier
- Used by: Ranking Vendedor (Leaderboard)

## Existing DS Components (example project)

| Atom | Existing? | Location | Notes |
|------|-----------|----------|-------|
| CardShell | Partial | `theme.dart` (CardTheme) | Needs PromoFlow-specific padding/radius |
| StatsCard | Yes | `widgets/stats_card.dart` | Similar to MetricValue + IconBadge but not decomposed |
| All others | No | — | Need to be created |

## Implementation Priority

**Phase 1 — Foundation atoms (used by 10+ widgets):**
1. CardShell (A1)
2. CardHeader (A2)
3. IconBadge (A3)
4. StatusBadge (A4)
5. MetricValue (A7)
6. DeltaIndicator (A8)

**Phase 2 — Chart atoms (used by 8+ gauge/chart widgets):**
7. GaugeArc (A5)
8. ProgressBar (A6)
9. SparklineChart (A27)

**Phase 3 — List atoms (used by 5+ list/table widgets):**
10. ListRow (A13)
11. AlertItem (A10)
12. TimelineItem (A11)
13. TaskItem (A12)

**Phase 4 — Specialized atoms:**
14-29. Remaining atoms as needed per widget
