import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:calorie_diary/presentation/auth_errors.dart';

void main() {
  test('recovery failures never claim login failed or expose server details', () {
    final result = authFailureMessage(
      const AuthException('private server details', statusCode: '500'),
      AuthAction.recovery,
    );
    expect(result, contains('письмо восстановления'));
    expect(result, isNot(contains('выполнить вход')));
    expect(result, isNot(contains('private server details')));
  });
  test('mail rate limits explain waiting and SMTP', () {
    final result = authFailureMessage(
      const AuthException('rate limit', statusCode: '429'),
      AuthAction.recovery,
    );
    expect(result, contains('частоту запросов'));
    expect(result, contains('SMTP'));
  });
  test('uncertain timeout warns against replacing a delivered link', () {
    expect(
      authFailureMessage(TimeoutException('network'), AuthAction.recovery),
      contains('проверьте почту перед повторной отправкой'),
    );
  });
}
