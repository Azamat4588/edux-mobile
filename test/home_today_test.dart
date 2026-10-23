import 'package:edux/core/design.dart';
import 'package:edux/core/home_today.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('direktor: CRM bo\'yicha 4 ta karta, qarzdorlar qizil', () {
    final cards = managerToday(
      <String, dynamic>{
        'crm': <String, dynamic>{'debtors': 3, 'debt_total': 450000, 'income_today': 1200000, 'new_leads_today': 2, 'open_leads': 5, 'tasks_today': 1},
        'testing': <String, dynamic>{'open_exams': 2, 'finished_week': 10, 'needs_review': 4},
      },
      lessons: <Map<String, dynamic>>[
        <String, dynamic>{'status': 'done', 'start': '09:00', 'group': <String, dynamic>{'name': 'A1'}},
        <String, dynamic>{'status': 'planned', 'start': '14:00', 'group': <String, dynamic>{'name': 'B2'}},
      ],
    );
    expect(cards.map((card) => card.key).toList(), <String>['debtors', 'income', 'lessons', 'leads']);
    expect(cards.first.tone, TodayTone.danger);
    expect(cards.first.value, '3');
    expect(cards.first.target, 'crm.debtors');
    expect(cards[2].hint, contains('14:00'));
    expect(cards[3].tone, TodayTone.warning);
  });

  test('direktor CRMsiz: testlar va varaqalar', () {
    final cards = managerToday(<String, dynamic>{'testing': <String, dynamic>{'open_exams': 1, 'finished_week': 0, 'needs_review': 2}});
    expect(cards.map((card) => card.key).toList(), <String>['review', 'exams']);
  });

  test('kassir va marketolog', () {
    final cashier = cashierToday(<String, dynamic>{'summary': <String, dynamic>{'amount': 300000, 'count': 2}}, <String, dynamic>{'count': 0, 'total_debt': 0});
    expect(cashier.first.tone, TodayTone.success);
    expect(cashier.last.tone, TodayTone.success);
    final marketer = marketerToday(<String, dynamic>{'new': 4, 'enrolled': 1});
    expect(marketer.map((card) => card.value).toList(), <String>['4', '0', '0', '1']);
  });

  test('o\'quvchi: qarz, testlar, uy vazifasi, keyingi dars', () {
    final cards = studentToday(
      <String, dynamic>{
        'crm': <String, dynamic>{'balance': -150000, 'attendance_30d': <String, dynamic>{'absent': 1}},
        'testing': <String, dynamic>{'pending': <dynamic>[1, 2], 'average_percent': null},
        'lms': <String, dynamic>{'assignments': <String, dynamic>{'pending': <dynamic>[<String, dynamic>{'overdue': true}]}},
      },
      upcoming: <Map<String, dynamic>>[<String, dynamic>{'start': '15:00', 'group': 'IELTS', 'date': '2026-10-23'}],
    );
    expect(cards.map((card) => card.key).toList(), <String>['balance', 'tests', 'homework', 'next']);
    expect(cards.first.tone, TodayTone.danger);
    expect(cards[2].tone, TodayTone.danger);
    final guardian = studentToday(<String, dynamic>{'crm': <String, dynamic>{'balance': 0, 'attendance_30d': <String, dynamic>{'absent': 0}}}, guardian: true);
    expect(guardian.map((card) => card.key).toList(), <String>['balance', 'attendance']);
    expect(guardian.first.target, 'child.payments');
  });

  test('tezkor harakatlar: ko\'pi bilan 6 ta, asosiysi birinchi', () {
    final all = <String>{'crm', 'take_payments', 'students', 'attendance', 'leads', 'testing', 'scan', 'lms_staff'};
    final actions = quickActions('director', all.contains);
    expect(actions.length, 6);
    expect(actions.first.key, 'payment.take');
    expect(actions.first.primary, isTrue);
    final student = quickActions('student', <String>{'testing', 'crm'}.contains, debt: true);
    expect(student.map((item) => item.key).toList(), <String>['my', 'pay']);
    expect(student.last.primary, isTrue);
  });
}
