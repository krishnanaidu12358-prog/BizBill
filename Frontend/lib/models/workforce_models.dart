// Workers (HRMS): staff, attendance, advances, salary and who-sold-what.

double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();
int _i(dynamic v) => v == null ? 0 : (v as num).toInt();

const attendanceStatuses = ['Present', 'HalfDay', 'Absent', 'Leave', 'WeekOff'];

String attendanceLabel(String? s) => switch (s) {
      'Present' => 'Present',
      'HalfDay' => 'Half day',
      'Absent' => 'Absent',
      'Leave' => 'Leave',
      'WeekOff' => 'Week off',
      _ => 'Not marked',
    };

/// Short code for the month grid: P, H, A, L, W.
String attendanceCode(String? s) => switch (s) {
      'Present' => 'P',
      'HalfDay' => 'H',
      'Absent' => 'A',
      'Leave' => 'L',
      'WeekOff' => 'W',
      _ => '-',
    };

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// yyyy-MM-dd, the format the API uses for calendar days.
String apiDay(DateTime d) => _day(d);

class Worker {
  Worker({
    required this.id,
    required this.name,
    required this.mobile,
    required this.salaryType,
    required this.salaryAmount,
    required this.joinDate,
    required this.canGiveUdhaar,
    required this.isActive,
    required this.hasLogin,
    required this.loginActive,
    this.designation,
    this.address,
    this.todayStatus,
    this.todayCheckIn,
    this.todayCheckOut,
    this.outstandingAdvance = 0,
  });

  final int id;
  final String name;
  final String mobile;
  final String? designation;
  final String salaryType;
  final double salaryAmount;
  final String joinDate;
  final String? address;
  final bool canGiveUdhaar;
  final bool isActive;
  final bool hasLogin;
  final bool loginActive;
  final String? todayStatus;
  final String? todayCheckIn;
  final String? todayCheckOut;
  final double outstandingAdvance;

  bool get isDaily => salaryType == 'Daily';

  factory Worker.fromJson(Map<String, dynamic> j) => Worker(
        id: _i(j['id']),
        name: j['name'] ?? '',
        mobile: j['mobile'] ?? '',
        designation: j['designation'],
        salaryType: j['salaryType'] ?? 'Monthly',
        salaryAmount: _d(j['salaryAmount']),
        joinDate: j['joinDate'] ?? '',
        address: j['address'],
        canGiveUdhaar: j['canGiveUdhaar'] == true,
        isActive: j['isActive'] == true,
        hasLogin: j['hasLogin'] == true,
        loginActive: j['loginActive'] == true,
        todayStatus: j['todayStatus'],
        todayCheckIn: j['todayCheckIn'],
        todayCheckOut: j['todayCheckOut'],
        outstandingAdvance: _d(j['outstandingAdvance']),
      );
}

class AttendanceRow {
  AttendanceRow({
    required this.workerId,
    required this.workerName,
    required this.workDate,
    this.designation,
    this.status,
    this.checkIn,
    this.checkOut,
    this.note,
  });

  final int workerId;
  final String workerName;
  final String? designation;
  final String workDate;
  String? status;
  final String? checkIn;
  final String? checkOut;
  String? note;

  DateTime get date => DateTime.parse(workDate);

  factory AttendanceRow.fromJson(Map<String, dynamic> j) => AttendanceRow(
        workerId: _i(j['workerId']),
        workerName: j['workerName'] ?? '',
        designation: j['designation'],
        workDate: j['workDate'] ?? '',
        status: j['status'],
        checkIn: j['checkIn'],
        checkOut: j['checkOut'],
        note: j['note'],
      );
}

class AttendanceMonth {
  AttendanceMonth({
    required this.workerId,
    required this.workerName,
    required this.year,
    required this.month,
    required this.daysInMonth,
    required this.present,
    required this.halfDay,
    required this.absent,
    required this.leave,
    required this.weekOff,
    required this.notMarked,
    required this.days,
  });

  final int workerId;
  final String workerName;
  final int year;
  final int month;
  final int daysInMonth;
  final double present;
  final double halfDay;
  final double absent;
  final double leave;
  final double weekOff;
  final int notMarked;
  final List<AttendanceRow> days;

  factory AttendanceMonth.fromJson(Map<String, dynamic> j) => AttendanceMonth(
        workerId: _i(j['workerId']),
        workerName: j['workerName'] ?? '',
        year: _i(j['year']),
        month: _i(j['month']),
        daysInMonth: _i(j['daysInMonth']),
        present: _d(j['present']),
        halfDay: _d(j['halfDay']),
        absent: _d(j['absent']),
        leave: _d(j['leave']),
        weekOff: _d(j['weekOff']),
        notMarked: _i(j['notMarked']),
        days: ((j['days'] as List?) ?? [])
            .map((e) => AttendanceRow.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class WorkerToday {
  WorkerToday({
    required this.worker,
    required this.billsToday,
    required this.salesToday,
    required this.cashToday,
    required this.upiToday,
    required this.cardToday,
    this.status,
    this.checkIn,
    this.checkOut,
  });

  final Worker worker;
  final String? status;
  final String? checkIn;
  final String? checkOut;
  final int billsToday;
  final double salesToday;
  final double cashToday;
  final double upiToday;
  final double cardToday;

  factory WorkerToday.fromJson(Map<String, dynamic> j) => WorkerToday(
        worker: Worker.fromJson(j['worker'] as Map<String, dynamic>),
        status: j['status'],
        checkIn: j['checkIn'],
        checkOut: j['checkOut'],
        billsToday: _i(j['billsToday']),
        salesToday: _d(j['salesToday']),
        cashToday: _d(j['cashToday']),
        upiToday: _d(j['upiToday']),
        cardToday: _d(j['cardToday']),
      );
}

class WorkerAdvance {
  WorkerAdvance({
    required this.id,
    required this.amount,
    required this.advanceDate,
    required this.paymentMode,
    required this.recovered,
    required this.isCancelled,
    this.note,
  });

  final int id;
  final double amount;
  final String advanceDate;
  final String paymentMode;
  final String? note;
  final bool recovered;
  final bool isCancelled;

  factory WorkerAdvance.fromJson(Map<String, dynamic> j) => WorkerAdvance(
        id: _i(j['id']),
        amount: _d(j['amount']),
        advanceDate: j['advanceDate'] ?? '',
        paymentMode: j['paymentMode'] ?? 'Cash',
        note: j['note'],
        recovered: j['recovered'] == true,
        isCancelled: j['isCancelled'] == true,
      );
}

class Payroll {
  Payroll({
    required this.workerId,
    required this.workerName,
    required this.year,
    required this.month,
    required this.salaryType,
    required this.salaryAmount,
    required this.daysInMonth,
    required this.presentDays,
    required this.halfDays,
    required this.leaveDays,
    required this.absentDays,
    required this.notMarkedDays,
    required this.payableDays,
    required this.grossPay,
    required this.bonus,
    required this.otherDeductions,
    required this.advanceDeducted,
    required this.outstandingAdvance,
    required this.netPay,
    required this.isPaid,
    this.id,
    this.designation,
    this.paidOn,
    this.paymentMode,
    this.note,
  });

  final int? id;
  final int workerId;
  final String workerName;
  final String? designation;
  final int year;
  final int month;
  final String salaryType;
  final double salaryAmount;
  final int daysInMonth;
  final double presentDays;
  final double halfDays;
  final double leaveDays;
  final double absentDays;
  final int notMarkedDays;
  final double payableDays;
  final double grossPay;
  final double bonus;
  final double otherDeductions;
  final double advanceDeducted;
  final double outstandingAdvance;
  final double netPay;
  final bool isPaid;
  final String? paidOn;
  final String? paymentMode;
  final String? note;

  factory Payroll.fromJson(Map<String, dynamic> j) => Payroll(
        id: j['id'] == null ? null : _i(j['id']),
        workerId: _i(j['workerId']),
        workerName: j['workerName'] ?? '',
        designation: j['designation'],
        year: _i(j['year']),
        month: _i(j['month']),
        salaryType: j['salaryType'] ?? 'Monthly',
        salaryAmount: _d(j['salaryAmount']),
        daysInMonth: _i(j['daysInMonth']),
        presentDays: _d(j['presentDays']),
        halfDays: _d(j['halfDays']),
        leaveDays: _d(j['leaveDays']),
        absentDays: _d(j['absentDays']),
        notMarkedDays: _i(j['notMarkedDays']),
        payableDays: _d(j['payableDays']),
        grossPay: _d(j['grossPay']),
        bonus: _d(j['bonus']),
        otherDeductions: _d(j['otherDeductions']),
        advanceDeducted: _d(j['advanceDeducted']),
        outstandingAdvance: _d(j['outstandingAdvance']),
        netPay: _d(j['netPay']),
        isPaid: j['isPaid'] == true,
        paidOn: j['paidOn'],
        paymentMode: j['paymentMode'],
        note: j['note'],
      );
}

class WorkerSalesRow {
  WorkerSalesRow({
    required this.name,
    required this.bills,
    required this.cancelledBills,
    required this.sales,
    required this.collected,
    required this.udhaar,
    required this.cash,
    required this.upi,
    required this.card,
    required this.cardInternational,
    required this.other,
    required this.averageBill,
    this.workerId,
    this.designation,
  });

  final int? workerId;
  final String name;
  final String? designation;
  final int bills;
  final int cancelledBills;
  final double sales;
  final double collected;
  final double udhaar;
  final double cash;
  final double upi;
  final double card;
  final double cardInternational;
  final double other;
  final double averageBill;

  bool get isOwner => workerId == null;

  factory WorkerSalesRow.fromJson(Map<String, dynamic> j) => WorkerSalesRow(
        workerId: j['workerId'] == null ? null : _i(j['workerId']),
        name: j['name'] ?? '',
        designation: j['designation'],
        bills: _i(j['bills']),
        cancelledBills: _i(j['cancelledBills']),
        sales: _d(j['sales']),
        collected: _d(j['collected']),
        udhaar: _d(j['udhaar']),
        cash: _d(j['cash']),
        upi: _d(j['upi']),
        card: _d(j['card']),
        cardInternational: _d(j['cardInternational']),
        other: _d(j['other']),
        averageBill: _d(j['averageBill']),
      );
}

class WorkerSalesReport {
  WorkerSalesReport({required this.rows, required this.totalSales, required this.totalBills});

  final List<WorkerSalesRow> rows;
  final double totalSales;
  final int totalBills;

  factory WorkerSalesReport.fromJson(Map<String, dynamic> j) => WorkerSalesReport(
        rows: ((j['rows'] as List?) ?? [])
            .map((e) => WorkerSalesRow.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalSales: _d(j['totalSales']),
        totalBills: _i(j['totalBills']),
      );
}
