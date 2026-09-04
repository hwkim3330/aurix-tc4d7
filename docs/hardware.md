# 하드웨어 사실 (KIT_A3G_TC4D7_LITE)

출처: [유저 가이드 002-41555 Rev. *A, 2026-05-12](https://www.infineon.com/assets/row/public/documents/10/44/infineon-kit-a3g-tc4d7-lite-aurix-lite-kit-user-guide-usermanual-en.pdf)

## MCU

`SAK-TC4D7XP-20MF500MC` — AURIX TC4Dx, TriCore 1.8P

- 6 코어 @ 500 MHz (락스텝), 최대 20 MB eFlash / 10 MB SRAM
- PPU (Parallel Processing Unit, Synopsys ARC 기반 벡터 코프로세서)
- **칩 기준** 이더넷: 2× 최대 5 Gbps (L2 브리징) + 4× 10/100 Mbps (L2 브리징)
- CAN: 20× CAN FD + 4× CAN XL (최대 20 Mbps)
- 코어당 가상머신 최대 8개

## 기가비트가 불가능한 이유 (보드 한계)

세 겹으로 막혀 있다:

1. **RJ45(X4) 는 GETH0 Port0 하나뿐**이고 PHY 가 TI **DP83825I = 10/100 전용**, **RMII** 연결
2. **칩의 나머지 4포트도 10/100** 이다. 기가 이상은 2× 5 Gbps 뿐이고 그건 **SGMII SerDes** —
   0.1인치 핀헤더로 물리적으로 못 뽑는다
3. **헤더로 추가 MII/RGMII 를 만들 수도 없다.** RMII 가 아래 핀을 이미 쓰고, X1 에 나오는
   나머지 P16 은 **P16.9~P16.12 네 개뿐**(X1.13/15/17/19). RGMII 는 12신호가 필요하므로 개수 자체가 안 됨

5 Gbps / PCIe 를 쓰려면 **TriBoard TC4x9** 급 보드가 필요하다 (PCIe 는 TC4D9 만).

### 이더넷 핀맵 (유저 가이드 Table 8)

| DP83825I 신호 | AURIX 핀 / 기능 |
|---|---|
| MDIO | P21.3, GETH0_PX_MDIOD / GETH0_PX_MDIO3 |
| MDC | P21.2, GETH0_P0_MDC |
| TX_EN | P16.13, GETH0_P0_RMIIC_TX_EN |
| TX_D0 | P16.6, GETH0_P0_RMIIC_TXD0 |
| TX_D1 | P16.8, GETH0_P0_RMIIC_TXD1 |
| CRS_DV | P16.1, GETH0_P0_CRSDVC |
| RX_D0 | P16.4, GETH0_P0_RXD0D |
| RX_D1 | P16.0, GETH0_P0_RXD1D |
| 50 MHz Out | P16.2, GETH0_P0_REFCLKD (RMII 기준 클럭 **입력**) |

주의: 컨트롤러가 **GETH0** 이다. Zephyr 벤더 브랜치의 이더넷 드라이버는
`eth_tc4x_leth.c` = **LETH**(저속 이더넷)이므로 이 포트를 구동하지 못한다.

## 100 Mbps 성능 여력

라인레이트는 하드웨어에 부담이 아니다:

- 64 B 프레임 on-wire = 64 + 8(preamble/SFD) + 12(IFG) = 84 B = 672 bit
  → **148,809 fps**, 프레임당 **6.72 µs**
- 500 MHz 에서 프레임당 **약 3,360 사이클**. DMA 디스크립터 링을 쓰므로 CPU 가 페이로드를
  만지지 않는다. GETH DMA 는 애초에 5 Gbps 급으로 설계된 블록
- 1518 B 프레임은 8,127 fps 로 더 여유

**병목은 속도가 아니라 정밀도**다 — [errata.md](errata.md) 의 `GETH_AI.034`(IPG),
`GETH_AI.039`(MII 언더플로), `GETH_AI.029`(CBS 크레딧) 참조.

## 커넥터 / 확장

- 핀 헤더 **X1, X2** (2×20, 0.1") — 대부분 AURIX 핀
- **Shield2Go 슬롯 2개** (S2G1, S2G2)
- **mikroBUS 1개**
- **Arduino 호환 헤더** (X301~X304)
- CAN 헤더 1×2 (0.1") — TLE9371VSJ, **CAN node 1**, 120 Ω 종단
- RJ45 (X4)
- USB-C (J1) — 전원 + miniWiggler
- 10핀 DAP 디버그 커넥터
- **로직 레벨 3.3 V 전용. 5 V 쉴드 비호환** (유저 가이드 명시)
- 옵션 미장착: SEMPER NOR flash (S25HL/S35HL, SOIC-16), F-RAM (FM25VN10-G/CY15B, SO8-150).
  장착 시 부속 저항·커패시터도 함께 필요

### 확장 시 쓸 수 있는 버스 (Zephyr 현재 기준)

| 버스 | mikroBUS 핀 | Zephyr 드라이버 |
|---|---|---|
| I2C | SCL P13.1 / SDA P13.2 | 있음 (`i2c_aurix.c`) |
| SPI | SCK P15.8 / MISO P15.7 / MOSI P15.6 / CS P14.7 | **없음** |
| UART | TX P15.0 / RX P15.1 | 있음 (ASCLIN) |
| PWM | P02.8 (eGTM) | 없음 |
| AN | AN10 | 없음 |

→ 지금 Zephyr 로 붙일 수 있는 확장 보드는 **I2C / GPIO / UART 계열**뿐이다.

## 전원

- DC 플러그 X3: **7~14 V 권장** (허용 5~16 V), 배럴 5.5 mm / 내경 2.1 또는 2.5 mm, **중심 +**
- USB-C J1: 5 V (Schottky D3 때문에 3.3 V 벅 입력은 약 4.5 V)
- 우선순위: X3 > 7 V → X3 / X3 < 5.5 V → J1 / 5.5~7 V → 둘 다
- **X3 나 J1 로 전원을 넣은 상태에서 헤더의 VDDEXT/+5V/+3.3V 핀에 외부 전원을 넣지 말 것**
  (역전류 보호 없음, 이 핀들은 출력 전용)

## LED / 버튼 / 포텐셔미터

| 이름 | AURIX 핀 | 비고 |
|---|---|---|
| LED1 | P03.9 | 녹색, low-active |
| LED2 | P03.10 | 녹색, low-active |
| LED5 | ESR0 | 적색, 리셋 표시 |
| LED4 | ADBUS4 (ACTIV) | miniWiggler 상태 (DAS 서버가 제어) |
| LED6 | ADBUS7 (RUN) | miniWiggler 연결 표시 |
| Button | P03.11 | low-active |
| Reset | /PORST | low-active |
| R32 포텐셔미터 | AN0 | 250 kΩ. R35 제거하면 AN0 를 다른 용도로 쓸 수 있으나 포텐셔미터 기능은 사라진다 |

주의: **LED4(miniWiggler 사용 중)가 켜져 있으면 DAP 커넥터에 아무것도 연결하지 말 것.**

## UART

- 기본 **ASCLIN0 = P14.0 / P14.1** (generic bootstrap loader 도 이 경로)
- ASCLIN0 는 Arduino 핀에도 걸려 있다 (X304.1 = P15.3 ASCLIN0_ARXB, X304.2 = P15.2 ASCLIN0_ATX)
- 대안으로 **ASCLIN11** 을 쓸 수 있다 — 단 R14, R15 를 장착하고 P14.0/P14.1 을 설정하지 않아야 함

## 부트 모드 (HWCFG[3..4])

| HWCFG[3..4] | 부트 타입 |
|---|---|
| 00 | Generic BSL, P14.0/1 (CAN/ASC) |
| 10 | ASC BSL, P15.2/3 |
| X1 | BMHD 에서 시작. BMHD 미프로그램이면 HARR 또는 generic BSL 로 폴백 |
