#include "mes.inc"
# =====================================================================
#  gpio20_test.s - TEST DE DIAGNOSTICO (temporal)
#
#  Pone GPIO20 como salida GPIO simple (sin UART) y lo hace parpadear
#  lento: alto ~medio segundo, bajo ~medio segundo, para siempre.
#
#  OBJETIVO: separar la capa fisica de la capa UART.
#    - Si GPIO20 parpadea (osciloscopio/multimetro/LED alterna 0V<->3.3V):
#      el pin esta sano, bien identificado, el IO_MUX en modo GPIO anda y
#      el output-enable (W1TS) funciona. => el problema es SOLO el ruteo
#      de la señal U1TXD por la matriz.
#    - Si GPIO20 queda plano: el problema es fisico/basico (pin equivocado,
#      valor de IO_MUX para modo GPIO, o el enable). Arreglar eso ANTES
#      de mirar nada de UART.
#
#  USO: en app_main, como PRIMERA llamada (no retorna):
#         call gpio20_blink_test
#  Quitarlo cuando termine el diagnostico.
#
#  Registros usados (en C3, ya en mes.inc):
#    IO_MUX_GPIO20_REG    0x60009054
#    GPIO_ENABLE_W1TS_REG 0x60004024   (habilitar salida: bit n)
#  Faltaban estos dos para manejar el nivel del pin manualmente:
#    GPIO_OUT_W1TS_REG    0x60004008   (poner el pin en ALTO: bit n)
#    GPIO_OUT_W1TC_REG    0x6000400C   (poner el pin en BAJO: bit n)
#  (Direcciones del handoff: OUT_W1TS=0x...4008, OUT_W1TC=0x...400C.)
# =====================================================================

        .equ    GPIO_OUT_W1TS_REG, 0x60004008
        .equ    GPIO_OUT_W1TC_REG, 0x6000400C

.text
.global gpio20_blink_test

gpio20_blink_test:
# --- configurar GPIO20 como salida GPIO simple ---
# IO_MUX: MCU_SEL=1 (funcion GPIO), FUN_DRV=2 -> 0x1800. Mismo valor que
# usa uart_init; si este test funciona, este valor queda VALIDADO.
        li      t0, IO_MUX_GPIO20_REG
        li      t1, 0x1800
        sw      t1, 0(t0)

# habilitar GPIO20 como salida (bit 20 en ENABLE)
        li      t0, GPIO_ENABLE_W1TS_REG
        li      t1, (1 << 20)
        sw      t1, 0(t0)

gbt_loop:
# --- GPIO20 = ALTO ---
        li      t0, GPIO_OUT_W1TS_REG
        li      t1, (1 << 20)
        sw      t1, 0(t0)
# esperar
        li      a0, 4000000
        call    delay

# --- GPIO20 = BAJO ---
        li      t0, GPIO_OUT_W1TC_REG
        li      t1, (1 << 20)
        sw      t1, 0(t0)
# esperar
        li      a0, 4000000
        call    delay

        j       gbt_loop