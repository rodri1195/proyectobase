# =====================================================================
#  MES (Mini Entertainment System) - punto de entrada
#  ESP32-C3 + SSD1306 128x64 + 5 pulsadores
#
#  Flujo:
#    1) oled_init  -> configura pines del OLED, resetea e inicializa
#                     el SSD1306 (queda encendido, sin dibujar nada)
#    2) menu_main  -> muestra el menu (PRUEBA / ONLINE) y no retorna:
#                     al confirmar salta al modo elegido.
#
#  Rutinas externas (definidas en otros archivos):
#    oled_init  -> oled_min.s
#    menu_main  -> menu.s
# =====================================================================

.text
.global app_main

app_main:
        call    oled_init               # 1) display listo
        call    menu_main               # 2) arranca el menu (no retorna)

# menu_main no retorna nunca; si por algun motivo lo hiciera,
# caemos en un lazo seguro para no ejecutar memoria basura.
hang:
        j       hang
