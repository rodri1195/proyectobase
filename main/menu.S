# =====================================================================
#  Menu inicial del MES (Mini Entertainment System)
#  Display SSD1306 128x64 por SPI bit-banging, ESP32-C3
#  Dos opciones: PRUEBA / ONLINE
#  Navegacion: GPIO0=ARRIBA, GPIO1=ABAJO, GPIO10=CONFIRMAR (pull-up, activo-bajo)
#  Resalte: recuadro alrededor de la opcion seleccionada
#
#  Depende de las rutinas de oled_min.s:
#    oled_cmd, oled_data, oled_gpio_setup, oled_reset, delay
# =====================================================================

# Rutinas definidas en oled_min.s (compilacion separada).
# .extern documenta que estos simbolos viven en otro objeto; el linker
# los resuelve siempre que oled_min.s los exporte con .global.
.extern oled_cmd
.extern oled_data
.extern delay

.data
# ---- Fuente 5x8: cada letra son 5 bytes (columnas verticales) ----
# bit0 = fila de arriba, bit7 = fila de abajo (formato pagina SSD1306)
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

# Cadenas como punteros a las letras de la fuente, terminadas en 0
# (cada entrada es la direccion de los 5 bytes de una letra)
        .align  2
str_prueba: .word font_P, font_R, font_U, font_E, font_B, font_A, 0
str_online: .word font_O, font_N, font_L, font_I, font_N, font_E, 0

.text
.global menu_main

# ---- Registros de entrada (botones) ----
        .equ    GPIO_IN_REG,  0x6000403C # estado de los pines (lectura)
        .equ    IO_MUX_GPIO0, 0x60009004 # +4*0
        .equ    IO_MUX_GPIO1, 0x60009008 # +4*1
        .equ    IO_MUX_GPIO10,0x6000902C # +4*10
# Valor IO_MUX para entrada con pull-up:
# MCU_SEL=1 (bit12) | FUN_IE=1 (bit9) | FUN_WPU=1 (bit8) = 0x1300
        .equ    IO_MUX_INPUT_PU, 0x1300

        .equ    BTN_UP,      0x001      # GPIO0  -> bit 0
        .equ    BTN_DOWN,    0x002      # GPIO1  -> bit 1
        .equ    BTN_CONFIRM, 0x400      # GPIO10 -> bit 10

# ---- Comandos de direccionamiento del SSD1306 ----
        .equ    CMD_PAGE_BASE, 0xB0     # 0xB0 | pagina -> set page start

# =====================================================================
#  Punto de entrada del menu. No retorna: cuando se confirma, salta
#  al modo elegido (placeholders modo_prueba / modo_online).
# =====================================================================
menu_main:
# s1 = opcion seleccionada (0 = PRUEBA, 1 = ONLINE)
# (s1 es callee-saved; este es el bucle principal, no retorna,
#  asi que no hace falta guardarlo en pila)
        li      s1, 0

        call    botones_setup

menu_loop:
# --- 1) Dibujar la pantalla del menu segun s1 ---
        mv      a0, s1
        call    menu_draw

# --- 2) Leer botones y actualizar seleccion ---
        call    boton_leer              # a0 = mascara de botones apretados

# CONFIRMAR? -> salir al modo elegido
        andi    t0, a0, BTN_CONFIRM
        bnez    t0, menu_confirmar

# ARRIBA? -> seleccion = 0
        andi    t0, a0, BTN_UP
        beqz    t0, chk_down
        li      s1, 0
        j       menu_delay

chk_down:
# ABAJO? -> seleccion = 1
        andi    t0, a0, BTN_DOWN
        beqz    t0, menu_delay
        li      s1, 1

menu_delay:
# Delay que marca el ritmo de repeticion al mantener apretado
# y sirve de anti-rebote.
        li      a0, 800000
        call    delay
        j       menu_loop

menu_confirmar:
# Pequeno anti-rebote y salto al modo elegido
        li      a0, 800000
        call    delay
        beqz    s1, modo_prueba
        j       modo_online

# ---------------------------------------------------------------------
#  Placeholders de los modos. Reemplazar por el codigo real del juego.
#  Por ahora solo vuelven al menu (lazo infinito de demostracion).
# ---------------------------------------------------------------------
modo_prueba:
# TODO: arrancar el modo de prueba (un solo jugador)
        j       menu_main

modo_online:
# TODO: arrancar el modo online
        j       menu_main

# =====================================================================
#  botones_setup: configura GPIO0, GPIO1, GPIO10 como entrada con pull-up
# =====================================================================
botones_setup:
        li      t1, IO_MUX_INPUT_PU
        li      t0, IO_MUX_GPIO0
        sw      t1, 0(t0)
        li      t0, IO_MUX_GPIO1
        sw      t1, 0(t0)
        li      t0, IO_MUX_GPIO10
        sw      t1, 0(t0)
        ret

# =====================================================================
#  boton_leer: lee GPIO_IN y devuelve en a0 una mascara con 1 en los
#  botones APRETADOS. Como usamos pull-up (activo-bajo), un bit en 0
#  significa apretado -> invertimos para trabajar con logica positiva.
# =====================================================================
boton_leer:
        li      t0, GPIO_IN_REG
        lw      t1, 0(t0)               # t1 = estado crudo (1=suelto, 0=apretado)
        not     t1, t1                  # ahora 1 = apretado
# aislar solo nuestros tres botones
        li      t2, BTN_UP | BTN_DOWN | BTN_CONFIRM
        and     a0, t1, t2
        ret

# =====================================================================
#  menu_draw: dibuja la pantalla completa del menu.
#  a0 = opcion seleccionada (0 = PRUEBA, 1 = ONLINE)
#
#  Layout:
#    PRUEBA en pagina 2 (filas 16-23), columna 40
#    ONLINE en pagina 4 (filas 32-39), columna 40
#    Recuadro alrededor de la opcion seleccionada.
# =====================================================================
menu_draw:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        mv      s0, a0                  # guardar seleccion

        call    oled_clear

# --- Texto "PRUEBA" en pagina 2, columna 40 ---
        li      a0, 2                   # pagina
        li      a1, 40                  # columna
        la      a2, str_prueba
        call    texto_dibujar

# --- Texto "ONLINE" en pagina 4, columna 40 ---
        li      a0, 4
        li      a1, 40
        la      a2, str_online
        call    texto_dibujar

# --- Recuadro alrededor de la opcion elegida ---
# PRUEBA ocupa pagina 2; ONLINE pagina 4.
# El recuadro lo dibujo una pagina arriba y una abajo del texto,
# de columna 34 a 92 (ancho que cubre las 6 letras + margen).
        beqz    s0, rec_prueba
        li      a0, 4                   # pagina del texto ONLINE
        j       rec_draw
rec_prueba:
        li      a0, 2                   # pagina del texto PRUEBA
rec_draw:
        li      a1, 34                  # columna izquierda
        li      a2, 92                  # columna derecha
        call    recuadro_dibujar

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret

# =====================================================================
#  oled_clear: pone toda la GDDRAM en 0 (pantalla negra).
#  Recorre las 8 paginas escribiendo 128 bytes de 0x00 en cada una.
# =====================================================================
oled_clear:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)

        li      s0, 0                   # pagina
oc_page:
        ori     a0, s0, CMD_PAGE_BASE   # set page start
        call    oled_cmd
        li      a0, 0x00                # lower col = 0
        call    oled_cmd
        li      a0, 0x10                # higher col = 0
        call    oled_cmd

        li      t0, 128                 # 128 columnas
oc_col:
        addi    sp, sp, -4
        sw      t0, 0(sp)               # guardar contador (oled_data usa t0)
        li      a0, 0x00
        call    oled_data
        lw      t0, 0(sp)
        addi    sp, sp, 4
        addi    t0, t0, -1
        bnez    t0, oc_col

        addi    s0, s0, 1
        li      t1, 8
        blt     s0, t1, oc_page

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret

# =====================================================================
#  texto_dibujar: escribe una cadena en una pagina.
#    a0 = pagina (0-7)
#    a1 = columna inicial
#    a2 = puntero a la cadena (lista de punteros-a-letra, terminada en 0)
#
#  Usa: s0=pagina, s1=columna actual, s2=puntero en la cadena,
#       s3=puntero a los 5 bytes de la letra actual, s4=contador de columnas
# =====================================================================
texto_dibujar:
        addi    sp, sp, -24
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        sw      s1, 8(sp)
        sw      s2, 12(sp)
        sw      s3, 16(sp)
        sw      s4, 20(sp)

        mv      s0, a0                  # pagina
        mv      s1, a1                  # columna
        mv      s2, a2                  # cadena

td_letra:
        lw      s3, 0(s2)               # puntero a la letra
        beqz    s3, td_fin              # 0 -> fin de la cadena

# Posicionar el puntero del display en (pagina s0, columna s1)
        ori     a0, s0, CMD_PAGE_BASE
        call    oled_cmd
        andi    a0, s1, 0x0F            # lower col = col & 0x0F
        call    oled_cmd
        srli    a0, s1, 4
        ori     a0, a0, 0x10            # higher col = 0x10 | (col >> 4)
        call    oled_cmd

# Enviar los 5 bytes de la letra
        li      s4, 5
td_col:
        lbu     a0, 0(s3)               # byte de columna
        addi    sp, sp, -4
        sw      s4, 0(sp)
        call    oled_data
        lw      s4, 0(sp)
        addi    sp, sp, 4
        addi    s3, s3, 1
        addi    s4, s4, -1
        bnez    s4, td_col

# Avanzar columna: 5 de la letra + 1 de separacion
        addi    s1, s1, 6
        addi    s2, s2, 4               # siguiente puntero en la cadena
        j       td_letra

td_fin:
        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        lw      s2, 12(sp)
        lw      s3, 16(sp)
        lw      s4, 20(sp)
        addi    sp, sp, 24
        ret

# =====================================================================
#  recuadro_dibujar: dibuja un rectangulo de 3 paginas de alto alrededor
#  de una pagina de texto.
#    a0 = pagina central (donde esta el texto)
#    a1 = columna izquierda
#    a2 = columna derecha
#
#  Lineas horizontales: en la pagina de arriba (a0-1) un byte con el bit
#  de mas abajo encendido (0x80), y en la de abajo (a0+1) un byte con el
#  bit de mas arriba (0x01), formando el marco. Lineas verticales: en las
#  columnas extrema izq/der, byte 0xFF en la pagina central.
#  (Aproximacion simple y legible; el marco "abraza" el texto.)
# =====================================================================
recuadro_dibujar:
        addi    sp, sp, -20
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        sw      s1, 8(sp)
        sw      s2, 12(sp)
        sw      s3, 16(sp)

        mv      s0, a0                  # pagina central
        mv      s1, a1                  # col izq
        mv      s2, a2                  # col der

# ----- Linea horizontal superior: pagina (s0-1), bit inferior -----
        addi    s3, s0, -1
        mv      a0, s3
        mv      a1, s1
        mv      a2, s2
        li      a3, 0x80                # bit de mas abajo de la pagina de arriba
        call    linea_horizontal

# ----- Linea horizontal inferior: pagina (s0+1), bit superior -----
        addi    s3, s0, 1
        mv      a0, s3
        mv      a1, s1
        mv      a2, s2
        li      a3, 0x01                # bit de mas arriba de la pagina de abajo
        call    linea_horizontal

# ----- Lados verticales: pagina central, columnas extremas -----
# columna izquierda
        mv      a0, s0
        mv      a1, s1
        li      a2, 0xFF
        call    punto_columna
# columna derecha
        mv      a0, s0
        mv      a1, s2
        li      a2, 0xFF
        call    punto_columna

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        lw      s2, 12(sp)
        lw      s3, 16(sp)
        addi    sp, sp, 20
        ret

# ---------------------------------------------------------------------
#  linea_horizontal: escribe el mismo byte en un rango de columnas.
#    a0=pagina, a1=col inicial, a2=col final, a3=byte a escribir
# ---------------------------------------------------------------------
linea_horizontal:
        addi    sp, sp, -20
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        sw      s1, 8(sp)
        sw      s2, 12(sp)
        sw      s3, 16(sp)
        mv      s0, a0
        mv      s1, a1
        mv      s2, a2
        mv      s3, a3

lh_loop:
# posicionar puntero en (s0, s1)
        ori     a0, s0, CMD_PAGE_BASE
        call    oled_cmd
        andi    a0, s1, 0x0F
        call    oled_cmd
        srli    a0, s1, 4
        ori     a0, a0, 0x10
        call    oled_cmd
# escribir el byte
        mv      a0, s3
        call    oled_data

        addi    s1, s1, 1
        ble     s1, s2, lh_loop

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        lw      s2, 12(sp)
        lw      s3, 16(sp)
        addi    sp, sp, 20
        ret

# ---------------------------------------------------------------------
#  punto_columna: escribe un byte en una sola (pagina, columna).
#    a0=pagina, a1=columna, a2=byte
# ---------------------------------------------------------------------
punto_columna:
        addi    sp, sp, -16
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        sw      s1, 8(sp)
        sw      s2, 12(sp)
        mv      s0, a0
        mv      s1, a1
        mv      s2, a2

        ori     a0, s0, CMD_PAGE_BASE
        call    oled_cmd
        andi    a0, s1, 0x0F
        call    oled_cmd
        srli    a0, s1, 4
        ori     a0, a0, 0x10
        call    oled_cmd
        mv      a0, s2
        call    oled_data

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        lw      s2, 12(sp)
        addi    sp, sp, 16
        ret