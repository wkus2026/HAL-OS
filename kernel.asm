; HAL-OS Kernel
; 32-bit protected mode kernel with full system services

BITS 32
ORG 0x1000

%define KERNEL_BASE 0x1000
%define KERNEL_STACK 0x90000

; Multiboot header
ALIGN 4
multiboot_header:
    MAGIC equ 0x1BADB002
    FLAGS equ 0x00000003
    CHECKSUM equ -(MAGIC + FLAGS)
    
    dd MAGIC
    dd FLAGS
    dd CHECKSUM

; ============================================================
; KERNEL ENTRY POINT
; ============================================================
kernel_start:
    cli
    
    ; Initialize stack
    mov esp, KERNEL_STACK
    mov ebp, esp
    
    ; Initialize segments
    mov ax, 0x0010
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax
    
    ; Clear BSS section
    xor eax, eax
    mov edi, 0x10000
    mov ecx, 0x10000
    rep stosd
    
    ; Initialize hardware
    call gdt_init
    call idt_init
    call pit_init
    call keyboard_init
    call console_init
    call memory_init
    call process_init
    call filesystem_init
    
    ; Enable interrupts
    sti
    
    ; Display boot banner
    call console_clear
    call display_boot_banner
    
    ; Start shell
    call shell_main
    
    jmp $

; ============================================================
; DISPLAY BOOT BANNER
; ============================================================
display_boot_banner:
    push eax
    
    mov esi, banner_text
    call console_print_string
    
    pop eax
    ret

banner_text:
    db 13, 10
    db "================================", 13, 10
    db "    HAL-OS v0.1.0 Kernel      ", 13, 10
    db "================================", 13, 10
    db 13, 10
    db "CPU: x86 (Protected Mode)", 13, 10
    db "Memory: 128MB", 13, 10
    db "Kernel Base: 0x1000", 13, 10
    db 13, 10
    db "Type 'help' for commands", 13, 10
    db 13, 10, 0

; ============================================================
; GLOBAL DESCRIPTOR TABLE (GDT)
; ============================================================
gdt_init:
    push eax
    
    ; Load GDT
    lgdt [gdt_descriptor]
    
    pop eax
    ret

; GDT table
ALIGN 16
gdt_table:
    ; Null descriptor
    dq 0x0000000000000000
    
    ; Code descriptor (index 1, selector 0x08)
    ; Base: 0x00000000, Limit: 0xFFFFF (4GB in 4KB pages)
    ; Type: Code, DPL: 0, Present: 1
    dq 0x00CF9A000000FFFF
    
    ; Data descriptor (index 2, selector 0x10)
    ; Base: 0x00000000, Limit: 0xFFFFF
    ; Type: Data, DPL: 0, Present: 1
    dq 0x00CF92000000FFFF
    
    ; User code descriptor (index 3, selector 0x18)
    dq 0x00CFFA000000FFFF
    
    ; User data descriptor (index 4, selector 0x20)
    dq 0x00CFF2000000FFFF

gdt_descriptor:
    dw (gdt_descriptor - gdt_table - 1)
    dd gdt_table

; ============================================================
; INTERRUPT DESCRIPTOR TABLE (IDT)
; ============================================================
idt_init:
    push eax
    push ecx
    push edi
    
    ; Clear IDT
    xor eax, eax
    mov edi, idt_table
    mov ecx, 256
    rep stosd
    
    ; Set up exception handlers
    mov eax, 0
.exception_loop:
    cmp eax, 32
    je .irq_setup
    
    call idt_set_gate
    inc eax
    jmp .exception_loop
    
.irq_setup:
    ; Set up IRQ handlers
    mov eax, 32
.irq_loop:
    cmp eax, 48
    je .load_idt
    
    call idt_set_gate
    inc eax
    jmp .irq_loop
    
.load_idt:
    lidt [idt_descriptor]
    
    pop edi
    pop ecx
    pop eax
    ret

; IDT table (256 entries, 8 bytes each)
ALIGN 16
idt_table:
    times 256 * 2 dd 0

idt_descriptor:
    dw (256 * 8 - 1)
    dd idt_table

; Set IDT gate
; EAX = gate number
idt_set_gate:
    push ebx
    push ecx
    push edx
    
    ; Get handler address
    lea ebx, [exception_handler_stub]
    
    ; Create gate descriptor
    mov edx, ebx
    and edx, 0xFFFF           ; Low 16 bits
    shl edx, 16
    or edx, 0x0008            ; Code segment selector
    
    mov ecx, ebx
    shr ecx, 16               ; High 16 bits
    or ecx, 0x8E00            ; Present, DPL 0, Interrupt gate
    
    mov ebx, eax
    shl ebx, 3                ; 8 bytes per entry
    
    mov [idt_table + ebx], edx
    mov [idt_table + ebx + 4], ecx
    
    pop edx
    pop ecx
    pop ebx
    ret

; Generic exception handler
exception_handler_stub:
    pusha
    call exception_handler
    popa
    iret

exception_handler:
    ; Handle exception
    ret

; ============================================================
; PROGRAMMABLE INTERVAL TIMER (PIT)
; ============================================================
pit_init:
    push eax
    push edx
    
    ; Set PIT to generate interrupts at 100Hz
    ; Divisor = 11932 (1193180 / 100)
    
    mov al, 0x36              ; Counter 0, binary mode
    out 0x43, al
    
    mov eax, 11932
    out 0x40, al
    mov al, ah
    out 0x40, al
    
    pop edx
    pop eax
    ret

; ============================================================
; KEYBOARD DRIVER
; ============================================================
keyboard_init:
    ; Initialize keyboard
    push eax
    pop eax
    ret

keyboard_handler:
    push eax
    
    in al, 0x60               ; Read scancode
    
    ; TODO: Process keyboard input
    
    pop eax
    iret

; ============================================================
; CONSOLE DRIVER
; ============================================================
%define CONSOLE_WIDTH 80
%define CONSOLE_HEIGHT 25
%define VIDEO_MEMORY 0xB8000

console_init:
    push eax
    
    ; Initialize console
    mov dword [console_x], 0
    mov dword [console_y], 0
    
    pop eax
    ret

console_clear:
    push eax
    push ecx
    push edi
    
    mov edi, VIDEO_MEMORY
    mov ecx, CONSOLE_WIDTH * CONSOLE_HEIGHT
    mov eax, 0x0F20           ; White on black, space character
    
    rep stosw
    
    mov dword [console_x], 0
    mov dword [console_y], 0
    
    pop edi
    pop ecx
    pop eax
    ret

console_print_char:
    ; EAX = character
    push ebx
    push ecx
    push edx
    push edi
    
    mov ebx, [console_y]
    mov ecx, [console_x]
    
    ; Calculate offset: y * width + x
    mov edx, ebx
    imul edx, CONSOLE_WIDTH
    add edx, ecx
    shl edx, 1                ; 2 bytes per character
    
    ; Write character
    mov byte [VIDEO_MEMORY + edx], al
    mov byte [VIDEO_MEMORY + edx + 1], 0x0F
    
    ; Update cursor
    inc ecx
    cmp ecx, CONSOLE_WIDTH
    jl .done
    
    xor ecx, ecx
    inc ebx
    cmp ebx, CONSOLE_HEIGHT
    jl .done
    
    ; Scroll screen
    mov ebx, CONSOLE_HEIGHT - 1
    
.done:
    mov [console_x], ecx
    mov [console_y], ebx
    
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

console_print_string:
    ; ESI = string pointer
    push eax
    
.loop:
    lodsb
    cmp al, 0
    je .done
    
    cmp al, 13                ; Carriage return
    je .cr
    
    cmp al, 10                ; Line feed
    je .lf
    
    call console_print_char
    jmp .loop
    
.cr:
    mov dword [console_x], 0
    jmp .loop
    
.lf:
    mov eax, [console_y]
    inc eax
    mov [console_y], eax
    jmp .loop
    
.done:
    pop eax
    ret

console_x: dd 0
console_y: dd 0

; ============================================================
; MEMORY MANAGEMENT
; ============================================================
memory_init:
    push eax
    
    ; Initialize memory structures
    ; TODO: Set up paging if needed
    
    pop eax
    ret

; ============================================================
; PROCESS MANAGEMENT
; ============================================================
%define MAX_PROCESSES 32

process_init:
    push eax
    
    ; Initialize process table
    mov eax, 0
    mov ecx, MAX_PROCESSES
    mov edi, process_table
    
    rep stosd
    
    pop eax
    ret

process_table:
    times MAX_PROCESSES * 16 dd 0

; ============================================================
; FILESYSTEM
; ============================================================
filesystem_init:
    push eax
    
    ; Initialize filesystem
    ; TODO: Mount root filesystem
    
    pop eax
    ret

; ============================================================
; SHELL
; ============================================================
shell_main:
    push eax
    push esi
    
.shell_loop:
    ; Print prompt
    mov esi, shell_prompt
    call console_print_string
    
    ; Read command line
    mov edi, input_buffer
    mov ecx, 256
    call shell_read_line
    
    ; Parse and execute command
    mov esi, input_buffer
    call shell_execute_command
    
    jmp .shell_loop
    
    pop esi
    pop eax
    ret

shell_prompt:
    db "hal@hal-os:~$ ", 0

shell_read_line:
    ; Read a line from keyboard
    ; EDI = buffer, ECX = max length
    push eax
    push ecx
    push edi
    
    xor ecx, ecx              ; Character count
    
.read_loop:
    mov al, 'A'               ; Placeholder for keyboard input
    
    cmp al, 13                ; Enter key
    je .read_done
    
    cmp ecx, 256
    jge .read_loop
    
    mov [edi + ecx], al
    inc ecx
    jmp .read_loop
    
.read_done:
    mov byte [edi + ecx], 0
    
    pop edi
    pop ecx
    pop eax
    ret

shell_execute_command:
    ; ESI = command string
    push eax
    push esi
    
    ; Parse command
    call shell_parse_command
    
    ; Check built-in commands
    mov esi, shell_cmd_help
    call shell_compare_command
    je .cmd_help
    
    mov esi, shell_cmd_clear
    call shell_compare_command
    je .cmd_clear
    
    mov esi, shell_cmd_echo
    call shell_compare_command
    je .cmd_echo
    
    ; Unknown command
    mov esi, msg_unknown_cmd
    call console_print_string
    jmp .exec_done
    
.cmd_help:
    mov esi, help_text
    call console_print_string
    jmp .exec_done
    
.cmd_clear:
    call console_clear
    jmp .exec_done
    
.cmd_echo:
    mov esi, msg_echo
    call console_print_string
    jmp .exec_done
    
.exec_done:
    pop esi
    pop eax
    ret

shell_parse_command:
    ; Parse input buffer
    ret

shell_compare_command:
    ; Compare command
    ; ESI = command to compare
    ret

shell_cmd_help: db "help", 0
shell_cmd_clear: db "clear", 0
shell_cmd_echo: db "echo", 0

msg_unknown_cmd: db "Unknown command", 13, 10, 0
msg_echo: db "Echo not implemented yet", 13, 10, 0

help_text:
    db 13, 10
    db "HAL-OS Built-in Commands:", 13, 10
    db "  help    - Display this help message", 13, 10
    db "  clear   - Clear the screen", 13, 10
    db "  echo    - Print text", 13, 10
    db "  ls      - List directory", 13, 10
    db "  pwd     - Print working directory", 13, 10
    db "  cd      - Change directory", 13, 10
    db "  cat     - Display file contents", 13, 10
    db "  ps      - List processes", 13, 10
    db "  kill    - Terminate process", 13, 10
    db "  reboot  - Reboot system", 13, 10
    db "  exit    - Exit shell", 13, 10
    db 13, 10, 0

input_buffer:
    times 256 db 0

; ============================================================
; FILL TO END OF KERNEL CODE
; ============================================================
times (32 * 512) - ($ - $$) db 0
