#include "soc/spi_mem_reg.h"
.data
str_oled_test:
        .string "OLED Test\n"

.text
.global oled_test
.global oled_init
.global oled_cmd
.global oled_data
.global oled_reset
.global oled_gpio_setup
.global delay

# ---- Mapeo de pines (bit en GPIO_OUT) ----
        .equ    PIN_RES,  0x08          # GPIO3
        .equ    PIN_DC,   0x10          # GPIO4
        .equ    PIN_CS,   0x20          # GPIO5
        .equ    PIN_SCLK, 0x40          # GPIO6
        .equ    PIN_MOSI, 0x80          # GPIO7
        .equ    PINS_OLED, 0xF8

# ---- Registros GPIO (base 0x60004000) ----
        .equ    GPIO_OUT_W1TS,    0x60004008
        .equ    GPIO_OUT_W1TC,    0x6000400C
        .equ    GPIO_ENABLE_W1TS, 0x60004024

# GPIO_FUNCn_OUT_SEL_CFG: OUT_SEL=128 (pin saca GPIO_OUT), OEN_SEL=1 (bit9)
        .equ    GPIO_FUNC3_OUT, 0x60004560
        .equ    GPIO_FUNC4_OUT, 0x60004564
        .equ    GPIO_FUNC5_OUT, 0x60004568
        .equ    GPIO_FUNC6_OUT, 0x6000456C
        .equ    GPIO_FUNC7_OUT, 0x60004570
        .equ    FUNC_OUT_GPIO,  0x280

# IO_MUX_GPIOn: MCU_SEL=1 (Funcion 1 = GPIO, bits 14:12), FUN_DRV=2 (bits 11:10)
        .equ    IO_MUX_GPIO3, 0x60009010
        .equ    IO_MUX_GPIO4, 0x60009014
        .equ    IO_MUX_GPIO5, 0x60009018
        .equ    IO_MUX_GPIO6, 0x6000901C
        .equ    IO_MUX_GPIO7, 0x60009020
        .equ    IO_MUX_GPIO_OUT, 0x1800

# =====================================================================
#  oled_init: configura los pines, resetea e inicializa el SSD1306.
#  Deja el display encendido y listo para recibir datos, pero NO dibuja
#  nada (la GDDRAM queda con lo que tuviera; conviene llamar oled_clear
#  despues, o dejar que menu_draw/el juego limpien antes de dibujar).
#
#  Esta es la rutina que debe llamar app_main antes de menu_main.
# =====================================================================
oled_init:
        addi    sp, sp, -4
        sw      ra, 0(sp)

        call    oled_gpio_setup
        call    oled_reset

# ---- Secuencia de comandos de configuracion ----
        li      a0, 0xAE                # Display OFF
        call    oled_cmd

        li      a0, 0x20                # Set Memory Addressing Mode
        call    oled_cmd
        li      a0, 0x02                #   0x02 = Page Addressing Mode
        call    oled_cmd

        li      a0, 0x8D                # Charge Pump Setting
        call    oled_cmd
        li      a0, 0x14                #   Enable Charge Pump
        call    oled_cmd

        li      a0, 0xA1                # Segment re-map (col 127 -> SEG0)
        call    oled_cmd
        li      a0, 0xC8                # COM scan direction remapped
        call    oled_cmd

        li      a0, 0xAF                # Display ON
        call    oled_cmd

        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret

# =====================================================================
#  oled_test: rutina de prueba. Inicializa el display y dibuja el
#  damero. NO se usa en el flujo normal del juego; queda disponible
#  para verificar que la pantalla y el control de la GDDRAM funcionan.
# =====================================================================
oled_test:
        addi    sp, sp, -4
        sw      ra, 0(sp)

        call    oled_init

        la      a0, str_oled_test
        call    jtag_send

        call    oled_draw_checkerboard

        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret

oled_gpio_setup:
# 1) IO_MUX: funcion GPIO
        li      t1, IO_MUX_GPIO_OUT
        li      t0, IO_MUX_GPIO3
        sw      t1, 0(t0)
        li      t0, IO_MUX_GPIO4
        sw      t1, 0(t0)
        li      t0, IO_MUX_GPIO5
        sw      t1, 0(t0)
        li      t0, IO_MUX_GPIO6
        sw      t1, 0(t0)
        li      t0, IO_MUX_GPIO7
        sw      t1, 0(t0)

# 2) Matriz de salida: pin saca GPIO_OUT, rompe JTAG
        li      t1, FUNC_OUT_GPIO
        li      t0, GPIO_FUNC3_OUT
        sw      t1, 0(t0)
        li      t0, GPIO_FUNC4_OUT
        sw      t1, 0(t0)
        li      t0, GPIO_FUNC5_OUT
        sw      t1, 0(t0)
        li      t0, GPIO_FUNC6_OUT
        sw      t1, 0(t0)
        li      t0, GPIO_FUNC7_OUT
        sw      t1, 0(t0)

# 3) Habilitar salida
        li      t0, GPIO_ENABLE_W1TS
        li      t1, PINS_OLED
        sw      t1, 0(t0)

# 4) Estado inicial: CS, RES, DC en alto
        li      t0, GPIO_OUT_W1TS
        li      t1, PIN_CS | PIN_RES | PIN_DC
        sw      t1, 0(t0)

# 5) SCLK y MOSI en bajo
        li      t0, GPIO_OUT_W1TC
        li      t1, PIN_SCLK | PIN_MOSI
        sw      t1, 0(t0)
        ret

delay:
        mv      t0, a0
delay_loop:
        addi    t0, t0, -1
        bnez    t0, delay_loop
        ret

# Reset SSD1306 (activo en bajo): alto -> bajo -> alto
oled_reset:
        addi    sp, sp, -4
        sw      ra, 0(sp)

        li      t0, GPIO_OUT_W1TS
        li      t1, PIN_RES
        sw      t1, 0(t0)
        li      a0, 50000
        call    delay

        li      t0, GPIO_OUT_W1TC
        li      t1, PIN_RES
        sw      t1, 0(t0)
        li      a0, 50000
        call    delay

        li      t0, GPIO_OUT_W1TS
        li      t1, PIN_RES
        sw      t1, 0(t0)
        li      a0, 50000
        call    delay

        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret

# Envia un byte por SPI, MSB primero. a0 = byte
spi_send_byte:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)

        andi    s0, a0, 0xFF
        li      t2, 8

spi_bit_loop:
        andi    t3, s0, 0x80
        beqz    t3, spi_bit_zero

spi_bit_one:
        li      t0, GPIO_OUT_W1TS
        li      t1, PIN_MOSI
        sw      t1, 0(t0)
        j       spi_clock

spi_bit_zero:
        li      t0, GPIO_OUT_W1TC
        li      t1, PIN_MOSI
        sw      t1, 0(t0)

spi_clock:
        li      t0, GPIO_OUT_W1TS
        li      t1, PIN_SCLK
        sw      t1, 0(t0)
        li      a0, 20
        call    delay

        li      t0, GPIO_OUT_W1TC
        li      t1, PIN_SCLK
        sw      t1, 0(t0)
        li      a0, 20
        call    delay

        slli    s0, s0, 1
        addi    t2, t2, -1
        bnez    t2, spi_bit_loop

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret

# Envia un COMANDO (DC=bajo). a0 = comando
oled_cmd:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        mv      s0, a0

        li      t0, GPIO_OUT_W1TC       # DC bajo -> comando
        li      t1, PIN_DC
        sw      t1, 0(t0)

        li      t0, GPIO_OUT_W1TC       # CS bajo -> seleccionar
        li      t1, PIN_CS
        sw      t1, 0(t0)

        mv      a0, s0
        call    spi_send_byte

        li      t0, GPIO_OUT_W1TS       # CS alto -> deseleccionar
        li      t1, PIN_CS
        sw      t1, 0(t0)

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret

# Envia un DATO (DC=alto). a0 = byte de datos
oled_data:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        mv      s0, a0

        li      t0, GPIO_OUT_W1TS       # DC alto -> dato
        li      t1, PIN_DC
        sw      t1, 0(t0)

        li      t0, GPIO_OUT_W1TC       # CS bajo -> seleccionar
        li      t1, PIN_CS
        sw      t1, 0(t0)

        mv      a0, s0
        call    spi_send_byte

        li      t0, GPIO_OUT_W1TS       # CS alto -> deseleccionar
        li      t1, PIN_CS
        sw      t1, 0(t0)

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret

# Dibuja un damero de cuadros de 8x8 pixeles (128x64, 8 paginas).
# Registros callee-saved usados: s0=pagina, s1=columna, s2=byte de pagina
oled_draw_checkerboard:
        addi    sp, sp, -16
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        sw      s1, 8(sp)
        sw      s2, 12(sp)

        li      s0, 0                   # pagina = 0

cb_page_loop:
# Fijar puntero al inicio de la pagina s0 (modo pagina)
        ori     a0, s0, 0xB0            # 0xB0 | pagina -> set page start
        call    oled_cmd
        li      a0, 0x00                # set lower column start = 0
        call    oled_cmd
        li      a0, 0x10                # set higher column start = 0
        call    oled_cmd

# Byte base de la pagina: filas pares -> 0xFF, impares -> 0x00.
# bit0 de la pagina decide el patron de arranque de la fila.
        andi    t0, s0, 1
        beqz    t0, cb_row_even
        li      s2, 0x00                # fila impar arranca en "apagado"
        j       cb_col_init
cb_row_even:
        li      s2, 0xFF                # fila par arranca en "encendido"

cb_col_init:
        li      s1, 0                   # columna = 0

cb_col_loop:
# Cada 8 columnas se invierte el byte (cuadros de 8 de ancho).
# (columna >> 3) & 1 decide si va el byte base o su inverso.
        srli    t0, s1, 3
        andi    t0, t0, 1
        beqz    t0, cb_use_base
        xori    a0, s2, 0xFF            # bloque invertido
        j       cb_send
cb_use_base:
        mv      a0, s2                  # bloque base
cb_send:
        call    oled_data

        addi    s1, s1, 1
        li      t0, 128
        blt     s1, t0, cb_col_loop     # siguiente columna

        addi    s0, s0, 1
        li      t0, 8
        blt     s0, t0, cb_page_loop    # siguiente pagina

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        lw      s2, 12(sp)
        addi    sp, sp, 16
        ret