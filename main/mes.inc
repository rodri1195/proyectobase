// =====================================================================
//  mes.inc - constantes compartidas del MES
//  Se incluye con #include "mes.inc" en los .S (preprocesador de C).
// =====================================================================

// ---- Botones: bits en GPIO_IN_REG ----
#define BTN_UP       0x001   // GPIO0
#define BTN_DOWN     0x002   // GPIO1
#define BTN_LEFT     0x004   // GPIO2
#define BTN_RIGHT    0x200   // GPIO9
#define BTN_CONFIRM  0x400   // GPIO10

// ---- Registro de entrada ----
#define GPIO_IN_REG  0x6000403C

// ---- RNG hardware del ESP32-C3 ----
#define RNG_DATA_REG 0x600260B0

// ---- Geometria del tablero ----
#define BOARD_COLS   13
#define BOARD_ROWS   7
#define CELL_PX      9       // tamano de casilla en pixeles
#define BOARD_OFF_X  5       // offset para centrar (128 - 13*9)/2
#define BOARD_OFF_Y  0

// ---- Codigos de casilla ----
#define CELL_EMPTY   0
#define CELL_WALL    1       // pared indestructible (P)
#define CELL_BOX     2       // caja destruible (C)
#define CELL_P1      3       // jugador 1 (X)
#define CELL_P2      4       // jugador 2 (O)
#define CELL_BOMB    5       // bomba (B)
#define CELL_FIRE    6       // fuego/explosion (muestra cuenta 6..1)
#define CELL_POWERUP 7       // power up (+)

// ---- Parametros de juego ----
#define BOMB_FRAMES  20      // frames hasta que la bomba explota
#define FIRE_FRAMES  6       // frames que dura el fuego (cuenta 6..1)
#define MAX_BOMBS    5       // maximo de bombas simultaneas por jugador
#define BOARD_CELLS  91      // 13*7

// ---- Temporizacion ----
// Frame objetivo: 150ms EXACTOS, requerido para sincronizar con otras MES
// en multijugador. Se usa el System Timer (SYSTIMER) cuyo reloj es 16MHz
// fijo (CNT_CLK), independiente de la frecuencia de CPU -> todas las
// consolas miden 150ms identicos.
//
// 16.000.000 ticks/s * 0,150 s = 2.400.000 ticks por frame.
#define FRAME_TICKS  2400000

// ---- Registros SYSTIMER (capitulo 10 del TRM) ----
// Base del periferico SYSTIMER (Tabla 3.3-3 del TRM, mapa de perifericos).
//   >>> CONFIRMAR la base en el TRM. Estimado: 0x60023000 <<<
#define SYSTIMER_BASE          0x60023000

// Offsets (CONFIRMADOS en la tabla de registros, cap. 10):
#define SYSTIMER_UNIT0_OP_REG       (SYSTIMER_BASE + 0x0004)
#define SYSTIMER_UNIT0_VALUE_LO_REG (SYSTIMER_BASE + 0x0044)

// Bits del registro OP (CONFIRMADOS en Register 10.2 del TRM):
//   UPDATE      = bit 30: escribir 1 para capturar el valor actual
//   VALUE_VALID = bit 29: el hardware lo pone en 1 cuando la captura termino
#define SYSTIMER_UNIT0_UPDATE_MASK      (1 << 30)
#define SYSTIMER_UNIT0_VALUE_VALID_MASK (1 << 29)

// Nota: el contador UNIT0 ya viene HABILITADO por el bootloader de ESP-IDF
// (lo usa esp_timer), asi que no hace falta configurar WORK_EN. El frame
// solo LEE el contador, nunca lo configura.

// ---- Registros UART (capitulo 26 del TRM) ----
// Usamos UART1 para el protocolo online (UART0 es la consola de debug/USB).
// Bases confirmadas (mapa de perifericos):
//   UART0 = 0x60000000 ; UART1 = 0x60010000
#define UART1_BASE       0x60010000

// Offsets (confirmados en el TRM, cap. 26):
#define UART_FIFO_REG    (UART1_BASE + 0x0000)   // dato: bits 7:0
#define UART_CLKDIV_REG  (UART1_BASE + 0x0014)   // divisor de baudrate
#define UART_STATUS_REG  (UART1_BASE + 0x001C)   // contadores de FIFO
#define UART_CONF0_REG   (UART1_BASE + 0x0020)   // config: bits de datos, paridad, stop
#define UART_CLK_CONF_REG (UART1_BASE + 0x0078)  // fuente de reloj, clock-enable, reset

// Valor de baudrate para CLKDIV: entera 694 (0x2B6) + frac 7/16 -> 115201 bps
#define UART_BAUD_115200  0x7002B6

// Valor de CONF0 para formato 8N1:
//   bit_num (bits 3:2) = 3 (8 bits) ; parity_en (bit 0) = 0 ; stop (bits 5:4) = 1
#define UART_CONF0_8N1    0x1C

// Valor de CLK_CONF: SCLK_SEL=1 (APB 80MHz, bits 19:18), SCLK_DIV_NUM=0,
//   SCLK_EN (bit 20), TX_SCLK_EN (bit 22), RX_SCLK_EN (bit 23)
#define UART_CLK_CONF_ON  0x00D40000
//   El mismo con RST_CORE (bit 21) para el pulso de reset
#define UART_CLK_CONF_RST 0x00F40000

// Campos de UART_STATUS_REG (TXFIFO_CNT shift 16, RXFIFO_CNT shift 0):
#define UART_RXFIFO_CNT_SHIFT  0
#define UART_TXFIFO_CNT_SHIFT  16
#define UART_FIFO_CNT_MASK     0xFF
#define UART_TX_FIFO_SIZE      128

// ---- System registers (clock/reset de perifericos, cap. 16) ----
#define SYSTEM_PERIP_CLK_EN0_REG  0x600C0010
#define SYSTEM_PERIP_RST_EN0_REG  0x600C0014
#define SYSTEM_UART1_BIT          (1 << 3)       // bit 3 = UART1

// ---- Ruteo de pines UART1 por la matriz GPIO ----
// Señal U1TXD/U1RXD = indice 9 en la tabla de señales del GPIO matrix.
#define U1_SIGNAL_IDX     9
// Salida TX: GPIO_FUNC20_OUT_SEL = 0x554 + 4*20
#define GPIO_FUNC20_OUT_SEL_REG  0x600045A4
// Entrada RX: GPIO_FUNC9_IN_SEL_CFG = 0x154 + 4*9 (señal 9 = U1RXD)
#define GPIO_FUNC9_IN_SEL_REG    0x60004178
// Valor para IN_SEL: pin 21 (bits 5:0) + bit de ruteo por matriz (bit 7)
#define GPIO_IN_SEL_GPIO21       (21 | (1 << 7))
// IO_MUX y enable (ya usados antes)
#define IO_MUX_GPIO20_REG        0x60009054      // 0x9004 + 4*20
#define IO_MUX_GPIO21_REG        0x60009058      // 0x9004 + 4*21
#define GPIO_ENABLE_W1TS_REG     0x60004024

// ---- Bytes del protocolo online ----
#define PROTO_M      0x4D    // 'M' inicio (controlador -> seguidor)
#define PROTO_K      0x4B    // 'K' ack
#define PROTO_F      0x46    // 'F' inicio de frame (+ tablero)
#define PROTO_R      0x52    // 'R' resultado (+ '1'/'0')
#define PROTO_W      0x57    // 'W' mover arriba
#define PROTO_S      0x53    // 'S' mover abajo
#define PROTO_A      0x41    // 'A' mover izquierda
#define PROTO_D      0x44    // 'D' mover derecha
#define PROTO_B      0x42    // 'B' poner bomba
#define PROTO_0      0x30    // '0' perdio/empate
#define PROTO_1      0x31    // '1' gano



