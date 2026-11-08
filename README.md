# AniCrN iOS

Перенос Android AniCrN на SwiftUI + Rust, iOS 16+.

Swift отвечает за интерфейс, сеть, WKWebView и AVPlayer. Rust нормализует
каталог AniLiberty и извлекает прямые HLS/MP4 URL через C ABI.

## Сборка IPA

GitHub Actions → Build IPA → артефакт AniCrN-unsigned. Распакуйте ZIP и
откройте IPA в Sideloadly для подписи и установки. Секреты Apple для CI не нужны.
Устройство: iPhone arm64. Simulator target пока не настроен.
На macOS для локальной сборки нужны Xcode, Rust и XcodeGen; команды находятся
в .github/workflows/ipa.yml.

## Покрытие

AniLiberty, AnimeGo, AnimeFox, AnimeLib, YummyAnime, каталог Shikimori и
дополнительный AnimeVost представлены в коде. Это не заявление полного паритета:
матрица конкретных возможностей и пробелов находится в PORTING.md.

Веб-потоки обнаруживаются через fetch/XHR, resource timing и media src.
Cookies/User-Agent и контекст страницы используются при открытии встроенного
плеера. MP4 byte-range transport и HLS loopback proxy передают заголовки источника.
HLS пока использует временные файлы перед выдачей ресурса; live/disk limits и
реальная работа всех источников требуют дальнейшей проверки.

CI проверяет Rust, Swift HTML/HLS fixtures, loopback transport, JS capture,
компиляцию Xcode и IPA. Не все новые ревизии уже прошли все эти этапы — смотрите
результат конкретного run. Воспроизведение на физическом iPhone ещё не подтверждено.
Избранное, история/прогресс, расширенные настройки и Android mpv/шейдеры не перенесены.