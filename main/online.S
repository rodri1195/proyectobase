#include "mes.inc"
# =====================================================================
#  online.s - Protocolo multijugador del MES (Bomberman en red)
#
#  Capa 1 (handshake): rompe la simetria entre dos nodos identicos.
#    - El primero que entra a ONLINE no escucha a nadie -> CONTROLADOR.
#    - El que detecta la 'M' del otro -> SEGUIDOR.
#
#  Capa 2 (este archivo): bucles de juego en lock-step.
#    - CONTROLADOR (juega 'X' = P1): simula el juego para AMBOS jugadores,
#      manda el tablero cada frame, espera el ACK del seguidor, renderiza.
#    - SEGUIDOR (juega 'O' = P2): manda su input, recibe el tablero,
#      lo dibuja. No simula nada.
#
#  Sincronizacion (lock-step): el controlador NO avanza de frame hasta
#  recibir la 'K' del seguidor. Asi ambas pantallas van al mismo ritmo
#  y el frame de 150ms del controlador marca el tempo de los dos.
#
#  Protocolo (todo ASCII, sin marca de fin; bytes definidos en mes.inc):
#    Handshake : controlador 'M' -> seguidor 'K'
#    Cada frame: controlador 'F' + 91 bytes de tablero -> seguidor 'K'
#    Input     : seguidor manda W/S/A/D/B (solo el ULTIMO del frame vale)
#    Fin       : controlador 'R' + ('1' gano / '0' perdio-empate)
#    Bytes inesperados se descartan.
#
#  Tablero codificado (1 byte ASCII por casilla, 91 en total):
#    ' ' vacio | 'P' pared | 'C' caja | 'X' P1 | 'O' P2 | 'B' bomba
#    '+' powerup | '1'..'6' fuego (el digito es la cuenta restante)
#  El seguidor reconstruye board[] y btimer[] desde estos bytes para que
#  board_draw pueda dibujar el digito del fuego igual que el controlador.
# =====================================================================

#include "mes.inc"

# ---- transporte (uart.s) ----
.extern uart_init
.extern uart_send_byte
.extern uart_recv_byte
.extern uart_recv_try

# ---- estado / logica reusada (juego.s) ----
.extern state_init
.extern board_generate
.extern wait_confirm_release
.extern boton_leer
.extern botones_setup
.extern tick_fire
.extern tick_bombs
.extern check_death
.extern board_draw
.extern p1_try_move
.extern p1_place_bomb
.extern delay

# ---- datos compartidos (juego.s) ----
.extern board
.extern btimer
.extern brange
.extern bowner
.extern p1_x
.extern p1_y
.extern p1_maxbombs
.extern p1_placed
.extern p1_range
.extern p1_alive
.extern p2_x
.extern p2_y
.extern p2_maxbombs
.extern p2_placed
.extern p2_range
.extern p2_alive
.extern game_over

        .equ    ROLE_CONTROLLER, 0
        .equ    ROLE_FOLLOWER,   1

# Para escuchar al inicio del handshake: ~200ms de sondeo.
# El bucle de escucha hace, por iteracion, una lectura UART no bloqueante
# (uart_recv_try) y un delay corto; HS_LISTEN_ITERS controla cuanto escucha.
# No es critico al milisegundo: solo debe dar tiempo a que, si el otro ya
# es controlador, su 'M' periodica llegue. Lo dejamos holgado.
        .equ    HS_LISTEN_ITERS, 4000
        .equ    HS_LISTEN_DELAY, 200
# Sondeos de 'K' entre cada reenvio de 'M' en la fase de anuncio.
# HS_ACK_POLLS * HS_LISTEN_DELAY define cada cuanto se reenvia 'M'.
        .equ    HS_ACK_POLLS, 50

.data
        .align  2
# Buffer de red: 91 bytes del tablero (ASCII). Reutilizado por encode/decode.
net_buffer: .space 91

.text
.global handshake
.global online_controller
.global online_follower
.global online_as_follower
.global online_as_controller
.global online_send_m_wait_k

# =====================================================================
#  juego_online: punto de entrada del modo online (lo llama menu.s).
#  Inicializa UART, setea botones, decide rol y entra al bucle que toque.
#  Al terminar la partida, vuelve (el menu se redibuja solo).
# =====================================================================
# =====================================================================
#  DOS PUNTOS DE ENTRADA AL MODO ONLINE
#
#  El ROL ya NO se negocia con handshake aqui: lo decide el menu segun
#  COMO se entro (ver menu.s):
#    - online_as_follower:   me llego una 'M' por UART estando en el menu.
#                            El menu YA respondio 'K'. Entro como SEGUIDOR.
#    - online_as_controller: yo elegi ONLINE en el menu. El menu YA mando
#                            'M' en loop y recibio 'K'. Entro como CONTROLADOR.
#
#  Precondiciones comunes (las cumple el menu antes de llamar):
#    - uart_init ya corrio (desde app_main).
#    - botones_setup ya corrio.
#  Por eso aqui NO se vuelve a inicializar UART ni botones.
# =====================================================================

# ---- Seguidor: arrastrado por una 'M' ----
online_as_follower:
        addi    sp, sp, -4
        sw      ra, 0(sp)
# state_init deja a los jugadores en posicion/contadores de arranque.
# El seguidor NO genera tablero: lo recibe completo en el primer 'F'.
        call    state_init
        call    online_follower
        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret

# ---- Controlador: yo elegi ONLINE ----
online_as_controller:
        addi    sp, sp, -4
        sw      ra, 0(sp)
        call    state_init
        call    board_generate          # solo el controlador genera el tablero
        call    online_controller
        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret

# =====================================================================
#  online_send_m_wait_k: yo seleccione ONLINE. Anuncio mandando 'M' en
#  loop y escucho (sin bloquear) la 'K' entre cada envio. No retorna
#  hasta recibir 'K'. Lo llama el menu; al volver, el menu salta a
#  online_as_controller.
#
#  Reusa HS_ACK_POLLS / HS_LISTEN_DELAY (definidos arriba) para el ritmo
#  de reenvio. Misma logica que la fase de anuncio del viejo handshake,
#  pero como rutina independiente porque ahora el rol lo decide el menu.
# =====================================================================
online_send_m_wait_k:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)
omw_announce:
        li      a0, PROTO_M
        call    uart_send_byte          # mandar 'M'
        li      s0, HS_ACK_POLLS
omw_poll:
        call    uart_recv_try           # a0 = byte o -1
        li      t0, PROTO_K
        beq     a0, t0, omw_done        # llego 'K' -> listo
        li      a0, HS_LISTEN_DELAY
        call    delay
        addi    s0, s0, -1
        bnez    s0, omw_poll
        j       omw_announce            # reenviar 'M'
omw_done:
        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret

# =====================================================================
#  handshake: decide rol por orden de llegada.
#    1) Escucha ~200ms (uart_recv_try en bucle). Si llega 'M' -> SEGUIDOR:
#       responde 'K' y retorna ROLE_FOLLOWER.
#    2) Si nadie hablo -> CONTROLADOR: envia 'M' y espera 'K' (sin limite),
#       descartando cualquier otro byte. Retorna ROLE_CONTROLLER.
#  a0 = rol.
# =====================================================================
handshake:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)

# --- 1) fase de escucha ---
        li      s0, HS_LISTEN_ITERS
hs_listen:
        call    uart_recv_try           # a0 = byte o -1
        li      t0, -1
        beq     a0, t0, hs_listen_next
        li      t0, PROTO_M
        beq     a0, t0, hs_be_follower  # llego 'M' -> somos seguidor
# cualquier otro byte: ruido, lo ignoramos y seguimos escuchando
hs_listen_next:
        li      a0, HS_LISTEN_DELAY
        call    delay
        addi    s0, s0, -1
        bnez    s0, hs_listen

# --- 2) nadie hablo: somos controlador ---
# Anunciarse con 'M' en loop hasta recibir 'K'. A diferencia de la version
# de un solo envio, aqui reenviamos 'M' periodicamente: si el seguidor
# todavia no estaba escuchando cuando salio la primera, una 'M' posterior
# caera dentro de su ventana. Entre envio y envio, escuchamos SIN bloquear
# (uart_recv_try) para no perder la 'K' ni quedar trabados.
hs_announce:
        li      a0, PROTO_M
        call    uart_send_byte          # mandar 'M'

# escuchar respuesta un rato, sin bloquear, antes de reenviar
        li      s0, HS_ACK_POLLS        # cantidad de sondeos por cada 'M'
hs_poll_k:
        call    uart_recv_try           # a0 = byte o -1
        li      t0, PROTO_K
        beq     a0, t0, hs_got_k        # llego 'K' -> listo, somos controlador
        li      a0, HS_LISTEN_DELAY
        call    delay
        addi    s0, s0, -1
        bnez    s0, hs_poll_k
        j       hs_announce             # se agoto el sondeo -> reenviar 'M'

hs_got_k:
        li      a0, ROLE_CONTROLLER
        j       hs_ret

hs_be_follower:
        li      a0, PROTO_K
        call    uart_send_byte          # responder ack
        li      a0, ROLE_FOLLOWER

hs_ret:
        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret

# =====================================================================
#  online_controller: bucle del controlador (juega P1='X').
#
#  Orden del frame (extiende el de juego.s a dos jugadores):
#    1) systimer: marca de inicio del frame (tempo de 150ms)
#    2) input LOCAL  -> acciones de P1
#    3) input REMOTO -> ultimo W/S/A/D/B recibido -> acciones de P2
#       (si P1 y P2 quieren la misma casilla, P1 ya se movio primero:
#        P2 la encuentra ocupada y no entra -> prioridad LOCAL, gratis)
#    4) tick_fire + tick_bombs (explosiones, cadenas)  [reusado de juego.s]
#    5) check_death (mata a quien este sobre fuego)    [reusado de juego.s]
#    6) encode_board -> enviar 'F' + 91 bytes -> esperar 'K'
#    7) render local (board_draw)                      [reusado de juego.s]
#    8) si game_over: enviar 'R' + resultado y salir
#    9) esperar a completar FRAME_TICKS desde (1)
# =====================================================================
online_controller:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)               # marca de tiempo del frame

oc_frame:
        call    systimer_read
        mv      s0, a0

# --- 2) input local (P1) ---
        call    boton_leer              # a0 = botones locales
        call    handle_input_p1         # mueve/pone bomba P1 (a0=botones)

# --- 3) input remoto (P2) ---
        call    drain_rx_last_move      # a0 = ultimo byte de movimiento o -1
        call    handle_input_p2         # interpreta a0 como accion de P2

# --- 4) tick de bombas/fuego ---
        call    tick_fire
        call    tick_bombs

# --- 5) muerte ---
        call    check_death

# --- 6) enviar tablero y esperar ACK ---
        call    encode_board            # llena net_buffer (91 bytes ASCII)
        li      a0, PROTO_F
        call    uart_send_byte
        call    send_board              # manda los 91 bytes de net_buffer
        call    wait_ack                # bloquea hasta recibir 'K'

# --- 7) render local ---
        call    board_draw

# --- 8) fin del juego? ---
        la      t0, game_over
        lw      t1, 0(t0)
        bnez    t1, oc_gameover

# --- 9) completar el frame de 150ms ---
oc_wait:
        call    systimer_read
        sub     t0, a0, s0
        li      t1, FRAME_TICKS
        bltu    t0, t1, oc_wait
        j       oc_frame

oc_gameover:
# Resultado desde el punto de vista del CONTROLADOR (P1):
#   gano  -> P1 vivo  -> 'R' '1'
#   perdio/empate -> P1 muerto -> 'R' '0'
# (empate = ambos mueren el mismo frame: P1 tambien esta muerto -> '0')
        li      a0, PROTO_R
        call    uart_send_byte
        la      t0, p1_alive
        lw      t1, 0(t0)
        beqz    t1, oc_send_lose
        li      a0, PROTO_1
        j       oc_send_res
oc_send_lose:
        li      a0, PROTO_0
oc_send_res:
        call    uart_send_byte
# dejar el resultado en pantalla un momento antes de volver al menu
        li      a0, 4000000
        call    delay

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret

# =====================================================================
#  online_follower: bucle del seguidor (juega P2='O').
#
#  No simula nada. Cada frame:
#    1) input local -> si hay tecla, mandar UN byte de movimiento (P2)
#    2) leer 1 byte de COMANDO del controlador (bloqueante)
#         'F' -> leer 91 bytes, responder 'K', decodificar, render
#         'R' -> leer 1 byte de resultado, mostrarlo (opcional) y salir
#         otro -> descartar
#
#  Notas de sincronizacion:
#   - El seguidor manda su input ANTES de leer el comando. El controlador
#     lo recogera en el drain del PROXIMO frame (no bloquea por el).
#   - El 'K' se manda apenas se recibe el tablero completo: eso libera al
#     controlador para renderizar y temporizar. Lock-step cerrado.
# =====================================================================
online_follower:
        addi    sp, sp, -4
        sw      ra, 0(sp)

of_frame:
# --- 1) input local del seguidor -> mandar movimiento ---
        call    boton_leer              # a0 = botones locales
        call    follower_send_input     # traduce a0 -> byte y lo manda (si hay)

# --- 2) leer comando del controlador ---
        call    uart_recv_byte          # bloquea; a0 = comando
        li      t0, PROTO_F
        beq     a0, t0, of_frame_cmd
        li      t0, PROTO_R
        beq     a0, t0, of_result_cmd
        j       of_frame                # byte inesperado -> descartar, seguir

of_frame_cmd:
# recibir 91 bytes -> net_buffer
        call    recv_board
# responder ACK apenas tenemos el tablero completo
        li      a0, PROTO_K
        call    uart_send_byte
# decodificar a board[]/btimer[] y dibujar
        call    decode_board
        call    board_draw
        j       of_frame

of_result_cmd:
        call    uart_recv_byte          # a0 = '1' / '0' (resultado)
# (Opcional: podriamos dibujar una pantalla de fin. Por ahora salimos y
#  el menu se redibuja.)
        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret

# =====================================================================
#  handle_input_p1(a0=botones): igual que handle_input de juego.s pero
#  expuesto aqui para el controlador. Bomba con boton central; movimiento
#  un paso por frame (prioridad U>D>L>R).
# =====================================================================
handle_input_p1:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        mv      s0, a0                  # botones

        li      t0, BTN_CONFIRM
        and     t1, s0, t0
        beqz    t1, hip1_move
        addi    sp, sp, -4
        sw      s0, 0(sp)
        call    p1_place_bomb
        lw      s0, 0(sp)
        addi    sp, sp, 4

hip1_move:
        li      t2, 0                   # dx
        li      t3, 0                   # dy
        li      t0, BTN_UP
        and     t1, s0, t0
        beqz    t1, hip1_d
        li      t3, -1
        j       hip1_do
hip1_d:
        li      t0, BTN_DOWN
        and     t1, s0, t0
        beqz    t1, hip1_l
        li      t3, 1
        j       hip1_do
hip1_l:
        li      t0, BTN_LEFT
        and     t1, s0, t0
        beqz    t1, hip1_r
        li      t2, -1
        j       hip1_do
hip1_r:
        li      t0, BTN_RIGHT
        and     t1, s0, t0
        beqz    t1, hip1_ret
        li      t2, 1

hip1_do:
        mv      a0, t2
        mv      a1, t3
        call    p1_try_move

hip1_ret:
        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret

# =====================================================================
#  handle_input_p2(a0=byte de movimiento o -1): traduce el comando remoto
#  a una accion de P2. Una sola accion por frame.
#    'W'->arriba 'S'->abajo 'A'->izq 'D'->der 'B'->bomba ; -1/otro -> nada
# =====================================================================
handle_input_p2:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        mv      s0, a0

        li      t0, -1
        beq     s0, t0, hip2_ret        # no llego nada

        li      t0, PROTO_B
        beq     s0, t0, hip2_bomb
        li      t0, PROTO_W
        beq     s0, t0, hip2_up
        li      t0, PROTO_S
        beq     s0, t0, hip2_down
        li      t0, PROTO_A
        beq     s0, t0, hip2_left
        li      t0, PROTO_D
        beq     s0, t0, hip2_right
        j       hip2_ret                # byte no reconocido

hip2_bomb:
        call    p2_place_bomb
        j       hip2_ret
hip2_up:
        li      a0, 0
        li      a1, -1
        call    p2_try_move
        j       hip2_ret
hip2_down:
        li      a0, 0
        li      a1, 1
        call    p2_try_move
        j       hip2_ret
hip2_left:
        li      a0, -1
        li      a1, 0
        call    p2_try_move
        j       hip2_ret
hip2_right:
        li      a0, 1
        li      a1, 0
        call    p2_try_move

hip2_ret:
        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret

# =====================================================================
#  follower_send_input(a0=botones): si hay alguna direccion o bomba
#  apretada, manda UN byte por UART (prioridad bomba > U > D > L > R).
#  Si no hay nada, no manda. Una sola accion por frame.
# =====================================================================
follower_send_input:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        mv      s0, a0

        li      t0, BTN_CONFIRM
        and     t1, s0, t0
        beqz    t1, fsi_up
        li      a0, PROTO_B
        j       fsi_send
fsi_up:
        li      t0, BTN_UP
        and     t1, s0, t0
        beqz    t1, fsi_down
        li      a0, PROTO_W
        j       fsi_send
fsi_down:
        li      t0, BTN_DOWN
        and     t1, s0, t0
        beqz    t1, fsi_left
        li      a0, PROTO_S
        j       fsi_send
fsi_left:
        li      t0, BTN_LEFT
        and     t1, s0, t0
        beqz    t1, fsi_right
        li      a0, PROTO_A
        j       fsi_send
fsi_right:
        li      t0, BTN_RIGHT
        and     t1, s0, t0
        beqz    t1, fsi_none
        li      a0, PROTO_D
fsi_send:
        call    uart_send_byte
fsi_none:
        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret

# =====================================================================
#  p2_place_bomb: clon de p1_place_bomb para P2 (bowner=1, usa p2_*).
#  Coloca bomba en la casilla de P2 si no supera su max ni MAX_BOMBS y la
#  casilla no tiene ya una bomba. Congela el rango actual de P2.
# =====================================================================
p2_place_bomb:
        addi    sp, sp, -4
        sw      ra, 0(sp)

        la      t0, p2_placed
        lw      t1, 0(t0)
        la      t0, p2_maxbombs
        lw      t2, 0(t0)
        bge     t1, t2, p2pb_no
        li      t3, MAX_BOMBS
        bge     t1, t3, p2pb_no

        la      t0, p2_x
        lw      t4, 0(t0)
        la      t0, p2_y
        lw      t5, 0(t0)
        li      t6, BOARD_COLS
        mul     t6, t5, t6
        add     t6, t6, t4              # indice

        la      t0, board
        add     t0, t0, t6
        lbu     t1, 0(t0)
        li      t2, CELL_BOMB
        beq     t1, t2, p2pb_no         # ya hay bomba

        li      t2, CELL_BOMB
        sb      t2, 0(t0)
        la      t1, btimer
        add     t1, t1, t6
        li      t2, BOMB_FRAMES
        sb      t2, 0(t1)
        la      t1, brange
        add     t1, t1, t6
        la      t0, p2_range
        lw      t2, 0(t0)
        sb      t2, 0(t1)
        la      t1, bowner
        add     t1, t1, t6
        li      t2, 1                   # dueno = 1 (P2)
        sb      t2, 0(t1)

        la      t0, p2_placed
        lw      t1, 0(t0)
        addi    t1, t1, 1
        sw      t1, 0(t0)

p2pb_no:
        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret

# =====================================================================
#  p2_try_move(dx=a0, dy=a1): clon de p1_try_move para P2.
#  Transitable: EMPTY o POWERUP (lo recoge -> +1 maxbombs hasta 5, +1 range).
#  Pared/caja/bomba/fuego bloquean. Escribe CELL_P2 en el tablero.
# =====================================================================
p2_try_move:
        addi    sp, sp, -16
        sw      ra, 0(sp)
        sw      s0, 4(sp)               # nx
        sw      s1, 8(sp)               # ny
        sw      s2, 12(sp)              # indice destino

        la      t0, p2_x
        lw      t1, 0(t0)
        la      t0, p2_y
        lw      t2, 0(t0)
        add     s0, t1, a0
        add     s1, t2, a1

        bltz    s0, p2tm_no
        li      t3, BOARD_COLS
        bge     s0, t3, p2tm_no
        bltz    s1, p2tm_no
        li      t3, BOARD_ROWS
        bge     s1, t3, p2tm_no

        li      t3, BOARD_COLS
        mul     t3, s1, t3
        add     s2, t3, s0              # indice destino
        la      t4, board
        add     t4, t4, s2
        lbu     t5, 0(t4)               # contenido destino

        li      t6, CELL_EMPTY
        beq     t5, t6, p2tm_ok
        li      t6, CELL_POWERUP
        beq     t5, t6, p2tm_powerup
        j       p2tm_no                 # pared, caja, bomba, fuego, X: bloquea

p2tm_powerup:
        la      t0, p2_maxbombs
        lw      t1, 0(t0)
        li      t2, MAX_BOMBS
        bge     t1, t2, p2p_skip_mb
        addi    t1, t1, 1
        sw      t1, 0(t0)
p2p_skip_mb:
        la      t0, p2_range
        lw      t1, 0(t0)
        addi    t1, t1, 1
        sw      t1, 0(t0)
# cae en p2tm_ok

p2tm_ok:
# vaciar casilla vieja si sigue siendo P2
        la      t0, p2_x
        lw      t1, 0(t0)
        la      t0, p2_y
        lw      t2, 0(t0)
        li      t3, BOARD_COLS
        mul     t3, t2, t3
        add     t3, t3, t1
        la      t0, board
        add     t0, t0, t3
        lbu     t4, 0(t0)
        li      t5, CELL_P2
        bne     t4, t5, p2tm_setnew
        li      t4, CELL_EMPTY
        sb      t4, 0(t0)
p2tm_setnew:
        la      t0, board
        add     t0, t0, s2
        li      t4, CELL_P2
        sb      t4, 0(t0)
        la      t0, p2_x
        sw      s0, 0(t0)
        la      t0, p2_y
        sw      s1, 0(t0)

p2tm_no:
        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        lw      s2, 12(sp)
        addi    sp, sp, 16
        ret

# =====================================================================
#  encode_board: barre board[] (y btimer[] para el fuego) y produce 91
#  bytes ASCII en net_buffer, segun el mapeo del protocolo.
#  Funcion hoja (solo temporales).
# =====================================================================
encode_board:
        la      t0, board
        la      t1, btimer
        la      t2, net_buffer
        li      t3, BOARD_CELLS
eb_loop:
        lbu     t4, 0(t0)               # codigo de casilla

        li      t5, CELL_EMPTY
        bne     t4, t5, eb_not_empty
        li      t6, ' '
        j       eb_store
eb_not_empty:
        li      t5, CELL_WALL
        bne     t4, t5, eb_not_wall
        li      t6, 'P'
        j       eb_store
eb_not_wall:
        li      t5, CELL_BOX
        bne     t4, t5, eb_not_box
        li      t6, 'C'
        j       eb_store
eb_not_box:
        li      t5, CELL_P1
        bne     t4, t5, eb_not_p1
        li      t6, 'X'
        j       eb_store
eb_not_p1:
        li      t5, CELL_P2
        bne     t4, t5, eb_not_p2
        li      t6, 'O'
        j       eb_store
eb_not_p2:
        li      t5, CELL_BOMB
        bne     t4, t5, eb_not_bomb
        li      t6, 'B'
        j       eb_store
eb_not_bomb:
        li      t5, CELL_POWERUP
        bne     t4, t5, eb_not_pu
        li      t6, '+'
        j       eb_store
eb_not_pu:
        li      t5, CELL_FIRE
        bne     t4, t5, eb_unknown
# fuego: byte = '0' + btimer (cuenta 1..6 -> '1'..'6')
        lbu     t6, 0(t1)               # timer
        addi    t6, t6, '0'
        j       eb_store
eb_unknown:
# por seguridad, cualquier codigo no previsto -> espacio
        li      t6, ' '
eb_store:
        sb      t6, 0(t2)
        addi    t0, t0, 1
        addi    t1, t1, 1
        addi    t2, t2, 1
        addi    t3, t3, -1
        bnez    t3, eb_loop
        ret

# =====================================================================
#  decode_board: lee los 91 bytes de net_buffer y reconstruye board[]
#  y btimer[]. El seguidor lo usa antes de board_draw.
#    ' '->EMPTY 'P'->WALL 'C'->BOX 'X'->P1 'O'->P2 'B'->BOMB '+'->POWERUP
#    '1'..'6' -> FIRE con btimer = digito
#  btimer se pone en 0 salvo para el fuego (board_draw solo lee btimer
#  cuando la casilla es FIRE, pero lo limpiamos igual por prolijidad).
#  Funcion hoja (solo temporales).
# =====================================================================
decode_board:
        la      t0, net_buffer
        la      t1, board
        la      t2, btimer
        li      t3, BOARD_CELLS
db_loop:
        lbu     t4, 0(t0)               # byte ASCII recibido
        li      t5, 0                   # btimer por defecto

        li      t6, ' '
        bne     t4, t6, db_not_empty
        li      t6, CELL_EMPTY
        j       db_store
db_not_empty:
        li      t6, 'P'
        bne     t4, t6, db_not_wall
        li      t6, CELL_WALL
        j       db_store
db_not_wall:
        li      t6, 'C'
        bne     t4, t6, db_not_box
        li      t6, CELL_BOX
        j       db_store
db_not_box:
        li      t6, 'X'
        bne     t4, t6, db_not_p1
        li      t6, CELL_P1
        j       db_store
db_not_p1:
        li      t6, 'O'
        bne     t4, t6, db_not_p2
        li      t6, CELL_P2
        j       db_store
db_not_p2:
        li      t6, 'B'
        bne     t4, t6, db_not_bomb
        li      t6, CELL_BOMB
        j       db_store
db_not_bomb:
        li      t6, '+'
        bne     t4, t6, db_not_pu
        li      t6, CELL_POWERUP
        j       db_store
db_not_pu:
# rango '1'..'6' -> fuego
        li      t6, '1'
        blt     t4, t6, db_unknown
        li      t6, '6'
        bgt     t4, t6, db_unknown
        addi    t5, t4, -'0'            # btimer = digito (1..6)
        li      t6, CELL_FIRE
        j       db_store
db_unknown:
# byte no reconocido -> casilla vacia
        li      t6, CELL_EMPTY
db_store:
        sb      t6, 0(t1)               # board[i]
        sb      t5, 0(t2)               # btimer[i]
        addi    t0, t0, 1
        addi    t1, t1, 1
        addi    t2, t2, 1
        addi    t3, t3, -1
        bnez    t3, db_loop
        ret

# =====================================================================
#  send_board: envia los 91 bytes de net_buffer por UART (en orden).
# =====================================================================
send_board:
        addi    sp, sp, -12
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        sw      s1, 8(sp)
        la      s0, net_buffer
        li      s1, BOARD_CELLS
sb_loop:
        lbu     a0, 0(s0)
        call    uart_send_byte
        addi    s0, s0, 1
        addi    s1, s1, -1
        bnez    s1, sb_loop
        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        addi    sp, sp, 12
        ret

# =====================================================================
#  recv_board: recibe 91 bytes (BLOQUEANTE) y los guarda en net_buffer.
# =====================================================================
recv_board:
        addi    sp, sp, -12
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        sw      s1, 8(sp)
        la      s0, net_buffer
        li      s1, BOARD_CELLS
rb_loop:
        call    uart_recv_byte          # a0 = byte
        sb      a0, 0(s0)
        addi    s0, s0, 1
        addi    s1, s1, -1
        bnez    s1, rb_loop
        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        addi    sp, sp, 12
        ret

# =====================================================================
#  wait_ack: bloquea hasta recibir 'K', descartando cualquier otro byte.
#  Lo usa el controlador despues de mandar el tablero (lock-step).
# =====================================================================
wait_ack:
        addi    sp, sp, -4
        sw      ra, 0(sp)
wa_loop:
        call    uart_recv_byte
        li      t0, PROTO_K
        bne     a0, t0, wa_loop
        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret

# =====================================================================
#  drain_rx_last_move: vacia el FIFO de RX SIN bloquear y devuelve en a0
#  el ULTIMO byte que sea un comando de movimiento (W/S/A/D/B). Descarta
#  todo lo demas. Si no habia ningun movimiento, devuelve -1.
#
#  Por que el ultimo: la spec dice que si llegan varios movimientos en un
#  frame, vale solo el ultimo (cada sistema procesa una accion por cuadro).
#  Vaciar el FIFO entero ademas evita que se acumule lag de input.
# =====================================================================
drain_rx_last_move:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        li      s0, -1                  # ultimo movimiento visto
drm_loop:
        call    uart_recv_try           # a0 = byte o -1
        li      t0, -1
        beq     a0, t0, drm_done        # FIFO vacio -> terminar

# es un comando de movimiento valido?
        li      t0, PROTO_W
        beq     a0, t0, drm_keep
        li      t0, PROTO_S
        beq     a0, t0, drm_keep
        li      t0, PROTO_A
        beq     a0, t0, drm_keep
        li      t0, PROTO_D
        beq     a0, t0, drm_keep
        li      t0, PROTO_B
        beq     a0, t0, drm_keep
        j       drm_loop                # otro byte: descartar, seguir vaciando
drm_keep:
        mv      s0, a0                  # recordar (se quedara el ultimo)
        j       drm_loop

drm_done:
        mv      a0, s0
        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret