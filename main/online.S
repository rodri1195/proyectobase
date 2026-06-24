#include "mes.inc"
# =====================================================================
#  online.s - Protocolo multijugador del MES (Bomberman en red)
#
#  Capa 2: bucles de juego en lock-step. El ROL lo decide menu.s segun
#  COMO se entro al modo online (no se negocia aqui):
#    - online_as_follower:   me llego una 'M' por UART estando en el menu.
#                            El menu YA respondio 'K'. Entro como SEGUIDOR ('O').
#    - online_as_controller: yo elegi ONLINE. El menu llamo primero a
#                            online_send_m_wait_k (manda 'M', espera 'K') y al
#                            volver entra aqui como CONTROLADOR ('X').
#
#  Sincronizacion (lock-step): el controlador NO avanza de frame hasta
#  recibir la 'K' del seguidor. Asi ambas pantallas van al mismo ritmo y
#  el frame de 150ms del controlador marca el tempo de los dos.
#
#  Protocolo (todo ASCII, sin marca de fin; bytes definidos en mes.inc):
#    Handshake : controlador 'M' -> seguidor 'K'  (envio UNICO de 'M')
#    Cada frame: controlador 'F' + 91 bytes de tablero -> seguidor 'K'
#    Input     : seguidor manda W/S/A/D/B (solo el ULTIMO del frame vale)
#    Fin       : controlador 'R' + ('1' gano / '0' perdio-empate)
#    Bytes inesperados se descartan.
#
#  Tablero codificado (1 byte ASCII por casilla, 91 en total):
#    ' ' vacio | 'P' pared | 'C' caja | 'X' P1 | 'O' P2 | 'B' bomba
#    '+' powerup | '1'..'6' fuego (el digito es la cuenta restante)
#  El seguidor reconstruye board[] y btimer[] desde estos bytes para que
#  board_draw dibuje el digito del fuego igual que el controlador.
# =====================================================================
.extern fb_cartel                       # cartel GANASTE/PERDISTE (en menu.s)

.data
        .align  2
# Buffer de red: 91 bytes del tablero (ASCII). Reutilizado por encode/decode.
net_buffer: .space 91

.text
.global online_send_m_wait_k
.global online_as_controller
.global online_as_follower

# =====================================================================
#  online_send_m_wait_k: yo seleccione ONLINE. Anuncio mi presencia con
#  UN solo envio de 'M' y luego escucho la 'K' del seguidor (bloqueante,
#  sin reenviar). No retorna hasta recibir 'K'. Lo llama menu.s; al volver,
#  el menu salta a online_as_controller.
#
#  Por que envio unico: en HW se observo que reenviar 'M' periodicamente
#  ensuciaba el canal y desincronizaba al par. Una sola 'M' basta: el otro
#  nodo, ya escuchando desde el menu, la captura y responde 'K'. Si la 'K'
#  no llega, nos quedamos escuchando (el seguidor reintenta su lado).
#
#  Funcion hoja en cuanto a callee-saved: solo usa a0/t0 entre llamadas,
#  pero llama a otras rutinas, asi que guarda ra.
# =====================================================================
online_send_m_wait_k:
        addi    sp, sp, -4
        sw      ra, 0(sp)

        li      a0, PROTO_M
        call    uart_send_byte          # mandar 'M' UNA sola vez

omw_wait_k:
        call    uart_recv_byte          # bloquea; a0 = byte recibido
        li      t0, PROTO_K
        bne     a0, t0, omw_wait_k      # cualquier otro byte -> seguir esperando

        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret

# =====================================================================
#  online_as_controller: yo elegi ONLINE. El menu ya completo el handshake
#  (online_send_m_wait_k). Genero el tablero y corro el bucle de control.
# =====================================================================
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
#  online_as_follower: me llego una 'M' estando en el menu (que ya respondio
#  'K'). No genero tablero: lo recibo completo en el primer 'F'.
# =====================================================================
online_as_follower:
        addi    sp, sp, -4
        sw      ra, 0(sp)
        call    state_init
        call    online_follower
        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret

# =====================================================================
#  online_controller: bucle del controlador (juega P1='X').
#  Orden del frame (extiende el de juego.s a dos jugadores):
#    1) systimer: marca de inicio del frame (tempo de 150ms)
#    2) input LOCAL  -> acciones de P1
#    3) input REMOTO -> ultimo W/S/A/D/B recibido -> acciones de P2
#       (si P1 y P2 quieren la misma casilla, P1 ya se movio primero:
#        P2 la encuentra ocupada y no entra -> prioridad LOCAL, gratis)
#    4) tick_fire + tick_bombs (explosiones, cadenas)
#    5) check_death (mata a quien este sobre fuego)
#    6) encode_board -> 'F' + 91 bytes -> esperar 'K'
#    7) render local (board_draw)
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

        call    boton_leer              # a0 = botones locales
        call    handle_input_p1         # mueve/pone bomba P1 (a0=botones)

        call    drain_rx_last_move      # a0 = ultimo byte de movimiento o -1
        call    handle_input_p2         # interpreta a0 como accion de P2

        call    tick_fire
        call    tick_bombs
        call    check_death

        call    encode_board            # llena net_buffer (91 bytes ASCII)
        li      a0, PROTO_F
        call    uart_send_byte
        call    send_board              # manda los 91 bytes de net_buffer
        call    wait_ack                # bloquea hasta recibir 'K'

        call    board_draw

        la      t0, game_over
        lw      t1, 0(t0)
        bnez    t1, oc_gameover

oc_wait:
        call    systimer_read
        sub     t0, a0, s0
        li      t1, FRAME_TICKS
        bltu    t0, t1, oc_wait
        j       oc_frame

oc_gameover:
# Resultado desde el punto de vista del CONTROLADOR (P1):
#   P1 vivo -> 'R' '1' ; P1 muerto (perdio/empate) -> 'R' '0'
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
# Mostrar el cartel en MI pantalla (controlador = P1 = "vos"):
#   p1_alive==1 -> GANASTE ; p1_alive==0 -> PERDISTE
        la      t0, p1_alive
        lw      a0, 0(t0)               # a0 = 1 (ganaste) / 0 (perdiste)
        call    fb_cartel
        li      a0, 4000000             # dejar el cartel en pantalla
        call    delay

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret

# =====================================================================
#  online_follower: bucle del seguidor (juega P2='O'). No simula nada.
#  Cada frame:
#    1) input local -> si hay tecla, mandar UN byte de movimiento (P2)
#    2) leer 1 byte de COMANDO del controlador (bloqueante)
#         'F' -> leer 91 bytes, responder 'K', decodificar, render
#         'R' -> leer 1 byte de resultado y salir
#         otro -> descartar
# =====================================================================
online_follower:
        addi    sp, sp, -4
        sw      ra, 0(sp)

of_frame:
        call    boton_leer              # a0 = botones locales
        call    follower_send_input     # traduce a0 -> byte y lo manda (si hay)

        call    uart_recv_byte          # bloquea; a0 = comando
        li      t0, PROTO_F
        beq     a0, t0, of_frame_cmd
        li      t0, PROTO_R
        beq     a0, t0, of_result_cmd
        j       of_frame                # byte inesperado -> descartar

of_frame_cmd:
        call    recv_board              # 91 bytes -> net_buffer
        li      a0, PROTO_K
        call    uart_send_byte          # ACK apenas tenemos el tablero
        call    decode_board            # a board[]/btimer[]
        call    board_draw
        j       of_frame

of_result_cmd:
        call    uart_recv_byte          # a0 = '1'/'0' en optica de P1
# El byte viene en optica del CONTROLADOR (P1). Para el seguidor (P2) hay
# que INVERTIRLO: el controlador manda '1' si EL gano, lo que significa que
# el seguidor PERDIO. '0' (P1 perdio/empate) -> el seguidor GANO.
#   recibido '1' -> fb_cartel(0) = PERDISTE
#   recibido '0' -> fb_cartel(1) = GANASTE
        li      t0, PROTO_1
        bne     a0, t0, ofr_win
        li      a0, 0                   # P1 gano -> P2 perdio
        j       ofr_show
ofr_win:
        li      a0, 1                   # P1 no gano -> P2 gano
ofr_show:
        call    fb_cartel
        li      a0, 4000000             # dejar el cartel en pantalla
        call    delay

        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret

# =====================================================================
#  handle_input_p1(a0=botones): bomba con boton central; movimiento un
#  paso por frame (prioridad U>D>L>R).
# =====================================================================
handle_input_p1:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        mv      s0, a0                  # botones

        li      t0, BTN_CONFIRM
        and     t1, s0, t0
        beqz    t1, hip1_move
        call    p1_place_bomb

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
#  handle_input_p2(a0=byte de movimiento o -1): una sola accion por frame.
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
#  follower_send_input(a0=botones): si hay direccion o bomba apretada,
#  manda UN byte (prioridad bomba > U > D > L > R). Una accion por frame.
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
#  p2_place_bomb: coloca bomba en la casilla de P2 si no supera su max ni
#  MAX_BOMBS y la casilla no tiene ya bomba. Congela el rango actual de P2.
#  dueno = 1 (P2).
# =====================================================================
p2_place_bomb:
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
        ret

# =====================================================================
#  p2_try_move(dx=a0, dy=a1): transitable EMPTY o POWERUP (lo recoge:
#  +1 maxbombs hasta MAX_BOMBS, +1 range). Pared/caja/bomba/fuego/X
#  bloquean. Escribe CELL_P2 en el tablero.
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
#  bytes ASCII en net_buffer. Funcion hoja (solo temporales).
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
        lbu     t6, 0(t1)
        addi    t6, t6, '0'
        j       eb_store
eb_unknown:
        li      t6, ' '                 # codigo no previsto -> espacio
eb_store:
        sb      t6, 0(t2)
        addi    t0, t0, 1
        addi    t1, t1, 1
        addi    t2, t2, 1
        addi    t3, t3, -1
        bnez    t3, eb_loop
        ret

# =====================================================================
#  decode_board: lee 91 bytes de net_buffer y reconstruye board[]/btimer[].
#    ' '->EMPTY 'P'->WALL 'C'->BOX 'X'->P1 'O'->P2 'B'->BOMB '+'->POWERUP
#    '1'..'6' -> FIRE con btimer = digito ; resto -> EMPTY
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
        li      t6, '1'
        blt     t4, t6, db_unknown
        li      t6, '6'
        bgt     t4, t6, db_unknown
        addi    t5, t4, -'0'            # btimer = digito (1..6)
        li      t6, CELL_FIRE
        j       db_store
db_unknown:
        li      t6, CELL_EMPTY          # byte no reconocido -> vacio
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
#  el ULTIMO byte de movimiento (W/S/A/D/B). Descarta el resto. Si no
#  hubo movimiento, devuelve -1. Vaciar todo evita acumular lag de input.
# =====================================================================
drain_rx_last_move:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        li      s0, -1                  # ultimo movimiento visto
drm_loop:
        call    uart_recv_try           # a0 = byte o -1
        li      t0, -1
        beq     a0, t0, drm_done        # FIFO vacio

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
        j       drm_loop                # otro byte: descartar
drm_keep:
        mv      s0, a0                  # recordar (quedara el ultimo)
        j       drm_loop
drm_done:
        mv      a0, s0
        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret