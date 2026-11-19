# Ядро RC2014 для Karabas Go / Mini / Mini G

Модульный Z80-компьютер [RC2014](https://rc2014.co.uk/) для плат семейства Karabas Go (Xilinx Spartan-6 XC6SLX25): Z80 с обычными платами RC2014 и встроенным терминалом VT100 на HDMI. Запускает RomWBW (CP/M 2.2, CP/M 3, ZSDOS, BASIC, Forth, игры), Fuzix, SCM и NASCOM BASIC.

Состояние: собрано для Karabas Go, Mini и Mini G (`src/rc2014.kg`, один файл на все три); проверено на Mini G, на Go и Mini ещё не запускалось. План и история — в `docs/PLAN.md`, английский README — `README.md`.

## Машина

| Плата | Порты |
|---|---|
| Z80 на 7,3728 МГц (OSD *CPU*: 14,7456 МГц) | |
| 512K ROM + 512K RAM (RomWBW), Pageable ROM + 64K RAM (Classic), 8K ROM + 32K RAM (Mini) | 78-7C / 38 |
| SIO/2 (или ACIA, OSD *Serial*) | 80-83 |
| Compact Flash (8-битный IDE): образ на SD-карте или CF-карта платы | 10-17 |
| Часы DS1302 (часы платы) | C0 |
| Видео TMS9918A (VRAM 16K) | 98-99 |
| Звук YM2149 (модуль Ed Brindley, 1,79 МГц) | D8 / D0 |
| Звуковой модуль SN76489 (два чипа: левый, правый; 3,58 МГц) | FF / FB |
| Контроллер клавиатуры PS/2 8242 (клавиатура консоли на TMS) | 60 / 64 |
| Модуль джойстиков (два геймпада USB / Sega) | 01 / 02 |
| Переключатели передней панели | 00 |

ROM лежат внутри `rc2014.kg`: RomWBW 3.6 (наша сборка `RCZ80_kg`: RCZ80_std с драйверами TMS9918, клавиатуры, YM2149 и SN76489), заводские ROM RC2014 с SCM (Classic) и BASIC (Mini).

## Как пользоваться

- **Profile** (OSD): *RomWBW 512K*, *Classic* (SCM, BASIC, CP/M с CF), *Mini* (BASIC 32K на ACIA). Смена сбрасывает машину.
- **Console** (OSD, Menu+C): *Terminal* — встроенный VT100 на последовательной линии (SIO/2 A или ACIA), клавиатура USB идёт в терминал; *TMS9918* — картинка TMS9918 и клавиатура на 8242: RomWBW тогда запускает консоль там (передняя панель читается как SW_CRT). *Colour* — цвет терминала: янтарный, зелёный или белый.
- **Второй последовательный порт**: канал B SIO/2 — второй USB-serial порт платы («Karabas core serial», `/dev/serial/by-id/usb-Karabas_Go_*-if02` в Linux; прошивка с двумя портами CDC). В RomWBW это SIO1: `I 1` в загрузчике переносит туда консоль, `XM` передаёт файлы.
- **CF card** (Menu+F1): образ диска (`.img`, `.hdf`) в `/rc2014` на SD-карте, например образы RomWBW `hd1k` (`hd1k_prefix.dat` + слайсы). *CF source* = *Card* — вместо образа CF-карта в слоте платы (осторожно: ядро пишет на неё, как машина).
- **Fuzix**: распакуйте `src/roms/fuzix/rc2014_fuzix.img.xz` (образ CF 40 МБ, Fuzix 0.5, собран `src/tools/rc2014_fuzix.sh`) в `/rc2014`, выберите его в *CF card*, в загрузчике RomWBW наберите `2`, на `bootdev:` — `hda1`, вход `root`. Таймер — кадровое прерывание TMS9918. При *Console* = *TMS9918* Fuzix работает на экране TMS с клавиатурой (tty1-4), при *Terminal* — на терминале (tty1); tty2 / tty6 — второй USB-serial порт. Выходите командой `shutdown` (иначе при следующей загрузке ответьте на вопросы `fsck`).
- **Время**: DS1302 читает и ставит часы платы (RomWBW `RTC`, `TIME` в ZSDOS).
- **Сброс**: Menu+F12.

## Сборка

ISE 14.7: `cd src; make minig` (или `go`, `mini`). ROM RomWBW: `src/tools/rc2014_romwbw.sh <рабочий каталог>` (нужны gcc, srecord, libncurses-dev), затем пересобрать `.kg` (`python3 make_core.py core.json rc2014.kg`). Симуляция машины: `src/sim/run_machine.sh` (Verilator + GHDL), платы TMS / YM2149 / 8242: `src/sim/run_f3.sh`.

## Лицензия

Файлы, написанные для этого ядра, — GPL-3.0 (см. [LICENSE](LICENSE)). Взятые файлы сохраняют лицензию из своих заголовков:

- T80 (Daniel Wallner, правки MiSTer): BSD-подобная;
- vdp18 (Arnim Läuger): GPL-2.0;
- JT49, JT89 (Jose Tejada): GPL-3.0;
- терминал VT100 pdp2011 / vt10x (Sytse van Slooten) в версии [tsybulin/karabas-go-core-pdp2026](https://github.com/tsybulin/karabas-go-core-pdp2026): **только некоммерческое использование**;
- afifo (Dan Gisselquist): GPL-3.0;
- RomWBW (Wayne Warthen и соавторы): AGPL-3.0, отдельная программа в `.kg`;
- Fuzix (Alan Cox и соавторы): GPL-2.0, образ диска в `src/roms/fuzix` (исходники — коммиты в `rc2014_fuzix.txt`);
- SCM (Steve Cousins), NASCOM BASIC (Microsoft, Grant Searle): как их распространяет RC2014.

RC2014 — торговая марка Spencer Owen. Проект не связан с RC2014.
