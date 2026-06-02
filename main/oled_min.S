#include "soc/spi_mem_reg.h"
.text
.global oled_test

        .equ    PIN_RES, 0x08
        .equ    PIN_DC, 0x10
        .equ    PIN_CS, 0x20
        .equ    PIN_SCLK, 0x40
        .equ    PIN_MOSI, 0x80


        .equ    PINS_OLED, 0xF8         # Todos los pines OLED juntos


        .equ    GPIO_OUT_W1TS, 0x60004008 #Poner pines en alto
        .equ    GPIO_OUT_W1TC, 0x6000400C #Poner pines en bajo
        .equ    GPIO_ENABLE, 0x60004020 #Configurar pines como salida


oled_test:
        call    oled_gpio_setup
        call    oled_reset

        li      a0, 0xAE                # Display OFF
        call    oled_cmd

        li      a0, 0x8D                # Charge Pump Setting
        call    oled_cmd

        li      a0, 0x14                # Enable Charge Pump
        call    oled_cmd

        li      a0, 0xA5                # All pixels ON
        call    oled_cmd

        li      a0, 0xAF                # Display ON
        call    oled_cmd
        ret

oled_gpio_setup:
# Configurar pines como salida
        li      t0, GPIO_ENABLE
        li      t1, PINS_OLED
        sw      t1, 0(t0)

        li      t0, GPIO_OUT_W1TS
        li      t1, PIN_CS | PIN_RES | PIN_DC # Poner CS, RES y DC en alto
        sw      t1, 0(t0)

        li      t0, GPIO_OUT_W1TC
        li      t1, PIN_SCLK | PIN_MOSI # Poner SCLK y MOSI en bajo
        sw      t1, 0(t0)

        ret

delay:
        mv      t0, a0

delay_loop:
        addi    t0, t0, -1
        bnez    t0, delay_loop
        ret

oled_reset:
        addi    sp, sp, -4
        sw      ra, 0(sp)

        li      t0, GPIO_OUT_W1TS
        li      t1, PIN_RES
        sw      t1, 0(t0)               # RES en bajo
        li      a0, 50000
        call    delay

        li      t0, GPIO_OUT_W1TC
        li      t1, PIN_RES
        sw      t1, 0(t0)               # RES en alto


        li      a0, 50000
        call    delay

        li      t0, GPIO_OUT_W1TS
        li      t1, PIN_RES
        sw      t1, 0(t0)               # RES en bajo

        li      a0, 50000
        call    delay

        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret

spi_send_byte:
# a0 = byte a enviar
# a1 = 0 para comando, 1 para dato

        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        
        andi    s0, a0, 0xFF            # Asegurar que solo se envíe un byte
        li      t2, 8                   # Contador de bits

spi_bit_loop:
        andi    t3, s0, 0x80            # Extraer el bit más significativo
        beqz    t3, spi_bit_zero

spi_bit_one:
# Enviar bit 1
        li      t0, GPIO_OUT_W1TS
        li      t1, PIN_MOSI
        sw      t1, 0(t0)               # MOSI en alto
        j       spi_clock

spi_bit_zero:
# Enviar bit 0
        li      t0, GPIO_OUT_W1TC
        li      t1, PIN_MOSI
        sw      t1, 0(t0)               # MOSI en bajo

spi_clock:
    
# Generar pulso de reloj
        li      t0, GPIO_OUT_W1TS
        li      t1, PIN_SCLK
        sw      t1, 0(t0)               # SCLK en alto
        li      a0, 20
        call    delay

        li      t0, GPIO_OUT_W1TC
        li      t1, PIN_SCLK
        sw      t1, 0(t0)               # SCLK en bajo
        li      a0, 20
        call    delay

        slli    s0, s0, 1               # Desplazar el siguiente bit al MSB
        addi    t2, t2, -1              # Decrementar contador de bits
        bnez    t2, spi_bit_loop        # Repetir para el siguiente bit

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret

oled_cmd:
        addi    sp,sp,-8
        sw      ra,0(sp)
        sw      s0,4(sp)

        mv      s0, a0                  # Guardar comando en s0

#DC=LOW-> comando

        li      t0, GPIO_OUT_W1TC
        li      t1, PIN_DC
        sw      t1, 0(t0)               # DC en bajo

#CS=LOW->SELECCIONAR PANTALLA
        li      t0, GPIO_OUT_W1TC
        li      t1, PIN_CS
        sw      t1, 0(t0)               # CS en bajo

#Enviar el byte por spi manual
        mv      a0, s0
        call    spi_send_byte

#CS=HIGH->DESELECCIONAR PANTALLA
        li      t0, GPIO_OUT_W1TS
        li      t1, PIN_CS
        sw      t1, 0(t0)               # CS en alto

        lw      ra,0(sp)
        lw      s0,4(sp)
        addi    sp,sp,8
        ret

