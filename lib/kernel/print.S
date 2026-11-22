TI_GDT equ 0
RPL0 equ 0
SELECTOR_VIDEO equ (0x0003<<3 + TI_GDT + RPL0)

[bits 32]
section .text
;----------------------------- put_char -----------------------------
;func desc：将栈中的一个字符显示在光标处
;--------------------------------------------------------------------
global put_char
put_char:
; 1.备份寄存器现场
    pushad      ; 保存8个32位寄存器 保存顺序为eax->ecx->edx->ebx->esp->ebp->esi->edi
    mov ax, SELECTOR_VIDEO
    mov gs, ax
; 2.获取光标所在位置
    mov dx, 0x3D4   ; 地址寄存器端口
    mov al, 0x0E    ; 指定操作的寄存器
    out dx, al
    mov dx, 0x3D5   ; 数据寄存器端口
    in al, dx       ; 从指定的寄存器中取出数据，光标位置高8位
    mov ah, al


    mov dx, 0x3D4   ; 地址寄存器端口
    mov al, 0x0F    ; 指定操作的寄存器
    out dx, al
    mov dx, 0x3D5   ; 数据寄存器端口
    in al, dx       ; 从指定的寄存器中取出数据，光标位置低8位

    mov bx, ax      ; 将光标保存在bx
;2. 获取要显示的字符
    mov ecx, [esp + 36] ; 从栈中取出要显示的字符，8*4 + eip = 36
                        ; 回车(CR)是0xd，换行(LF)是0xa，退格(backspace)是0x8
;3. 判断字符是否是控制字符
    cmp cl, 0xd
    jz .is_carriage_return      ; 回车键处理
    cmp cl, 0xa
    jz .is_line_feed            ; 换行键处理
    cmp cl, 0x8
    jz .is_backspace            ; 退格键处理
    
    jmp .put_other               ; 对于非CR、LF、BS的字符，这里默认为可见字符直接显示


.is_backspace:                  ; 退格键处理
    ; 关于退格键的说明
    ; backspace需要处理两件事
    ;   1. 将光标前移一个字符
    ;   2. 将光标前移一个字符的字符显示为空格
    ;--------------------------------------------------------------------
    dec bx
    shl bx, 1                   ; 将光标位置乘2，因为1个字符占2B
    mov byte gs:bx, 0x20        ; 将光标前移一个字符的字符显示为空格
    inc bx
    mov byte gs:bx, 0x07        ; 将光标前移一个字符的字符显示为不闪烁，背景色黑色，前景色白色
    shr bx, 1
    jmp .set_cursor


.put_other:
    shl bx, 1
    mov gs:bx, cl               ; 将字符显示在光标处
    inc bx
    mov gs:bx, 0x07             ; 将光标前移一个字符的字符显示为不闪烁，背景色黑色，前景色白色
    shr bx, 1
    inc bx                      ; 将光标位置后移一个字符
    cmp bx, 2000                ; 检查是否超出屏幕范围
    jl .set_cursor              ; 小于25*80，说明没有超出屏幕范围，直接设置光标位置
                                ; 否则就将1~24行整体向上移动一行，实现换行效果

.is_line_feed:                  ; 换行符
.is_carriage_return:            ; 回车符
    xor dx, dx
    mov ax, bx
    mov si, 80
    div si

    sub bx, dx                  ; dx存放的是出发的余数，将bx减去余数刚好就是80的整数倍

.is_carriage_return_end:        ; 回车符处理结束
    add bx, 80
    cmp bx, 2000
.is_line_feed_end:              ; 换行符处理结束
    jl .set_cursor
;5. 判断是否需要滚屏
; 将1~24行整体向上移动一行，实现换行效果
; 然后将24行的字符全部填空格
.roll_screen:
    cld
    mov ecx, 960                ; 一个屏幕有25*80个字符，每个字符占2B，esi一次可以搬4B
                                ; 整体就是2000-80=1920个字符 1920 * 2=3840B
                                ; 3840B / 4B=960次
    mov esi, 0xC00B80A0        ; 第1行行首
    mov edi, 0xC00B8000        ; 第0行行首
    rep movsd
; 将最后一行填成空格
    mov ecx, 80                 ; 80个字符
    mov ebx, 3840              ; 从第3840B开始填空格

.cls:
    mov word gs:ebx, 0x0720     ; 不闪烁，背景色黑色，前景色白色，空格
    add ebx, 2
    loop .cls

    mov ebx, 1920               ; 将光标重新恢复到第24行的第1列


;6. 更新光标位置，使其指向下一个打印字符的位置
.set_cursor:
; 将光标设为bx值
    ; 设置光标的高8位
    mov dx, 0x3D4   ; 地址寄存器端口
    mov al, 0x0E    ; 指定操作的寄存器，光标的高8位
    out dx, al
    mov dx, 0x3D5   ; 数据寄存器端口
    mov al, bh
    out dx, al
    ; 设置光标的低8位
    mov dx, 0x3D4   ; 地址寄存器端口
    mov al, 0x0F    ; 指定操作的寄存器，光标的低8位
    out dx, al
    mov dx, 0x3D5   ; 数据寄存器端口
    mov al, bl
    out dx, al
;7. 恢复现场，返回
.put_char_done:
    popad
    ret

[bits 32]
section .text
;---------------------------------------------
;func des：put_str通过put——char打印字符串
;input：栈中参数未打印的字符串
;output：无
;---------------------------------------------
global put_str
put_str:
; 本函数只是用ebx与ecx寄存器，其他寄存器没有被使用
    push ebx
    push ecx
    xor ecx, ecx            ; 后续使用ecx存储参数
    mov ebx, [esp + 12]     ; 从栈中获取字符串的地址， 栈上的内容：ecx、ebx、eip、字符串地址


; 从字符串中依次取出字符，然后调用put_char函数打印，直到遇到0结束
.loop_call_put_char:
    mov cl, [ebx]
    cmp cl, 0
    jz .str_done
    push ecx                ; 传递需要打印的字符
    call put_char
    inc ebx
    jmp .loop_call_put_char
.str_done:
    pop ecx
    pop ebx
    ret