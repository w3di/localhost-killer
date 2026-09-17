# Localhost Killer

Нативное menu bar приложение для macOS. Показывает все процессы, слушающие TCP-порты
на локальной машине, и убивает любой из них одним кликом.

Не виджет: WidgetKit живёт в песочнице и не может запускать `lsof` или слать сигналы
чужим процессам. Поэтому — menu bar app (`MenuBarExtra`, стиль `.window`).

## Требования

- macOS 14+
- Xcode / Command Line Tools (нужен `swiftc`). Сторонних зависимостей нет — только
  SwiftUI, Foundation, AppKit.

## Сборка

```bash
./build.sh
open build/LocalhostKiller.app
```

`build.sh`:

1. Компилирует `Sources/*.swift` через `swiftc -O` под архитектуру хоста
   (`arm64` или `x86_64`, определяется через `uname -m`), таргет macOS 14.0.
2. Собирает бандл `build/LocalhostKiller.app` (`Contents/MacOS`, `Info.plist`, `PkgInfo`).
3. Подписывает ad-hoc (`codesign --sign -`) — без подписи macOS 26 приложение не запустит.

## Что делает

- Иконка `network` в строке меню + число активных слушающих сокетов.
- Клик открывает список: одна строка на PID (несколько портов одного PID — через запятую).
  Порт жирным моноширинным, имя процесса, PID серым, полная команда (обрезана посередине,
  полностью — в тултипе).
- ✕ справа: `SIGTERM`, и если через 2 секунды процесс жив — `SIGKILL`. Без подтверждений:
  это dev-тулза, клик = убить.
- «Kill all node» — прибивает только процессы с именем `node` (dev-серверы),
  Docker/Spotify/прочее не трогает.
- «Refresh», «Quit».
- Автообновление раз в 3 секунды, пока попап открыт; закрыт — таймер стоит, CPU в простое 0%.
- Процессы, которые нельзя убить (EPERM — чужой пользователь/root), подсвечиваются красным
  с тултипом «Permission denied».
- Нет Dock-иконки и главного окна (`LSUIElement`).

### Сортировка и фильтрация

- Сначала `node`-процессы, потом остальные; внутри — по номеру порта.
- Из списка исключены системные процессы (`rapportd`, `ControlCenter`, `sharingd`,
  `AirPlayXPCHelper`, `identityservicesd`) — список-константа в `PortScanner.swift`,
  легко расширяется.

## Автозапуск (Login Items)

Встроен: в попапе есть чекбокс **«Launch at Login»**. Он через `SMAppService`
(ServiceManagement, macOS 13+) регистрирует/снимает приложение в «Объектах входа» —
руками в System Settings лазить не нужно. Чекбокс показывает фактический статус
(если система откажет — галка не встанет).

**Важно:** login item ссылается на текущее расположение бандла. Перед включением
автозапуска скопируйте приложение в `/Applications`, иначе после переноса/удаления
папки сборки автозапуск отвалится:

```bash
cp -R build/LocalhostKiller.app /Applications/
open /Applications/LocalhostKiller.app
```

Проверить/снять вручную при желании: **System Settings → General →
Login Items & Extensions → Open at Login**.

## Иконка

Иконка приложения генерируется скриптом `scripts/make-icon.swift` (чистый AppKit,
без сторонних тулов): градиентный squircle + глиф `network` + красный kill-бейдж.
`build.sh` сам рендерит PNG-сет, собирает `AppIcon.icns` через `iconutil` и кладёт
в `Contents/Resources`. Иконка в строке меню — отдельно, это SF Symbol `network`.

## Структура

```
localhost-killer/
├── Sources/
│   ├── App.swift            # @main App, MenuBarExtra, PortViewModel, автозапуск (SMAppService)
│   ├── PortScanner.swift    # запуск lsof, парсинг формата -F, модель ListeningProcess
│   ├── ProcessKiller.swift  # SIGTERM → SIGKILL, обработка EPERM
│   └── PortListView.swift   # SwiftUI попап + чекбокс Launch at Login
├── scripts/
│   └── make-icon.swift      # генератор иконки (AppKit → PNG-сет → .icns)
├── Info.plist               # LSUIElement, CFBundleIconFile, bundle id, версия, минимальная macOS 14
├── build.sh
├── .gitignore
└── README.md
```

> Примечание: `@main` App лежит в `App.swift`, а не в `main.swift`. Файл с именем
> `main.swift` компилятор Swift трактует как top-level точку входа, и это конфликтует
> с атрибутом `@main`. Функционально — ровно тот же единый бинарник.
