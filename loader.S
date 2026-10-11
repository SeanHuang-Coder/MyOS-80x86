;=====================loader用于实模式到保护模式的切换=====================
;本章节目前的目标是，使用loader在屏幕上打印字符串"hello hsl's loader."


; 包含配置文件，使用LOADER_BASE_ADDR宏定义
%include "boot.inc"
section loader vstart=LOADER_BASE_ADDR
LOADER_STACK_TOP equ LOADER_BASE_ADDR


; 构建gdt及其内部的段描述符
GDT_BASE:                   ; 0号段描述符，空段，不使用
    dd 0x00000000
    dd 0x00000000


CODE_DESC:                  ; 1号段描述符，代码段
    dd 0x0000FFFF
    dd DESC_CODE_HIGH4

; 
DATA_STACK_DESC:            ; 2号段描述符，数据段与栈段的段描述符
    dd 0x0000FFFF
    dd DESC_DATA_HIGH4

; 显存的段描述符我们没有采用平坦模式，应为显存对应的内存范围是0xC0000~0xAFFFF
; 我们只是用这个范围中的黑白现实适配器对应的物理内存范围 0xB8000~0xBFFFF 
; 所以整个内存范围包含( 0xBFFFF - 0xB8000 ) / 4K = 7，这里应该是包含8个4k，但是段界限是
; 从0开始的，所以( 0xBFFFF - 0xB8000 ) / 4K算出结果刚好符合
VIDEO_DESC:
    dd 0x80000007
    dd DESC_VIDEO_HIGH4


times 60 dq 0           ; 预留60个段描述符的空间

; 计算GDT表的大小
GDT_SIZE equ $ - GDT_BASE
GDT_LIMIT equ GDT_SIZE - 1

; total_mem_bytes用于保存内存容量，以byte为单位
; 当前位置的偏移是0x200=512字节(64个段描述符占64*8=512字节)
; 所以total_mem_bytes的内存位置是0x900+0x200=0xB00
total_mem_bytes dd 0            ; 4byte



; 定义gdt的指针，用于后续载入gdtr
; GDT一共6B，48位
gdt_ptr dw GDT_LIMIT
        dd GDT_BASE

; 凑256byte对齐，total_mem_bytes4+gdt_ptr6+ards_buf244+ards_nr2
ards_buf times 244 db 0         ; 244byte，用于存储段描述符的物理地址
ards_nr dw 0                    ; 记录ARDS结构体的数量，2byte


loader_start:
; 1. 首先使用0xE820中断获取内存信息
; ======================
; 输入参数：
;   EAX = 0x0000E820
;   EBX ARDS = 0 表示后续值位置，第一次调用时赋0
;   ES:DI = 0:ards_buf
;   ECX = 20
;   EDX = 0x534D4150（"SMAP"的ASCII码），用于ES:DI中信息的回读校验
; 输出参数：
;   EAX 签名验证：0x534D4150（"SMAP"的ASCII码）
;   ES:DI ARDS缓冲区地址：同输入值，此时已填充ARDS信息
;   ECX 实际写入字节数：BIOS实际写入ARDS结构的字节数（≥20）
;   EBX 后续值：下一个ARDS的位置，若为0表示已经是最后一个结构
; ======================
    xor ebx, ebx
    mov di, ards_buf
    mov edx, 0x534D4150
.e820_get_mem_loop:
    mov eax, 0x0000E820
    mov ecx, 20
    int 0x15
    jc .e820_failed_try_e801    ; 如果CF为1，说明调用失败，尝试使用0xE801中断

    add di, 20                  ; 调整ARDS保存在内存的位置
    inc word [ards_nr]          ; 记录ARDS结构体的数量
    cmp ebx, 0                  ; 如果ebx为0，说明没有后续值了
    jnz .e820_get_mem_loop      ; 如果不是0，说明还有后续值，继续调用

; 采用冒泡排序，在所有的ards结构中，找出基地址最大的那个，BaseAddr + Length = mem_size(最大内存地址)
    mov cx, [ards_nr]
    mov ebx, ards_buf
    xor edx, edx                ; 用于存储最大内存地址

.bubble_sort_loop:
    mov eax, [ebx]              ; 获取ards结构的基地址
    add eax, [ebx+8]            ; 基地址 + 长度 = 当前内存段的内存地址上限
    add ebx, 20                 ; 调整到下一个ards结构
    cmp edx, eax
    jge .next_ards              ; 如果edx >= eax，说明当前结构的基地址 <= 最大内存地址，跳过

    mov edx, eax                ; 更新最大内存地址

 .next_ards:   
    loop .bubble_sort_loop
    jmp .get_mem_size_success   ; 所有ards结构都处理完了，跳转到成功处理

; 2. 如果1失败，使用0xE801获取内存
; ======================
; 输入参数：
;   AX = 0xE801
; 输出参数：
;   CF = 0 表示成功
;   AX 以 1KB 为单位，显示 15MB 以下的内存容量
;   BX 以 64KB 为单位，内存空间 16MB～4GB 中连续的单位数量
; ======================
.e820_failed_try_e801:
    mov ax, 0xE801
    int 0x15
    jc .e801_failed_try_88      ; 如果CF为1，说明调用失败，尝试使用0x88中断

    ; 1.计算低15MB的内存
    mov cx, 1024
    mul cx                      ; 高16位放在dx，低16位放在ax
    shl edx, 16                 ; 将dx左移16位，与ax合并，得到低15MB的内存容量
    and eax, 0x0000FFFF         ; 只保留低16位，得到低15MB的内存容量
    or edx, eax                 ; 合并高16位和低16位，得到低15MB的内存容量
    add edx, 0x100000           ; 加上低端1MB的扫描不到的内存
    mov esi, edx                ; 备份

    ; 2.计算高16MB之后的内存
    xor eax, eax
    mov ax, bx
    mov ecx, 64*1024
    mul ecx                      ; 高32位放在edx，低32位放在eax
    add eax, esi                 ; 我们规划的内存在32位之内，所以只需要低32位
    mov edx, eax
    jmp .get_mem_size_success


; 3. 如果2失败，使用0x88获取内存
; ======================
; 输入参数：
;   AH = 0x88
; 输出参数：
;   CF = 0 表示成功
;   AX 以KB为单位数量，不包括低端1MB的内存，最大返回值为0xfc00（63MB）
; ======================
.e801_failed_try_88:
    mov ah, 0x88
    int 0x15
    jc .error_hlt      ; 如果CF为1，说明获取失败，已经无其他方式获取内存，跳转到错误处理函数
    and eax, 0x0000FFFF         ; 只保留低16位，得到内存容量
    mov ecx, 1024
    mul ecx                      ; 高32位放在edx，低32位放在eax
    add eax, 0x100000           ; 加上低端1MB的扫描不到的内存
    mov edx, eax
.get_mem_size_success:
    mov [total_mem_bytes], edx
    jmp $

.error_hlt:
;;;;;;;;;;;;;;;;;;打印字符串;;;;;;;;;;;;;;;;;;
; 直接使用显存输出字符串
; 输出闪烁背景为绿色，前景为红色的字符串

    mov ax, 0xB800          ; 显存地址段地址
    mov gs, ax
; 使用循环输出字符串
    mov di, 0x0000
    mov bx, 0           ; 字符串索引
    mov ch, 10101100b
ShowString:
    mov cl, message[bx]
    mov word gs:[di], cx

    add di, 2
    inc bx
    cmp cl, 0x00
    je ShowStringEnd
    jmp ShowString
ShowStringEnd:
    jmp $

    message db "error: get memory failed."