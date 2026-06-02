.data
str_hola:
        .string "Hola Mundo RISC-V!\n"

str_chau:
        .string "Chau Mundo RISC-V!\n"
.text
.global app_main

app_main:
        la      a0, str_hola
        call    jtag_send

        call    oled_test
        
        la      a0, str_chau
        call    jtag_send

        call    led_setup
        call    boton_setup

app_loop:
        la      a0, str_hola
        call    jtag_send

        call    boton_read
        call    led_set

        j       app_loop
