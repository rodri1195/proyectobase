#include "mes.inc"
# =====================================================================
#  uart.s - Capa de transporte serie para el protocolo online (UART1)
#
#  UART1 a 115200 bps, 8N1, sin flow control, ruteada a GPIO20 (TX) y
#  GPIO21 (RX) mediante la matriz GPIO.
#
#  Rutinas publicas:
#    uart_init        - configura UART1 (baudrate, formato, pines)
#    uart_send_byte   - envia un byte (a0 = byte); bloquea si el FIFO TX lleno
#    uart_recv_byte   - recibe un byte (bloquea hasta que llegue); a0 = byte
#    uart_recv_try    - recibe sin bloquear; a0 = byte o -1 si no hay nada
#
#  NOTA: uart_init configura el divisor de baudrate asumiendo que la
#  fuente de reloj de UART1 es la APB a 80MHz (lo habitual en ESP-IDF).
#  El divisor exacto se calcula como reloj/baudrate. ESTO PUEDE NECESITAR
#  AJUSTE segun la fuente de reloj real; ver comentario en uart_init.
# =====================================================================

.extern delay

.text
.global uart_init
.global uart_send_byte
.global uart_recv_byte
.global uart_recv_try

# =====================================================================
#  uart_init: inicializa UART1 a 115200 8N1 y rutea GPIO20(TX)/GPIO21(RX).
#
#  Secuencia (el orden importa):
#    1) Habilitar el clock del periferico UART1 a nivel sistema
#    2) Pulsar el reset del periferico UART1 (1 luego 0)
#    3) Configurar fuente de reloj (APB), clock-enable interno, baudrate
#    4) Configurar formato 8N1
#    5) Rutear los pines por la matriz GPIO
# =====================================================================
uart_init:
# --- 1) Clock-enable del periferico UART1 (bit 3) ---
        li      t0, SYSTEM_PERIP_CLK_EN0_REG
        lw      t1, 0(t0)
        li      t2, SYSTEM_UART1_BIT
        or      t1, t1, t2
        sw      t1, 0(t0)

# --- 2) Pulso de reset del periferico UART1 (set luego clear) ---
        li      t0, SYSTEM_PERIP_RST_EN0_REG
        lw      t1, 0(t0)
        li      t2, SYSTEM_UART1_BIT
        or      t1, t1, t2
        sw      t1, 0(t0)               # reset = 1
        lw      t1, 0(t0)
        li      t2, SYSTEM_UART1_BIT
        not     t2, t2
        and     t1, t1, t2
        sw      t1, 0(t0)               # reset = 0

# --- 3a) Pulso de reset del core UART (RST_CORE en CLK_CONF) ---
        li      t0, UART_CLK_CONF_REG
        li      t1, UART_CLK_CONF_RST   # con bit RST_CORE=1
        sw      t1, 0(t0)
        li      t1, UART_CLK_CONF_ON    # RST_CORE=0, clocks habilitados
        sw      t1, 0(t0)

# --- 3b) Baudrate ---
        li      t0, UART_CLKDIV_REG
        li      t1, UART_BAUD_115200
        sw      t1, 0(t0)

# --- 4) Formato 8N1 ---
        li      t0, UART_CONF0_REG
        li      t1, UART_CONF0_8N1
        sw      t1, 0(t0)

# --- 5) Rutear pines ---
# GPIO20 como salida, funcion GPIO
        li      t0, IO_MUX_GPIO20_REG
        li      t1, 0x1800              # MCU_SEL=1 (GPIO), FUN_DRV=2
        sw      t1, 0(t0)
# señal U1TXD (9) sale por GPIO20
        li      t0, GPIO_FUNC20_OUT_SEL_REG
        li      t1, U1_SIGNAL_IDX
        sw      t1, 0(t0)
# habilitar GPIO20 como salida
        li      t0, GPIO_ENABLE_W1TS_REG
        li      t1, (1 << 20)
        sw      t1, 0(t0)

# GPIO21 como entrada con pull-up, funcion GPIO
        li      t0, IO_MUX_GPIO21_REG
        li      t1, 0x1300              # MCU_SEL=1, FUN_IE=1, FUN_WPU=1
        sw      t1, 0(t0)
# señal U1RXD (9) lee de GPIO21 (via matriz)
        li      t0, GPIO_FUNC9_IN_SEL_REG
        li      t1, GPIO_IN_SEL_GPIO21
        sw      t1, 0(t0)

        ret

# =====================================================================
#  uart_send_byte(a0 = byte): envia un byte por UART1.
#  Espera a que haya lugar en el FIFO de TX (TXFIFO_CNT < tamano), luego
#  escribe el byte en FIFO_REG.
# =====================================================================
uart_send_byte:
        mv      t4, a0                  # guardar el byte a enviar
usb_wait:
# leer TXFIFO_CNT
        li      t0, UART_STATUS_REG
        lw      t1, 0(t0)
        srli    t1, t1, UART_TXFIFO_CNT_SHIFT
        andi    t1, t1, UART_FIFO_CNT_MASK
        li      t2, UART_TX_FIFO_SIZE
        bge     t1, t2, usb_wait        # FIFO lleno -> esperar

# escribir el byte
        li      t0, UART_FIFO_REG
        sb      t4, 0(t0)
        ret

# =====================================================================
#  uart_recv_byte: recibe un byte (BLOQUEA hasta que llegue uno).
#  Espera a que RXFIFO_CNT > 0, luego lee FIFO_REG. a0 = byte recibido.
# =====================================================================
uart_recv_byte:
urb_wait:
        li      t0, UART_STATUS_REG
        lw      t1, 0(t0)
        andi    t1, t1, UART_FIFO_CNT_MASK # RXFIFO_CNT (shift 0)
        beqz    t1, urb_wait            # nada -> esperar

        li      t0, UART_FIFO_REG
        lbu     a0, 0(t0)
        andi    a0, a0, 0xFF
        ret

# =====================================================================
#  uart_recv_try: recibe sin bloquear. Si hay un byte, a0 = byte.
#  Si no hay nada, a0 = -1.
# =====================================================================
uart_recv_try:
        li      t0, UART_STATUS_REG
        lw      t1, 0(t0)
        andi    t1, t1, UART_FIFO_CNT_MASK # RXFIFO_CNT
        bnez    t1, urt_have
        li      a0, -1
        ret
urt_have:
        li      t0, UART_FIFO_REG
        lbu     a0, 0(t0)
        andi    a0, a0, 0xFF
        ret