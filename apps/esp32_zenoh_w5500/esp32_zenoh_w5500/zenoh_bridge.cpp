// The two boards are wired back-to-back over Ethernet through a W5500
// SPI-Ethernet module (no switch, no DHCP server) -- so both ends use static
// IPs and an explicit Zenoh peer locator instead of multicast scouting.
//
// zenoh-pico is vendored under ../lib/zenoh-pico (see
// scripts/50-build-zenoh-arduino-lib.sh at the repo root) and pulled in via
// `arduino-cli compile --library apps/esp32_zenoh_w5500/lib/zenoh-pico`.
//
// CONFIRM BEFORE FLASHING: the SPI/CS/IRQ/RST pins below match this
// machine's *generic* ESP32-S3 DevKit + W5500 breakout wiring guess, not a
// measurement of the actual board. Adjust to match the real wiring.
#include "zenoh_bridge.h"

#include <Arduino.h>
#include <ETH.h>
#include <SPI.h>
#include <zenoh-pico.h>

// ---- W5500 SPI wiring (adjust to match the physical board) ----
#define W5500_PIN_SCK 12
#define W5500_PIN_MISO 13
#define W5500_PIN_MOSI 11
#define W5500_PIN_CS 10
#define W5500_PIN_IRQ 14
#define W5500_PIN_RST 9
#define W5500_PHY_ADDR 1

// ---- Direct-link static addressing (AURIX side must use .1) ----
static const IPAddress kLocalIP(192, 168, 50, 2);
static const IPAddress kGateway(192, 168, 50, 2);  // no router; loops to self
static const IPAddress kSubnet(255, 255, 255, 0);
#define AURIX_LOCATOR "udp/192.168.50.1:7447"

#define PUB_KEYEXPR "aurix/bridge/esp32"
#define SUB_KEYEXPR "aurix/bridge/**"

static z_owned_session_t s_session;
static z_owned_publisher_t s_pub;
static z_owned_subscriber_t s_sub;
static volatile bool s_eth_up = false;
static uint32_t s_idx = 0;

static void onEthEvent(arduino_event_id_t event) {
  switch (event) {
    case ARDUINO_EVENT_ETH_START:
      Serial.println("[eth] started");
      ETH.setHostname("esp32-zenoh-bridge");
      break;
    case ARDUINO_EVENT_ETH_CONNECTED:
      Serial.println("[eth] link up");
      break;
    case ARDUINO_EVENT_ETH_GOT_IP:
      Serial.printf("[eth] got IP: %s\n", ETH.localIP().toString().c_str());
      s_eth_up = true;
      break;
    case ARDUINO_EVENT_ETH_DISCONNECTED:
      Serial.println("[eth] link down");
      s_eth_up = false;
      break;
    default:
      break;
  }
}

static void dataHandler(z_loaned_sample_t *sample, void *arg) {
  (void)arg;
  z_view_string_t keystr;
  z_keyexpr_as_view_string(z_sample_keyexpr(sample), &keystr);
  z_owned_string_t value;
  z_bytes_to_string(z_sample_payload(sample), &value);

  Serial.print(" >> [sub] (");
  Serial.write(z_string_data(z_view_string_loan(&keystr)), z_string_len(z_view_string_loan(&keystr)));
  Serial.print(", ");
  Serial.write(z_string_data(z_string_loan(&value)), z_string_len(z_string_loan(&value)));
  Serial.println(")");

  z_string_drop(z_string_move(&value));
}

static bool startZenoh() {
  z_owned_config_t config;
  z_config_default(&config);
  zp_config_insert(z_config_loan_mut(&config), Z_CONFIG_MODE_KEY, "peer");
  zp_config_insert(z_config_loan_mut(&config), Z_CONFIG_CONNECT_KEY, AURIX_LOCATOR);

  Serial.print("[zenoh] opening session...");
  if (z_open(&s_session, z_config_move(&config), NULL) < 0) {
    Serial.println(" FAILED");
    return false;
  }
  Serial.println(" ok");

  z_view_keyexpr_t sub_ke;
  z_view_keyexpr_from_str_unchecked(&sub_ke, SUB_KEYEXPR);
  z_owned_closure_sample_t callback;
  z_closure_sample(&callback, dataHandler, NULL, NULL);
  if (z_declare_subscriber(z_session_loan(&s_session), &s_sub, z_view_keyexpr_loan(&sub_ke),
                            z_closure_sample_move(&callback), NULL) < 0) {
    Serial.println("[zenoh] subscriber declare FAILED");
    return false;
  }

  z_view_keyexpr_t pub_ke;
  z_view_keyexpr_from_str_unchecked(&pub_ke, PUB_KEYEXPR);
  if (z_declare_publisher(z_session_loan(&s_session), &s_pub, z_view_keyexpr_loan(&pub_ke), NULL) < 0) {
    Serial.println("[zenoh] publisher declare FAILED");
    return false;
  }

  Serial.println("[zenoh] session up: pub=" PUB_KEYEXPR " sub=" SUB_KEYEXPR);
  return true;
}

void zenohBridgeSetup() {
  Serial.begin(115200);
  uint32_t t0 = millis();
  while (!Serial && millis() - t0 < 3000) {
    delay(10);
  }

  Network.onEvent(onEthEvent);
  SPI.begin(W5500_PIN_SCK, W5500_PIN_MISO, W5500_PIN_MOSI, W5500_PIN_CS);
  if (!ETH.begin(ETH_PHY_W5500, W5500_PHY_ADDR, W5500_PIN_CS, W5500_PIN_IRQ, W5500_PIN_RST, SPI)) {
    Serial.println("[eth] ETH.begin() failed");
  }
  ETH.config(kLocalIP, kGateway, kSubnet);

  Serial.print("[eth] waiting for link");
  while (!s_eth_up) {
    Serial.print(".");
    delay(500);
  }
  Serial.println();

  while (!startZenoh()) {
    delay(2000);
  }
}

void zenohBridgeLoop() {
  if (!s_eth_up) {
    delay(500);
    return;
  }

  delay(1000);
  char buf[64];
  snprintf(buf, sizeof(buf), "[esp32 %4u] hello from W5500", (unsigned)s_idx++);

  z_owned_bytes_t payload;
  z_bytes_copy_from_str(&payload, buf);
  if (z_publisher_put(z_publisher_loan(&s_pub), z_bytes_move(&payload), NULL) < 0) {
    Serial.println("[zenoh] publish failed");
  } else {
    Serial.printf("[pub] %s\n", buf);
  }
}
