# AURIX TC4D7 Lite Kit — Linux 개발 환경

Infineon **KIT_A3G_TC4D7_LITE** (AURIX TC4Dx, TriCore 1.8P) 를 **Linux 호스트에서** 개발하기
위한 작업 레포. Windows 전용 AURIX Development Studio / DAS 를 쓰지 않는 경로를 목표로 한다.

> **판정 (2026-09-04)**: 원래 목표였던 **TSN 트래픽 제너레이터로는 쓸 수 없다.**
> 100 Mbps 천장(영구) + errata 가 정밀도를 깎음 + Zephyr 에 GETH 드라이버 없음.
> 그리고 **굽는 경로가 미해결**이라 현재 보드에서 코드를 실행할 수 없다.
> 근거와 재개 조건은 → **[STATUS.md](STATUS.md)**

## 문서

| 문서 | 내용 |
|---|---|
| **[STATUS.md](STATUS.md)** | 판정, 관문 순서, 확보된 것, 재개 조건, 용량 |
| [docs/hardware.md](docs/hardware.md) | 기가비트 불가 근거(RMII 핀맵), 커넥터, 전원, 부트모드, LED/버튼 핀, 100M 성능 계산 |
| [docs/errata.md](docs/errata.md) | GETH 실리콘 결함 — 10/100 MII 전용 2개 + TSN 결함 + RX DMA 스톨 계열 |
| [docs/toolchain.md](docs/toolchain.md) | tricore-elf-gcc 후보 5개 비교, Zephyr 에 커스텀 GCC 물리기 |
| [docs/flashing.md](docs/flashing.md) | **실질적 관문.** 굽는 경로 후보 4개와 우선순위 |

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
| LED · 버튼 · UART 콘솔 · Zephyr shell | 코드 가능 | Zephyr (벤더 브랜치에 dts 완비) |
| **CAN FD** (500 kbit/s arb + 2 Mbit/s data) | 코드 가능 | Zephyr (`can01`, TLE9371 STB gpio-hog) |
| I2C + 온보드 EEPROM(MAC ID) | 코드 가능 | Zephyr (`i2c0`, 24AA02E48) |
| I2C 센서 (예: LSM6DSL 계열 IMU) | 코드 가능 | Zephyr, 포크에 드라이버 있음 |
| 멀티코어 (cpu0~cpu5 + cpucs) | 코드 가능 | Zephyr, 코어별 dts |
| **이더넷 / TSN** | 불가 | Zephyr 에 GETH 드라이버 없음 → iLLD 베어메탈 필요 |
| SPI | 불가 | Zephyr 에 AURIX SPI 드라이버 없음 |
| BLE / WiFi | 불가 | TC4D7 에 무선이 없다 |
| 1 Gbps 이상 | **영구 불가** | 보드가 5G SerDes 를 안 뽑음 |
| **보드에서 실행** | **미해결** | flash runner 가 winIDEA (상용/Windows) |

"코드 가능"은 **빌드까지**를 뜻한다. 실행은 굽는 경로가 뚫려야 한다.

## 시작하기

```bash
scripts/00-check-env.sh        # 전제조건 + 보드 연결 확인 (아무것도 변경하지 않는다)
scripts/40-bsl-probe.py --watch 120   # ← 먼저 이걸 해라. 굽기가 뚫리는지 확인
scripts/20-init-workspace.sh   # Zephyr 워크스페이스 (Infineon 포크 aurix 브랜치, 약 6.5 GB)
scripts/10-build-toolchain.sh  # tricore-elf-gcc 소스 빌드 (오래 걸림, apt 의존성 필요)
scripts/30-build-app.sh apps/blinky cpu0
scripts/99-disk.sh             # 용량 리포트 (지우려면 --purge-ws)
```

**번호 순서대로 하지 말 것.** `40` 을 먼저 해야 한다 — 굽는 경로가 안 뚫리면
`10`(툴체인 소스 빌드)에 쓴 시간이 전부 버려진다. 이유는 [docs/flashing.md](docs/flashing.md).
번호는 파이프라인 단계이고 실행 순서가 아니다.

sudo 가 필요한 것은 하나뿐이다:

```bash
sudo apt install -y build-essential texinfo flex bison libgmp-dev libmpfr-dev libmpc-dev
```

## 이 레포의 Zephyr 는 별개 트리다

이 머신에 이미 `~/zephyrproject` (Zephyr **3.7.3** LTS, nRF52840 작업용) 가 있지만
**재사용할 수 없다.** Infineon 포크는 Zephyr **4.4.0** 기반이고 TriCore 아키텍처가
업스트림에 아직 머지되지 않았다 (PR #107516, open). 두 워크스페이스는 독립적으로 공존한다.

## 참고

- [KIT_A3G_TC4D7_LITE 유저 가이드](https://www.infineon.com/assets/row/public/documents/10/44/infineon-kit-a3g-tc4d7-lite-aurix-lite-kit-user-guide-usermanual-en.pdf)
- [AURIX TC4Dx errata sheet (E)ES-AB](https://www.infineon.com/assets/row/public/documents/10/52/infineon-aurix-tc4dx-ab-es-erratasheet-en.pdf)
- [Infineon/zephyr-aurix (`aurix` 브랜치)](https://github.com/Infineon/zephyr-aurix/tree/aurix)
- [Zephyr 업스트림 PR #107516](https://github.com/zephyrproject-rtos/zephyr/pull/107516) — 미머지
- [EEESlab/tricore-gcc-toolchain-11.3.0](https://github.com/EEESlab/tricore-gcc-toolchain-11.3.0)
