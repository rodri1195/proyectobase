#include "stdint_wrapper.h"
#include "soc/usb_serial_jtag_reg.h"

.text
.global jtag_send
jtag_send:
# a0 = str a mandar
        la      t0, USB_SERIAL_JTAG_EP1_CONF_REG
        la      t1, USB_SERIAL_JTAG_EP1_REG

free_loop:
        lw      t3, (t0)
        andi    t3, t3, USB_SERIAL_JTAG_SERIAL_IN_EP_DATA_FREE
        beqz    t3, free_loop

        lb      t3, (a0)
        beqz    t3, force_send          # fin de string
        sw      t3, (t1)

        addi    a0, a0, 1
        j       free_loop

force_send:
        li      t1, USB_SERIAL_JTAG_WR_DONE
        sw      t1, (t0)
        ret
