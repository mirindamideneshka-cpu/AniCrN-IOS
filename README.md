# AniCrN iOS

Начальный перенос Android AniCrN на SwiftUI + Rust. iOS 16+.

Swift: URLSession, интерфейс каталога/поиска/серий, AVPlayer.
Rust: нормализация ответа каталога AniLiberty через C ABI с явным освобождением памяти.
Контракты и адреса взяты из Android AniLibertyProvider в архиве от 2026-11-01.

## IPA для Sideloadly

GitHub Actions → Build IPA → Run workflow. Скачайте артефакт
`AniCrN-unsigned`, распакуйте ZIP и откройте IPA в Sideloadly для подписи и установки.
Workflow также запускается при push. Apple-сертификаты в репозитории не нужны.

На macOS: установить Rust и XcodeGen, выполнить команды из `.github/workflows/ipa.yml`.
Сейчас конфигурация линковки рассчитана на физический iPhone arm64.

## Состояние переноса

Реализован первый исходный сценарий: каталог AniLiberty → поиск → серии → HLS.
Это начальная реализация: сборку Xcode и воспроизведение на устройстве ещё нужно проверить.
Избранное, история/прогресс, остальные провайдеры, расширенные настройки,
Android mpv/шейдеры и обработка заголовков HLS ещё не перенесены.
Rust-тесты выполняются в CI; на текущем Windows Rust отсутствует в PATH.
