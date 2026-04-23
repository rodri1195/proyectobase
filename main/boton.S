#include "soc/gpio_reg.h"
#include "soc/io_mux_reg.h"

.text
.global boton_setup
.global boton_read

        .equ    GPIO0_BTN, 1

boton_setup:
# GPIO0 como input con pull up interno
        la      t0, IO_MUX_GPIO0_REG
        li      t1, FUN_IE | FUN_PU     # Input enable + Pull up
        sw      t1, (t0)
        ret

boton_read:
        la      t0, GPIO_IN_REG
        lw      t1, (t0)
        andi    a0, t1, GPIO0_BTN
# Esta con pullup, 1 = apagado, lo flipeo
        xori    a0, a0, 1
        ret
