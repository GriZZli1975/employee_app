import 'package:flutter_test/flutter_test.dart';
import 'package:stoox_employee_app/core/session.dart';

void main() {
  test('normalizeBotUrl strips duplicate and broken schemes', () {
    expect(
      EmployeeSession.normalizeBotUrl('http://web-production-7087e.up.railway.app'),
      'https://web-production-7087e.up.railway.app',
    );
    expect(
      EmployeeSession.normalizeBotUrl('https://http://web-production-7087e.up.railway.app'),
      'https://web-production-7087e.up.railway.app',
    );
    expect(
      EmployeeSession.normalizeBotUrl('http//web-production-7087e.up.railway.app'),
      'https://web-production-7087e.up.railway.app',
    );
    expect(
      EmployeeSession.normalizeBotUrl('web-production-7087e.up.railway.app'),
      'https://web-production-7087e.up.railway.app',
    );
  });
}
