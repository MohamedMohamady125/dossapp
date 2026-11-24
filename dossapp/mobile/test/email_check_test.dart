import 'package:flutter_test/flutter_test.dart';
import 'package:aqua_athletic/widgets/email_suggestion.dart';

void main() {
  test('email slips', () {
    final cases = {
      'a@gmail.comm': 'a@gmail.com',
      'a@gmial.com': 'a@gmail.com',
      'a@gmail.con': 'a@gmail.com',
      'a@gmail.co': 'a@gmail.com',
      'a@gmail': 'a@gmail.com',
      'a@gamil.com': 'a@gmail.com',
      'a@hotmial.com': 'a@hotmail.com',
      'a@yahooo.com': 'a@yahoo.com',
      'a@gmail,com': 'a@gmail.com',
      'a @gmail.com': 'a@gmail.com',
      'a@outlok.com': 'a@outlook.com',
      'a@iclod.com': 'a@icloud.com',
    };
    cases.forEach((k, v) => expect(EmailCheck.suggestion(k), v, reason: k));
    for (final ok in ['a@gmail.com', 'a@mail.com', 'a@ymail.com', 'a@aquathletic.app', 'a@school.edu.eg', 'MAD-1091', 'a@live.com', 'a@company.com']) {
      expect(EmailCheck.suggestion(ok), null, reason: ok);
    }
    expect(EmailCheck.isValid('a@gmail'), false);
    expect(EmailCheck.isValid('a@b.co'), true);
  });
}
