#include "soc/gpio_reg.h"

        .equ    PIN_SCK,  (1 << 4)
        .equ    PIN_MOSI, (1 << 6)
        .equ    PIN_RES,  (1 << 7)
        .equ    PIN_DC,   (1 << 2)
        .equ    PIN_CS,   (1 << 3)
.global ssd1306_setup

ssd1306_setup:
# habilitar como salida
        la      t0, GPIO_ENABLE_W1TS_REG

        li      t1, PIN_SCK | PIN_MOSI | PIN_RES | PIN_DC | PIN_CS
        sw      t1, (t0)

        ret
# poner pin en 1
pin_set:
        la      t0, GPIO_OUT_W1TS_REG
        sw      a0, (t0)
        ret

# poner pin en 0
pin_clear:
        la      t0, GPIO_OUT_W1TC_REG
        sw      a0, (t0)
        ret

delay:
        li      t0, 50
delay_loop:
        addi    t0, t0, -1
        bnez    t0, delay_loop
        ret

.global ssd1306_reset

ssd1306_reset:
        li      a0, PIN_RES
        call    pin_clear               # RES = 0
        call    delay

        li      a0, PIN_RES
        call    pin_set                 # RES = 1
        call    delay

        ret

.global spi_write_byte

# a0 = byte a enviar
spi_write_byte:
        li      t0, 8                   # 8 bits

spi_loop:
# sacar MSB
        andi    t1, a0, 0x80
        beqz    t1, bit_zero

bit_one:
        li      a1, PIN_MOSI
        call    pin_set
        j       clock

bit_zero:
        li      a1, PIN_MOSI
        call    pin_clear

clock:
# pulso de clock
        li      a1, PIN_SCK
        call    pin_set
        call    delay

        li      a1, PIN_SCK
        call    pin_clear
        call    delay

        slli    a0, a0, 1
        addi    t0, t0, -1
        bnez    t0, spi_loop

        ret

.global ssd1306_cmd

# a0 = comando
ssd1306_cmd:
# CS = 0
        li      a1, PIN_CS
        call    pin_clear

# DC = 0 (comando)
        li      a1, PIN_DC
        call    pin_clear

        call    spi_write_byte

# CS = 1
        li      a1, PIN_CS
        call    pin_set

        ret