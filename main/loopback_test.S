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

# =====================================================================
#  test_main: punto de entrada del test. No retorna.
# =====================================================================
# test_main:
#         call    oled_init
#         call    uart_init

#         li      a0, 0x55
#         call    uart_tx_byte            # intenta mandar UN byte

# # leer STATUS justo después
#         li      t0, 0x60010000          # UART1_BASE
#         lw      t3, 0x001C(t0)          # t3 = STATUS completo

# # TXFIFO_CNT = bits [25:16]
#         srli    t4, t3, 16
#         andi    t4, t4, 0x3FF           # t4 = bytes en TX FIFO

# # TXD interno = bit 31
#         srli    t5, t3, 31              # t5 = nivel de la linea TX interna

# # pantalla LLENA si el FIFO quedo en 0 (byte salio) -> t4==0
# # pantalla VACIA si el FIFO quedo con el byte atascado -> t4!=0
#         beqz    t4, dbg_empty_fifo
# # FIFO NO vacio: byte atascado
#         call    fb_clear
#         call    oled_flush
#         j       dbg_halt
# dbg_empty_fifo:
#         call    fb_fill
#         call    oled_flush
# dbg_halt:
#         j       dbg_halt


# test_main:
#         call    oled_init
#         call    uart_init

# tx_loop:
#         li      a0, 0x40                # patrón visible en osciloscopio
#         call    uart_tx_byte
#         j       tx_loop

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
# test_main:
#         addi    sp, sp, -4
#         sw      ra, 0(sp)

# # ---- Inits propios (autocontenido) ----
#         call    oled_init
#         call    uart_init

# # ---- Pantalla arranca vacia = estado FAIL por defecto ----
#         call    fb_clear
#         call    oled_flush

# # =====================================================================
# #  Lazo principal: manda 0x55, y si volvio algo, lo valida.
# # =====================================================================
# tl_loop:
#         li      a0, TEST_BYTE
#         call    uart_tx_byte            # escupe byte (osciloscopio lo ve)

#         call    uart_rx_ready           # a0 = bytes en RX FIFO (no bloquea)
#         beqz    a0, tl_pause            # sin puente -> nada -> seguir mandando

# # ---- Llego algo: leerlo y validar ----
#         call    uart_rx_byte            # a0 = byte, a1 = status de error
#         li      t0, TEST_BYTE
#         bne     a0, t0, tl_fail         # byte distinto -> FAIL
#         bnez    a1, tl_fail             # framing u overflow -> FAIL
#         j       tl_ok

# # ---- Pausa entre envios y volver ----
# tl_pause:
#         li      a0, TX_PAUSE
#         call    delay
#         j       tl_loop

# # =====================================================================
# #  Resultado OK: pantalla LLENA, congelar.
# # =====================================================================
# tl_ok:
#         call    fb_fill
#         call    oled_flush
#         j       tl_halt

# # =====================================================================
# #  Resultado FAIL: pantalla VACIA, congelar.
# # =====================================================================
# tl_fail:
#         call    fb_clear
#         call    oled_flush
#         j       tl_halt

# # =====================================================================
# #  Congelar el primer resultado (no sigue actualizando).
# # =====================================================================
# tl_halt:
#         j       tl_halt

# =====================================================================
#  fb_fill: pone los 1024 bytes del framebuffer en 0xFF (pantalla llena).
#  Gemelo de fb_clear pero encendiendo todos los pixeles.
#  Clobbers: t0, t1, t2 (no llama a nadie -> no toca ra)
# =====================================================================
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
