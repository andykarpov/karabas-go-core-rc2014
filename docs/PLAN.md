# План ядра RC2014 для Karabas Go / Mini / Mini G

Цель: модульный Z80-компьютер [RC2014](https://rc2014.co.uk/) с периферией, которая под него выпускается, на платах Karabas (XC6SLX25, ISE 14.7). Своё ядро: на шине RC2014 стоят обычные микросхемы, их модели у нас уже есть. Ядра RC2014 для MiSTer / MiST на 2026-11-18 не нашлось, есть только FPGA-платы для шины (TMS9918 + AY на Tang Nano, V9958).

## Решения пользователя (2026-11-18)

- Процессор Z80 (T80). Z180 и eZ80 потом, в беклоге.
- Три профиля в OSD: **RomWBW 512K** (основной), **Classic** (SCM + NASCOM BASIC, CP/M с CF), **Mini / Micro** (BASIC 32K на ACIA).
- Консоль по умолчанию — встроенный в FPGA терминал VT100 на SIO A / ACIA, вывод на HDMI, клавиатура USB в терминал. TMS9918 — в Ф3.
- ROM (SCM, BASIC, RomWBW) встроены в `.kg`.
- Имя ядра `rc2014`, репозиторий karabas-go-core-rc2014, публичный.

## Блоки и откуда они

| Модуль RC2014 | У нас |
|---|---|
| Z80 7,3728 МГц | T80 |
| Pageable ROM, 64K RAM, 512K ROM + 512K RAM (банки) | SRAM платы 4 МБ |
| Serial I/O (ACIA 68B50), Dual Serial (SIO/2) | свои блоки |
| Compact Flash (8-битный IDE) | `hdf_ata.v` + `img_sdc` из modules (образ на SD1 через прошивку) |
| RTC DS1302 | свой блок, время от прошивки (`kg_mcu_rtc`) |
| Z80 CTC | свой блок (таймер и прерывания для Fuzix / RomWBW) |
| TMS9918A (J.B. Langston) | `vdp18` из core-msx |
| YM2149 (Ed Brindley) | `jt49` из core-msx |
| Джойстики | геймпады USB через прошивку |
| Терминал (Pi Zero / Pico VGA) | RTL терминала VT100 из core-vt100 (pdp2011 vt, Sytse van Slooten, некоммерческая лицензия) |
| Второй последовательный порт | SIO B → `kg_mcu_uart` (мост через MCU), XMODEM с ПК |

Эталон для проверки — эмулятор Alan Cox [EmulatorKit](https://github.com/etchedpixels/emulatorkit) `rc2014`: 512K, ACIA, SIO/2, CTC, CF, DS1302, TMS9918A (без спрайтов). Трассы загрузки и снимки экрана сверяем с ним.

Софт: SCM (Steve Cousins), NASCOM BASIC (Grant Searle / Spencer Owen), RomWBW 3.6 (`RCZ80_std`: нужен модуль 512K, ACIA и SIO определяет сам), CP/M 2.2 / CP/M 3 / ZSDOS / Fuzix на CF, загрузчик MSX8 (игры MSX на TMS + AY).

## Плата

XC6SLX25: 15 032 LUT6, 30 064 FF, 52 RAMB16. SRAM 4 МБ, SDRAM 32 МБ. Вход 50 МГц. Z80 7,3728 МГц (ACIA: 7,3728 / 64 = 115 200 бод), турбо 14,7456 МГц — пункт OSD.

## Фазы

### Ф0 — исследование и замер (ветка f0-measure)

- [ ] Карта портов и памяти из исходников RomWBW 3.6 (`Source/HBIOS/Config/RCZ80_*.asm`, `cfg_RCZ80.asm`), SCM, NASCOM BASIC: адреса ACIA, SIO, CTC, CF, DS1302, TMS, AY, регистров банков 512K, ROM paging. Записать таблицу сюда.
- [ ] Набор ROM и образов CF для всех трёх профилей, их лицензии (можно ли класть в `.kg` и в репозиторий).
- [ ] Сборка EmulatorKit `rc2014`, прогон каждого ROM, эталонные трассы / экраны.
- [ ] XST на xc6slx25: T80 + vdp18 + jt49 + vt100 + hdf_ata + свои ACIA / SIO / CTC (заглушки), сумма LUT / BRAM.

### Ф1 — Mini G, первый запуск (ветка f1-minig)

Верх платы на kg_* (`kg_mcu2`: OSD, клавиатура, загрузка ROM из `.kg` в SRAM), Z80, банки ROM / RAM трёх профилей, ACIA + SIO/2, терминал VT100 на HDMI 720×576p50 (синхросигналы всегда есть), клавиатура USB → терминал → RX последовательного порта. Симуляция загрузки (Verilator / ghdl) против эталона из Ф0.
Цель: приглашение SCM, `Ok` у BASIC, загрузчик RomWBW и CP/M с ROM-диска.

### Ф2 — накопители и время (ветка f2-storage)

CF на образе SD1 (чтение и запись), DS1302, CTC с прерываниями (режим 2 / IM1 как в RomWBW), SIO B через MCU.
Цель: CP/M 2.2, CP/M 3 и ZSDOS с CF; `TIME` / `RTC`; загрузка Fuzix; передача файла XMODEM.

### Ф3 — графика, звук, джойстики (ветка f3-tms)

TMS9918A (вывод на HDMI вместо терминала по пункту OSD), YM2149 в микшер, джойстики, консоль RomWBW на TMS + клавиатура.
Цель: CP/M-игры под TMS, игры MSX через MSX8, звук AY.

### Ф4 — Go / Mini и релиз (ветка f4-release)

Топы Go и Mini, README / README.ru, сборки всех плат, `cores.json` в karabas-go.

## OSD (набросок, показать пользователю до мержа Ф1)

Profile (RomWBW 512K / Classic / Mini), Console (Terminal / TMS9918, с Ф3), CPU (7.37 / 14.74 MHz), CF image (файл, с Ф2), Reset.

## Беклог

V9958 (из core-msx2), SN76489, WD37C65 + образы дискет, Wi-Fi через ESP, модули Z180 и eZ80 (eZ80 из core-agon), принтер.
