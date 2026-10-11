# Calorie Diary

Flutter-приложение для Android: личный дневник питания, общий каталог продуктов для приглашенных пользователей, цели и вес, локальное хранение и синхронизация Supabase.

**Статус: разработка и проверка. Готовность к ежедневному использованию и выпуск APK пока не подтверждены.** Фактические результаты записываются в [технический отчет](docs/TECHNICAL_REPORT_RU.md). В приложение не включены демонстрационные продукты или чужие API-ключи.

## Стек и проект

Flutter 3.35.7 / Dart 3.9, Riverpod, Drift/SQLite, Supabase Auth/PostgreSQL, Material 3. Публичные параметры подключения задаются при сборке, сессия хранится в Android secure storage. Для каждого Auth UUID используется отдельный файл SQLite. Все записи сначала сохраняются локально вместе с outbox; сеть не нужна для ввода после первого входа.

Каталог имеет версии, серверный аудит, именованные порции и скрытие. Дневник хранит снимок продукта: изменение карточки не меняет прошлые КБЖУ. NULL для быстрых БЖУ означает неизвестное значение. Граммы и миллилитры не конвертируются без плотности. Импортированные продукты остаются локальными до отдельного подтверждения публикации.

- `lib/domain`: расчеты, типы и валидация без Flutter/Supabase.
- `lib/data`: Drift, outbox, синхронизация, защищенная сессия, JSON backup.
- `lib/presentation`: Riverpod и экраны.
- `supabase/migrations`: серверная схема, RLS, журнал, RPC.
- `test`, `integration_test`, `scripts/server_tests.py`: автоматические проверки.
- `.github/workflows/ci.yml`: анализ, unit/server/Android проверки.
- `.github/workflows/release.yml`: подписанный release APK и проверка установки.

Подробности: [архитектура](docs/ARCHITECTURE_RU.md), [UI по референсам](docs/UI_SPEC_RU.md), [план приемки](docs/IMPLEMENTATION_PLAN_RU.md), [формулы](docs/FORMULAS_RU.md).

## Настройка нового Supabase

Создайте проект по [инструкции](docs/SUPABASE_SETUP_RU.md). Отключите публичную регистрацию, настройте email/password и почту, добавьте redirect `com.fatstar.calorie_diary://auth/recovery`.

После применения миграций пригласите два email в Auth. Через административный SQL Editor добавьте их Auth UUID:

```sql
insert into public.allowed_users(user_id)
values ('UUID-ПЕРВОГО-ПОЛЬЗОВАТЕЛЯ'), ('UUID-ВТОРОГО-ПОЛЬЗОВАТЕЛЯ');
```

Приложение получает только project URL и publishable/anon key. Service-role ключ и пароль базы не помещайте в APK или репозиторий. Проверка принадлежности и RLS выполняются на сервере независимо от HTTP-параметров клиента.

## Разработка на машине с Flutter SDK

В текущей облачной среде лимит **2 vCPU / 8 ГБ RAM / 8 ГБ диска**. Android SDK, эмулятор и сборки здесь не запускаются. Используйте существующий checkout, worktree не требуется. Все тяжелые проверки выполняются GitHub Actions.

На отдельной машине разработчика:

```sh
flutter pub get --enforce-lockfile
bash scripts/bootstrap_android.sh
dart format lib test integration_test
flutter analyze
flutter test
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLIC_KEY
```

Drift использует custom SQL и версионированный schemaVersion; генератор Dart не требуется. Схема v1 создается транзакционно Drift, будущие обновления должны включать миграции и тесты перехода. SQLite-файлы нельзя удалять при исправлении ошибок или выходе из аккаунта.

## Проверки в GitHub Actions

Push в `main`/`codex/**` или pull request запускает `Verify Calorie Diary`. На ветке реализации CI сохраняет Android scaffold, lockfile, форматирование и безопасные исправления анализатора отдельным коммитом. Отчеты доступны также в ветках `ci-results/<job>/<run>-<attempt>`: `docs/ci/*.txt`. Эти ветки не запускают новую цепочку CI.

Server job поднимает временный Supabase, применяет миграции и запускает HTTP-тесты с двумя локальными пользователями. `server_tests.py` отказывается работать с production URL. Android job использует эмулятор API 35 и тот же временный сервер. Фикстуры существуют только на CI-сервере и не включаются в приложение.

## Release-подпись и APK

В GitHub Environment `production` задайте Variables:

- `SUPABASE_URL`: HTTPS URL вашего проекта.
- `SUPABASE_ANON_KEY`: публичный ключ приложения.

В Actions Secrets этого environment:

- `DIARY_KEYSTORE_BASE64`: base64 release-keystore.
- `DIARY_STORE_PASSWORD`, `DIARY_KEY_ALIAS`, `DIARY_KEY_PASSWORD`.

Создайте ключ на своей доверенной машине, сохраните резервную копию вне GitHub и репозитория:

```sh
keytool -genkeypair -v -keystore diary-release.jks -alias diary -keyalg RSA -keysize 3072 -validity 10000
```

Пароли вводите интерактивно; не вставляйте их в shell history или чат. Без этого же ключа будущий APK не сможет обновить установленное приложение. Приватный файл исключен из Git и удаляется с runner после сборки.

Запустите вручную `Signed release APK` на ветке проекта. Он проверяет настройки, форматирование, анализ, unit-тесты, выполняет `flutter build apk --release`, проверяет подпись и устанавливает APK на эмулятор. Скачать можно из artifact `calorie-diary-signed-release`: `app-release.apk` и SHA-256. Это не публикация в Play Store.

Для повседневной приемки дополнительно проверьте на телефонах обоих пользователей вход по приглашению, холодный запуск без сети, отправку накопленных изменений, восстановление пароля, экспорт/импорт и обновление APK без потери базы. Непроверенные сценарии фиксируются в отчете; зеленый unit job сам по себе не доказывает готовность приложения.
