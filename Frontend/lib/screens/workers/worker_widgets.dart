import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../models/workforce_models.dart';
import '../../services/repo.dart';
import '../../widgets/common.dart';

Color attendanceColor(String? s) => switch (s) {
      'Present' => const Color(0xFF1B7F3B),
      'HalfDay' => const Color(0xFFB7791F),
      'Absent' => const Color(0xFFC62828),
      'Leave' => const Color(0xFF3949AB),
      'WeekOff' => const Color(0xFF6B7280),
      _ => const Color(0xFF9CA3AF),
    };

/// Today's status as a small coloured pill.
class AttendanceChip extends StatelessWidget {
  const AttendanceChip({super.key, this.status, this.checkIn});

  final String? status;
  final String? checkIn;

  @override
  Widget build(BuildContext context) {
    final c = attendanceColor(status);
    final time = checkIn == null ? null : DateFormat('hh:mm a').format(DateTime.parse(checkIn!).toLocal());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(attendanceLabel(status),
              style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w700)),
          if (time != null) Text(time, style: TextStyle(color: c, fontSize: 10)),
        ],
      ),
    );
  }
}

/// A month of attendance as a calendar grid with the totals underneath.
class AttendanceMonthView extends StatelessWidget {
  const AttendanceMonthView({super.key, required this.month});

  final AttendanceMonth month;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = DateTime(month.year, month.month, 1);
    final leading = first.weekday - 1; // Monday first
    final today = DateTime.now();

    final cells = <Widget>[
      for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
        Center(
            child: Text(d,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.outline))),
      for (var i = 0; i < leading; i++) const SizedBox(),
      for (final day in month.days)
        Builder(builder: (_) {
          final date = day.date;
          final future = date.isAfter(today);
          final c = attendanceColor(day.status);
          return Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: day.status == null ? null : c.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
              border: DateUtils.isSameDay(date, today) ? Border.all(color: scheme.primary, width: 1.5) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${date.day}',
                    style: TextStyle(fontSize: 11, color: future ? scheme.outlineVariant : scheme.onSurface)),
                Text(future ? '' : attendanceCode(day.status),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c)),
              ],
            ),
          );
        }),
    ];

    String n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.05,
          children: cells,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _count('Present', n(month.present), 'Present'),
            _count('Half day', n(month.halfDay), 'HalfDay'),
            _count('Leave', n(month.leave), 'Leave'),
            _count('Week off', n(month.weekOff), 'WeekOff'),
            _count('Absent', n(month.absent), 'Absent'),
            if (month.notMarked > 0) _count('Not marked', '${month.notMarked}', null),
          ],
        ),
      ],
    );
  }

  Widget _count(String label, String v, String? status) {
    final c = attendanceColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text('$label $v', style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

/// One worker's salary line for a month.
class PayrollCard extends StatelessWidget {
  const PayrollCard({super.key, required this.payroll, this.onPay, this.showName = true});

  final Payroll payroll;
  final VoidCallback? onPay;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = payroll;
    String n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          showName
                              ? p.workerName
                              : DateFormat('MMMM yyyy').format(DateTime(p.year, p.month)),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                        '${p.salaryType == 'Daily' ? '${money(p.salaryAmount)}/day' : '${money(p.salaryAmount)}/month'}'
                        '  ·  ${n(p.payableDays)} of ${p.daysInMonth} days paid',
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(money(p.netPay),
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: scheme.primary)),
                    Text(p.isPaid ? 'Paid ${dateOf(p.paidOn)}' : 'Not paid',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: p.isPaid ? const Color(0xFF1B7F3B) : scheme.error)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                'P ${n(p.presentDays)}',
                if (p.halfDays > 0) 'H ${n(p.halfDays)}',
                if (p.leaveDays > 0) 'L/W ${n(p.leaveDays)}',
                if (p.absentDays > 0) 'A ${n(p.absentDays)}',
                if (!p.isPaid && p.notMarkedDays > 0) '${p.notMarkedDays} not marked',
                'Gross ${money(p.grossPay)}',
                if (p.bonus > 0) '+ bonus ${money(p.bonus)}',
                if (p.otherDeductions > 0) '- deductions ${money(p.otherDeductions)}',
                if (p.advanceDeducted > 0) '- advance ${money(p.advanceDeducted)}',
              ].join('  ·  '),
              style: const TextStyle(fontSize: 12.5),
            ),
            if (onPay != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: onPay,
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Pay salary'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pay screen: adjust days / bonus / deductions / advance recovery, see the
/// net pay recalculated by the server, then pay. Returns true when paid.
Future<bool?> showPayDialog(BuildContext context, Repo repo, Payroll start) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _PayDialog(repo: repo, start: start),
  );
}

class _PayDialog extends StatefulWidget {
  const _PayDialog({required this.repo, required this.start});
  final Repo repo;
  final Payroll start;

  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
  late Payroll _p = widget.start;
  late final _days = TextEditingController(text: _fmt(widget.start.payableDays));
  final _bonus = TextEditingController();
  final _deduct = TextEditingController();
  late final _advance = TextEditingController(text: _fmt(widget.start.advanceDeducted));
  final _note = TextEditingController();
  String _mode = 'Cash';
  bool _busy = false;

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  void dispose() {
    _days.dispose();
    _bonus.dispose();
    _deduct.dispose();
    _advance.dispose();
    _note.dispose();
    super.dispose();
  }

  Map<String, dynamic> _body() => {
        'year': _p.year,
        'month': _p.month,
        'payableDays': double.tryParse(_days.text.trim()),
        'bonus': double.tryParse(_bonus.text.trim()) ?? 0,
        'otherDeductions': double.tryParse(_deduct.text.trim()) ?? 0,
        'advanceDeducted': double.tryParse(_advance.text.trim()) ?? 0,
        'paymentMode': _mode,
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      };

  Future<void> _recalc() async {
    try {
      final p = await widget.repo.previewPayroll(_p.workerId, _body());
      if (mounted) setState(() => _p = p);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _pay() async {
    setState(() => _busy = true);
    try {
      final msg = await widget.repo.payPayroll(_p.workerId, _body());
      if (!mounted) return;
      showSnack(context, msg);
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _num(TextEditingController c, String label, {String? helper, String? prefix}) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        onEditingComplete: _recalc,
        decoration: InputDecoration(labelText: label, helperText: helper, prefixText: prefix),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = _p;

    return AlertDialog(
      title: Text('Pay ${p.workerName}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(DateFormat('MMMM yyyy').format(DateTime(p.year, p.month)),
                  style: TextStyle(color: scheme.outline)),
              if (p.notMarkedDays > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${p.notMarkedDays} day(s) have no attendance and are counted unpaid. '
                    'Change "days paid" if they worked.',
                    style: TextStyle(fontSize: 12.5, color: scheme.error),
                  ),
                ),
              const SizedBox(height: 8),
              _num(_days, 'Days paid', helper: 'Out of ${p.daysInMonth}'),
              _num(_bonus, 'Bonus / overtime', prefix: '₹ '),
              _num(_deduct, 'Other deductions', prefix: '₹ '),
              if (p.outstandingAdvance > 0)
                _num(_advance, 'Advance to take back',
                    prefix: '₹ ', helper: 'Open advance ${money(p.outstandingAdvance)}'),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Cash', label: Text('Cash')),
                  ButtonSegment(value: 'UPI', label: Text('UPI')),
                  ButtonSegment(value: 'BankTransfer', label: Text('Bank')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)')),
              const Divider(height: 24),
              MoneyRow('Gross (${_fmt(p.payableDays)} days)', p.grossPay),
              if (p.bonus > 0) MoneyRow('Bonus', p.bonus),
              if (p.otherDeductions > 0) MoneyRow('Deductions', -p.otherDeductions),
              if (p.advanceDeducted > 0) MoneyRow('Advance recovered', -p.advanceDeducted),
              MoneyRow('Net pay', p.netPay, bold: true),
              Text('Recorded under Expenses as Salary.',
                  style: TextStyle(fontSize: 12, color: scheme.outline)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _recalc, child: const Text('Recalculate')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : () async {
            await _recalc();
            if (mounted) await _pay();
          },
          child: Text('Pay ${money(p.netPay)}'),
        ),
      ],
    );
  }
}
