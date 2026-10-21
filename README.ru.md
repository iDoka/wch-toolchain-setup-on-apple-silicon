# WCH: Инструкция по установке тулчейна и SDK на macOS ARM64 (и Linux x86_64 как бонус)

Сборка прошивок для CH32 (двухъядерный QingKe V3F + V5F) работает на **macOS ARM64 нативно**, без Rosetta и без IDE. Для этого нужны три вещи:

- апстримный **xPack GNU RISC-V GCC 15.2.0** (есть сборка `darwin-arm64`);
- штатный SDK WCH ([openwch/ch32h417](https://github.com/openwch/ch32h417), каталог `EVT/`);
- приложенные `Makefile` и `wvproj2mk.py`.

На **Linux x86_64** работает то же самое. Дополнительно там есть официальный MounRiver Studio II с WCH GCC15 и WCH OpenOCD.

`setup-toolchain-wch.sh` разворачивает всё одной командой на обеих платформах. Он самодостаточен: `Makefile`, `wvproj2mk.py` и конфиг OpenOCD встроены внутрь.

Рядом с xPack скрипт может поставить MounRiver Studio из локального архива (`--mrs-archive`). Ключ `--mcu` выбирает, SDK какого MCU качать (по умолчанию выбран **CH32H417**).

| Компонент | macOS ARM64 | Linux x86_64 |
| --- | --- | --- |
| Компилятор | xPack GCC 15.2.0-1, darwin-arm64 | xPack GCC 15.2.0-1, linux-x64 |
| Компилятор WCH (необязательно) | WCH GCC15 из `MRS_Toolchain_MAC_V2xx.zip` или MRS2 `.dmg` | WCH GCC15 из `MounRiverStudio_Linux_X64_V2xx.tar.xz` |
| SDK | openwch/ch32h417 (git) | то же |
| Make | GNU Make 4.x из Homebrew (`gmake`) | системный `make` 4.x |
| Прошивка и отладка (этап 2) | WCH OpenOCD arm64 из пакета MRS + libusb/hidapi из Homebrew | WCH OpenOCD из MRS2 + udev-правила |

---

## 1. Быстрый старт

```bash
chmod +x setup-toolchain-wch.sh
./setup-toolchain-wch.sh                 # всё в ~/ch32
# открыть новый терминал (или: . ~/ch32/env.sh)
cd ~/ch32/ch32h417/EVT/EXAM/GPIO/GPIO_Toggle
ch32-make -j8                       # -> build/GPIO_Toggle_merged.bin
```

**macOS ARM64.** Нужны Xcode Command Line Tools и [Homebrew](https://brew.sh). Если CLT нет, скрипт запустит их установку и попросит перезапуститься. Через brew он поставит `make` (`gmake`), `libusb` и `hidapi`.

**Linux x86_64 (Ubuntu/Debian).** Скрипт ставит через `apt` пакеты `make git curl xz-utils unzip python3 file libusb-1.0-0 libhidapi-hidraw0 udev`. Для этого вызывается `sudo`.

### Опции

| Опция | Что делает |
| --- | --- |
| `--mcu NAME` | для какого MCU качать SDK (по умолчанию `CH32H417`). Подходят и полные обозначения (`CH32V307VCT6`), см. раздел «Выбор MCU» |
| `--sdk-repo URL` | взять SDK из этого git-репозитория |
| `--mrs-archive FILE` | установить MounRiver Studio из архива на локальном диске **рядом** с xPack: WCH GCC, WCH OpenOCD, IDE. Псевдоним - `--wch-archive` |
| `--default-toolchain xpack\|wch` | какой компилятор `ch32-make` берёт без `TOOLCHAIN=` (по умолчанию `xpack`) |
| `--no-xpack` | не ставить xPack, только WCH GCC из архива (тогда по умолчанию `wch`) |
| `--prefix DIR` | куда ставить (по умолчанию `~/ch32`) |
| `--xpack-version VER` | другой релиз xPack (по умолчанию `15.2.0-1`) |
| `--skip-deps` | не трогать brew/apt |
| `--no-sudo` | Linux: не вызывать sudo (без пакетов, udev-правил и библиотек) |
| `--no-rc` | не дописывать `env.sh` в `~/.zshrc` / `~/.bashrc` |
| `--no-selftest` | пропустить тестовую сборку |
| `--platform macos-arm64\|linux-x64` | принудительно задать платформу |

Скрипт можно запускать повторно. Уже установленный xPack и уже распакованный архив MounRiver он пропускает, SDK обновляет через `git pull`, встроенные файлы перезаписывает.

### MounRiver Studio из локального архива

```bash
# Linux x86_64
./setup-toolchain-wch.sh --mrs-archive ~/Downloads/MounRiverStudio_Linux_X64_V250.tar.xz
# macOS arm64
./setup-toolchain-wch.sh --mrs-archive ~/Downloads/MRS_Toolchain_MAC_V210.zip
# сделать WCH GCC компилятором по умолчанию
./setup-toolchain-wch.sh --mrs-archive <архив> --default-toolchain wch
```

**Форматы.** Архив передаётся только путём на локальном диске. Принимаются tar.xz, tar.gz, tar.bz2, tar и zip; формат определяется по содержимому, а не по расширению. На macOS zip распаковывается через `ditto`, чтобы не ломались `.app`-бандлы. Пакеты (`.deb`, `.rpm`, `.dmg`, `.exe`) скрипт отклоняет.

**Проверка платформы.** Архив должен быть под ту платформу, на которой запущен скрипт. Это проверяется дважды:

1. По имени - до распаковки. Linux-архив на Mac, маковский архив на Linux и Windows-пакеты отклоняются сразу.
2. По бинарникам - после распаковки. Компилятор и OpenOCD должны быть ELF x86-64 на Linux и Mach-O на macOS. Если нет, распакованное удаляется и скрипт останавливается с ошибкой.

**Куда ставится.** Архив распаковывается в `mrs/<имя архива>/`, ссылка `mrs/current` указывает на последний. Повторный запуск с тем же архивом ничего не распаковывает заново. Новая версия MRS встаёт рядом со старой.

**Что скрипт находит в архиве:**

- **Компилятор.** `RISC-V Embedded GCC15` (если его нет - GCC12 с предупреждением) → ссылка `toolchains/wch-gcc`. Абсолютный префикс записывается в `CH32_WCH_CROSS`, поэтому WCH GCC не конфликтует с xPack в `PATH`.
- **OpenOCD.** `OpenOCD/bin/openocd` → ссылка `toolchains/wch-openocd`, путь записывается в `CH32_OPENOCD` для `ch32-make flash`. На macOS скрипт сам подкладывает libusb/hidapi и подписывает бинарник ad-hoc.
- **IDE.** Если в архиве полная MounRiver Studio, появляется команда `bin/mounriver`.
    - Linux: создаётся ярлык в меню, `chrome-sandbox` от Electron получает setuid; без sudo IDE запускается с `--no-sandbox`.
    - macOS: команда открывает `.app` из архива.
- **Linux, `beforeinstall/`.** udev-правила для WCH-Link и runtime-библиотеки MRS, плюс пользователь добавляется в группу `plugdev`.

Self-test собирает GPIO_Toggle обоими компиляторами.

### Выбор MCU (`--mcu`)

SDK у WCH выложен отдельными репозиториями на GitHub, один репозиторий на семейство. По `--mcu` скрипт выбирает нужный и клонирует его в `~/ch32/<репозиторий>/`. Можно ставить несколько MCU, запуская скрипт с разным `--mcu`; `CH32_SDK` в `env.sh` указывает на последний.

| `--mcu` | Репозиторий openwch |
| --- | --- |
| CH32H417 (CH32H41x) - по умолчанию | `ch32h417` |
| CH32V002, V004, V005, V006, V007, CH32M007 | `ch32v002_004_005_006_007` |
| CH32V003 | `ch32v003` |
| CH32V103 | `ch32v103` |
| CH32V203, CH32V208 | `ch32v20x` |
| CH32V303, V305, V307, V317 | `ch32v307` |
| CH32L103 | `ch32l103` |
| CH32X033, CH32X035 | `ch32x035` |
| CH32M030 | `ch32m030` |
| CH32F203, CH32F208 | `ch32f20x` |
| CH641 / CH643 | `ch641` / `ch643` |
| CH565, CH569 | `ch569` |
| CH570, CH572 | `ch570` |
| CH581, CH582 / CH583 | `ch582` / `ch583` |
| CH584, CH585 | `ch585` |
| CH592 | `ch592` |
| любое другое `CHxxx` | пробуется `openwch/<chxxx>`, иначе ошибка с подсказкой про `--sdk-repo` |

Существование каждого репозитория проверено, семейства сверены по README репозиториев. CH581 отнесён к `ch582` по смыслу: в README он не упомянут.

Компиляторы (xPack и WCH) и OpenOCD годятся для любого из этих MCU.

**Ограничение.** `ch32-make`, `tools/Makefile` и self-test рассчитаны на двухъядерную раскладку CH32H417 (V3F + V5F). Для других MCU скрипт ставит SDK и компиляторы, пропускает self-test и предупреждает об этом. Собирать примеры для них пока проще в MounRiver Studio. Одноядерный Makefile под CH32V/CH5xx - отдельная доработка.

### Что делает скрипт по шагам

1. Ставит системные пакеты и проверяет GNU Make ≥ 4. На macOS штатный `make` - версия 3.81 от 2006 года, поэтому используется `gmake`.
2. Скачивает xPack GCC с GitHub и сверяет SHA-256 с файлом `.sha` из релиза. Распаковывает в `toolchains/`, на macOS снимает карантин Gatekeeper (`xattr`). Шаг пропускается при `--no-xpack`.
3. Только с `--mrs-archive`: ставит MounRiver Studio из архива (подробно - в разделе «MounRiver Studio из локального архива»).
4. Клонирует SDK для `--mcu` (`git clone --depth 1`) в `<репозиторий>/`.
5. Кладёт `tools/Makefile`, `tools/wvproj2mk.py`, `tools/openocd-ch32h417.cfg` и обёртку `bin/ch32-make`. Пишет `env.sh` и подключает его в rc-файл оболочки.
6. Самопроверка (только для CH32H417): собирает GPIO_Toggle для обоих ядер каждым установленным компилятором в `selftest/<компилятор>/`.

### Что где лежит

```
~/ch32/
  env.sh                      PATH, CH32_HOME, CH32_MCU, CH32_SDK, CH32_TOOLCHAIN,
                              CH32_WCH_CROSS, CH32_OPENOCD
  bin/ch32-make               сборка проекта в текущей папке (CH32H417)
  bin/mounriver               IDE MounRiver Studio (если она была в архиве)
  tools/Makefile              сборка V3F + V5F + склейка образа
  tools/wvproj2mk.py          .wvproj (MounRiver) -> project.mk
  tools/openocd-ch32h417.cfg  WCH-LinkE + оба ядра (этап 2)
  toolchains/xpack-gcc/ ->    xpack-riscv-none-elf-gcc-15.2.0-1/
  toolchains/wch-gcc/ ->      (с --mrs-archive) WCH GCC15, префикс riscv32-wch-elf-
  toolchains/wch-openocd/ ->  (с --mrs-archive) WCH OpenOCD
  mrs/<имя архива>/, current  распакованная MounRiver Studio
  ch32h417/EVT/EXAM/          примеры; SRC/ = общий слой SDK (для --mcu CH32H417)
  ch32v307/, ch582/ ...       SDK других MCU, если ставили с --mcu
  selftest/                   результат самопроверки
```

---

## 2. Сборка проектов

`ch32-make` запускается в папке двухъядерного проекта, где лежат `Common/`, `V3F/` и `V5F/`.

При первом запуске обёртка генерирует `project.mk` из файлов MounRiver `V3F/*.wvproj` и `V5F/*.wvproj`. Чтобы перегенерировать его, удалите `project.mk`. Все аргументы передаются в make.

```bash
ch32-make -j8                 # xPack (по умолчанию)
ch32-make TOOLCHAIN=wch       # WCH GCC15 (riscv32-wch-elf-), с расширением XW
ch32-make V=1                 # полные командные строки
ch32-make OPT=-Og             # для отладки
ch32-make info | clean | flash
```

| Файл в `build/` | Что это |
| --- | --- |
| `V3F/<имя>_V3F.{elf,hex,bin,lst,map}` | boot-ядро V3F, flash 0x00000000 |
| `V5F/<имя>_V5F.{elf,hex,bin,lst,map}` | ядро приложения V5F, flash 0x00010000 (в отдельных примерах до 0x30000) |
| `<имя>_merged.bin` | V3F, добитый 0xFF до начала V5F, затем V5F. Аналог `obj/Merge.Bin` из MounRiver |

### Что Makefile делает сам, как MRS2

- Находит SDK: `../SRC` на 1–4 уровня вверх, иначе берёт `$CH32_SDK`.
- Компилирует всё дерево `V3F/` и `V5F/`: не только `User/`, но и, например, деревья FreeRTOS/RT-Thread. Компилирует и все подпапки `Common/`.
- Берёт `Ld/` и `Startup/` из самого проекта, если они там есть.
- Заменяет файлы SDK одноимёнными копиями из проекта. Например, `Common/Debug/debug.c` используется вместо `SRC/Debug/debug.c`.
- Определяет адрес V5F для склейки по V5F-ELF.

### Что переносит `wvproj2mk.py` → `project.mk`

- `linkedFolders` вне SDK, например `../NetLib`;
- `libraries` и `library_search_path` (`.a` от WCH);
- `excludeResources`;
- дефайны;
- FPU (`FPU := 1` → `rv32imafc` + `ilp32f`);
- уровень оптимизации.

Предупреждения скрипта (WCH printf/IQmath, GCC8) означают, что проекту нужен `TOOLCHAIN=wch`.

### Переменные Makefile

Их можно задать в командной строке или в своём `project.mk`.

| Переменная | Назначение |
| --- | --- |
| `TOOLCHAIN=xpack\|wch` | компилятор (`riscv-none-elf-` / `riscv32-wch-elf-`) |
| `MARCH`, `MABI` | переопределить ISA (по умолчанию `rv32imac_zicsr_zifencei_zba_zbb_zbc_zbs` / `ilp32`) |
| `FPU=1` | аппаратный FPU: `rv32imafc...` + `ilp32f` |
| `OPT=-Os` | уровень оптимизации |
| `EXTRA_SRCS_V3F/V5F` | доп. исходники ядра |
| `EXTRA_INC_V3F/V5F` | доп. include-пути |
| `EXTRA_LIBS_V3F/V5F` | `-L... -lname` |
| `EXCLUDE_V3F/V5F` | исключить файлы |
| `EXTRA_DEFS_V3F/V5F` | `-DFOO` |
| `EXTRA_CFLAGS`, `EXTRA_LDFLAGS` | общие доп. флаги |
| `LD_V3F`, `LD_V5F` | свой линкер-скрипт |
| `V5F_OFFSET=0x...` | адрес V5F для склейки (по умолчанию берётся из ELF) |
| `SDK=...`, `BUILD=...`, `NAME=...` | пути и имя |

**Свой проект.** Скопируйте ближайший пример EVT целиком (с `.wvproj`) куда угодно и запустите `ch32-make`. SDK подставится из `$CH32_SDK`.

### Проверка на всём EVT

Были прогнаны все 199 двухъядерных примеров EVT: xPack 15.2.0-1 (linux-x64), Makefile + `wvproj2mk.py`.

| Результат | Примеров | Подробности |
| --- | --- | --- |
| Собираются без правок | 181 | В том числе проекты с `libwchnet.a`, `libRV3UFI.a`, `libCH32H417_TOUCH.a`, RT-Thread и FPU |
| Регистр букв в `#include` | 6 | FMC/NAND, UHSIF_SLAVE, IoCHub ×2, Host_UDisk_Exams ×2. На Linux падают, на нечувствительной к регистру ФС (Windows, macOS по умолчанию) должны собраться |
| Нужен обход (раздел 5) | 2 | FreeRTOS_Core, HSEM_DataSharing. С обходом проверены, собираются |
| Ошибка в самом примере | 3 | FMC/SDRAM_*: `#define bank1 0` ломает локальную `u32 bank1=0`. У одного из них ещё и пробел в имени папки |
| Не проверялись | 7 | 5 требуют WCH printf/IQmath или GCC8 (CoreMark, SerDes ×2, FMC SRAM/NORFLASH), 2 IAP с нестандартной раскладкой |

Единственная потеря на xPack - нет WCH-расширения XW (сжатые команды загрузки/записи байта и полуслова). Код получается чуть крупнее, на корректность это не влияет.

Атрибут `interrupt("WCH-Interrupt-fast")` апстримный GCC принимает с предупреждением и делает обычный machine-mode обработчик. Сама WCH в RTOS-примерах для H417 пишет именно `interrupt()`.

Готовые закрытые библиотеки WCH, собранные с XW, линкуются xPack-ом без ошибок.

---

## 3. Ручная установка (без скрипта)

### macOS ARM64

```bash
xcode-select --install
brew install make libusb hidapi

mkdir -p ~/ch32/toolchains && cd ~/ch32/toolchains
V=15.2.0-1
B=https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v$V
curl -LO $B/xpack-riscv-none-elf-gcc-$V-darwin-arm64.tar.gz
curl -LO $B/xpack-riscv-none-elf-gcc-$V-darwin-arm64.tar.gz.sha
shasum -a 256 -c xpack-riscv-none-elf-gcc-$V-darwin-arm64.tar.gz.sha
tar xzf xpack-riscv-none-elf-gcc-$V-darwin-arm64.tar.gz
xattr -dr com.apple.quarantine xpack-riscv-none-elf-gcc-$V
echo "export PATH=\"$HOME/ch32/toolchains/xpack-riscv-none-elf-gcc-$V/bin:\$PATH\"" >> ~/.zshrc

git clone --depth 1 https://github.com/openwch/ch32h417.git ~/ch32/ch32h417
cd ~/ch32/ch32h417/EVT/EXAM/GPIO/GPIO_Toggle
gmake -f ~/ch32/tools/Makefile -j8      # Makefile/wvproj2mk.py/cfg положите в ~/ch32/tools
```

### Linux x86_64 (Ubuntu)

```bash
sudo apt install -y make git curl xz-utils python3 file libusb-1.0-0 libhidapi-hidraw0 udev
# далее как на macOS, только архив ...-linux-x64.tar.gz, sha256sum -c и make вместо gmake
```

**WCH GCC15 из MounRiver Studio II (Linux).** Архив `MounRiverStudio_Linux_X64_V<версия>.tar.xz` берётся с [mounriver.com/download](https://www.mounriver.com/download). Последняя версия на данный момент в публичных сборках - V2.50.

Внутри архива:

- `MRS-linux-x64/resources/app/resources/linux/components/WCH/Toolchain/RISC-V Embedded GCC15/` - компилятор, префикс `riscv32-wch-elf-`;
- `.../WCH/OpenOCD/OpenOCD/` - WCH OpenOCD;
- `.../WCH/SDK/default/RISC-V/` - SVD-файлы;
- `beforeinstall/` - udev-правила и runtime-библиотеки.

Проще всего: `./setup-toolchain-wch.sh --mrs-archive MounRiverStudio_Linux_X64_V250.tar.xz`.

---

## 4. Этап 2: прошивка и отладка

Нужен **WCH-форк OpenOCD** (драйвер `wlinke`, таргет `wch_riscv`). Апстримный OpenOCD с WCH-LinkE не работает.

- Linux: WCH OpenOCD есть в MRS2.
- macOS: есть в `MRS_Toolchain_MAC_V2xx.zip`, собран под arm64. Подтверждено пользователями M1/M4 в [issue #208](https://github.com/openwch/arduino_core_ch32/issues/208) и [issue #260](https://github.com/openwch/arduino_core_ch32/issues/260).

Скачайте архив для своей ОС с сайта MounRiver и передайте его скрипту:

```bash
./setup-toolchain-wch.sh --mrs-archive ~/Downloads/MRS_Toolchain_MAC_V2xx.zip           # macOS
./setup-toolchain-wch.sh --mrs-archive ~/Downloads/MounRiverStudio_Linux_X64_V250.tar.xz # Linux
```

На macOS после первого запуска WCH OpenOCD может понадобиться разрешить его: «Системные настройки → Конфиденциальность и безопасность → Разрешить».

Если WCH GCC в маковском пакете окажется x86_64 (скрипт напечатает архитектуру), поставьте Rosetta 2:

```bash
softwareupdate --install-rosetta --agree-to-license
```

**Железо.** WCH-LinkE должен быть в режиме RISC-V. Интерфейс по умолчанию - однопроводной SDI: SWDIO + GND + 3V3. Держите прошивку LinkE свежей: MRS2 предлагает обновление при подключении.

### Прошивка

Шейте всегда **склеенным** образом. В проверенном потоке Zephyr запись одного образа может стереть второй.

```bash
ch32-make flash
# = openocd -f openocd-ch32h417.cfg -c init -c halt \
#     -c "program build/<имя>_merged.bin 0x00000000 verify" -c reset -c shutdown
```

`openocd-ch32h417.cfg` взят из Zephyr (`boards/wch/ch32h417evt/support/openocd.cfg`, Apache-2.0). Он повторяет `wch-dual-core.cfg` от MounRiver с картой памяти H417.

Альтернатива - родной `wch-dual-core.cfg` из `OpenOCD/bin` с ключом `-c page_erase`, так его вызывает MRS2.

Некоторые версии WCH OpenOCD падают уже после успешного verify. Если в логе есть `Verified OK`, образ записан.

### Отладка

OpenOCD открывает два GDB-порта: 3333 - V3F, 3334 - V5F. Сначала прошейте образ, собранный с `OPT=-Og`, затем запустите `openocd -f ~/ch32/tools/openocd-ch32h417.cfg` и подключитесь:

```gdb
# riscv-none-elf-gdb (из xPack) или riscv32-wch-elf-gdb
set architecture riscv:rv32
set mem inaccessible-by-default off
set remotetimeout unlimited
target extended-remote :3334
file build/V5F/<имя>_V5F.elf
monitor reset halt
break main
continue
```

После сброса V5F спит, пока V3F не вызовет `NVIC_WakeUp_V5F()`. Поэтому точки останова в V5F срабатывают только после старта V3F.

Команды взяты из `debugConfigurations` в `.wvproj`. Команду `set disassembler-options xw` понимает только WCH GDB.

---

## 5. Грабли

| Симптом | Причина | Что делать |
| --- | --- | --- |
| `extension 'xw' ... unsupported` | XW есть только в WCH GCC | На xPack не добавляйте XW в `MARCH`. По умолчанию его там нет |
| `warning: argument to 'interrupt' attribute is not "user"...` | `WCH-Interrupt-fast` - расширение WCH GCC | Безвредно. Скрыть: `EXTRA_CFLAGS=-Wno-attributes` |
| `_close is not implemented and will always fail` | заглушки newlib из `nosys.specs` | Безвредно, MRS выдаёт то же самое |
| `V3F image ... does not fit below V5F start` | код V3F не помещается до начала V5F | Переразбейте flash в обоих `Link_*.ld` и в `Core_V5F_StartAddr` (`debug.h`) |
| `fatal error: NAND_Flash.h: No such file` | include с другим регистром, чем имя файла | На Linux переименуйте файл или поправьте include |
| `unknown type name 'uint8_t'` (HSEM, FreeRTOS) | `shared.h` не подключает `<stdint.h>` | `EXTRA_CFLAGS="-include stdint.h"` |
| `cannot find ../../V3F/obj/User/shared.o` | `Link_v5f.ld` ссылается на папку `obj/` MRS | см. ниже |
| На Mac `"openocd" Not Opened` / `dyld: Library not loaded` | Gatekeeper и пути к libusb | `--mrs-archive` делает это сам; иначе - `xattr`, ссылки на libusb/hidapi, `codesign --force -s -` |
| Ошибки `make` на Mac | системный GNU Make 3.81 | `gmake` из Homebrew (`ch32-make` вызывает его сам) |
| V5F не стартует после прошивки только своего образа | V5F будит V3F; одиночная запись может стереть соседний образ | Всегда шить `*_merged.bin` |

Обход для FreeRTOS_Core и HSEM_DataSharing (в HSEM скрипт лежит в `Common/Ld/V5F/`):

```bash
mkdir -p build
sed 's#../../V3F/obj/User/shared.o#build/V3F/V3F/User/shared.o#' V5F/Ld/Link_v5f.ld > build/Link_v5f_cli.ld
ch32-make EXTRA_CFLAGS="-include stdint.h" LD_V5F=build/Link_v5f_cli.ld
```

В Makefile включён `-fpermissive`. Начиная с GCC 14 неявные объявления функций и несовместимые указатели - ошибки, а без этого флага не собираются LVGL-пример и PIOC_UART. Для своего кода флаг лучше убрать и чинить предупреждения.

---

## 6. Справка: устройство SDK

```
EVT/EXAM/
  SRC/                  общий слой: Core/ Debug/ Ld/{V3F,V5F}/ Peripheral/{inc,src}/ Startup/
  GPIO/GPIO_Toggle/
    Common/             код обоих ядер, иногда свой Ld/ или Debug/
    V3F/User/           main.c, system_ch32h417.c, ch32h417_it.c ... + *.wvproj
    V5F/User/           то же для V5F
    GPIO_Toggle.wvsln   «решение» MRS2 из двух проектов
```

| Ядро | Flash (LMA) | Исполняется из | Define | Линкер-скрипт |
| --- | --- | --- | --- | --- |
| V3F (boot) | 0x00000000, 64 КБ | RAM_CODE 0x20100000 | `Core_V3F` | `SRC/Ld/V3F/Link_v3f.ld` |
| V5F | 0x00010000, 128 КБ | ITCM 0x200A0000 | `Core_V5F` | `SRC/Ld/V5F/Link_v5f.ld` |

После сброса работает только V3F. Он будит V5F вызовом `NVIC_WakeUp_V5F(0x00010000)`. Режим (оба ядра или одно) задаётся `Run_Core` в `SRC/Debug/debug.h`.

Flash алиасится: 0x08000000 и 0x00000000 - одна и та же память. MRS пишет `Merge.Bin` с адреса 0x08000000.

Флаги взяты из `*.wvproj`; 398 из 402 проектов настроены одинаково:

- тулчейн `${WCH:Toolchain:GCC15}`;
- ISA rv32i + M + A + C + B + XW, где «B» = `zba_zbb_zbc_zbs` (видно по атрибутам WCH-библиотек), а XW = `xw2p2`;
- ABI `ilp32` (soft-float, хотя FPU есть);
- компиляция: `-Os -msave-restore -msmall-data-limit=8 -std=gnu99 -ffunction-sections -fdata-sections -fno-common -fsigned-char`;
- линковка: `-nostartfiles --gc-sections --specs=nano.specs --specs=nosys.specs -lm`.

---

## 7. Что проверено

**Проверено:**

- Linux x86_64: скрипт целиком (apt, xPack, SDK, tools, `env.sh`, самопроверка), повторный запуск, `ch32-make` для примера в EVT и для проекта вне EVT.
- Ветка `--mrs-archive` на Linux - на макетах архивов с раскладкой MRS2 в форматах tar.xz, zip и tar.bz2:
    - повторный запуск и `--no-xpack`;
    - сборка WCH-компилятором по `CH32_WCH_CROSS`;
    - IDE-лаунчер;
    - отказы на маковский архив, `.deb` и архив с Mach-O-бинарниками (с очисткой распакованного).
- `--mcu`: все репозитории из таблицы существуют. На CH32V307VCT6 и CH582 проверено клонирование SDK; на CH32V307VCT6, кроме того, - что self-test и `ch32-make` корректно пропускаются.
- Сборка всех примеров EVT (раздел 2).
- macOS-ветка скрипта: синтаксис и shellcheck; на Linux с заглушками - шаги 1–2. Скачанный darwin-arm64 xPack сверен по SHA-256 и действительно является `Mach-O 64-bit arm64`.
- Запуск скрипта на настоящем Mac Mini.
- Архитектура WCH GCC в маковском пакете.
- Прошивка и отладка на железе.

**Не проверено:**

- Архивы MounRiver недоступны из скрипта из-за требования наличия js для скачки

---

## Источники

- [openwch/ch32h417](https://github.com/openwch/ch32h417) - EVT, `*.wvproj`, линкер-скрипты, `debug.h`
- [MounRiver: загрузки](https://www.mounriver.com/download)
- [Zephyr: WCH CH32H417EVT](https://docs.zephyrproject.org/latest/boards/wch/ch32h417evt/doc/index.html) и [openocd.cfg](https://github.com/zephyrproject-rtos/zephyr/blob/main/boards/wch/ch32h417evt/support/openocd.cfg)
- [xPack GNU RISC-V Embedded GCC](https://xpack-dev-tools.github.io/riscv-none-elf-gcc-xpack/), релиз 15.2.0-1
- [islandcontroller/wch-riscv-devcontainer](https://github.com/islandcontroller/wch-riscv-devcontainer) - раскладка архива MRS2 V2.50, префикс `riscv32-wch-elf-`
- [arduino_core_ch32 #208](https://github.com/openwch/arduino_core_ch32/issues/208), [#260](https://github.com/openwch/arduino_core_ch32/issues/260) - WCH OpenOCD arm64 на Apple Silicon
