#include "mes.inc"
# =====================================================================
#  juego.s - Modo de PRUEBA del MES (Bomberman)
#  Tablero 13x7, casillas 9x9. Un jugador movible (P1) + P2 inmovil.
#
#  Sistema de bombas y explosiones:
#   - boton central coloca bomba (rango congelado al colocar)
#   - bomba: 20 frames -> explota
#   - explosion: radio = rango de la bomba; rompe cajas, destruye powerups
#     (sin detenerse), cadena con otras bombas en el mismo frame
#   - fuego: 6 frames, muestra cuenta 6..1
#   - caja rota: 30% -> powerup
#   - powerup recogido: +1 bombas max (hasta 5), +1 rango
#
#  Orden del frame (segun enunciado):
#    1 entradas  2 movimiento/accion  3 tick bombas  4 propagacion
#    5 deteccion de muerte  6 render
#
#  Estado por casilla (arrays paralelos de BOARD_CELLS bytes/words):
#    board\[i\]  : codigo de casilla
#    btimer\[i\] : frames restantes (bomba o fuego)
#    brange\[i\] : rango congelado de la bomba en esa casilla
#    bowner\[i\] : dueno de la bomba (0=P1, 1=P2, -1=ninguno)
# =====================================================================

.data
        .align  2
board:  .space  BOARD_CELLS             # codigo de cada casilla
btimer: .space  BOARD_CELLS             # frames restantes (bomba/fuego)
brange: .space  BOARD_CELLS             # rango de la bomba en la casilla
bowner: .space  BOARD_CELLS             # dueno de la bomba (0,1) o 255=ninguno

# ---- Jugador 1 ----
p1_x:   .word   0
p1_y:   .word   0
p1_maxbombs: .word 1
p1_placed: .word 0
p1_range: .word 1
p1_alive: .word 1

# ---- Jugador 2 ----
# En modo prueba: solo se usan x,y,alive (queda inmovil, no pone bombas).
# En modo online: se usan todas, igual que P1.
p2_x:   .word   12
p2_y:   .word   6
p2_maxbombs: .word 1
p2_placed: .word 0
p2_range: .word 1
p2_alive: .word 1

# ---- Flag de fin de juego ----
game_over: .word 0

.text
.global juego_prueba
# ---- Reusables por online.s ----
.global state_init
.global board_generate
.global wait_confirm_release
.global tick_fire
.global tick_bombs
.global check_death
.global board_draw
.global p1_try_move
.global p1_place_bomb
.global explode_at
.global pending_push
.global rng_mod
.global systimer_read
# datos compartidos
.global board
.global btimer
.global brange
.global bowner
.global p1_x
.global p1_y
.global p1_maxbombs
.global p1_placed
.global p1_range
.global p1_alive
.global p2_x
.global p2_y
.global p2_maxbombs
.global p2_placed
.global p2_range
.global p2_alive
.global game_over

# =====================================================================
#  juego_prueba: punto de entrada del modo de prueba.
# =====================================================================
juego_prueba:
        addi    sp, sp, -4
        sw      ra, 0(sp)

        call    botones_setup
        call    wait_confirm_release    # consumir el apreton del menu
        call    state_init
        call    board_generate
        call    juego_loop

        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret

# =====================================================================
#  wait_confirm_release: espera a que el boton CONFIRM (central) este
#  liberado. Evita que el apreton que selecciono "PRUEBA" en el menu se
#  lea como "poner bomba" en el primer frame del juego.
#  Lee GPIO_IN directamente: con pull-up, el bit en 1 = suelto.
# =====================================================================
wait_confirm_release:
        li      t0, GPIO_IN_REG
        li      t1, BTN_CONFIRM
wcr_loop:
        lw      t2, 0(t0)
        and     t3, t2, t1
        beqz    t3, wcr_loop            # bit en 0 = apretado -> seguir esperando
        ret

# =====================================================================
#  state_init: inicializa variables de jugadores y flags.
# =====================================================================
state_init:
        la      t0, p1_x
        sw      zero, 0(t0)
        la      t0, p1_y
        sw      zero, 0(t0)
        li      t1, 1
        la      t0, p1_maxbombs
        sw      t1, 0(t0)
        la      t0, p1_placed
        sw      zero, 0(t0)
        la      t0, p1_range
        sw      t1, 0(t0)
        la      t0, p1_alive
        sw      t1, 0(t0)

        li      t1, 12
        la      t0, p2_x
        sw      t1, 0(t0)
        li      t1, 6
        la      t0, p2_y
        sw      t1, 0(t0)
        li      t1, 1
        la      t0, p2_alive
        sw      t1, 0(t0)

# ---- campos de bombas de P2 (relevantes en online) ----
        li      t1, 1
        la      t0, p2_maxbombs
        sw      t1, 0(t0)
        la      t0, p2_placed
        sw      zero, 0(t0)
        la      t0, p2_range
        sw      t1, 0(t0)

        la      t0, game_over
        sw      zero, 0(t0)
        ret

# =====================================================================
#  board_generate: tablero inicial. Paredes en impares, 70% cajas,
#  P1 en (0,0) con (1,0)/(0,1) libres, P2 en (12,6) con vecinas libres.
#  Limpia los arrays btimer/brange/bowner.
# =====================================================================
board_generate:
        addi    sp, sp, -16
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        sw      s1, 8(sp)
        sw      s2, 12(sp)

# limpiar arrays auxiliares
        la      t0, btimer
        la      t1, brange
        la      t2, bowner
        li      t3, BOARD_CELLS
bg_clr:
        sb      zero, 0(t0)
        sb      zero, 0(t1)
        li      t4, 255
        sb      t4, 0(t2)               # bowner = 255 (ninguno)
        addi    t0, t0, 1
        addi    t1, t1, 1
        addi    t2, t2, 1
        addi    t3, t3, -1
        bnez    t3, bg_clr

        la      s2, board
        li      s0, 0                   # y
bg_row:
        li      s1, 0                   # x
bg_col:
        li      t0, BOARD_COLS
        mul     t0, s0, t0
        add     t0, t0, s1              # indice
        add     t1, s2, t0

        andi    t2, s1, 1
        andi    t3, s0, 1
        and     t2, t2, t3
        beqz    t2, bg_not_wall
        li      t4, CELL_WALL
        sb      t4, 0(t1)
        j       bg_next

bg_not_wall:
        addi    sp, sp, -16
        sw      t1, 0(sp)
        sw      s0, 4(sp)
        sw      s1, 8(sp)
        sw      s2, 12(sp)
        call    rng_mod100
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

# zona P1 (0,0),(1,0),(0,1)
        la      t0, board
        li      t1, CELL_P1
        sb      t1, 0(t0)
        li      t1, CELL_EMPTY
        sb      t1, 1(t0)
        li      t2, BOARD_COLS
        add     t3, t0, t2
        sb      t1, 0(t3)

# zona P2 (12,6),(11,6),(12,5)
# indice (12,6) = 6*13+12 = 90
        li      t1, CELL_P2
        li      t2, 90
        add     t3, t0, t2
        sb      t1, 0(t3)
        li      t1, CELL_EMPTY
# (11,6) = 89
        li      t2, 89
        add     t3, t0, t2
        sb      t1, 0(t3)
# (12,5) = 5*13+12 = 77
        li      t2, 77
        add     t3, t0, t2
        sb      t1, 0(t3)

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        lw      s2, 12(sp)
        addi    sp, sp, 16
        ret

# =====================================================================
#  rng_mod100: a0 = valor 0..99 del RNG de hardware.
# =====================================================================
rng_mod100:
        li      t0, RNG_DATA_REG
        lw      t1, 0(t0)
        li      t2, 100
        remu    a0, t1, t2
        ret

# =====================================================================
#  rng_mod(a0=n): a0 = valor 0..n-1 del RNG.
# =====================================================================
rng_mod:
        mv      t3, a0
        li      t0, RNG_DATA_REG
        lw      t1, 0(t0)
        remu    a0, t1, t3
        ret

# =====================================================================
#  systimer_read: a0 = 32 bits bajos del contador UNIT0 (16MHz).
# =====================================================================
systimer_read:
        li      t0, SYSTIMER_UNIT0_OP_REG
        li      t1, SYSTIMER_UNIT0_UPDATE_MASK
        sw      t1, 0(t0)
        li      t2, SYSTIMER_UNIT0_VALUE_VALID_MASK
sr_wait:
        lw      t3, 0(t0)
        and     t4, t3, t2
        beqz    t4, sr_wait
        li      t0, SYSTIMER_UNIT0_VALUE_LO_REG
        lw      a0, 0(t0)
        ret

# =====================================================================
#  juego_loop: bucle principal. Cada frame dura FRAME_TICKS (150ms).
#  Orden: entradas, movimiento, tick bombas, propagacion, muerte, render.
# =====================================================================
juego_loop:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)               # marca de tiempo del frame

jl_frame:
        call    systimer_read
        mv      s0, a0

# --- 1 entradas ---
        call    boton_leer              # a0 = botones apretados

# --- 2 movimiento/accion ---
        call    handle_input            # usa a0 (botones) directamente

# --- 3 tick de bombas (decrementa fuego viejo, luego explota) ---
        call    tick_fire               # decrementar fuego (al inicio)
        call    tick_bombs              # decrementar bombas; explotar las que llegan a 0

# --- 5 deteccion de muerte ---
        call    check_death

# --- 6 render ---
        call    board_draw

# fin del juego? (solo termina por muerte)
        la      t0, game_over
        lw      t1, 0(t0)
        bnez    t1, jl_gameover

jl_wait:
        call    systimer_read
        sub     t0, a0, s0
        li      t1, FRAME_TICKS
        bltu    t0, t1, jl_wait
        j       jl_frame

jl_gameover:
        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret

# =====================================================================
#  handle_input(a0=botones): mueve a P1 y/o coloca bomba.
#  Movimiento: un paso por frame (prioridad U>D>L>R).
#  Bomba: si CONFIRMAR... (no, CONFIRMAR sale). El boton de bomba es
#  BTN_CONFIRM? No: en el menu era confirmar. Aqui CONFIRMAR=salir.
#  Bomba = boton central. Segun el mapeo, el "central" es GPIO10=CONFIRM.
#  Para no chocar: usamos CONFIRM=colocar bomba en el juego, y para SALIR
#  se mantiene... -> ver nota. Aqui: el boton central (CONFIRM) coloca
#  bomba; no hay "salir" desde el juego salvo game over.
# =====================================================================
handle_input:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        mv      s0, a0                  # botones

# colocar bomba con el boton central
        li      t0, BTN_CONFIRM
        and     t1, s0, t0
        beqz    t1, hi_move
        addi    sp, sp, -4
        sw      s0, 0(sp)
        call    p1_place_bomb
        lw      s0, 0(sp)
        addi    sp, sp, 4

hi_move:
        li      t2, 0                   # dx
        li      t3, 0                   # dy
        li      t0, BTN_UP
        and     t1, s0, t0
        beqz    t1, hi_d
        li      t3, -1
        j       hi_do
hi_d:
        li      t0, BTN_DOWN
        and     t1, s0, t0
        beqz    t1, hi_l
        li      t3, 1
        j       hi_do
hi_l:
        li      t0, BTN_LEFT
        and     t1, s0, t0
        beqz    t1, hi_r
        li      t2, -1
        j       hi_do
hi_r:
        li      t0, BTN_RIGHT
        and     t1, s0, t0
        beqz    t1, hi_ret
        li      t2, 1

hi_do:
        mv      a0, t2
        mv      a1, t3
        call    p1_try_move

hi_ret:
        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret

# =====================================================================
#  p1_place_bomb: coloca una bomba en la casilla de P1 si no supera su
#  maximo ni MAX_BOMBS, y si la casilla no tiene ya una bomba.
#  Congela el rango actual del jugador en la bomba.
# =====================================================================
p1_place_bomb:
        addi    sp, sp, -4
        sw      ra, 0(sp)

        la      t0, p1_placed
        lw      t1, 0(t0)               # bombas colocadas
        la      t0, p1_maxbombs
        lw      t2, 0(t0)               # max del jugador
        bge     t1, t2, pb_no           # supera su max?
        li      t3, MAX_BOMBS
        bge     t1, t3, pb_no           # supera tope global?

# indice de la casilla del jugador
        la      t0, p1_x
        lw      t4, 0(t0)
        la      t0, p1_y
        lw      t5, 0(t0)
        li      t6, BOARD_COLS
        mul     t6, t5, t6
        add     t6, t6, t4              # indice

        la      t0, board
        add     t0, t0, t6
        lbu     t1, 0(t0)
        li      t2, CELL_BOMB
        beq     t1, t2, pb_no           # ya hay bomba aqui

# colocar bomba
        li      t2, CELL_BOMB
        sb      t2, 0(t0)
        la      t1, btimer
        add     t1, t1, t6
        li      t2, BOMB_FRAMES
        sb      t2, 0(t1)
# rango congelado
        la      t1, brange
        add     t1, t1, t6
        la      t0, p1_range
        lw      t2, 0(t0)
        sb      t2, 0(t1)
# dueno = 0 (P1)
        la      t1, bowner
        add     t1, t1, t6
        sb      zero, 0(t1)

# incrementar bombas colocadas
        la      t0, p1_placed
        lw      t1, 0(t0)
        addi    t1, t1, 1
        sw      t1, 0(t0)

pb_no:
        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret

# =====================================================================
#  p1_try_move(dx=a0, dy=a1): mueve a P1 si la casilla destino es
#  transitable. Transitable: EMPTY o POWERUP (lo recoge). Bomba, pared,
#  caja bloquean. Al recoger powerup: +1 maxbombs (hasta 5), +1 range.
# =====================================================================
p1_try_move:
        addi    sp, sp, -16
        sw      ra, 0(sp)
        sw      s0, 4(sp)               # nx
        sw      s1, 8(sp)               # ny
        sw      s2, 12(sp)              # indice destino

        la      t0, p1_x
        lw      t1, 0(t0)
        la      t0, p1_y
        lw      t2, 0(t0)
        add     s0, t1, a0
        add     s1, t2, a1

        bltz    s0, ptm_no
        li      t3, BOARD_COLS
        bge     s0, t3, ptm_no
        bltz    s1, ptm_no
        li      t3, BOARD_ROWS
        bge     s1, t3, ptm_no

        li      t3, BOARD_COLS
        mul     t3, s1, t3
        add     s2, t3, s0              # indice destino
        la      t4, board
        add     t4, t4, s2
        lbu     t5, 0(t4)               # contenido destino

        li      t6, CELL_EMPTY
        beq     t5, t6, ptm_ok
        li      t6, CELL_POWERUP
        beq     t5, t6, ptm_powerup
        j       ptm_no                  # pared, caja, bomba, fuego: bloquea

ptm_powerup:
# recoger: +1 maxbombs (tope 5), +1 range
        la      t0, p1_maxbombs
        lw      t1, 0(t0)
        li      t2, MAX_BOMBS
        bge     t1, t2, pp_skip_mb
        addi    t1, t1, 1
        sw      t1, 0(t0)
pp_skip_mb:
        la      t0, p1_range
        lw      t1, 0(t0)
        addi    t1, t1, 1
        sw      t1, 0(t0)
# cae en ptm_ok para completar el movimiento

ptm_ok:
# vaciar casilla vieja
        la      t0, p1_x
        lw      t1, 0(t0)
        la      t0, p1_y
        lw      t2, 0(t0)
        li      t3, BOARD_COLS
        mul     t3, t2, t3
        add     t3, t3, t1
        la      t0, board
        add     t0, t0, t3
# solo vaciar si la casilla vieja sigue siendo el jugador
# (podria haberse vuelto fuego; en ese caso no la tocamos)
        lbu     t4, 0(t0)
        li      t5, CELL_P1
        bne     t4, t5, ptm_setnew
        li      t4, CELL_EMPTY
        sb      t4, 0(t0)
ptm_setnew:
        la      t0, board
        add     t0, t0, s2
        li      t4, CELL_P1
        sb      t4, 0(t0)
        la      t0, p1_x
        sw      s0, 0(t0)
        la      t0, p1_y
        sw      s1, 0(t0)

ptm_no:
        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        lw      s2, 12(sp)
        addi    sp, sp, 16
        ret

# =====================================================================
#  tick_fire: decrementa el timer de cada casilla de fuego. Las que
#  llegan a 0 vuelven a EMPTY. Se llama al INICIO del tick, antes de
#  generar fuego nuevo, para que el fuego nuevo dure 6 frames completos.
#  Funcion hoja: usa solo registros temporales (no toca la pila).
# =====================================================================
tick_fire:
        la      t0, board
        la      t1, btimer
        li      t2, BOARD_CELLS
tf_loop:
        lbu     t3, 0(t0)
        li      t4, CELL_FIRE
        bne     t3, t4, tf_next
        lbu     t5, 0(t1)
        addi    t5, t5, -1
        sb      t5, 0(t1)
        bnez    t5, tf_next
        li      t6, CELL_EMPTY
        sb      t6, 0(t0)               # fuego extinguido
tf_next:
        addi    t0, t0, 1
        addi    t1, t1, 1
        addi    t2, t2, -1
        bnez    t2, tf_loop
        ret

# =====================================================================
#  tick_bombs: decrementa el timer de cada bomba. Recolecta las que
#  llegan a 0 y las hace explotar (con cadena en el mismo frame).
#  Usa una pila de "pendientes" en memoria (pending_stack).
# =====================================================================
.data
        .align  2
pending_stack: .space 364               # hasta 91 bombas * 4 bytes
pending_count: .word 0
.text

tick_bombs:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)

# vaciar la pila de pendientes
        la      t0, pending_count
        sw      zero, 0(t0)

# recorrer board: decrementar bombas, encolar las que llegan a 0
        la      s0, board
        la      s1, btimer
        li      t0, BOARD_CELLS
        li      s2, 0                   # indice lineal
tb_scan:
        lbu     t1, 0(s0)
        li      t2, CELL_BOMB
        bne     t1, t2, tb_scan_next
        lbu     t3, 0(s1)
        addi    t3, t3, -1
        sb      t3, 0(s1)
        bnez    t3, tb_scan_next
# llego a 0 -> encolar indice s2
        mv      a0, s2
        addi    sp, sp, -16
        sw      s0, 0(sp)
        sw      s1, 4(sp)
        sw      t0, 8(sp)
        sw      s2, 12(sp)
        call    pending_push
        lw      s0, 0(sp)
        lw      s1, 4(sp)
        lw      t0, 8(sp)
        lw      s2, 12(sp)
        addi    sp, sp, 16
tb_scan_next:
        addi    s0, s0, 1
        addi    s1, s1, 1
        addi    s2, s2, 1
        addi    t0, t0, -1
        bnez    t0, tb_scan

# procesar la pila de pendientes (puede crecer por cadenas)
        li      s0, 0                   # i = 0
tb_proc:
        la      t0, pending_count
        lw      t1, 0(t0)
        bge     s0, t1, tb_done         # i >= count -> fin
# leer pending_stack\[i\]
        la      t0, pending_stack
        slli    t2, s0, 2
        add     t0, t0, t2
        lw      a0, 0(t0)               # indice de la bomba
# solo explotar si sigue siendo bomba
        la      t1, board
        add     t1, t1, a0
        lbu     t2, 0(t1)
        li      t3, CELL_BOMB
        bne     t2, t3, tb_proc_next
        addi    sp, sp, -8
        sw      s0, 0(sp)
        sw      ra, 4(sp)
        call    explode_at              # a0 = indice
        lw      s0, 0(sp)
        lw      ra, 4(sp)
        addi    sp, sp, 8
tb_proc_next:
        addi    s0, s0, 1
        j       tb_proc

tb_done:
        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret

# ---------------------------------------------------------------------
#  pending_push(a0=indice): agrega un indice a la pila de pendientes
#  si no esta ya (evita duplicados).
# ---------------------------------------------------------------------
pending_push:
        la      t0, pending_count
        lw      t1, 0(t0)
# buscar duplicado
        la      t2, pending_stack
        li      t3, 0
pp_find:
        bge     t3, t1, pp_add
        slli    t4, t3, 2
        add     t5, t2, t4
        lw      t6, 0(t5)
        beq     t6, a0, pp_done         # ya esta
        addi    t3, t3, 1
        j       pp_find
pp_add:
        slli    t4, t1, 2
        add     t5, t2, t4
        sw      a0, 0(t5)
        addi    t1, t1, 1
        sw      t1, 0(t0)
pp_done:
        ret

# =====================================================================
#  explode_at(a0=indice): convierte la bomba en fuego y propaga en las
#  4 direcciones hasta su rango. Maneja cajas, powerups, cadenas.
#  Decrementa p_placed del dueno.
# =====================================================================
explode_at:
        addi    sp, sp, -28
        sw      ra, 0(sp)
        sw      s0, 4(sp)               # indice bomba
        sw      s1, 8(sp)               # bx
        sw      s2, 12(sp)              # by
        sw      s3, 16(sp)              # rango
        sw      s4, 20(sp)              # iterador direccion
        sw      s5, 24(sp)              # iterador paso
        mv      s0, a0

# bx = indice % COLS ; by = indice / COLS
        li      t0, BOARD_COLS
        remu    s1, s0, t0
        divu    s2, s0, t0

# rango congelado
        la      t0, brange
        add     t0, t0, s0
        lbu     s3, 0(t0)

# dueno -> liberar slot
        la      t0, bowner
        add     t0, t0, s0
        lbu     t1, 0(t0)
        li      t2, 255
        beq     t1, t2, ea_nodueno
# liberar el slot del dueno: bowner==0 -> P1, bowner==1 -> P2
        beqz    t1, ea_libera_p1
        li      t2, 1
        beq     t1, t2, ea_libera_p2
        j       ea_nodueno
ea_libera_p1:
        la      t3, p1_placed
        j       ea_libera_do
ea_libera_p2:
        la      t3, p2_placed
ea_libera_do:
        lw      t4, 0(t3)
        addi    t4, t4, -1
        bgez    t4, ea_store_placed
        li      t4, 0
ea_store_placed:
        sw      t4, 0(t3)
ea_nodueno:
# casilla de la bomba -> fuego
        la      t0, board
        add     t0, t0, s0
        li      t1, CELL_FIRE
        sb      t1, 0(t0)
        la      t0, btimer
        add     t0, t0, s0
        li      t1, FIRE_FRAMES
        sb      t1, 0(t0)
        la      t0, brange
        add     t0, t0, s0
        sb      zero, 0(t0)
        la      t0, bowner
        add     t0, t0, s0
        li      t1, 255
        sb      t1, 0(t0)

# propagar en 4 direcciones
# dx,dy por direccion: U(0,-1) D(0,1) L(-1,0) R(1,0)
        li      s4, 0                   # indice de direccion 0..3
ea_dir:
# cargar dx,dy segun s4
# uso una mini-tabla en registros via saltos
        li      t0, 0                   # dx
        li      t1, 0                   # dy
        li      t2, 0
        beq     s4, t2, ea_set_u
        li      t2, 1
        beq     s4, t2, ea_set_d
        li      t2, 2
        beq     s4, t2, ea_set_l
# s4==3
        li      t0, 1                   # R
        j       ea_have_dir
ea_set_u:
        li      t1, -1
        j       ea_have_dir
ea_set_d:
        li      t1, 1
        j       ea_have_dir
ea_set_l:
        li      t0, -1
ea_have_dir:
# guardar dx,dy en pila (los s* estan ocupados)
        addi    sp, sp, -8
        sw      t0, 0(sp)               # dx
        sw      t1, 4(sp)               # dy

        li      s5, 1                   # paso = 1
ea_step:
        bgt     s5, s3, ea_dir_done     # paso > rango -> fin de esta direccion
        lw      t0, 0(sp)               # dx
        lw      t1, 4(sp)               # dy
        mul     t2, t0, s5              # dx*paso
        mul     t3, t1, s5              # dy*paso
        add     t4, s1, t2              # nx = bx + dx*paso
        add     t5, s2, t3              # ny = by + dy*paso
# limites
        bltz    t4, ea_dir_done
        li      t6, BOARD_COLS
        bge     t4, t6, ea_dir_done
        bltz    t5, ea_dir_done
        li      t6, BOARD_ROWS
        bge     t5, t6, ea_dir_done

# indice destino
        li      t6, BOARD_COLS
        mul     t6, t5, t6
        add     t6, t6, t4              # indice destino en t6
        la      t0, board
        add     t0, t0, t6
        lbu     t1, 0(t0)               # contenido

        li      t2, CELL_WALL
        beq     t1, t2, ea_dir_done     # pared: detiene
        li      t2, CELL_BOX
        beq     t1, t2, ea_hit_box
        li      t2, CELL_BOMB
        beq     t1, t2, ea_hit_bomb
        li      t2, CELL_POWERUP
        beq     t1, t2, ea_hit_powerup
# EMPTY o jugador -> fuego
        li      t1, CELL_FIRE
        sb      t1, 0(t0)
        la      t2, btimer
        add     t2, t2, t6
        li      t1, FIRE_FRAMES
        sb      t1, 0(t2)
        addi    s5, s5, 1
        j       ea_step

ea_hit_box:
# destruir caja (30% powerup), detiene
        mv      a0, t6
        addi    sp, sp, -4
        sw      ra, 0(sp)
        call    destroy_box
        lw      ra, 0(sp)
        addi    sp, sp, 4
        j       ea_dir_done

ea_hit_bomb:
# cadena: encolar esta bomba, detiene la original
        mv      a0, t6
        addi    sp, sp, -4
        sw      ra, 0(sp)
        call    pending_push
        lw      ra, 0(sp)
        addi    sp, sp, 4
        j       ea_dir_done

ea_hit_powerup:
# destruir powerup -> fuego, NO detiene
        li      t1, CELL_FIRE
        sb      t1, 0(t0)
        la      t2, btimer
        add     t2, t2, t6
        li      t1, FIRE_FRAMES
        sb      t1, 0(t2)
        addi    s5, s5, 1
        j       ea_step

ea_dir_done:
        addi    sp, sp, 8               # quitar dx,dy de pila
        addi    s4, s4, 1
        li      t0, 4
        blt     s4, t0, ea_dir

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        lw      s2, 12(sp)
        lw      s3, 16(sp)
        lw      s4, 20(sp)
        lw      s5, 24(sp)
        addi    sp, sp, 28
        ret

# ---------------------------------------------------------------------
#  destroy_box(a0=indice): rompe una caja. 30% -> powerup, si no fuego.
# ---------------------------------------------------------------------
destroy_box:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        mv      s0, a0                  # indice

        li      a0, 100
        call    rng_mod                 # a0 = 0..99
        li      t0, 30
        bge     a0, t0, db_fire

# powerup
        la      t0, board
        add     t0, t0, s0
        li      t1, CELL_POWERUP
        sb      t1, 0(t0)
        la      t0, btimer
        add     t0, t0, s0
        sb      zero, 0(t0)
        j       db_done

db_fire:
        la      t0, board
        add     t0, t0, s0
        li      t1, CELL_FIRE
        sb      t1, 0(t0)
        la      t0, btimer
        add     t0, t0, s0
        li      t1, FIRE_FRAMES
        sb      t1, 0(t0)

db_done:
        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret

# =====================================================================
#  check_death: si un jugador esta sobre una casilla de fuego, muere y
#  se activa game_over.
# =====================================================================
check_death:
# P1
        la      t0, p1_alive
        lw      t1, 0(t0)
        beqz    t1, cd_p2
        la      t0, p1_x
        lw      t2, 0(t0)
        la      t0, p1_y
        lw      t3, 0(t0)
        li      t4, BOARD_COLS
        mul     t4, t3, t4
        add     t4, t4, t2
        la      t0, board
        add     t0, t0, t4
        lbu     t5, 0(t0)
        li      t6, CELL_FIRE
        bne     t5, t6, cd_p2
        la      t0, p1_alive
        sw      zero, 0(t0)
        la      t0, game_over
        li      t1, 1
        sw      t1, 0(t0)

cd_p2:
        la      t0, p2_alive
        lw      t1, 0(t0)
        beqz    t1, cd_ret
        la      t0, p2_x
        lw      t2, 0(t0)
        la      t0, p2_y
        lw      t3, 0(t0)
        li      t4, BOARD_COLS
        mul     t4, t3, t4
        add     t4, t4, t2
        la      t0, board
        add     t0, t0, t4
        lbu     t5, 0(t0)
        li      t6, CELL_FIRE
        bne     t5, t6, cd_ret
        la      t0, p2_alive
        sw      zero, 0(t0)
        la      t0, game_over
        li      t1, 1
        sw      t1, 0(t0)

cd_ret:
        ret

# =====================================================================
#  board_draw: dibuja el tablero completo (doble buffer).
# =====================================================================
board_draw:
        addi    sp, sp, -20
        sw      ra, 0(sp)
        sw      s0, 4(sp)               # y
        sw      s1, 8(sp)               # x
        sw      s2, 12(sp)              # \&board
        sw      s3, 16(sp)              # codigo

        call    fb_clear

        la      s2, board
        li      s0, 0
bd_row:
        li      s1, 0
bd_col:
        li      t0, BOARD_COLS
        mul     t0, s0, t0
        add     t0, t0, s1
        add     t1, s2, t0
        lbu     s3, 0(t1)

# px = OFF_X + x*CELL_PX ; py = OFF_Y + y*CELL_PX
        li      t2, CELL_PX
        mul     t2, s1, t2
        addi    t2, t2, BOARD_OFF_X
        li      t3, CELL_PX
        mul     t3, s0, t3
        addi    t3, t3, BOARD_OFF_Y

# para FIRE necesitamos el timer (numero a mostrar)
        li      t4, CELL_FIRE
        bne     s3, t4, bd_nofire
# cargar timer de esta casilla en a3
        li      t4, BOARD_COLS
        mul     t4, s0, t4
        add     t4, t4, s1
        la      t5, btimer
        add     t5, t5, t4
        lbu     a3, 0(t5)
        j       bd_call
bd_nofire:
        li      a3, 0
bd_call:
        mv      a0, t2
        mv      a1, t3
        mv      a2, s3
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
#  draw_sprite(px=a0, py=a1, code=a2, fire_timer=a3): dibuja el sprite
#  de una casilla 9x9 en el framebuffer.
# =====================================================================
draw_sprite:
        addi    sp, sp, -28
        sw      ra, 0(sp)
        sw      s0, 4(sp)               # px
        sw      s1, 8(sp)               # py
        sw      s2, 12(sp)              # code
        sw      s3, 16(sp)              # iter i
        sw      s4, 20(sp)              # iter j / fire_timer
        sw      s5, 24(sp)
        mv      s0, a0
        mv      s1, a1
        mv      s2, a2
        mv      s5, a3                  # fire timer (para FIRE)

        li      t0, CELL_EMPTY
        beq     s2, t0, ds_ret

        li      t0, CELL_WALL
        beq     s2, t0, ds_wall
        li      t0, CELL_BOX
        beq     s2, t0, ds_box
        li      t0, CELL_P1
        beq     s2, t0, ds_p1
        li      t0, CELL_P2
        beq     s2, t0, ds_p2
        li      t0, CELL_BOMB
        beq     s2, t0, ds_bomb
        li      t0, CELL_FIRE
        beq     s2, t0, ds_fire
        li      t0, CELL_POWERUP
        beq     s2, t0, ds_powerup
        j       ds_ret

# --- WALL: relleno 8x8 ---
ds_wall:
        li      s3, 0
dsw_r:
        li      s4, 0
dsw_c:
        add     a0, s0, s4
        add     a1, s1, s3
        call    ds_px
        addi    s4, s4, 1
        li      t0, 8
        blt     s4, t0, dsw_c
        addi    s3, s3, 1
        li      t0, 8
        blt     s3, t0, dsw_r
        j       ds_ret

# --- BOX: marco + diagonal ---
ds_box:
        li      s3, 0
dsb_h:
        add     a0, s0, s3
        mv      a1, s1
        call    ds_px
        add     a0, s0, s3
        addi    a1, s1, 7
        call    ds_px
        addi    s3, s3, 1
        li      t0, 8
        blt     s3, t0, dsb_h
        li      s3, 0
dsb_v:
        mv      a0, s0
        add     a1, s1, s3
        call    ds_px
        addi    a0, s0, 7
        add     a1, s1, s3
        call    ds_px
        addi    s3, s3, 1
        li      t0, 8
        blt     s3, t0, dsb_v
        li      s3, 0
dsb_d:
        add     a0, s0, s3
        add     a1, s1, s3
        call    ds_px
        addi    s3, s3, 1
        li      t0, 8
        blt     s3, t0, dsb_d
        j       ds_ret

# --- P1: X ---
ds_p1:
        li      s3, 0
dsp1_d:
        add     a0, s0, s3
        add     a1, s1, s3
        call    ds_px
        li      t0, 7
        sub     t0, t0, s3
        add     a0, s0, t0
        add     a1, s1, s3
        call    ds_px
        addi    s3, s3, 1
        li      t0, 8
        blt     s3, t0, dsp1_d
        j       ds_ret

# --- P2: O (cuadrado hueco redondeado: marco sin esquinas) ---
ds_p2:
        li      s3, 1
dsp2_h:
        add     a0, s0, s3
        mv      a1, s1
        call    ds_px
        add     a0, s0, s3
        addi    a1, s1, 7
        call    ds_px
        addi    s3, s3, 1
        li      t0, 7
        blt     s3, t0, dsp2_h
        li      s3, 1
dsp2_v:
        mv      a0, s0
        add     a1, s1, s3
        call    ds_px
        addi    a0, s0, 7
        add     a1, s1, s3
        call    ds_px
        addi    s3, s3, 1
        li      t0, 7
        blt     s3, t0, dsp2_v
        j       ds_ret

# --- BOMB: circulo relleno aproximado (rombo relleno) ---
ds_bomb:
# rombo: para cada fila i, pintar desde centro-ancho a centro+ancho
# centro en (4,4); usar un patron simple: cuadrado 6x6 centrado
        li      s3, 1
dsbo_r:
        li      s4, 1
dsbo_c:
        add     a0, s0, s4
        add     a1, s1, s3
        call    ds_px
        addi    s4, s4, 1
        li      t0, 7
        blt     s4, t0, dsbo_c
        addi    s3, s3, 1
        li      t0, 7
        blt     s3, t0, dsbo_r
        j       ds_ret

# --- FIRE: dibujar el digito del timer (s5) centrado ---
ds_fire:
# dibujar el digito s5 (1..6) usando draw_digit
        mv      a0, s0                  # px
        mv      a1, s1                  # py
        mv      a2, s5                  # digito
        call    draw_digit
        j       ds_ret

# --- POWERUP: signo + ---
ds_powerup:
# linea horizontal en y=4 (x 2..6) y vertical en x=4 (y 2..6)
        li      s3, 2
dspu_h:
        add     a0, s0, s3
        addi    a1, s1, 4
        call    ds_px
        addi    s3, s3, 1
        li      t0, 7
        blt     s3, t0, dspu_h
        li      s3, 2
dspu_v:
        addi    a0, s0, 4
        add     a1, s1, s3
        call    ds_px
        addi    s3, s3, 1
        li      t0, 7
        blt     s3, t0, dspu_v
        j       ds_ret

ds_ret:
        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        lw      s2, 12(sp)
        lw      s3, 16(sp)
        lw      s4, 20(sp)
        lw      s5, 24(sp)
        addi    sp, sp, 28
        ret

# ---------------------------------------------------------------------
#  ds_px: wrapper de fb_set_pixel preservando ra.
# ---------------------------------------------------------------------
ds_px:
        addi    sp, sp, -4
        sw      ra, 0(sp)
        call    fb_set_pixel
        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret

# ---------------------------------------------------------------------
#  draw_digit(px=a0, py=a1, d=a2): dibuja el digito d (0..9) en 5x7
#  dentro de la celda, usando la tabla digit_font.
# ---------------------------------------------------------------------
draw_digit:
        addi    sp, sp, -24
        sw      ra, 0(sp)
        sw      s0, 4(sp)               # px
        sw      s1, 8(sp)               # py
        sw      s2, 12(sp)              # puntero a los 5 bytes del digito
        sw      s3, 16(sp)              # col
        sw      s4, 20(sp)              # byte de columna
        mv      s0, a0
        mv      s1, a1

# puntero = digit_font + d*5
        la      t0, digit_font
        li      t1, 5
        mul     t1, a2, t1
        add     s2, t0, t1

# dibujar offset +2 en x para centrar el 5 de ancho en la celda de 9
# (queda en columnas 2..6)
        li      s3, 0
dd_col:
        lbu     s4, 0(s2)               # byte de columna (8 bits verticales)
        li      t5, 0                   # bit
dd_bit:
        srl     t6, s4, t5
        andi    t6, t6, 1
        beqz    t6, dd_bit_next
        addi    a0, s0, 2               # x = px + 2 + col
        add     a0, a0, s3
        addi    a1, s1, 1               # y = py + 1 + bit
        add     a1, a1, t5
        addi    sp, sp, -16
        sw      t5, 0(sp)
        sw      s2, 4(sp)
        sw      s3, 8(sp)
        sw      s4, 12(sp)
        call    ds_px
        lw      t5, 0(sp)
        lw      s2, 4(sp)
        lw      s3, 8(sp)
        lw      s4, 12(sp)
        addi    sp, sp, 16
dd_bit_next:
        addi    t5, t5, 1
        li      t6, 8
        blt     t5, t6, dd_bit
        addi    s2, s2, 1
        addi    s3, s3, 1
        li      t6, 5
        blt     s3, t6, dd_col

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        lw      s2, 12(sp)
        lw      s3, 16(sp)
        lw      s4, 20(sp)
        addi    sp, sp, 24
        ret

.data
        .align  2
# Fuente de digitos 0-9, 5 columnas x 8 filas (bit0 arriba)
digit_font:
        .byte   0x3E, 0x51, 0x49, 0x45, 0x3E # 0
        .byte   0x00, 0x42, 0x7F, 0x40, 0x00 # 1
        .byte   0x42, 0x61, 0x51, 0x49, 0x46 # 2
        .byte   0x21, 0x41, 0x45, 0x4B, 0x31 # 3
        .byte   0x18, 0x14, 0x12, 0x7F, 0x10 # 4
        .byte   0x27, 0x45, 0x45, 0x45, 0x39 # 5
        .byte   0x3C, 0x4A, 0x49, 0x49, 0x30 # 6
        .byte   0x01, 0x71, 0x09, 0x05, 0x03 # 7
        .byte   0x36, 0x49, 0x49, 0x49, 0x36 # 8
        .byte   0x06, 0x49, 0x49, 0x29, 0x1E # 9
.text