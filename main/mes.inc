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

