# =====================================================================
#  Menu inicial del MES (Mini Entertainment System) - con DOBLE BUFFER
#  Display SSD1306 128x64 por SPI bit-banging, ESP32-C3
#  Dos opciones: PRUEBA / ONLINE
#  Navegacion: GPIO0=ARRIBA, GPIO1=ABAJO, GPIO10=CONFIRMAR (pull-up, activo-bajo)
#
#  ARQUITECTURA DE DOBLE BUFFER:
#    - framebuffer: 1024 bytes en RAM (8 paginas x 128 columnas).
#      El byte [pagina*128 + columna] es una columna vertical de 8 px.
#    - Las rutinas de dibujo escriben en el framebuffer (instantaneo,
#      invisible). NO tocan el display.
#    - oled_flush vuelca el framebuffer entero al display de una vez.
#      El usuario nunca ve estados intermedios -> sin parpadeo ni fantasmas.
#
#  Depende de oled_min.s: oled_cmd, oled_data, delay
#
#  NOTA: la logica ONLINE esta desactivada temporalmente. La opcion sigue
#  siendo navegable y se dibuja, pero al confirmar vuelve al menu sin actuar.
# =====================================================================



.data
# ---- Fuente 5x8: cada letra son 5 bytes (columnas verticales) ----
font_P: .byte   0x7F, 0x09, 0x09, 0x09, 0x0F
font_R: .byte   0x7F, 0x09, 0x19, 0x29, 0x4F
font_U: .byte   0x3F, 0x40, 0x40, 0x40, 0x3F
font_E: .byte   0x7F, 0x49, 0x49, 0x49, 0x41
font_B: .byte   0x7F, 0x49, 0x49, 0x49, 0x36
font_A: .byte   0x7E, 0x11, 0x11, 0x11, 0x7E
font_O: .byte   0x3E, 0x41, 0x41, 0x41, 0x3E
font_N: .byte   0x7F, 0x02, 0x0C, 0x10, 0x7F
font_L: .byte   0x7F, 0x40, 0x40, 0x40, 0x40
font_I: .byte   0x41, 0x41, 0x7F, 0x41, 0x41

        .align  2
str_prueba: .word font_P, font_R, font_U, font_E, font_B, font_A, 0
str_online: .word font_O, font_N, font_L, font_I, font_N, font_E, 0

# ---- El framebuffer: 1024 bytes (8*128). La "pantalla virtual". ----
        .align  4
framebuffer: .space 1024

.text
.global menu_main
.global botones_setup
.global boton_leer
.global fb_clear
.global fb_set_pixel
.global oled_flush
.global framebuffer

# ---- Registros de entrada (botones) ----
        .equ    GPIO_IN_REG,  0x6000403C
        .equ    IO_MUX_GPIO0, 0x60009004
        .equ    IO_MUX_GPIO1, 0x60009008
        .equ    IO_MUX_GPIO2, 0x6000900C
        .equ    IO_MUX_GPIO9, 0x60009028
        .equ    IO_MUX_GPIO10,0x6000902C
        .equ    IO_MUX_INPUT_PU, 0x1300 # MCU_SEL=1 | FUN_IE=1 | FUN_WPU=1

        .equ    BTN_UP,      0x001      # GPIO0  -> bit 0
        .equ    BTN_DOWN,    0x002      # GPIO1  -> bit 1
        .equ    BTN_LEFT,    0x004      # GPIO2  -> bit 2
        .equ    BTN_RIGHT,   0x200      # GPIO9  -> bit 9
        .equ    BTN_CONFIRM, 0x400      # GPIO10 -> bit 10

# Debounce del menu: ITERS vueltas de DELAY ciclos.
        .equ    MENU_DEBOUNCE_ITERS, 16
        .equ    MENU_DEBOUNCE_DELAY, 50000

        .equ    CMD_PAGE_BASE, 0xB0

# =====================================================================
#  menu_main: punto de entrada. No retorna.
# =====================================================================
menu_main:
        li      s1, 0                   # s1 = seleccion (0=PRUEBA, 1=ONLINE)
        call    botones_setup           # configurar GPIO0,1,10 como entrada con pull-up

menu_loop:
        mv      a0, s1
        call    menu_draw               # dibuja el cuadro y lo vuelca

        call    menu_poll_online

        call    boton_leer              # a0 = botones apretados
        andi    t0, a0, BTN_CONFIRM
        bnez    t0, menu_confirmar

        andi    t0, a0, BTN_UP
        beqz    t0, chk_down
        li      s1, 0
        
        j       menu_delay
chk_down:
        andi    t0, a0, BTN_DOWN
        beqz    t0, menu_delay
        li      s1, 1

menu_delay:
        li      s2, MENU_DEBOUNCE_ITERS
md_loop:
        li      a0, MENU_DEBOUNCE_DELAY
        call    delay
        addi    s2, s2, -1
        bnez    s2, md_loop
        j       menu_loop

# --- Confirmacion local del boton central ---
menu_confirmar:
        li      s2, MENU_DEBOUNCE_ITERS
mc_loop:
        li      a0, MENU_DEBOUNCE_DELAY
        call    delay
        addi    s2, s2, -1
        bnez    s2, mc_loop
        beqz    s1, modo_prueba
        j       modo_online

modo_prueba:
        call    juego_prueba            # arranca el modo de prueba
        j       menu_main               # al salir del juego, vuelve al menu

# --- ONLINE: placeholder. Logica desactivada temporalmente. ---
modo_online:
        call    online_send_m_wait_k
        call    online_as_controller
        j       menu_main               # no hace nada por ahora, vuelve al menu


menu_poll_online:
        addi    sp, sp, -4
        sw      ra, 0(sp)

        call    uart_recv_try           # a0 = byte recibido o -1

        li      t0, 0x4D                # 'M'
        bne     a0, t0, mpo_ret

# Llegó una M: somos secundaria
        li      a0, 0x4B                # 'K'
        call    uart_send_byte

        lw      ra, 0(sp)
        addi    sp, sp, 4

        call    online_as_follower
        j       menu_main

mpo_ret:
        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret
# =====================================================================
#  botones_setup: GPIO0, GPIO1, GPIO10 como entrada con pull-up
# =====================================================================
botones_setup:
        li      t1, IO_MUX_INPUT_PU
        li      t0, IO_MUX_GPIO0
        sw      t1, 0(t0)
        li      t0, IO_MUX_GPIO1
        sw      t1, 0(t0)
        li      t0, IO_MUX_GPIO2
        sw      t1, 0(t0)
        li      t0, IO_MUX_GPIO9
        sw      t1, 0(t0)
        li      t0, IO_MUX_GPIO10
        sw      t1, 0(t0)
        ret

# =====================================================================
#  boton_leer: a0 = mascara de botones apretados (logica activa-baja)
# =====================================================================
boton_leer:
        li      t0, GPIO_IN_REG
        lw      t1, 0(t0)
        not     t1, t1                  # 1 = apretado
        li      t2, BTN_UP | BTN_DOWN | BTN_LEFT | BTN_RIGHT | BTN_CONFIRM
        and     a0, t1, t2
        ret

# =====================================================================
#  menu_draw: arma el cuadro completo EN EL BUFFER y lo vuelca.
#  a0 = seleccion (0=PRUEBA, 1=ONLINE)
# =====================================================================
menu_draw:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        mv      s0, a0

# 1) Limpiar el buffer (instantaneo, invisible)
        call    fb_clear

# 2) Texto "PRUEBA" en pagina 2, columna 40
        li      a0, 2
        li      a1, 40
        la      a2, str_prueba
        call    fb_texto

# 3) Texto "ONLINE" en pagina 4, columna 40
        li      a0, 4
        li      a1, 40
        la      a2, str_online
        call    fb_texto

# 4) Recuadro alrededor de la opcion elegida.
#    Caja en pixeles: x de 34 a 92, y segun la pagina del texto.
#    PRUEBA: pagina 2 -> filas 16..23 ; caja y = 14..25
#    ONLINE: pagina 4 -> filas 32..39 ; caja y = 30..41
        beqz    s0, rec_prueba
        li      a0, 30                  # y_top   (ONLINE)
        li      a1, 41                  # y_bottom
        j       rec_draw
rec_prueba:
        li      a0, 14                  # y_top   (PRUEBA)
        li      a1, 25                  # y_bottom
rec_draw:
        li      a2, 34                  # x_left
        li      a3, 92                  # x_right
        call    fb_recuadro

# 5) Volcar el buffer al display (un solo barrido)
        call    oled_flush

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret

# =====================================================================
#  fb_clear: pone los 1024 bytes del framebuffer en 0.
# =====================================================================
fb_clear:
        la      t0, framebuffer
        li      t1, 1024
fc_loop:
        sb      zero, 0(t0)
        addi    t0, t0, 1
        addi    t1, t1, -1
        bnez    t1, fc_loop
        ret

# =====================================================================
#  fb_set_pixel: enciende el pixel (x, y) en el framebuffer.
#    a0 = x (0..127), a1 = y (0..63)
#  indice = (y/8)*128 + x ; bit = y%8
#  Si x o y estan fuera de rango, no hace nada.
# =====================================================================
fb_set_pixel:
# validar rango
        li      t0, 128
        bgeu    a0, t0, fsp_ret         # x >= 128 -> fuera
        li      t0, 64
        bgeu    a1, t0, fsp_ret         # y >= 64  -> fuera

        srli    t0, a1, 3               # t0 = pagina = y/8
        slli    t0, t0, 7               # t0 = pagina*128
        add     t0, t0, a0              # t0 = indice = pagina*128 + x
        la      t1, framebuffer
        add     t1, t1, t0              # t1 = &framebuffer[indice]

        andi    t2, a1, 7               # t2 = y%8 (bit dentro del byte)
        li      t3, 1
        sll     t3, t3, t2              # t3 = mascara del bit

        lbu     t4, 0(t1)
        or      t4, t4, t3
        sb      t4, 0(t1)
fsp_ret:
        ret

# =====================================================================
#  fb_texto: escribe una cadena en el framebuffer.
#    a0 = pagina (0..7) -> y base = pagina*8
#    a1 = columna inicial (x)
#    a2 = puntero a cadena (lista de punteros-a-letra terminada en 0)
#  Escribe cada letra como 5 columnas; usa fb_set_pixel para cada px.
# =====================================================================
fb_texto:
        addi    sp, sp, -28
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        sw      s1, 8(sp)
        sw      s2, 12(sp)
        sw      s3, 16(sp)
        sw      s4, 20(sp)
        sw      s5, 24(sp)

        slli    s0, a0, 3               # s0 = y base = pagina*8
        mv      s1, a1                  # s1 = x actual
        mv      s2, a2                  # s2 = puntero en la cadena

ft_letra:
        lw      s3, 0(s2)               # s3 = puntero a la letra (5 bytes)
        beqz    s3, ft_fin

        li      s4, 0                   # s4 = indice de columna (0..4)
ft_col:
        lbu     s5, 0(s3)               # s5 = byte de la columna (8 px)
# recorrer los 8 bits de la columna
        li      t5, 0                   # t5 = bit (0..7)
ft_bit:
        srl     t6, s5, t5
        andi    t6, t6, 1
        beqz    t6, ft_bit_next         # bit 0 -> no encender

# encender pixel (x = s1+s4, y = s0+t5)
        add     a0, s1, s4
        add     a1, s0, t5
# guardar lo que necesito (fb_set_pixel usa t0-t4, a0-a1)
        addi    sp, sp, -16
        sw      t5, 0(sp)
        sw      s5, 4(sp)
        sw      s3, 8(sp)
        sw      s4, 12(sp)
        call    fb_set_pixel
        lw      t5, 0(sp)
        lw      s5, 4(sp)
        lw      s3, 8(sp)
        lw      s4, 12(sp)
        addi    sp, sp, 16

ft_bit_next:
        addi    t5, t5, 1
        li      t6, 8
        blt     t5, t6, ft_bit

        addi    s3, s3, 1               # siguiente columna de la letra
        addi    s4, s4, 1
        li      t6, 5
        blt     s4, t6, ft_col

        addi    s1, s1, 6               # avanzar x: 5 + 1 separacion
        addi    s2, s2, 4               # siguiente puntero en la cadena
        j       ft_letra

ft_fin:
        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        lw      s2, 12(sp)
        lw      s3, 16(sp)
        lw      s4, 20(sp)
        lw      s5, 24(sp)
        addi    sp, sp, 28
        ret

# =====================================================================
#  fb_recuadro: dibuja un rectangulo hueco en el framebuffer.
#    a0 = y_top, a1 = y_bottom, a2 = x_left, a3 = x_right
#  Dos lineas horizontales (y_top, y_bottom de x_left a x_right) y
#  dos verticales (x_left, x_right de y_top a y_bottom).
# =====================================================================
fb_recuadro:
        addi    sp, sp, -24
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        sw      s1, 8(sp)
        sw      s2, 12(sp)
        sw      s3, 16(sp)
        sw      s4, 20(sp)
        mv      s0, a0                  # y_top
        mv      s1, a1                  # y_bottom
        mv      s2, a2                  # x_left
        mv      s3, a3                  # x_right

# --- lineas horizontales: recorrer x de x_left a x_right ---
        mv      s4, s2                  # x = x_left
fr_h:
# pixel (x, y_top)
        mv      a0, s4
        mv      a1, s0
        call    fb_set_pixel
# pixel (x, y_bottom)
        mv      a0, s4
        mv      a1, s1
        call    fb_set_pixel
        addi    s4, s4, 1
        ble     s4, s3, fr_h

# --- lineas verticales: recorrer y de y_top a y_bottom ---
        mv      s4, s0                  # y = y_top
fr_v:
# pixel (x_left, y)
        mv      a0, s2
        mv      a1, s4
        call    fb_set_pixel
# pixel (x_right, y)
        mv      a0, s3
        mv      a1, s4
        call    fb_set_pixel
        addi    s4, s4, 1
        ble     s4, s1, fr_v

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        lw      s2, 12(sp)
        lw      s3, 16(sp)
        lw      s4, 20(sp)
        addi    sp, sp, 24
        ret

# =====================================================================
#  oled_flush: vuelca el framebuffer entero al display.
#  Por cada pagina: fija el puntero (page start, col 0) y manda 128 bytes.
#  Este es el unico momento en que se toca el display por cuadro.
# =====================================================================
oled_flush:
        addi    sp, sp, -12
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        sw      s1, 8(sp)

        li      s0, 0                   # pagina
of_page:
        ori     a0, s0, CMD_PAGE_BASE   # set page start
        call    oled_cmd
        li      a0, 0x00                # lower col = 0
        call    oled_cmd
        li      a0, 0x10                # higher col = 0
        call    oled_cmd

# puntero al inicio de la pagina en el buffer: framebuffer + pagina*128
        la      s1, framebuffer
        slli    t0, s0, 7               # pagina*128
        add     s1, s1, t0

        li      t1, 128                 # 128 columnas
of_col:
        lbu     a0, 0(s1)               # byte del buffer
        addi    sp, sp, -16
        sw      s1, 0(sp)
        sw      t1, 4(sp)
        call    oled_data
        lw      s1, 0(sp)
        lw      t1, 4(sp)
        addi    sp, sp, 16
        addi    s1, s1, 1
        addi    t1, t1, -1
        bnez    t1, of_col

        addi    s0, s0, 1
        li      t2, 8
        blt     s0, t2, of_page

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        addi    sp, sp, 12
        ret