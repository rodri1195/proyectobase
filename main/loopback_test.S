# =====================================================================
#  loopback_test.s  -  Test de validacion de uart.S
#
#  USO:
#    En app_main, reemplazar temporalmente "call menu_main" por
#    "call test_main". test_main es autocontenido: hace oled_init y
#    uart_init el mismo, no depende de que app_main los haya llamado.
#
#  DOS PRUEBAS EN UN MISMO BINARIO:
#
#    PASO 1 - OSCILOSCOPIO (sin puente):
#      Sin nada conectado a GPIO20, el RX FIFO nunca recibe -> el test
#      se queda mandando 0x55 sin parar. Pone la sonda en GPIO20 y mide
#      el ancho de bit: a 115200 bps debe ser ~8.68 us/bit.
#      0x55 = 0b01010101 -> onda cuadrada alternante, ideal para medir.
#
#    PASO 2 - LOOPBACK (con puente GPIO20 <-> GPIO21):
#      El byte transmitido por GPIO20 entra por GPIO21. El test lo lee,
#      compara con 0x55 y revisa el status de error.
#        - Coincide y sin error  -> pantalla LLENA (OK)
#        - No coincide o framing/overflow -> pantalla VACIA (FAIL)
#      El resultado se CONGELA (primer resultado, no sigue actualizando).
#
#  Depende de:
#    uart.S    : uart_init, uart_tx_byte, uart_rx_byte, uart_rx_ready
#    oled_min.s: oled_init, oled_cmd, oled_data, delay
#    menu.s    : framebuffer, fb_clear, oled_flush
# =====================================================================

.text
.global test_main

        .equ    TEST_BYTE,   0x55       # patron alternante 0b01010101
        .equ    TX_PAUSE,    2000       # iteraciones de delay entre envios
        .equ    CMD_PAGE_BASE, 0xB0

test_main:
        call    oled_init
        call    uart_init

        call    fb_clear
        call    oled_flush

loop:
        li      a0, 0x4D                # 'M'
        call    uart_tx_byte

        call    uart_rx_byte            # espera recibir la M por RX

        li      t0, 0x4D
        bne     a0, t0, fail
        bnez    a1, fail

        call    fb_fill                 # pantalla llena = RX OK
        call    oled_flush

        j       loop                    # vuelve a mandar M

fail:
        call    fb_clear
        call    oled_flush
        j       fail

fb_fill:
        la      t0, framebuffer
        li      t1, 1024
        li      t2, 0xFF
ff_loop:
        sb      t2, 0(t0)
        addi    t0, t0, 1
        addi    t1, t1, -1
        bnez    t1, ff_loop
        ret
