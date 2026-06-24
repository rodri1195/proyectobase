# =====================================================================
#  MES (Mini Entertainment System) - punto de entrada

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
        call    oled_init
        call    uart_init
        call    menu_main
hang:
        j       hang