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

