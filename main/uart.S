# ============================================================================
#  uart.S  -  UART1 bare-metal sobre ESP32-C3 (sin ESP-IDF driver)
#
#  Enlace full-duplex entre dos ESP32-C3 Super Mini a 115200 bps, 8N1.
#  Clock source: XTAL 40 MHz.  TX = GPIO20, RX = GPIO21 via GPIO Matrix.
#  Todas las direcciones/bits derivadas del ESP32-C3 TRM.
#
#  API publica:
#     uart_init      ()              -> inicializa UART1 completo
#     uart_tx_byte   (a0 = byte)     -> envia 1 byte (bloqueante por polling)
#     uart_rx_byte   ()              -> a0 = byte recibido, a1 = status
#                                       a1: 0=ok, bit0=framing err, bit1=overflow
#                                       (bloqueante: espera hasta tener 1 byte)
#     uart_rx_ready  ()              -> a0 = nº de bytes en RX FIFO (no bloquea)
# ============================================================================

# ---------------------------------------------------------------------------
#  Bases de periferico (TRM - Peripheral Address Mapping)
# ---------------------------------------------------------------------------
        .equ    SYSTEM_BASE,   0x600C0000
        .equ    UART1_BASE,    0x60010000
        .equ    GPIO_BASE,     0x60004000
        .equ    IOMUX_BASE,    0x60009000

# ---------------------------------------------------------------------------
#  System: habilitacion de clock y reset de UART1 (bit 5 en ambos)
# ---------------------------------------------------------------------------
        .equ    PERIP_CLK_EN0, 0x0010   # SYSTEM_PERIP_CLK_EN0_REG
        .equ    PERIP_RST_EN0, 0x0018   # SYSTEM_PERIP_RST_EN0_REG
        .equ    UART1_EN_BIT,  (1 << 5)

# ---------------------------------------------------------------------------
#  Registros UART (offset desde UART1_BASE)
# ---------------------------------------------------------------------------
        .equ    UART_FIFO,     0x0000   # [7:0]  RD/WR byte
        .equ    UART_INT_RAW,  0x0004
        .equ    UART_INT_CLR,  0x0010
        .equ    UART_CLKDIV,   0x0014   # [11:0] int, [23:20] frag
        .equ    UART_STATUS,   0x001C   # RXFIFO_CNT[9:0], TXFIFO_CNT[25:16]
        .equ    UART_CONF0,    0x0020
        .equ    UART_CONF1,    0x0024
        .equ    UART_CLK_CONF, 0x0078
        .equ    UART_ID,       0x0080   # UPDATE_CTRL[30], REG_UPDATE[31]

# --- INT bits ---
        .equ    INT_FRM_ERR,   (1 << 3) # framing error
        .equ    INT_RXFIFO_OVF,(1 << 4) # rx fifo overflow

# --- CONF0 bits (frame 8N1) ---
#   BIT_NUM[3:2]=3 (8 data bits), PARITY_EN[1]=0, STOP_BIT_NUM[5:4]=1 (1 stop)
        .equ    CONF0_8N1,     ((3 << 2) | (1 << 4)) # = 0x1C
        .equ    CONF0_RXFIFO_RST, (1 << 17)
        .equ    CONF0_TXFIFO_RST, (1 << 18)

# --- CLKDIV: 40 MHz / 115200 = 347.25 -> int=347, frag=4 ---
#   baud_real = 40e6 / (347 + 4/16) = 115190.8 bps  (error -0.008%)
        .equ    CLKDIV_VAL,    ((4 << 20) | 347) # = 0x0040015B

# --- CLK_CONF: SCLK_SEL=3 (XTAL), DIV_NUM=0 (passthrough), clocks ON ---
#   SCLK_SEL[21:20]=3, SCLK_EN[22]=1, TX_SCLK_EN[24]=1, RX_SCLK_EN[25]=1
        .equ    CLK_CONF_VAL,  ((3 << 20) | (1 << 22) | (1 << 24) | (1 << 25)) # 0x03700000

# --- ID: para sincronizar config al dominio de reloj del Core ---
        .equ    ID_REG_UPDATE, (1 << 31)
        .equ    ID_UPDATE_CTRL,(1 << 30)

# ---------------------------------------------------------------------------
#  GPIO Matrix
#     U1 signal index = 9  (U1RXD_in / U1TXD_out)
#     TX: GPIO20 saca señal 9  -> FUNC20_OUT_SEL_CFG
#     RX: señal 9 lee GPIO21   -> FUNC9_IN_SEL_CFG
# ---------------------------------------------------------------------------
        .equ    U1_SIGNAL,     9
        .equ    PIN_TX,        20
        .equ    PIN_RX,        21

        .equ    GPIO_OUT_SEL_BASE, 0x0554 # FUNCn_OUT_SEL_CFG, n indexado por GPIO
        .equ    GPIO_IN_SEL_BASE,  0x0154 # FUNCn_IN_SEL_CFG, n indexado por SEÑAL
        .equ    GPIO_ENABLE_W1TS,  0x0024 # habilita output del pin

# OUT_SEL_CFG para TX: OUT_SEL[7:0]=9, OEN_SEL[9]=0, OUT_INV[10]=0
        .equ    TX_OUT_SEL_OFF, (GPIO_OUT_SEL_BASE + 4 * PIN_TX) # 0x05A4
        .equ    TX_OUT_SEL_VAL, U1_SIGNAL

# IN_SEL_CFG para RX: IN_SEL[4:0]=21, IN_INV[5]=0, SIG_IN_SEL[6]=1
#   SIG_IN_SEL=1 -> la señal viene de la GPIO Matrix (no bypass)
        .equ    RX_IN_SEL_OFF,  (GPIO_IN_SEL_BASE + 4 * U1_SIGNAL) # 0x0178
        .equ    RX_IN_SEL_VAL,  ((1 << 6) | PIN_RX) # 0x55

# IO_MUX del pin RX: FUN_IE[9]=1 (input enable)
        .equ    IOMUX_RX_OFF,   (0x0004 + 4 * PIN_RX) # 0x0058
        .equ    IOMUX_FUN_IE,   (1 << 9)

# ---------------------------------------------------------------------------
#  STATUS field masks
# ---------------------------------------------------------------------------
        .equ    RXFIFO_CNT_MASK, 0x3FF  # [9:0]
        .equ    TXFIFO_CNT_SHIFT, 16
        .equ    TXFIFO_CNT_MASK, 0x3FF  # [25:16] -> 10 bits tras shift

# ============================================================================
.section .text
.global uart_init
.global uart_tx_byte
.global uart_rx_byte
.global uart_rx_ready

# ----------------------------------------------------------------------------
#  uart_init  -  no recibe args, no retorna nada util.
#  Clobbers: t0, t1, t2  (no usa callee-saved, no llama a nadie -> no toca ra)
# ----------------------------------------------------------------------------
uart_init:
# ---- 1. Habilitar clock del periferico UART1 (RMW para no pisar otros) ----
        li      t0, SYSTEM_BASE
        lw      t1, PERIP_CLK_EN0(t0)
        li      t2, UART1_EN_BIT
        or      t1, t1, t2
        sw      t1, PERIP_CLK_EN0(t0)

# ---- 2. Pulso de reset del periferico: set bit, luego clear bit ----
        lw      t1, PERIP_RST_EN0(t0)
        or      t1, t1, t2              # assert reset
        sw      t1, PERIP_RST_EN0(t0)
        lw      t1, PERIP_RST_EN0(t0)
        not     t2, t2                  # ~UART1_EN_BIT
        and     t1, t1, t2              # de-assert reset
        sw      t1, PERIP_RST_EN0(t0)

# ---- 3. Configurar clock source y divisor del Core (CLK_CONF) ----
        li      t0, UART1_BASE
        li      t1, CLK_CONF_VAL
        sw      t1, UART_CLK_CONF(t0)

# ---- 4. Baudrate (CLKDIV) ----
        li      t1, CLKDIV_VAL
        sw      t1, UART_CLKDIV(t0)

# ---- 5. Frame 8N1 + reset de las FIFOs ----
#   Escribimos CONF0 con los bits de RST en 1, luego los bajamos.
        li      t1, CONF0_8N1
        li      t2, (CONF0_RXFIFO_RST | CONF0_TXFIFO_RST)
        or      t2, t1, t2
        sw      t2, UART_CONF0(t0)      # FIFOs en reset
        sw      t1, UART_CONF0(t0)      # libera reset, queda 8N1 limpio

# ---- 6. CONF1: thresholds de FIFO ----
#   RX_FULL_THRHD[8:0]=1  (señaliza con 1 byte; usamos polling de todos modos)
#   TX_EMPTY_THRHD[17:9]=0
        li      t1, 1
        sw      t1, UART_CONF1(t0)

# ---- 7. Limpiar flags de interrupcion pendientes (framing/overflow) ----
        li      t1, (INT_FRM_ERR | INT_RXFIFO_OVF)
        sw      t1, UART_INT_CLR(t0)

# ---- 8. Sincronizar config al dominio de reloj del Core ----
#   UPDATE_CTRL debe estar en 0 antes de poner REG_UPDATE=1.
        li      t1, ID_REG_UPDATE
        sw      t1, UART_ID(t0)
1:      lw      t1, UART_ID(t0)         # esperar a que HW baje REG_UPDATE
        li      t2, ID_REG_UPDATE
        and     t1, t1, t2
        bnez    t1, 1b

# ---- 9. GPIO Matrix: rutear TX (GPIO20 <- señal 9) ----
        li      t0, GPIO_BASE
        li      t1, TX_OUT_SEL_VAL
        li      t2, TX_OUT_SEL_OFF
        add     t2, t0, t2
        sw      t1, 0(t2)

# habilitar driver de salida del pin TX
        li      t1, (1 << PIN_TX)
        sw      t1, GPIO_ENABLE_W1TS(t0)

# ---- 10. GPIO Matrix: rutear RX (señal 9 <- GPIO21) ----
        li      t1, RX_IN_SEL_VAL
        li      t2, RX_IN_SEL_OFF
        add     t2, t0, t2
        sw      t1, 0(t2)

# ---- 11. IO_MUX del pin RX: habilitar input ----
        li      t0, IOMUX_BASE
        li      t1, IOMUX_FUN_IE
        li      t2, IOMUX_RX_OFF
        add     t2, t0, t2
        sw      t1, 0(t2)

        ret

# ----------------------------------------------------------------------------
#  uart_tx_byte  -  a0 = byte a enviar.  Bloquea hasta que haya hueco en TX FIFO.
#  Clobbers: t0, t1, t2
# ----------------------------------------------------------------------------
uart_tx_byte:
        li      t0, UART1_BASE
# esperar a que TXFIFO_CNT < 128 (hay espacio). FIFO de 128 bytes.
1:      lw      t1, UART_STATUS(t0)
        srli    t1, t1, TXFIFO_CNT_SHIFT
        andi    t1, t1, TXFIFO_CNT_MASK
        li      t2, 128
        bge     t1, t2, 1b              # FIFO llena -> seguir esperando
# escribir byte
        andi    a0, a0, 0xFF
        sw      a0, UART_FIFO(t0)
        ret

# ----------------------------------------------------------------------------
#  uart_rx_byte  -  bloquea hasta tener >=1 byte. Devuelve:
#     a0 = byte leido (0..255)
#     a1 = status de error: bit0 framing, bit1 overflow (0 = sin error)
#  Clobbers: t0, t1, t2
# ----------------------------------------------------------------------------
uart_rx_byte:
        li      t0, UART1_BASE
        li      a1, 0                   # status limpio

# ---- esperar a que RXFIFO_CNT > 0 ----
1:      lw      t1, UART_STATUS(t0)
        andi    t1, t1, RXFIFO_CNT_MASK
        beqz    t1, 1b

# ---- comprobar flags de error ANTES de leer el dato ----
        lw      t1, UART_INT_RAW(t0)
# framing
        li      t2, INT_FRM_ERR
        and     t2, t1, t2
        beqz    t2, 2f
        ori     a1, a1, 0x1             # marca framing en a1
2:                                      # overflow
        li      t2, INT_RXFIFO_OVF
        and     t2, t1, t2
        beqz    t2, 3f
        ori     a1, a1, 0x2             # marca overflow en a1
3:
# limpiar los flags que hayamos visto (escribir 1 en INT_CLR)
        beqz    a1, 4f
        li      t2, (INT_FRM_ERR | INT_RXFIFO_OVF)
        sw      t2, UART_INT_CLR(t0)
4:
# ---- leer el byte del FIFO ----
        lw      a0, UART_FIFO(t0)
        andi    a0, a0, 0xFF
        ret

# ----------------------------------------------------------------------------
#  uart_rx_ready  -  no bloquea. a0 = nº de bytes disponibles en RX FIFO.
#  Clobbers: t0
# ----------------------------------------------------------------------------
uart_rx_ready:
        li      t0, UART1_BASE
        lw      a0, UART_STATUS(t0)
        andi    a0, a0, RXFIFO_CNT_MASK
        ret