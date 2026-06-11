#include "mes.inc"
# =====================================================================
#  juego.s - Modo de PRUEBA del MES (Bomberman)
#  Tablero 13x7, casillas de 9x9 px, un jugador movible.
#
#  Genera el tablero (70% cajas, paredes en posiciones impares, jugador
#  en (0,0) con sus adyacentes libres), lo dibuja con doble buffer, y
#  mueve al jugador con los 4 botones de direccion.
#
#  Reutiliza de menu.s: botones_setup, boton_leer, fb_clear,
#                       fb_set_pixel, oled_flush
#  Reutiliza de oled_min.s: delay
# =====================================================================

.extern botones_setup
.extern boton_leer
.extern fb_clear
.extern fb_set_pixel
.extern oled_flush
.extern delay

.data
# ---- Estado del tablero: 13*7 = 91 bytes, un byte por casilla ----
        .align  2
board:  .space  91

# ---- Posicion del jugador (en casillas) ----
player_x: .word 0
player_y: .word 0

.text
.global juego_prueba

# =====================================================================
#  juego_prueba: punto de entrada del modo de prueba. Genera el tablero,
#  coloca al jugador, y entra en el bucle de juego.
# =====================================================================
juego_prueba:
        addi    sp, sp, -4
        sw      ra, 0(sp)

        call    botones_setup           # asegurar pines de botones
        call    board_generate          # crear tablero aleatorio
        call    juego_loop              # bucle principal (retorna si se sale)

        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret

# =====================================================================
#  board_generate: llena 'board' con el tablero inicial.
#    - paredes (CELL_WALL) donde x e y son impares
#    - resto: 70% CELL_BOX, 30% CELL_EMPTY (via RNG)
#    - jugador (CELL_P1) en (0,0); (1,0) y (0,1) forzadas a EMPTY
#  Indice en board: y*BOARD_COLS + x
# =====================================================================
board_generate:
        addi    sp, sp, -16
        sw      ra, 0(sp)
        sw      s0, 4(sp)               # y
        sw      s1, 8(sp)               # x
        sw      s2, 12(sp)              # &board

        la      s2, board
        li      s0, 0                   # y = 0
bg_row:
        li      s1, 0                   # x = 0
bg_col:
# indice = y*COLS + x
        li      t0, BOARD_COLS
        mul     t0, s0, t0
        add     t0, t0, s1              # t0 = indice
        add     t1, s2, t0              # t1 = &board[indice]

# pared si (x impar) y (y impar)
        andi    t2, s1, 1
        andi    t3, s0, 1
        and     t2, t2, t3
        beqz    t2, bg_not_wall

        li      t4, CELL_WALL
        sb      t4, 0(t1)
        j       bg_next

bg_not_wall:
# 70% caja: tomar RNG % 100 < 70
# guardar punteros antes de llamar a rng
        addi    sp, sp, -16
        sw      t1, 0(sp)
        sw      s0, 4(sp)
        sw      s1, 8(sp)
        sw      s2, 12(sp)
        call    rng_mod100              # a0 = valor 0..99
        mv      t5, a0
        lw      t1, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        lw      s2, 12(sp)
        addi    sp, sp, 16

        li      t6, 70
        bge     t5, t6, bg_empty
        li      t4, CELL_BOX
        sb      t4, 0(t1)
        j       bg_next
bg_empty:
        li      t4, CELL_EMPTY
        sb      t4, 0(t1)

bg_next:
        addi    s1, s1, 1
        li      t0, BOARD_COLS
        blt     s1, t0, bg_col

        addi    s0, s0, 1
        li      t0, BOARD_ROWS
        blt     s0, t0, bg_row

# --- Forzar zona del jugador ---
# (0,0) = P1
        la      t0, board
        li      t1, CELL_P1
        sb      t1, 0(t0)               # indice 0 = (0,0)
# (1,0) = EMPTY  -> indice 1
        li      t1, CELL_EMPTY
        sb      t1, 1(t0)
# (0,1) = EMPTY  -> indice COLS
        li      t2, BOARD_COLS
        add     t3, t0, t2
        sb      t1, 0(t3)

# jugador en (0,0)
        la      t0, player_x
        sw      zero, 0(t0)
        la      t0, player_y
        sw      zero, 0(t0)

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        lw      s2, 12(sp)
        addi    sp, sp, 16
        ret

# =====================================================================
#  rng_mod100: devuelve en a0 un valor 0..99 del RNG de hardware.
#  Lee RNG_DATA_REG (32 bits aleatorios) y toma el resto mod 100.
# =====================================================================
rng_mod100:
        li      t0, RNG_DATA_REG
        lw      t1, 0(t0)               # 32 bits aleatorios
        li      t2, 100
        remu    a0, t1, t2              # a0 = t1 % 100
        ret

# =====================================================================
#  juego_loop: bucle principal del modo de prueba.
#    - dibuja el tablero
#    - lee botones, mueve al jugador si la casilla destino es transitable
#    - CONFIRMAR sale del modo (vuelve al menu)
# =====================================================================
juego_loop:
        addi    sp, sp, -4
        sw      ra, 0(sp)

jl_frame:
        call    board_draw              # dibuja tablero + jugador y vuelca

        call    boton_leer              # a0 = botones apretados

# CONFIRMAR -> salir
        li      t0, BTN_CONFIRM
        and     t1, a0, t0
        bnez    t1, jl_exit

# Determinar desplazamiento (dx, dy) segun el boton
# Solo se procesa un movimiento por iteracion (prioridad arriba->abajo->izq->der)
        li      t2, 0                   # dx
        li      t3, 0                   # dy

        li      t0, BTN_UP
        and     t1, a0, t0
        beqz    t1, jl_chk_down
        li      t3, -1
        j       jl_move
jl_chk_down:
        li      t0, BTN_DOWN
        and     t1, a0, t0
        beqz    t1, jl_chk_left
        li      t3, 1
        j       jl_move
jl_chk_left:
        li      t0, BTN_LEFT
        and     t1, a0, t0
        beqz    t1, jl_chk_right
        li      t2, -1
        j       jl_move
jl_chk_right:
        li      t0, BTN_RIGHT
        and     t1, a0, t0
        beqz    t1, jl_delay
        li      t2, 1

jl_move:
# intentar mover al jugador por (dx=t2, dy=t3)
        mv      a0, t2
        mv      a1, t3
        call    player_try_move

jl_delay:
        li      a0, 600000              # ritmo de repeticion / anti-rebote
        call    delay
        j       jl_frame

jl_exit:
        li      a0, 600000
        call    delay                   # anti-rebote al salir
        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret

# =====================================================================
#  player_try_move: intenta mover al jugador por (dx=a0, dy=a1).
#  Calcula la casilla destino; si esta dentro del tablero y es
#  transitable (EMPTY), actualiza la posicion del jugador y el tablero.
#  Casillas transitables: solo CELL_EMPTY (pared y caja bloquean).
# =====================================================================
player_try_move:
        addi    sp, sp, -16
        sw      ra, 0(sp)
        sw      s0, 4(sp)               # nuevo x
        sw      s1, 8(sp)               # nuevo y
        sw      s2, 12(sp)              # &board

# leer posicion actual
        la      t0, player_x
        lw      t1, 0(t0)               # x actual
        la      t0, player_y
        lw      t2, 0(t0)               # y actual

        add     s0, t1, a0              # nuevo x = x + dx
        add     s1, t2, a1              # nuevo y = y + dy

# validar limites: 0 <= nx < COLS, 0 <= ny < ROWS
        bltz    s0, ptm_no
        li      t3, BOARD_COLS
        bge     s0, t3, ptm_no
        bltz    s1, ptm_no
        li      t3, BOARD_ROWS
        bge     s1, t3, ptm_no

# indice destino = ny*COLS + nx
        la      s2, board
        li      t3, BOARD_COLS
        mul     t3, s1, t3
        add     t3, t3, s0              # t3 = indice destino
        add     t4, s2, t3
        lbu     t5, 0(t4)               # contenido destino

# transitable solo si EMPTY
        li      t6, CELL_EMPTY
        bne     t5, t6, ptm_no

# --- mover: limpiar casilla vieja, ocupar la nueva ---
# indice viejo = y*COLS + x
        la      t0, player_x
        lw      t1, 0(t0)
        la      t0, player_y
        lw      t2, 0(t0)
        li      t3, BOARD_COLS
        mul     t3, t2, t3
        add     t3, t3, t1              # indice viejo
        add     t0, s2, t3
        li      t1, CELL_EMPTY
        sb      t1, 0(t0)               # vaciar casilla vieja

        li      t1, CELL_P1
        sb      t1, 0(t4)               # ocupar casilla nueva

# actualizar posicion
        la      t0, player_x
        sw      s0, 0(t0)
        la      t0, player_y
        sw      s1, 0(t0)

ptm_no:
        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        lw      s2, 12(sp)
        addi    sp, sp, 16
        ret

# =====================================================================
#  board_draw: dibuja el tablero completo en el framebuffer y lo vuelca.
#  Recorre las 91 casillas; por cada una dibuja su sprite 9x9 segun el
#  codigo. Usa doble buffer (fb_clear -> dibujar -> oled_flush).
# =====================================================================
board_draw:
        addi    sp, sp, -20
        sw      ra, 0(sp)
        sw      s0, 4(sp)               # y
        sw      s1, 8(sp)               # x
        sw      s2, 12(sp)              # &board
        sw      s3, 16(sp)              # contenido casilla

        call    fb_clear

        la      s2, board
        li      s0, 0                   # y
bd_row:
        li      s1, 0                   # x
bd_col:
# contenido = board[y*COLS + x]
        li      t0, BOARD_COLS
        mul     t0, s0, t0
        add     t0, t0, s1
        add     t1, s2, t0
        lbu     s3, 0(t1)               # codigo de casilla

# pixel base de la casilla:
#   px = OFF_X + x*CELL_PX ; py = OFF_Y + y*CELL_PX
        li      t2, CELL_PX
        mul     t2, s1, t2
        addi    t2, t2, BOARD_OFF_X     # a0 = px (esquina)
        li      t3, CELL_PX
        mul     t3, s0, t3
        addi    t3, t3, BOARD_OFF_Y     # a1 = py (esquina)

# dibujar sprite segun s3
        mv      a0, t2
        mv      a1, t3
        mv      a2, s3
# guardar contexto de bucle (sprite usa muchos regs)
        addi    sp, sp, -16
        sw      s0, 0(sp)
        sw      s1, 4(sp)
        sw      s2, 8(sp)
        sw      s3, 12(sp)
        call    draw_sprite
        lw      s0, 0(sp)
        lw      s1, 4(sp)
        lw      s2, 8(sp)
        lw      s3, 12(sp)
        addi    sp, sp, 16

        addi    s1, s1, 1
        li      t0, BOARD_COLS
        blt     s1, t0, bd_col

        addi    s0, s0, 1
        li      t0, BOARD_ROWS
        blt     s0, t0, bd_row

        call    oled_flush

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        lw      s2, 12(sp)
        lw      s3, 16(sp)
        addi    sp, sp, 20
        ret

# =====================================================================
#  draw_sprite: dibuja el sprite de una casilla en el framebuffer.
#    a0 = px (esquina sup-izq), a1 = py, a2 = codigo de casilla
#  Sprites (8x8 dentro de la celda de 9, dejando 1px de separacion):
#    EMPTY -> nada
#    WALL  -> cuadrado relleno
#    BOX   -> marco + diagonal
#    P1    -> X (dos diagonales)
# =====================================================================
draw_sprite:
        addi    sp, sp, -24
        sw      ra, 0(sp)
        sw      s0, 4(sp)               # px
        sw      s1, 8(sp)               # py
        sw      s2, 12(sp)              # codigo
        sw      s3, 16(sp)              # iterador i
        sw      s4, 20(sp)              # iterador j
        mv      s0, a0
        mv      s1, a1
        mv      s2, a2

# EMPTY -> nada
        li      t0, CELL_EMPTY
        beq     s2, t0, ds_ret

# WALL -> relleno 8x8
        li      t0, CELL_WALL
        bne     s2, t0, ds_chk_box
        li      s3, 0                   # i (fila)
ds_wall_row:
        li      s4, 0                   # j (col)
ds_wall_col:
        add     a0, s0, s4
        add     a1, s1, s3
        call    ds_pixel
        addi    s4, s4, 1
        li      t0, 8
        blt     s4, t0, ds_wall_col
        addi    s3, s3, 1
        li      t0, 8
        blt     s3, t0, ds_wall_row
        j       ds_ret

ds_chk_box:
# BOX -> marco + diagonal
        li      t0, CELL_BOX
        bne     s2, t0, ds_chk_p1
# marco superior e inferior
        li      s3, 0
ds_box_h:
        add     a0, s0, s3
        mv      a1, s1                  # fila superior
        call    ds_pixel
        add     a0, s0, s3
        addi    a1, s1, 7               # fila inferior
        call    ds_pixel
        addi    s3, s3, 1
        li      t0, 8
        blt     s3, t0, ds_box_h
# marco izquierdo y derecho
        li      s3, 0
ds_box_v:
        mv      a0, s0                  # col izquierda
        add     a1, s1, s3
        call    ds_pixel
        addi    a0, s0, 7               # col derecha
        add     a1, s1, s3
        call    ds_pixel
        addi    s3, s3, 1
        li      t0, 8
        blt     s3, t0, ds_box_v
# diagonal
        li      s3, 0
ds_box_d:
        add     a0, s0, s3
        add     a1, s1, s3
        call    ds_pixel
        addi    s3, s3, 1
        li      t0, 8
        blt     s3, t0, ds_box_d
        j       ds_ret

ds_chk_p1:
# P1 -> X (dos diagonales)
        li      t0, CELL_P1
        bne     s2, t0, ds_ret
        li      s3, 0
ds_p1_d:
        add     a0, s0, s3              # diagonal \
        add     a1, s1, s3
        call    ds_pixel
        li      t0, 7
        sub     t0, t0, s3
        add     a0, s0, t0              # diagonal /
        add     a1, s1, s3
        call    ds_pixel
        addi    s3, s3, 1
        li      t0, 8
        blt     s3, t0, ds_p1_d

ds_ret:
        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        lw      s2, 12(sp)
        lw      s3, 16(sp)
        lw      s4, 20(sp)
        addi    sp, sp, 24
        ret

# ---------------------------------------------------------------------
#  ds_pixel: wrapper que llama a fb_set_pixel preservando s0-s4.
#    a0 = x, a1 = y
#  (fb_set_pixel usa t0-t4 y a0-a1; los s* del caller estan a salvo,
#   pero ra hay que guardarla porque hacemos call)
# ---------------------------------------------------------------------
ds_pixel:
        addi    sp, sp, -4
        sw      ra, 0(sp)
        call    fb_set_pixel
        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret