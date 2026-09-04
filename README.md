# AURIX TC4D7 Lite Kit — Linux 개발 환경

Infineon **KIT_A3G_TC4D7_LITE** (AURIX TC4Dx, TriCore 1.8P) 를 **Linux 호스트에서** 개발하기
위한 작업 레포. Windows 전용 AURIX Development Studio / DAS 를 쓰지 않는 경로를 목표로 한다.

## 하드웨어 식별 (실측)

USB 로 붙으면 이렇게 잡힌다:

```
Bus 001 Device 010: ID 058b:0043 Infineon Technologies DAS JDS AURIX LITE KIT V1.0 (TC4D7)
/dev/ttyUSB0  ftdi_sio  ID_SERIAL_SHORT=LKB1LPGR
```

- USB 는 온보드 miniWiggler = **FT2232HL**. 채널 A = DAP(디버그), 채널 B = **ttyUSB0 = 타깃 ASCLIN0 UART**
- USB 디스크립터 문자열은 `V1.0` 이지만 이건 FTDI EEPROM 에 구운 제품명 문자열이다.
  실크스크린 보드 리비전(유저 가이드는 2.x 기준)과 별개이므로 리비전 근거로 쓰지 말 것
- **펌웨어가 없어도 RJ45 링크는 올라온다.** DP83825I PHY 가 MAC/펌웨어와 무관하게 자체
  오토네고하므로, 링크업은 MAC 이 동작한다는 증거가 아니다

## 지금 되는 것 / 안 되는 것

| 기능 | 상태 | 경로 |
|---|---|---|
| LED · 버튼 · UART 콘솔 · Zephyr shell | 가능 | Zephyr (벤더 브랜치에 dts 완비) |
| **CAN FD** (500 kbit/s arb + 2 Mbit/s data) | 가능 | Zephyr (`can01`, TLE9371 STB gpio-hog) |
| I2C + 온보드 EEPROM(MAC ID) | 가능 | Zephyr (`i2c0`, 24AA02E48) |
| 멀티코어 (cpu0~cpu5 + cpucs) | 가능 | Zephyr, 코어별 dts |
| **이더넷 / TSN** | **불가** | Zephyr 에 GETH 드라이버 없음 → iLLD 베어메탈 필요 |
| SPI | 불가 | Zephyr 에 AURIX SPI 드라이버 없음 |
| 1 Gbps 이상 | **영구 불가** | 보드가 5G SerDes 를 안 뽑음 ([docs/hardware.md](docs/hardware.md)) |

자세한 근거는 [docs/hardware.md](docs/hardware.md), 실리콘 결함은 [docs/errata.md](docs/errata.md).

## 시작하기

```bash
scripts/00-check-env.sh        # 전제조건 확인 (west, cmake, ninja, dtc, 디스크)
scripts/10-build-toolchain.sh  # tricore-elf-gcc 소스 빌드 (오래 걸림)
scripts/20-init-workspace.sh   # Zephyr 워크스페이스 (Infineon 포크)
scripts/30-build-app.sh apps/hello cpu0
```

툴체인 선택지와 트레이드오프는 [docs/toolchain.md](docs/toolchain.md).

## 미해결 (순서대로 관문)

1. **tricore-elf-gcc 확보** — prebuilt 배포본이 없다. 소스 빌드 또는 등록형 상용 툴체인
2. **플래시 경로** — 벤더 Zephyr 의 `board.cmake` 가 flash runner 를 `winidea`
   (iSYSTEM, 상용/Windows) 로 지정한다. Linux 에서 굽는 경로는 미해결
3. **QEMU** — `qemu_tc4x` 타깃이 있지만 `qemu-system-tricore` 는 업스트림 QEMU 에 없다.
   커스텀 빌드 필요
4. **GETH 드라이버** — 이 보드 RJ45 를 쓰려면 직접 써야 한다 (아래 참고)

## 참고

- [KIT_A3G_TC4D7_LITE 유저 가이드](https://www.infineon.com/assets/row/public/documents/10/44/infineon-kit-a3g-tc4d7-lite-aurix-lite-kit-user-guide-usermanual-en.pdf)
- [AURIX TC4Dx errata sheet (E)ES-AB](https://www.infineon.com/assets/row/public/documents/10/52/infineon-aurix-tc4dx-ab-es-erratasheet-en.pdf)
- [Infineon/zephyr-aurix (`aurix` 브랜치)](https://github.com/Infineon/zephyr-aurix/tree/aurix)
- [Zephyr 업스트림 PR #107516](https://github.com/zephyrproject-rtos/zephyr/pull/107516) — 미머지
- [EEESlab/tricore-gcc-toolchain-11.3.0](https://github.com/EEESlab/tricore-gcc-toolchain-11.3.0)
