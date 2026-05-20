.data
str_hola:
        .string " RISCV\n"
.text
.global app_main

app_main:
        call    led_setup
        call    boton_setup
        call    ssd1306_setup
        call    ssd1306_reset
        li      a0, 0xAE
        call    ssd1306_cmd

app_loop:
        la      a0, str_hola
        call    jtag_send

        call    boton_read
        call    led_set

        j       app_loop
