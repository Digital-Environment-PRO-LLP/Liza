# Liza

Liza — Matrix-мессенджер от Prodamus. Безопасный, удобный и функциональный.

## Возможности

- Отправка сообщений, изображений и файлов
- Голосовые сообщения
- Отправка геолокации
- Push-уведомления
- Неограниченные приватные и публичные групповые чаты
- Публичные каналы
- Управление группами со всеми возможностями Matrix
- Тёмная тема
- Material You дизайн
- QR-коды вместо сложных Matrix ID
- Кастомные эмодзи и стикеры
- Пространства (Spaces)
- Совместимость с Element, Nheko, NeoChat и другими Matrix-клиентами
- Защищённая коммуникация
- Зашифрованный бэкап чатов
- Верификация по эмодзи и кросс-подпись

## Сборка

1. Установите [Flutter](https://flutter.dev) и [Rust](https://www.rust-lang.org/tools/install)

2. Запуск в debug-режиме: `flutter run`

3. Сборка:
```bash
flutter build apk          # Android
flutter build ios --release # iOS
flutter build macos --release # macOS
flutter build web --release   # Web (сначала ./scripts/prepare-web.sh)
flutter build linux --release # Linux
flutter build windows --release # Windows
```

## Веб-конфигурация

При деплое веб-версии можно добавить `config.json` рядом с приложением.
Пример: `config.sample.json`. Все значения опциональны.

## Сайт

https://liza.laba.pro
