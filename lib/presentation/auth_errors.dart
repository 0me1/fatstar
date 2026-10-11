import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AuthAction { login, recovery, password }

String authFailureMessage(Object error, AuthAction action) {
  if (error is AuthException && error.statusCode == '429') {
    return 'Supabase ограничил частоту запросов. Подождите несколько минут. '
        'При достижении лимита отправки писем потребуется настройка SMTP.';
  }
  if (error is TimeoutException) {
    return 'Сервер не ответил вовремя. Проверьте подключение. '
        'Если вы запросили письмо, проверьте почту перед повторной отправкой.';
  }
  if (error is ArgumentError) {
    return error.message.toString();
  }
  return switch (action) {
    AuthAction.login =>
      'Не удалось выполнить вход. Проверьте email, пароль и подключение.',
    AuthAction.recovery =>
      'Не удалось отправить письмо восстановления. Проверьте подключение '
          'и настройки почты Supabase (Authentication → Logs).',
    AuthAction.password =>
      'Не удалось сохранить пароль. Проверьте требования к паролю. '
          'Если сессия восстановления истекла, запросите новое письмо.',
  };
}
