/*
 * 첫 동작 확인용. 보드에서 검증할 것:
 *   - 코어가 부팅하고 클럭 트리(25 MHz FOSC -> PLL)가 잡히는가
 *   - ASCLIN0 콘솔이 /dev/ttyUSB0 로 나오는가
 *   - P03.9 / P03.10 LED, P03.11 버튼이 devicetree 대로 동작하는가
 *
 * 보레이트: Zephyr 기본 115200 (보드 dts 의 asclin0 설정 확인)
 */

#include <zephyr/kernel.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/sys/printk.h>

static const struct gpio_dt_spec led0 = GPIO_DT_SPEC_GET(DT_ALIAS(led0), gpios);
static const struct gpio_dt_spec led1 = GPIO_DT_SPEC_GET(DT_ALIAS(led1), gpios);
static const struct gpio_dt_spec sw0 = GPIO_DT_SPEC_GET(DT_ALIAS(sw0), gpios);

int main(void)
{
	int ret;

	printk("\nAURIX TC4D7 Lite Kit — blinky\n");
	printk("board: %s\n", CONFIG_BOARD_TARGET);

	if (!gpio_is_ready_dt(&led0) || !gpio_is_ready_dt(&led1)) {
		printk("LED GPIO 컨트롤러가 준비되지 않았다\n");
		return -ENODEV;
	}

	ret = gpio_pin_configure_dt(&led0, GPIO_OUTPUT_INACTIVE);
	if (ret) {
		printk("led0 configure 실패: %d\n", ret);
		return ret;
	}
	ret = gpio_pin_configure_dt(&led1, GPIO_OUTPUT_INACTIVE);
	if (ret) {
		printk("led1 configure 실패: %d\n", ret);
		return ret;
	}

	if (gpio_is_ready_dt(&sw0)) {
		ret = gpio_pin_configure_dt(&sw0, GPIO_INPUT);
		if (ret) {
			printk("sw0 configure 실패: %d\n", ret);
		}
	}

	printk("루프 진입\n");

	for (uint32_t tick = 0;; tick++) {
		/* 두 LED 를 서로 반대로 -> 한쪽이 죽었는지 바로 보인다 */
		gpio_pin_set_dt(&led0, tick & 1);
		gpio_pin_set_dt(&led1, !(tick & 1));

		if ((tick % 10U) == 0U) {
			int btn = gpio_is_ready_dt(&sw0) ? gpio_pin_get_dt(&sw0) : -1;

			printk("tick=%u uptime=%llu ms button=%d\n",
			       tick, k_uptime_get(), btn);
		}

		k_msleep(250);
	}

	return 0;
}
