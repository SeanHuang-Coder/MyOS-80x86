section .data
    str: db "asm_print says hello asm!", 0xa, 0 ; 0xa 是换行符，0 是字符串结束符
    str_len equ $-str

section .text
extern c_print
global _start
[bits 32]
_start:
    ; 调用C中的函数c_print
    push str
    call c_print        ; 调用C函数c_print
    add esp, 4          ; 清理栈
    
    mov eax, 1          ; 第1号子功能是退出程序
    int 0x80            ; 退出程序

global asm_print
asm_print:
    push ebp
    mov ebp, esp
    mov ebx, 1              ; fd = 1, stdout
    mov ecx, [ebp+8]        ; len
    mov edx, [ebp+12]       ; str
    mov eax, 4              ; sys_write
    int 0x80                ; 调用系统调用
    pop ebp
    ret