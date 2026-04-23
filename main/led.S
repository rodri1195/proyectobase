#include "soc/gpio_reg.h"
#include "soc/io_mux_reg.h"

        .equ    GPIO8_LED, 0x100
.text
.global led_setup
.global led_set

led_setup:
        la      t0, GPIO_ENABLE_W1TS_REG # W1TS = Write 1 To Set
        li      t1, GPIO8_LED
        sw      t1, 0(t0)
        ret

# El led esta con catodo (-) hacia el micro, por eso GPIO8=0 prende el led
led_set:
        li      t1, GPIO8_LED
        beqz    a0, led_off
        la      t0, GPIO_OUT_W1TC_REG   # Write 1 To Clear
        j       led_fin
led_off:
        la      t0, GPIO_OUT_W1TS_REG
led_fin:
        sw      t1, (t0)
        ret


