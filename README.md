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

1. **URL сервиса бота** — например `https://fo.messagebot.stoox.tech` (Miran), не ссылка `t.me`.
2. **PC-ключ** сотрудника: вставка или QR из профиля Stoox.

Хост Stoox и ключ компании приложение получает с бота: `POST /api/employee/bootstrap` с `pc_key`. Без валидного PC-ключа бот **не отдаёт** секреты — одного URL бота недостаточно злоумышленнику.

При необходимости хост/ключ можно задать вручную («Ручной хост / ключ компании»).

## После входа

Список **В работе** из MCP. По авто:

- работы заказ-наряда
- осмотр (`kind=inspection`)
- диагностика (`kind=diagnostics`)
- ИИ-чат (`POST /api/ai/chat`)

Каждый файл сразу: `POST {BOT}/api/media` с заголовками `X-Stoox-Host`, `X-Pc-Key`, `X-Stoox-Key`.
