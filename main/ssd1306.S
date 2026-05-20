# ssd1306.S - Driver SSD1306 128x64 via SPI para ESP32-C3
# Depende de spi.S: spi_write_byte, spi_write_buf
#
# Pines de control (GPIO normales):
#   RES = GPIO3
#   DC  = GPIO4
#   CS  = GPIO5
#
# Framebuffer: 1024 bytes (8 paginas x 128 columnas)
# bit0 de cada byte = fila superior de la pagina
#
# Funciones publicas:
#   ssd1306_setup
#   ssd1306_clear
#   ssd1306_fill       (a0 = patron)
#   ssd1306_flush
#   ssd1306_set_pixel  (a0=x, a1=y)
#   ssd1306_clear_pixel(a0=x, a1=y)
#   ssd1306_set_cursor (a0=pagina, a1=col)
#   ssd1306_draw_tile  (a0=tile_col, a1=tile_row, a2=ptr_sprite)

# Pines de control - bits en registros GPIO
        .equ    GPIO_RES_BIT,  0x08     # GPIO3 bit3
        .equ    GPIO_DC_BIT,   0x10     # GPIO4 bit4
        .equ    GPIO_CS_BIT,   0x20     # GPIO5 bit5

# Registros GPIO output
        .equ    GPIO_SET,      0x60004008 # W1TS - poner en HIGH
        .equ    GPIO_CLR,      0x6000400C # W1TC - poner en LOW
        .equ    GPIO_ENA_SET,  0x60004020 # habilitar como output

# IO_MUX pines de control
        .equ    IOMUX_GPIO3,   0x60009010
        .equ    IOMUX_GPIO4,   0x60009014
        .equ    IOMUX_GPIO5,   0x60009018
# MCU_SEL=0(GPIO), FUN_DRV=3, sin pull
        .equ    IOMUX_CTRL,    0x00000300

# Dimensiones
        .equ    DISP_W,        128
        .equ    DISP_H,        64
        .equ    DISP_PAGES,    8
        .equ    DISP_BUF,      1024

# Comandos SSD1306
        .equ    C_DISPLAY_OFF,     0xAE
        .equ    C_DISPLAY_ON,      0xAF
        .equ    C_SET_CONTRAST,    0x81
        .equ    C_ALL_ON_RESUME,   0xA4
        .equ    C_NORMAL_DISP,     0xA6
        .equ    C_SET_MUX,         0xA8
        .equ    C_DISP_OFFSET,     0xD3
        .equ    C_START_LINE,      0x40
        .equ    C_SEG_REMAP,       0xA1
        .equ    C_COM_FLIP,        0xC8
        .equ    C_SET_COM_PINS,    0xDA
        .equ    C_SET_OSC,         0xD5
        .equ    C_SET_PRECHARGE,   0xD9
        .equ    C_SET_VCOMH,       0xDB
        .equ    C_MEM_MODE,        0x20
        .equ    C_CHARGE_PUMP,     0x8D
        .equ    C_CHARGE_PUMP_ON,  0x14
        .equ    C_PAGE_BASE,       0xB0
        .equ    C_COL_LO,          0x00
        .equ    C_COL_HI,          0x10

# Macros de control de pines (usando pseudo-instrucciones)
# CS low  = seleccionar display
# CS high = deseleccionar
# DC low  = comando
# DC high = dato

.data
        .align  4
framebuffer:
        .space  DISP_BUF, 0

        .align  2
_init_seq:
        .byte   C_DISPLAY_OFF
        .byte   C_SET_OSC,        0x80
        .byte   C_SET_MUX,        0x3F
        .byte   C_DISP_OFFSET,    0x00
        .byte   C_START_LINE
        .byte   C_CHARGE_PUMP,    C_CHARGE_PUMP_ON
        .byte   C_MEM_MODE,       0x00
        .byte   C_SEG_REMAP
        .byte   C_COM_FLIP
        .byte   C_SET_COM_PINS,   0x12
        .byte   C_SET_CONTRAST,   0xCF
        .byte   C_SET_PRECHARGE,  0xF1
        .byte   C_SET_VCOMH,      0x40
        .byte   C_ALL_ON_RESUME
        .byte   C_NORMAL_DISP
        .byte   C_DISPLAY_ON
        .byte   0xFF                    # sentinel

.text
.global ssd1306_setup
.global ssd1306_clear
.global ssd1306_fill
.global ssd1306_flush
.global ssd1306_set_pixel
.global ssd1306_clear_pixel
.global ssd1306_set_cursor
.global ssd1306_draw_tile

# ─────────────────────────────────────────────────────
# _gpio_ctrl_setup
# Configura GPIO3(RES), GPIO4(DC), GPIO5(CS) como outputs
# ─────────────────────────────────────────────────────
_gpio_ctrl_setup:
        li      t0, IOMUX_GPIO3
        li      t1, IOMUX_CTRL
        sw      t1, 0(t0)

        li      t0, IOMUX_GPIO4
        sw      t1, 0(t0)

        li      t0, IOMUX_GPIO5
        sw      t1, 0(t0)

# Habilitar outputs
        li      t0, GPIO_ENA_SET
        li      t1, (GPIO_RES_BIT | GPIO_DC_BIT | GPIO_CS_BIT)
        sw      t1, 0(t0)

# Estado inicial: CS=HIGH, DC=HIGH, RES=HIGH
        li      t0, GPIO_SET
        li      t1, (GPIO_RES_BIT | GPIO_DC_BIT | GPIO_CS_BIT)
        sw      t1, 0(t0)
        ret

# ─────────────────────────────────────────────────────
# _delay_ms  (a0 = milisegundos aprox)
# Busy-wait simple. A ~160MHz: 160000 ciclos por ms
# ─────────────────────────────────────────────────────
_delay_ms:
        li      t1, 160000
        mul     t0, a0, t1
_delay_loop:
        addi    t0, t0, -1
        bnez    t0, _delay_loop
        ret

# ─────────────────────────────────────────────────────
# _send_cmd  (a0 = byte de comando)
# CS=LOW, DC=LOW, envia byte, CS=HIGH
# ─────────────────────────────────────────────────────
_send_cmd:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)

        mv      s0, a0

# DC = LOW (comando)
        li      t0, GPIO_CLR
        li      t1, GPIO_DC_BIT
        sw      t1, 0(t0)

# CS = LOW (seleccionar)
        li      t0, GPIO_CLR
        li      t1, GPIO_CS_BIT
        sw      t1, 0(t0)

        mv      a0, s0
        call    spi_write_byte

# CS = HIGH
        li      t0, GPIO_SET
        li      t1, GPIO_CS_BIT
        sw      t1, 0(t0)

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret

# ─────────────────────────────────────────────────────
# _send_data_byte  (a0 = byte de dato)
# CS=LOW, DC=HIGH, envia byte, CS=HIGH
# ─────────────────────────────────────────────────────
_send_data_byte:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)

        mv      s0, a0

# DC = HIGH (dato)
        li      t0, GPIO_SET
        li      t1, GPIO_DC_BIT
        sw      t1, 0(t0)

# CS = LOW
        li      t0, GPIO_CLR
        li      t1, GPIO_CS_BIT
        sw      t1, 0(t0)

        mv      a0, s0
        call    spi_write_byte

# CS = HIGH
        li      t0, GPIO_SET
        li      t1, GPIO_CS_BIT
        sw      t1, 0(t0)

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret

# ─────────────────────────────────────────────────────
# ssd1306_setup
# ─────────────────────────────────────────────────────
ssd1306_setup:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)

        call    _gpio_ctrl_setup

# Secuencia de reset hardware:
# RES=HIGH, esperar, RES=LOW, esperar, RES=HIGH
        li      t0, GPIO_SET
        li      t1, GPIO_RES_BIT
        sw      t1, 0(t0)

        li      a0, 1
        call    _delay_ms

        li      t0, GPIO_CLR
        li      t1, GPIO_RES_BIT
        sw      t1, 0(t0)

        li      a0, 10
        call    _delay_ms

        li      t0, GPIO_SET
        li      t1, GPIO_RES_BIT
        sw      t1, 0(t0)

        li      a0, 1
        call    _delay_ms

# Enviar secuencia de comandos de init
        la      s0, _init_seq

_setup_loop:
        lbu     t0, 0(s0)
        li      t1, 0xFF
        beq     t0, t1, _setup_done
        mv      a0, t0
        call    _send_cmd
        addi    s0, s0, 1
        j       _setup_loop

_setup_done:
        call    ssd1306_clear

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret

# ─────────────────────────────────────────────────────
# ssd1306_clear
# ─────────────────────────────────────────────────────
ssd1306_clear:
        addi    sp, sp, -4
        sw      ra, 0(sp)

        la      t0, framebuffer
        li      t1, DISP_BUF
_clr_loop:
        beqz    t1, _clr_done
        sb      zero, 0(t0)
        addi    t0, t0, 1
        addi    t1, t1, -1
        j       _clr_loop
_clr_done:
        call    ssd1306_flush

        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret

# ─────────────────────────────────────────────────────
# ssd1306_fill  (a0 = patron byte)
# ─────────────────────────────────────────────────────
ssd1306_fill:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)

        andi    s0, a0, 0xFF
        la      t0, framebuffer
        li      t1, DISP_BUF
_fill_loop:
        beqz    t1, _fill_done
        sb      s0, 0(t0)
        addi    t0, t0, 1
        addi    t1, t1, -1
        j       _fill_loop
_fill_done:
        call    ssd1306_flush

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret

# ─────────────────────────────────────────────────────
# ssd1306_flush - envia framebuffer completo al display
# ─────────────────────────────────────────────────────
ssd1306_flush:
        addi    sp, sp, -20
        sw      ra,  0(sp)
        sw      s0,  4(sp)              # pagina actual
        sw      s1,  8(sp)              # ptr framebuffer
        sw      s2, 12(sp)              # contador columnas
        sw      s3, 16(sp)

        li      s0, 0
        la      s1, framebuffer

_flush_page:
        li      t0, DISP_PAGES
        bge     s0, t0, _flush_done

# Posicionar cursor
        mv      a0, s0
        li      a1, 0
        call    ssd1306_set_cursor

# DC = HIGH (datos)
        li      t0, GPIO_SET
        li      t1, GPIO_DC_BIT
        sw      t1, 0(t0)

# CS = LOW
        li      t0, GPIO_CLR
        li      t1, GPIO_CS_BIT
        sw      t1, 0(t0)

# Enviar 128 bytes de esta pagina de una vez
        mv      a0, s1
        li      a1, DISP_W
        call    spi_write_buf

# CS = HIGH
        li      t0, GPIO_SET
        li      t1, GPIO_CS_BIT
        sw      t1, 0(t0)

        addi    s1, s1, DISP_W
        addi    s0, s0, 1
        j       _flush_page

_flush_done:
        lw      ra,  0(sp)
        lw      s0,  4(sp)
        lw      s1,  8(sp)
        lw      s2, 12(sp)
        lw      s3, 16(sp)
        addi    sp, sp, 20
        ret

# ─────────────────────────────────────────────────────
# ssd1306_set_cursor  (a0=pagina 0-7, a1=col 0-127)
# ─────────────────────────────────────────────────────
ssd1306_set_cursor:
        addi    sp, sp, -12
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        sw      s1, 8(sp)

        mv      s0, a0
        mv      s1, a1

        ori     a0, s0, C_PAGE_BASE
        call    _send_cmd

        andi    a0, s1, 0x0F
        call    _send_cmd

        srli    t0, s1, 4
        andi    a0, t0, 0x0F
        ori     a0, a0, C_COL_HI
        call    _send_cmd

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        addi    sp, sp, 12
        ret

# ─────────────────────────────────────────────────────
# ssd1306_set_pixel  (a0=x 0-127, a1=y 0-63)
# Solo modifica framebuffer. Llamar flush para ver.
# ─────────────────────────────────────────────────────
ssd1306_set_pixel:
        li      t0, DISP_W
        bgeu    a0, t0, _sp_out
        li      t0, DISP_H
        bgeu    a1, t0, _sp_out

        srli    t0, a1, 3               # pagina = y/8
        andi    t1, a1, 0x07            # bit   = y%8
        slli    t2, t0, 7               # pagina*128
        add     t2, t2, a0              # indice
        la      t3, framebuffer
        add     t3, t3, t2
        li      t4, 1
        sll     t4, t4, t1
        lbu     t5, 0(t3)
        or      t5, t5, t4
        sb      t5, 0(t3)
_sp_out:
        ret

# ─────────────────────────────────────────────────────
# ssd1306_clear_pixel  (a0=x, a1=y)
# ─────────────────────────────────────────────────────
ssd1306_clear_pixel:
        li      t0, DISP_W
        bgeu    a0, t0, _cp_out
        li      t0, DISP_H
        bgeu    a1, t0, _cp_out

        srli    t0, a1, 3
        andi    t1, a1, 0x07
        slli    t2, t0, 7
        add     t2, t2, a0
        la      t3, framebuffer
        add     t3, t3, t2
        li      t4, 1
        sll     t4, t4, t1
        not     t4, t4
        lbu     t5, 0(t3)
        and     t5, t5, t4
        sb      t5, 0(t3)
_cp_out:
        ret

# ─────────────────────────────────────────────────────
# ssd1306_draw_tile  (a0=col 0-15, a1=row 0-7, a2=ptr)
# Copia 8 bytes de sprite directo al framebuffer
# ─────────────────────────────────────────────────────
ssd1306_draw_tile:
        addi    sp, sp, -16
        sw      ra,  0(sp)
        sw      s0,  4(sp)
        sw      s1,  8(sp)
        sw      s2, 12(sp)

        slli    t0, a1, 7               # row*128
        slli    t1, a0, 3               # col*8
        add     t0, t0, t1
        la      t2, framebuffer
        add     s0, t2, t0
        mv      s1, a2
        li      s2, 8

_tile_loop:
        beqz    s2, _tile_done
        lbu     t3, 0(s1)
        sb      t3, 0(s0)
        addi    s0, s0, 1
        addi    s1, s1, 1
        addi    s2, s2, -1
        j       _tile_loop

_tile_done:
        lw      ra,  0(sp)
        lw      s0,  4(sp)
        lw      s1,  8(sp)
        lw      s2, 12(sp)
        addi    sp, sp, 16
        ret