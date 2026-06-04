.data
str_hola:
        .string "Hola Mundo RISC-V!\n"

str_chau:
        .string "Chau Mundo RISC-V!\n"
.text
.global app_main

.text
.global app_main
 
app_main:
        call    oled_init               # 1) display listo
        call    menu_main               # 2) arranca el menu (no retorna)
 
# menu_main no retorna nunca; si por algun motivo lo hiciera,
# caemos en un lazo seguro para no ejecutar memoria basura.
hang:
        j       hang
