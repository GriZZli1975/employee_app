# Приложение сотрудников Stoox

Репозиторий: https://github.com/GriZZli1975/employee_app

Flutter (Android + iOS). Вход только через Stoox: хост, ключ компании и PC-ключ (QR или вставка). Медиа осмотра и диагностики уходят в Yandex через этого бота — `WEBHOOK_SECRET` на телефон не кладётся.

## Обновления приложения

При старте после входа приложение смотрит **GitHub Releases** репозитория `employee_app` и предлагает скачать новый APK, если версия новее.

Полный процесс (сборка → tag → APK → release): **[RELEASE.md](RELEASE.md)**.

Кратко: поднять `version` в `pubspec.yaml` → `flutter build apk --release` → Release с tag `v1.0.14+16` и прикреплённым `.apk`.

## Сборка

Нужен Flutter SDK (`C:\flutter` или свой PATH).

```bash
cd mobile/stoox_employee_app
flutter pub get
flutter run
```

Release APK:

```bash
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

## Вход

1. Хост, например `fo.stoox.ru` (нормализуется в `https://fo.stoox.ru`).
2. Ключ компании — заголовок `key` копии Stoox.
3. PC-ключ сотрудника: вставка или QR из профиля Stoox.
4. URL сервиса бота подтягивается из `/bot/get-options`. Если там `t.me` или пусто — укажите Railway вручную (`https://xxx.up.railway.app`). В Stoox удобно прописать тот же адрес в `OPTION_TELEGRAM_BOT_URL` (не ссылку t.me).

## После входа

Список **В работе** из MCP. По авто:

- работы заказ-наряда
- осмотр (`kind=inspection`)
- диагностика (`kind=diagnostics`)
- ИИ-чат (`POST /api/ai/chat`)

Каждый файл сразу: `POST {BOT}/api/media` с заголовками `X-Stoox-Host`, `X-Pc-Key`, `X-Stoox-Key`.
