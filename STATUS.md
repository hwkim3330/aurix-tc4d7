# 상태와 결정 (2026-09-04, 2026-09-21 갱신)

## 2026-09-21 업데이트 — 관문 1(굽기)이 다시 열렸다, 목표도 바뀌었다

새 목표: TSN 트래픽 제너레이터가 아니라 **AURIX TC4D7 ↔ ESP32-S3(W5500) Zenoh 브리지**
데모. 두 보드를 랜 케이블로 직결하고 zenoh-pico 로 pub/sub 하는 것이 목표다. 기가비트
천장·errata 판정(아래 원래 판정)은 이 새 목표에는 적용되지 않는다 — CBS/TAS 트래픽
젠 용도로는 여전히 접힌 채다.

**관문 1 (굽기) 이 열렸다.** `tools/openocd` 를 오늘 아침 직접 빌드했는데(Infineon 이
`interface/tas_client.cfg` + `target/infineon/tc4dx.cfg` 를 커밋한 dev 스냅샷,
`0.12.0+dev-g58c6c61`), Infineon **TAS**(DAS 와 별개로 Linux 바이너리가 있는 그 도구,
`tools/das/opt/Tools/DAS/8.3.0/bin/tas_server`) 와 물려서 **Linux 에서 TC4D7 에 실제로
디버그 연결됐다** — cpu0~cpu5 + cpucs 전부 TriCore 1.8 로 examine 성공. 아래 "후보 2"
문서화 당시엔 "TC4x 실증을 찾지 못했다"고 적었는데 그게 오늘 뒤집혔다.

곁들여 확인된 것:
- 함께 꽂힌 무관한 FT232 케이블이 TAS 의 "짝수 개 장치" 가정을 깨서 `FT_Open` 이 깨졌다
  — `scripts/tas_ftdi_filter.c` (LD_PRELOAD, Infineon VID/PID 만 통과) 로 우회
- **PFLASH0 은 캐시드 별칭(`0x80000000`)으로는 읽힌다. 비캐시드 별칭(`0xa0000000`,
  `.lsl` 의 `pfls0_nc`)으로는 `TAS PL0 mem request failed` 로 실패한다.** 원인 미확인
  (OCDS 락 추정은 아님 — 캐시드 쪽은 halt 상태에서 바로 읽힘)
- 비캐시드 주소 접근이 한 번 실패한 뒤로 세션이 `No targets to connect` 로 재연결이
  안 됐다. **타겟 RESET 버튼과 `usbreset`으로는 안 풀렸다** — 실제 원인은 둘 다 아니었다
  (아래).
- **관문 2 (툴체인) 도 이미 끝나 있다** — `toolchain/gcc-src/INSTALL/bin/tricore-elf-gcc`
  (11.3.1) 가 빌드되어 있다

**ESP32 쪽 (`apps/esp32_zenoh_w5500/`)**: zenoh-pico 를 Arduino 라이브러리로 조립하는
`scripts/50-build-zenoh-arduino-lib.sh` 작성, vendor/zenoh-pico 에 작은 패치 3개
(link.c/endpoint.c/transport 쪽 raweth 심볼이 `Z_FEATURE_RAWETH_TRANSPORT=0` 에서도
무조건 참조되던 버그 — 다른 전송(TCP/UDP/BT/…)과 같은 방식으로 `#if` 로 감쌈).
ESP32-S3(a4:cb:8f:e7:f0:bc) 에 실제로 컴파일·플래시·부팅 확인함 — **FQBN 에
`CDCOnBoot=cdc` 를 빠뜨리면 보드가 부팅은 하지만 USB 시리얼 출력이 전혀 안 나온다**
(크래시가 아니라 무음이었다, 헷갈리기 좋음). W5500 SPI 핀은 esp32-lidar/firmware/
lidar_probe (keti-reconfig 가 실측한 핀아웃: SCK=48/MISO=47/MOSI=21/CS=45, INT·RST
없음)의 `eth_w5500.h`/`w5500_spi.h` 를 그대로 재사용 — Arduino `ETH.begin()` 은 10ms
MAC 폴링이 박혀 있고 IDF W5500 드라이버 자체에 16KB RX 버퍼 랩어라운드 버그가 있어서
일부러 안 씀. **실기에서 링크업 확인됨**(100Mbit full-duplex, IP 192.168.50.2) —
AURIX 쪽에 아직 아무 펌웨어도 없는데도 PHY 링크가 뜬 것으로 봐서 두 보드가 랜 케이블로
이미 물려 있다.

### 2026-09-21 계속 — 진짜 원인은 `ftdi_sio`, 그리고 32바이트 전송 한계

USB 케이블을 완전히 뽑았다 다시 꽂고, `/dev/bus/usb/001/0xx` 권한(udev 규칙
`/etc/udev/rules.d/99-infineon-tas.rules`, `058b:0043` → `MODE="0666"`)까지 고친
뒤에도 `No targets to connect` 가 계속됐다. `strace -f -p <tas_server pid>` 로
잡은 진짜 원인: **커널 `ftdi_sio` 가 미니위글러의 UART 채널(`1-4:1.1`, `/dev/ttyUSB0`)
을 이미 바인드하고 있어서 TAS 의 `USBDEVFS_CLAIMINTERFACE` 가 `EBUSY` 로 실패**했다
(채널 A 는 원래부터 안 잡혀 있었다). `echo -n 1-4:1.1 > /sys/bus/usb/drivers/ftdi_sio/unbind`
로 풀자 cpu0~5+cpucs 전부 다시 examine 성공.

그런데 이어서 실제 메모리 접근을 해보니 **한 번의 읽기가 32바이트(8워드)를 넘으면
무조건 실패한다** (`mdw 0x80000000 8` 성공, `mdw 0x80000000 9` 부터 실패 — 여러 번
재현). `tools/openocd/src/target/aurix/tricore.c` 의 `ocmts_queue_read_block` 은
소프트웨어 단에서 최대 256워드까지 청크로 나누지만, 그보다 아래(DAP 자체의 버스트
전송) 어딘가에서 32바이트 넘는 요청이 깨진다 — 오늘 06:04 에 막 빌드된 dev 스냅샷의
미완성 지점으로 보인다. 이 한계 안에서는:
- **20MB 플래시 전체 백업은 32바이트 × 65만 번 왕복이 되어 비현실적**
- **플래시 굽기도 막힌다** — OpenOCD 의 flash write 는 보통 작은 알고리즘을 work-area
  RAM 에 먼저 올려 실행시키는데, 그 업로드 자체가 32바이트보다 크다

**결론: 디버그 연결(examine)까지는 확실히 된다. 그 이상(백업/굽기)은 이 dev 빌드가
아직 못 버틴다.** 다음에 재개한다면 `tricore-oss/openocd` 에 이후 커밋(수정)이 있는지
먼저 확인할 것 — 지금 커밋을 더 파고드는 건 시간 대비 소득이 낮다고 판단해 멈췄다.

## 원래 목표와 판정 (2026-09-04, TSN 트래픽 젠 용도 — 아래는 그 판정만 다룬다)

**목표**: LAN9662 / 9692 TSN 검증용 정밀 트래픽 제너레이터 (talker + 하드웨어 타임스탬프 listener)

**판정: 이 보드로는 안 된다.** 세 겹으로 막혔고 전부 우회 불가다.

1. **100 Mbps 천장 (영구)** — RJ45 하나, DP83825I 10/100, RMII. 칩의 나머지 4포트도 10/100 이고
   기가 이상인 2× 5 Gbps 는 SGMII SerDes 라 핀헤더로 못 뽑는다. 헤더에 남은 P16 은 4개뿐이라
   RGMII(12신호)도 불가 → [docs/hardware.md](docs/hardware.md)

2. **정밀도가 errata 로 깎여 있다** — errata 문서가 명시한다:
   *"there is no workaround to guarantee minimum IPG between transmission of back to back
   packets in the same time slot"* (`GETH_AI.032`). 정밀 talker 로서 팔아야 할 바로 그 속성이다.
   추가로 `GETH_AI.029` 는 CBS 가 프로그램한 대역폭보다 더 먹게 만들고(30% → 32.65%),
   `GETH_AI.034`/`GETH_AI.039` 는 **10/100 MII 모드 전용** 결함이다
   → [docs/errata.md](docs/errata.md)

3. **소프트웨어가 없다** — Zephyr 벤더 브랜치에 GETH 드라이버가 없다
   (`eth_tc4x_leth.c` = LETH 뿐, `ETH_TC4X_GETH` 는 Kconfig 심볼만 있고 소스 없음).
   보드 dtsi 에 ethernet 노드도 없다. iLLD 베어메탈로 직접 써야 하고 Qbv 공식 예제도 없다

**부수 판정**: 이 칩을 CBS/TAS 레퍼런스로 삼으면 안 된다. `GETH_AI.029`/`.032` 때문에
기준점 자체가 틀어진다.

## 결론: 접었다 (2026-09-04)

위 판정에 더해 실물에서 확인된 것:

- **BSL 프로브 무응답** — 굽는 유일한 저비용 후보가 응답하지 않았다.
  가설 2(부트 모드가 BSL 이 아님)가 맞으면 `R73`~`R76` 0603 리워크가 필요하다
  → [docs/flashing.md](docs/flashing.md) 측정 결과
- **Shield2Go / mikroBUS 소켓 미장착** — 확장 커넥터가 패드 상태다. I2C OLED 같은
  가장 값싼 확장조차 인두 작업이 선행된다

즉 남은 모든 경로에 인두 또는 상용 Windows 도구가 끼어 있다.

**이 보드는 자동차 평가 킷이다.** ASIL-D 락스텝 / CAN XL / PPU / 5 Gbps TSN 같은 값어치가
**Windows + ADS·winIDEA + iLLD + AUTOSAR** 안에서만 나온다. Linux + 취미 워크플로에서는
양쪽의 단점만 모인다 — ESP32 계열과 비교하면 굽기·무선·생태계에서 전부 밀린다.

**재개 조건이 충족될 때까지 보류.** 조사 결과는 이 레포에 남으므로 다시 조사할 일은 없다.

## 관문 순서 (수정됨)

처음엔 툴체인이 첫 관문이라고 봤는데 **틀렸다. 굽는 게 먼저다.**

```
1. 굽는 경로 확보     ← 미해결. 여기가 막히면 아래는 전부 버려지는 시간
2. tricore-elf-gcc    ← prebuilt 없음, 소스 빌드 필요 (apt 의존성도 필요)
3. 앱 빌드            ← 스크립트 준비됨
4. GETH 드라이버       ← TSN 을 원한다면. 비용 가장 큼
```

**1번이 왜 막혔나**: 벤더 보드 정의의 flash runner 가 `winidea`(iSYSTEM, 상용/Windows).
DAS 도 Windows 전용. → [docs/flashing.md](docs/flashing.md)

**1번의 유일한 저비용 후보**: **BSL over `/dev/ttyUSB0`**. 부트스트랩 로더가 쓰는
P14.0/P14.1 이 곧 ASCLIN0 이고 그게 곧 `ttyUSB0` 다. 추가 하드웨어 없이 USB 케이블만으로
말을 걸 수 있다. 재개한다면 **여기부터** 봐야 한다.

## 지금 확보된 것

| 항목 | 상태 |
|---|---|
| 보드 식별 · UART 매핑 · dialout · 디스크 확인 | ✅ `scripts/00-check-env.sh` 실측 통과 |
| Zephyr 워크스페이스 (Infineon 포크 `aurix`) | ✅ `ws/`, 보드 정의 7개 코어 타깃 확인 |
| 하드웨어 사실 · errata · 툴체인 · 굽기 조사 | ✅ `docs/` |
| apt 빌드 의존성 | ❌ sudo 필요 (아래) |
| tricore-elf-gcc | ❌ |
| 보드에서 코드 실행 | ❌ |

진행하려면:

```bash
sudo apt install -y build-essential texinfo flex bison libgmp-dev libmpfr-dev libmpc-dev
pip3 install --break-system-packages -r ws/zephyr/scripts/requirements.txt
```

## 이 보드가 값싸게 주는 것

TSN 을 포기하면 남는 것:

- **CAN FD** — 벤더 dts 가 이미 완성돼 있다. `can01`(M_CAN node 1), 500 kbit/s + 데이터 2 Mbit/s,
  TLE9371 STB 를 gpio-hog 로 부팅 시 normal 모드로 내려준다. 칩은 CAN XL 20 Mbps 도 지원
  (헤더는 1개)
- **PPU** — Synopsys ARC 벡터 코프로세서. MetaWare NN 컴파일러가 TensorFlow/ONNX 를 받아
  PPU 용으로 컴파일한다. 이 칩의 유일무이한 부분. 단 툴킷 확보(등록/라이선스)가 선행이고
  아직 조사하지 않았다
- 6 코어 @500 MHz 락스텝, 20 MB flash / 10 MB SRAM, 코어당 VM 8개

단, **어느 쪽이든 굽는 문제는 그대로다.**

## 기존 Zephyr 작업(nRF52840 / Joy-Con)에서 재사용 가능한 것

이 머신의 `~/pocket-hardware/joycon2-zephyr` (XIAO nRF52840 Sense, Zephyr 3.7.3 LTS + SDK 0.16.5)
와 비교하면:

**옮겨지는 것**
- **센서 경로** — Infineon 포크에 `lsm6dsl` / `lsm6dso` 등 ST IMU 드라이버가 있고
  `i2c_aurix.c` 도 있다. Joy-Con 쪽의 `sensor_sample_fetch` / `sensor_channel_get` 코드는
  Shield2Go 나 mikroBUS 에 I2C IMU 를 물리면 **그대로 포팅된다**
- Zephyr 작업 방식 자체 (west, prj.conf, devicetree, Kconfig)
- **단계 게이팅 방법론** — Joy-Con 프로젝트에서 "stage 1/2/3 으로 나눠 싸게 확인"한 그 방식.
  여기서는 **stage 0 = 굽기 검증**이어야 한다. 그게 안 되면 나머지가 전부 무효다

**옮겨지지 않는 것**
- **BLE 전부** — TC4D7 에는 무선이 없다. SoftDevice Controller, GATT, SMP 관련 지식은 무용
- **SDK 0.16.5** — arm-zephyr-eabi 만 들어 있다. TriCore 타깃이 없다
- **워크스페이스** — Joy-Con 쪽은 Zephyr **3.7.3**, Infineon 포크는 **4.4.0**. 릴리스가 7개
  차이나는 별개 트리다. 합칠 수 없고 각자 6 GB 를 쓴다

**가장 큰 차이는 굽는 방식이다**
- XIAO: **UF2** — 리셋 더블탭 → USB 드라이브로 마운트 → 파일 드래그. 도구가 0개다
- AURIX: winIDEA(상용/Windows). Joy-Con 이 쉬웠던 이유와 이 보드가 막힌 이유가 정확히 같은 지점이다

## 재개 조건

이 중 하나가 생기면 재개할 가치가 있다:

- **Windows 박스** — winIDEA / ADS + DAS 를 쓰면 관문 1이 아예 사라진다. 가장 빠른 길
- **TriBoard TC4x9** — 5 Gbps 포트와 PCIe 를 실제로 뽑는 보드. 트래픽 젠 목표가 되살아난다
- **BSL 프로토콜 문서 확보** — 관문 1을 Linux 에서 뚫을 수 있게 된다
- **PPU 를 쓸 이유** — 온디바이스 NN 을 ASIL-D 급 MCU 에서 돌려야 할 때

## 용량

| 경로 | 크기 | 성격 |
|---|---|---|
| `ws/modules` | 5.2 GB | 대부분 TriCore 무관 (nordic/st/nxp HAL 등). west 가 관리 |
| `ws/zephyr` | 1.3 GB | Infineon 포크 |
| 레포 본체 (`ws/` 제외) | **408 KB** | ← 실제 산출물. 조사 결과는 여기 다 있다 |

`ws/` 는 gitignore 되어 있고 `scripts/20-init-workspace.sh` 로 언제든 재생성된다.
공간이 급하면 지워도 손실이 없다 — `scripts/99-disk.sh` 참조.
