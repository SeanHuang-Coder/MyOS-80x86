;=====================loader用于实模式到保护模式的切换=====================
;本章节目前的目标是，使用loader在屏幕上打印字符串"hello hsl's loader."


; 包含配置文件，使用LOADER_BASE_ADDR宏定义
%include "boot.inc"
section loader vstart=LOADER_BASE_ADDR
;;;;;;;;;;;;;清屏;;;;;;;;;;;;;
; 使用0x10 BIOS中断的0x06号子功能清屏
; AH 功能号
; AL 上卷的行数，如果为0则表示清屏
; BH 上卷行属性
; (CL, CH) 窗口左上角的(X, Y)坐标
; (DL, DH) 窗口右下角的(X, Y)坐标

    mov ax, 0x600
    mov bx, 0x700
    mov cx, 0x0000
    mov dx, 0x184F
    int 0x10

    
    mov ah, 10001010b
    mov bx, 0
    mov di, 0
    jmp .ShowString



; 循环打印字符串中的字符
.ShowString:
    mov al, msgHello[bx]
    cmp al, 0x00
    je .ShowStringEnd
    mov gs:[di], ax
    add di, 2
    inc bx
    jmp .ShowString
.ShowStringEnd:
    jmp $

; 跳转到loader之后，gs的值为0
    msgHello db "hello hsl's loader.", 0x00