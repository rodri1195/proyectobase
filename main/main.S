# =====================================================================
#  MES (Mini Entertainment System) - punto de entrada
#  ESP32-C3 + SSD1306 128x64 + 5 pulsadores
#
#  Flujo:
#    1) oled_init  -> configura pines del OLED, resetea e inicializa
#                     el SSD1306 (queda encendido, sin dibujar nada)
#    2) uart_init  -> inicializa UART1 (115200 8N1, TX=GPIO20/RX=GPIO21).
#                     Se hace ACA, una sola vez, para que el menu pueda
#                     escuchar 'M' por UART desde el arranque (un MES puede
#                     arrastrar a este al modo ONLINE como jugador 2).
#    3) menu_main  -> muestra el menu (PRUEBA / ONLINE) y no retorna:
#                     al confirmar salta al modo elegido.
#
#  Rutinas externas (definidas en otros archivos):
#    oled_init  -> oled_min.s
#    uart_init  -> uart.s
#    menu_main  -> menu.s
# =====================================================================
.text
.global app_main
app_main:
#call    gpio20_blink_test       # 0) test de GPIO20 (no retorna)
#call    oled_init               # 1) display listo      
#call    uart_init               # 2) UART1 lista (menu escucha 'M')
#call    menu_main
        call    test_main               # 3) test de validacion de uart (no retorna)
#call    menu_main               # 3) arranca el menu (no retorna)
# menu_main no retorna nunca; si por algun motivo lo hiciera,
# caemos en un lazo seguro para no ejecutar memoria basura.
hang:
        j       hang
