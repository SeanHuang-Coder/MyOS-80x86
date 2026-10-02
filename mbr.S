; ***********************MBR程序，负责加载内核加载器，然后跳转到内核加载器
; cs:ip从BIOS跳转到MBR时的值分别为0x0000:0x7c00
%include "boot.inc"     ; 包含boot.inc文件
section mbr vstart=0x7c00
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov sp, 0x7c00
    mov ax, 0xB800          ; 显存地址段地址
    mov gs, ax



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


;;;;;;;;;;;;;获取光标位置;;;;;;;;;;;;;
; 使用0x10 BIOS中断的0x03号子功能获取光标位置
; 获取光标位置，然后在光标位置出打印字符
    mov ah, 0x03                ; 输入：3号子功能是获取光标位置
    mov bh, 0x00                ; bh存放待获取光标的页号
    int 0x10                    ; 调用中断，获取光标位置，结果ch=光标开始行，cl=光标结束行
                                ;                           dh=光标所在行号，dl=光标所在列号


;;;;;;;;;;;;;;;;;;打印字符串;;;;;;;;;;;;;;;;;;
; 直接使用显存输出字符串
; 输出闪烁背景为绿色，前景为红色的字符串

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
;====================从此处开始将loader载入内存====================
    mov eax, LOADER_START_SECTOR        ; loader在磁盘中的起始扇区
    mov ebx, LOADER_BASE_ADDR           ; loader在内存起始位置中的位置
    mov cx, 4                           ; 要加载的扇区数

    call rd_disk_m_16                   ; 将loader从磁盘加载到内存中
    jmp LOADER_BASE_ADDR                ; 跳转到loader的内存起始位置中



;====================读取硬盘的第n个扇区到内存中====================
; 输入：eax=磁盘起始扇区，ebx=内存起始位置，cx=要读取的扇区数
; 输出：无
; shr的用法： ①shr reg, imm8，②shr reg, cl

rd_disk_m_16:
    mov esi, eax        ; 保存eax的值，因为后续会修改eax的值
;1.设置读取硬盘的扇区数量
    mov dx, 0x1F2       ; 读取硬盘的扇区数量寄存器编号
    mov al, cl          ; al=要读取的扇区数
    out dx, al          ; 将要读取的扇区数写入寄存器
    mov di, cx          ; 保存要读取的扇区数

    mov eax, esi        ; 恢复eax值
;2.设置读取硬盘的LBA地址，LBA一共28位
    mov dx, 0x1F3       ; 设定存放LBA的0~7位的寄存器编号
    out dx, al          ; 将0~7位写入寄存器

    mov dx, 0x1F4       ; 设定存放LBA的8~15位的寄存器编号
    mov al, ah          ; 8~15位
    out dx, al          ; 将8~15位写入寄存器

    mov dx, 0x1F5       ; 设定存放LBA的16~23位的寄存器编号
    shr eax, 16         ; 16~23位
    out dx, al          ; 将16~23位写入寄存器

    mov dx, 0x1F6       ; 设定存放LBA的24~27位的寄存器编号
    shr eax, 8          ; 24~27位
    or al, 11100000b    ; 设置硬盘的寻址模式、读取的硬盘 与 24~27位
    out dx, al          ; 将配置信息与24~27位写入寄存器

;3.发出读取硬盘命令
    mov dx, 0x1F7       ; 读取硬盘的命令寄存器编号
    mov al, 0x20        ; 读取硬盘的命令为0x20
    out dx, al          ; 将读取硬盘的命令写入寄存器

;4.轮询硬盘的状态寄存器，就绪后将硬盘的信息载入内存中
.not_ready:
    nop                 ; 这里添加一个nop指令，用于延时，不用一直轮询状态寄存器
    in al, dx           ; 读取硬盘的状态寄存器的值
    and al, 0x88        ; 取出硬盘的 busy位 与 ready位
    cmp al, 0x08        ; 如果硬盘的ready位为1，则硬盘就绪
    ; 若硬盘未就绪，则继续轮询状态寄存器
    jne .not_ready

;5.硬盘就绪后，循环的将硬盘的数据从硬盘的缓存中载入内存
;  要读取4个sector的大小，即4*512B，循环读取4*256次
    mov ax, di          ; 保存要读取的扇区数
    mov cx, 256         ; 一个sector读取word大小数据需要读取的次数
    mul cx
    mov cx, ax          ; 循环次数
    mov dx, 0x1F0       ; 读取硬盘的数据寄存器编号

.loop_rd_data_from_disk_to_mem:
    in ax, dx           ; 读取硬盘的数据寄存器的值
    mov ds:[bx], ax     ; 将硬盘的数据写入内存中
    add bx, 2           ; 挏次读取2字节，所以bx要加2
    loop .loop_rd_data_from_disk_to_mem
    ret

;;;;;;;;;;;;;;;;;;  打印字符串结束

    message db "hello, this is hsl's MBR."


    times 510-($-$$) db 0
    db 0x55, 0xAA
