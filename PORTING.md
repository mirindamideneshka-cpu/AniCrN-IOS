# Блоки переноса

1. **Провайдеры и получение потока (приоритет)** — общий контракт, каталог/поиск/карточка/серии/озвучки, прямые URL и iframe fallback.
2. **Сеть** — cookies, Referer/Origin, таймауты, отмена, редиректы, HLS-плейлисты/сегменты и CDN.
3. **Плеер** — качество, переключение серий, прогресс, субтитры, фон/PiP, восстановление ошибок.
4. **Интерфейс** — навигация, каталог, фильтры, карточка, состояния загрузки.
5. **Данные** — избранное, история, прогресс и миграции.
6. **Настройки/медиа** — темы, звук; отдельная оценка переносимости mpv, шейдеров и Android-ускорения.
7. **Поставка и проверки** — IPA/CI, тесты парсеров, проверка на устройстве.

## Источники Android

Отдельные реализации: AniLiberty, AnimeGo, AnimeVost, YummyAnime, KinoKino;
группы webcatalog: WebCatalogProviders, AdditionalProviders, NewAnimeProviders,
FilmCatalogProviders, DoramaTvProvider. Mock не считать рабочим источником.
Каждая группа требует отдельной инвентаризации: файл не равен одному провайдеру.

## Покрытие на 2026-11-08

| Источник | Реализовано в коде | Остаётся проверить/перенести |
| --- | --- | --- |
| AniLiberty | Каталог, поиск, серии, resolve серии, качества HLS | Pagination, fixtures, видео на устройстве |
| AnimeGo | Каталог, поиск, страницы эпизодов, legacy markup, озвучки, iframe | Live HTTP500 с Windows; direct-host extractors, fixtures, видео |
| AnimeFox | Каталог/search GET, iframe, серии выбранного сезона | POST search как Android, все сезоны, AJAX fallback, fixtures, видео |
| AnimeLib | Каталог, поиск, серии, озвучки/players | Live HTTP403 с Windows, paging, fixtures, видео |
| YummyAnime | Feed, поиск, API mirrors, серии/озвучки и iframe | Headers API, web fallback, region-locked filtering, fixtures, видео |
| Shikimori | Каталог/поиск metadata, явный поиск в видеоисточниках | Детальная карточка, автоматическое сопоставление; собственного видео нет и в Android |
| AnimeVost (дополнительный модуль) | Каталог/поиск, var data, getlink MP4, web fallback | Mirror failover, fixtures, видео |

Активный аниме-реестр Android AppModule содержит первые шесть источников.
AnimeVost включён дополнительно, поскольку его модуль есть в архиве.
Фильмовые/дорамные источники перечислены выше для общего проекта и в текущую
цель полного списка аниме-источников не входят.

## Перехват и транспорт

- WKUserScript во всех фреймах: fetch/XHR, PerformanceObserver, media src;
  HLS/MP4 URL с расширением, ручной выбор найденного потока.
- WK cookies передаются в AVURLAsset. MP4 с headers использует AVAssetResourceLoader
  с byte ranges; HLS с headers использует loopback HLSProxy с URI rewrite.
- HLSProxy скачивает ресурсы во временные файлы и выдаёт 64 KiB блоками;
  плейлисты ограничены 2 MiB. Это пока store-and-forward, не streaming upstream.
- Остаются workers/blob/MSE/URL без расширения, headers/cookie redirect audit,
  ограничение disk/live route growth, автоматический handoff и device QA.
- DRM не реализован. Обнаружение URL не доказывает доступность декодирования.

## Проверки

CI проверяет Rust core, Swift playlist fixtures, loopback transport integration,
Xcode device build и наличие локального ATS dictionary. Результаты каждого run
проверять отдельно: наличие теста не означает его успешного выполнения.
На физическом iPhone воспроизведение ни одного провайдера пока не подтверждено.

## Следующие шаги

1. Дождаться последних CI; исправить transport integration/compile при сбоях.
2. Закрыть перечисленные различия провайдеров и добавить fixture tests.
3. Довести потоковый транспорт и проверить реальные потоки на iOS.