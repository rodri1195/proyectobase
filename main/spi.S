# spi.S - Driver SPI para ESP32-C3, modo master
# Periférico SPI2 (GPSPI2), base 0x60024000
# SCLK = GPIO6, MOSI = GPIO7
# CS, DC, RES se manejan como GPIO normales
#
# Funciones publicas:
#   spi_setup        - inicializa SPI2
#   spi_write_byte   - envia 1 byte (a0 = byte)
#   spi_write_buf    - envia buffer (a0=ptr, a1=len)

# SPI2 registers (base 0x60024000)
        .equ    SPI_CMD,       0x60024000 # bit17=USR para iniciar
        .equ    SPI_CTRL,      0x60024008
        .equ    SPI_CLOCK,     0x60024010
        .equ    SPI_USER,      0x60024018
        .equ    SPI_USER1,     0x6002401C
        .equ    SPI_MS_DLEN,   0x60024024
        .equ    SPI_MISC,      0x60024034
        .equ    SPI_W0,        0x60024054 # data buffer

# SPI_CMD bits
        .equ    SPI_USR_START, 0x00020000 # bit17

# SPI_USER bits
        .equ    SPI_USR_MOSI,  0x10000000 # bit28 - habilitar fase MOSI

# SPI_CLOCK ~4MHz conservador (40MHz/10)
# N=9, H=4, L=9 -> 0x00009109
        .equ    SPI_CLK_4MHZ,  0x00009109

# SPI_MISC - deshabilitar todos los CS hardware (los manejamos manual)
        .equ    SPI_CS_DIS_ALL, 0x00000E00 # bits 9,10,11

# SYSTEM clock/reset
        .equ    SYS_CLK_EN0,   0x600C0010
        .equ    SYS_RST_EN0,   0x600C0014
        .equ    SPI2_CLK_BIT,  0x00000040 # bit6

# IO_MUX
        .equ    IOMUX_GPIO6,   0x6000901C # SCLK
        .equ    IOMUX_GPIO7,   0x60009020 # MOSI
# FUN_DRV=3(max drive), MCU_SEL=0(GPIO matrix), IE=0, WPU=0
        .equ    IOMUX_OUT,     0x00000300 # FUN_DRV bits[7:6]=11 -> drive strength max

# GPIO matrix OUT_SEL
        .equ    GPIO_OUT6_CFG, 0x6000456C # GPIO6 out -> SCLK (signal 20)
        .equ    GPIO_OUT7_CFG, 0x60004570 # GPIO7 out -> MOSI (signal 21)
        .equ    SIG_SPICLK,    20
        .equ    SIG_SPIMOSI,   21

# GPIO output control
        .equ    GPIO_ENABLE_SET, 0x60004020 # W1TS enable output
        .equ    GPIO6_BIT,     0x40     # bit6
        .equ    GPIO7_BIT,     0x80     # bit7

.text
.global spi_setup
.global spi_write_byte
.global spi_write_buf

# ─────────────────────────────────────────────────────
# spi_setup
# ─────────────────────────────────────────────────────
spi_setup:
        addi    sp, sp, -4
        sw      ra, 0(sp)

# 1. Habilitar clock SPI2
        li      t0, SYS_CLK_EN0
        lw      t1, 0(t0)
        ori     t1, t1, SPI2_CLK_BIT
        sw      t1, 0(t0)

# 2. Reset SPI2 y quitar reset
        li      t0, SYS_RST_EN0
        lw      t1, 0(t0)
        ori     t1, t1, SPI2_CLK_BIT
        sw      t1, 0(t0)
        lw      t1, 0(t0)
        li      t2, SPI2_CLK_BIT
        not     t2, t2
        and     t1, t1, t2
        sw      t1, 0(t0)

# 3. IO_MUX GPIO6 (SCLK) - output, max drive
        li      t0, IOMUX_GPIO6
        li      t1, IOMUX_OUT
        sw      t1, 0(t0)

# 4. IO_MUX GPIO7 (MOSI) - output, max drive
        li      t0, IOMUX_GPIO7
        li      t1, IOMUX_OUT
        sw      t1, 0(t0)

# 5. Habilitar GPIO6,7 como output
        li      t0, GPIO_ENABLE_SET
        li      t1, (GPIO6_BIT | GPIO7_BIT)
        sw      t1, 0(t0)

# 6. GPIO matrix: GPIO6 → SCLK signal
        li      t0, GPIO_OUT6_CFG
        li      t1, SIG_SPICLK
        sw      t1, 0(t0)

# 7. GPIO matrix: GPIO7 → MOSI signal
        li      t0, GPIO_OUT7_CFG
        li      t1, SIG_SPIMOSI
        sw      t1, 0(t0)

# 8. SPI2 modo master, half-duplex, solo MOSI
        li      t0, SPI_USER
        li      t1, SPI_USR_MOSI
        sw      t1, 0(t0)

# 9. Clock ~4MHz (conservador para SSD1306)
        li      t0, SPI_CLOCK
        li      t1, SPI_CLK_4MHZ
        sw      t1, 0(t0)

# 10. Deshabilitar CS hardware (usamos GPIO manual)
        li      t0, SPI_MISC
        li      t1, SPI_CS_DIS_ALL
        sw      t1, 0(t0)

# 11. Ctrl: MSB first, modo 0
        li      t0, SPI_CTRL
        sw      zero, 0(t0)

        lw      ra, 0(sp)
        addi    sp, sp, 4
        ret


# ─────────────────────────────────────────────────────
# spi_write_byte  (a0 = byte a enviar)
# ─────────────────────────────────────────────────────
spi_write_byte:
        addi    sp, sp, -8
        sw      ra, 0(sp)
        sw      s0, 4(sp)

        andi    s0, a0, 0xFF

# Escribir dato en buffer W0 (MSB first: desplazar a bit31)
        slli    t1, s0, 24
        li      t0, SPI_W0
        sw      t1, 0(t0)

# Longitud = 8 bits - 1 = 7
        li      t0, SPI_MS_DLEN
        li      t1, 7
        sw      t1, 0(t0)

# Tambien USER1 para MOSI bitlen
        li      t0, SPI_USER1
        li      t1, (7 << 17)           # MOSI_BITLEN bits[23:17] = 7
        sw      t1, 0(t0)

# Iniciar transaccion
        li      t0, SPI_CMD
        li      t1, SPI_USR_START
        sw      t1, 0(t0)

# Esperar que termine (bit17 vuelve a 0)
# andi no acepta inmediatos > 11 bits, usar li + and
        li      t2, SPI_USR_START
_spibyte_wait:
        li      t0, SPI_CMD
        lw      t1, 0(t0)
        and     t1, t1, t2
        bnez    t1, _spibyte_wait

        lw      ra, 0(sp)
        lw      s0, 4(sp)
        addi    sp, sp, 8
        ret


# ─────────────────────────────────────────────────────
# spi_write_buf  (a0 = ptr, a1 = len bytes)
# ─────────────────────────────────────────────────────
spi_write_buf:
        addi    sp, sp, -12
        sw      ra, 0(sp)
        sw      s0, 4(sp)
        sw      s1, 8(sp)

        mv      s0, a0
        mv      s1, a1

_spibuf_loop:
        beqz    s1, _spibuf_done
        lbu     a0, 0(s0)
        call    spi_write_byte
        addi    s0, s0, 1
        addi    s1, s1, -1
        j       _spibuf_loop

_spibuf_done:
        lw      ra, 0(sp)
        lw      s0, 4(sp)
        lw      s1, 8(sp)
        addi    sp, sp, 12
        ret