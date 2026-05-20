# main.S
# Comportamiento original conservado: led, boton, jtag
# Agregado: spi_setup + ssd1306_setup + demo visual

.data
str_hola: .string " RISC-V!\n"
str_spi_ok: .string "[spi] OK\n"
str_disp_ok: .string "[disp] OK\n"

.text
.global app_main

app_main:
        call    led_setup
        call    boton_setup

        call    spi_setup

        la      a0, str_spi_ok
        call    jtag_send

        call    ssd1306_setup

        la      a0, str_disp_ok
        call    jtag_send

        call    _draw_demo
        call    ssd1306_flush

app_loop:
        la      a0, str_hola
        call    jtag_send

        call    boton_read
        call    led_set

# === Logica del juego va aqui ===

        j       app_loop


# ─────────────────────────────────────────────────────
# _draw_demo - marco exterior + cruz central
# ─────────────────────────────────────────────────────
_draw_demo:
        addi    sp, sp, -12
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        sw      s1, 8(sp)

# Borde superior y=0
        li      s0, 0
_top:
        li      t0, 128
        bge     s0, t0, _top_done
        mv      a0, s0
        li      a1, 0
        call    ssd1306_set_pixel
        addi    s0, s0, 1
        j       _top
_top_done:

# Borde inferior y=63
        li      s0, 0
_bot:
        li      t0, 128
        bge     s0, t0, _bot_done
        mv      a0, s0
        li      a1, 63
        call    ssd1306_set_pixel
        addi    s0, s0, 1
        j       _bot
_bot_done:

# Borde izquierdo x=0
        li      s1, 0
_left:
        li      t0, 64
        bge     s1, t0, _left_done
        li      a0, 0
        mv      a1, s1
        call    ssd1306_set_pixel
        addi    s1, s1, 1
        j       _left
_left_done:

# Borde derecho x=127
        li      s1, 0
_right:
        li      t0, 64
        bge     s1, t0, _right_done
        li      a0, 127
        mv      a1, s1
        call    ssd1306_set_pixel
        addi    s1, s1, 1
        j       _right
_right_done:

# Linea horizontal central y=32
        li      s0, 44
_hline:
        li      t0, 84
        bge     s0, t0, _hline_done
        mv      a0, s0
        li      a1, 32
        call    ssd1306_set_pixel
        addi    s0, s0, 1
        j       _hline
_hline_done:

# Linea vertical central x=64
        li      s1, 24
_vline:
        li      t0, 40
        bge     s1, t0, _vline_done
        li      a0, 64
        mv      a1, s1
        call    ssd1306_set_pixel
        addi    s1, s1, 1
        j       _vline
_vline_done:

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        addi    sp, sp, 12
        ret