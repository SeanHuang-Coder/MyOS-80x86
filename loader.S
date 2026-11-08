;=====================loader用于实模式到保护模式的切换=====================
;本章节目前的目标是，使用loader在屏幕上打印字符串"hello hsl's loader."


; 包含配置文件，使用LOADER_BASE_ADDR宏定义
%include "boot.inc"
section loader vstart=LOADER_BASE_ADDR
LOADER_STACK_TOP equ LOADER_BASE_ADDR
jmp loader_start

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

GDT_SIZE equ $ - GDT_BASE
GDT_LIMIT equ GDT_SIZE - 1

times 60 dq 0           ; 预留60个段描述符的空间

;=====================定义段选择子=====================
; 代码段
    SELECTOR_CODE equ ( 0x001 << 3 ) + TI_GDT + RPL0
; 数据段与栈段
    SELECTOR_DATA equ ( 0x002 << 3 ) + TI_GDT + RPL0
; 显存段
    SELECTOR_VIDEO equ ( 0x003 << 3 ) + TI_GDT + RPL0


; 定义gdt的指针，用于后续载入gdtr
; GDT一共6B，48位
    gdt_ptr dw GDT_LIMIT
            dd GDT_BASE

; 定义一个测试字符串，loader处于实模式时打印该字符串
    loadermsg db 'loader in real mode.', 0x00

; ==================== 创建页目录表及页表====================
[bits 32]
setup_page:
    ; 保存上下文环境
    push ebp
    mov ebp, esp
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi


    ; 清空整个页目录表
    mov ecx, 4096
    mov esi, 0
.clear_page_dir:
    mov byte [PAGE_DIR_TABLE_POS + esi], 0
    inc esi
    loop .clear_page_dir

; 构建页目录项
.create_pde:
    mov eax, PAGE_DIR_TABLE_POS         ; base address
    ; AVL给0 G位给0 PAT位给0 Dirty给0，Accessed给0，PCD给0，PWT给0，第三位后续再处理
    ; 000000000000b
    add eax, 0x1000                     ; 加0x1000后，eax存放的是第一个页表的物理地址
    mov ebx, eax
    or eax, PG_US_U | PG_RW_W | PG_P
    ; 让第0号目录项与第0xC00号目录项指向相同的页表，他们都指向第0号页表
    ; 低端1MB的内存范围是0x000000~0x00100000，在启动分页以后，loader仍然使用的是这段内存，所以我们需要保证这段虚拟地址的0x00000000~0x00100000仍然映射到物理内存的0x00000000~0x00100000
    ; 所以第0号页表前256个页表项需要指向低端的1MB物理内存
    mov dword [PAGE_DIR_TABLE_POS + 0x0], eax
    ; 高端地址3GB~4GB是内核地址空间，我们这里使用了低端1MB存放内核程序，所以从3GB开始的页表的页表项需要指向低端的1MB物理内存
    mov dword [PAGE_DIR_TABLE_POS + 0xC00], eax

    ; 将最后一个页目录项指向页目录表自己(1023*4B)
    sub eax, 0x1000
    mov dword [PAGE_DIR_TABLE_POS + 4092], eax

    ; 创建第0号页表的前256个页表项PTE，使其映射到低端1MB物理内存
    mov ecx, 256
    mov esi, 0
    mov edx, PG_US_U | PG_RW_W | PG_P           ; edx在下面的循环中代表0~255号的4K物理页
.create_pte_entry:
    mov [ebx + esi*4], edx
    add edx, 4096
    inc esi
    loop .create_pte_entry

    ; 创建内核其他页目录项，这里我们使用0x100000 + 0x1000之后的254个页表作为内核的页表
    mov ecx, 254
    mov esi, 769                                  ; 低端1MB    页目录表4K  第0号页表4K
    mov eax, PAGE_DIR_TABLE_POS + 0x2000          ; 0x100000 + 0x1000 + 0x1000
    or eax, PG_US_U | PG_RW_W | PG_P
    mov ebx, PAGE_DIR_TABLE_POS
.create_kernel_pde_entry:
    mov [ebx + esi*4], eax
    add eax, 0x1000
    inc esi
    loop .create_kernel_pde_entry


    ; 恢复上下文环境
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    mov esp, ebp
    pop ebp
    ret

; ==================== 加载内核====================
[bits 32]
; @param eax = start sector
; @param ebx = base address
; @param ecx = sector count
rd_disk_m_32:
    mov esi, eax        ; 保存eax的值，因为后续会修改eax的值
;1.设置读取硬盘的扇区数量
    mov dx, 0x1F2       ; 读取硬盘的扇区数量寄存器编号
    mov al, cl          ; al=要读取的扇区数
    out dx, al          ; 将要读取的扇区数写入寄存器
    mov edi, ecx          ; 保存要读取的扇区数

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
;  要读取200个sector的大小，即200*512B，循环读取200*256次
    mov ax, di          ; 保存要读取的扇区数
    mov cx, 256         ; 一个sector读取word大小数据需要读取的次数
    mul cx
    mov cx, ax          ; 循环次数
    mov dx, 0x1F0       ; 读取硬盘的数据寄存器编号

.loop_rd_data_from_disk_to_mem:
    in ax, dx           ; 读取硬盘的数据寄存器的值
    mov ds:[ebx], ax     ; 将硬盘的数据写入内存中
    add ebx, 2           ; 挏次读取2字节，所以ebx要加2
    loop .loop_rd_data_from_disk_to_mem
    ret

; ==================== 解析kernel.bin的头文件====================
; 主要工作：讲解析后的segment、section复制到对应的内存地址
kernel_init:
    ; 清空寄存器
    xor eax, eax
    xor ebx, ebx        ; 记录程序头表地址，        文件开头偏移28B处，大小4B
    xor ecx, ecx        ; 记录程序头表entry数量，   文件开头偏移44B处，大小2B
    xor edx, edx        ; 记录程序头表entry的大小， 文件开头偏移42B处，大小2B


    mov ebx, [KERNEL_BIN_BASE_ADDR + 28]     ; 读取程序头表偏移地址
    mov cx,  [KERNEL_BIN_BASE_ADDR + 44]     ; 读取程序头表entry数量
    mov dx,  [KERNEL_BIN_BASE_ADDR + 42]     ; 读取程序头表entry的大小

    add ebx, KERNEL_BIN_BASE_ADDR            ; 计算程序头表地址的物理内存地址


    ; 解析程序头表中的每个segment entry
.each_segment_entry:    ; 解析segment entry
    cmp byte [ebx], PT_NULL
    je .PT_NULL
    ; ======如果不是空segment，解析segment entry
    ; 使用memcpy(dst, src, size)来复制segment entry到内存中
        ; struct Elf32_Phdr {
        ;     // 第4行
        ;     Elf32_Word    p_type;        // 说明程序中段的类型
        ;     Elf32_Off     p_offset;      // 指明本段在文件内的起始偏移字节
        ;     Elf32_Addr    p_vaddr;       // 指明本段在内存中的起始虚拟地址
        ;     //第5行
        ;     Elf32_Addr    p_paddr;       // 仅用于物理地址相关的系统中，因为System V忽略用户程序中所有的物理地址，所以此项暂且保留，未设定
        ;     Elf32_Word    p_filesz;      // 指明本段在文件中的大小
        ;     Elf32_Word    p_memsz;       // 指明本段在内存中的大小
        ;     Elf32_Word    p_flags;       // 指明与本段相关的标志，标志取值见表p_flags
        ;     // 第6行
        ;     Elf32_Word    p_align;       // 指明本段在文件和内存中的对齐方式，值为或1，表示不对齐，否则p_align应该是2的幂次数
        ; };
    push dword [ebx + 16]                       ; 压入segment entry的大小 size

    mov eax,   [ebx + 4]                        ; 读取segment entry在文件中的偏移字节
    add eax, KERNEL_BIN_BASE_ADDR               ; 计算segment entry在内存中的物理地址
    push dword eax                              ; 压入segment entry在内存中的物理地址 src

    push dword [ebx + 8]                        ; 压入segment entry在内存中的起始虚拟地址 dst

    call mem_cpy
    add esp, 12                                 ; 清空栈

.PT_NULL:
    add ebx, edx
    loop .each_segment_entry
    ret


; ==================== memcpy(dst, src, size) ====================
; 栈帧布局： 从高地址到低地址
; size src dst eip ebp
mem_cpy:
    cld                         ; 清除方向标志位，使rep movsb从低地址向高地址复制
    ; 保存环境
    push ebp
    mov ebp, esp
    push ecx                    ; 我们需要用到ecx寄存器，所以要保存它


    mov edi, [ebp + 8]          ; dst
    mov esi, [ebp + 12]         ; src
    mov ecx, [ebp + 16]         ; size
    ; movsb movsw movs
    ; movs表示mov string，后面的b、w、d表示表示byte、word、dword
    ; ecx
    ; rep表示repeat，该指令按照ecx寄存器中指定的次数重复执行movs<b/w/d>指令
    rep movsb                   ; 复制size个字节，

    ; 恢复环境
    pop ecx
    pop ebp
    ret

[bits 16]
loader_start:
;=====================使用bios的10h中断的13h子功能打印字符串=====================
; 输入参数：
; AH 子功能号
; BH = 页码
; BL = 属性
; CX = 字符串长度
; (DH, DL) = (行坐标，列坐标)
; ES:BP = 字符串地址
; AL = 显示输出方式，我们使用 方式1
;       0——字符串中只含显示字符，期限是属性在BL中，显示后，光标位置不变
;       1——字符串中只包含属性字节，属性字节在BL中，显示后，光标位置改变
;       2——字符串中包含显示字符和属性字节，显示后，光标位置不变
;       3——字符串中包含显示字符和属性字节，显示后，光标位置改变

    mov sp, LOADER_BASE_ADDR
    mov bp, loadermsg               ; 传入字符串地址
    mov cx, 20                      ; 传入字符串长度
    mov ax, 0x1301                  ; 子功能号
    mov bx, 0x001F                  ; 0号页，不闪烁，黑色背景，亮度增强，白色字体
    mov dx, 0x1800                  ; 在24行，0列打印字符串
    int 0x10

;=====================开始进入保护模式=====================
; 进入保护模式的步骤：
    ; 1. 加载gdt到gdtr
    ; 2. 开启A20地址线
    ; 3. 切换到保护模式

    ; 加载gdt到gdtr
    lgdt [gdt_ptr]
    ; 开启A20地址线
    in al, 0x92
    or al, 00000010b
    out 0x92, al
    ; 将CR0的PE位进行置位 cr0是32位寄存器，PE位在第1位上
    mov eax, cr0
    or eax, 0x00000001
    mov cr0, eax
    ; 执行到此处，表示保护模式已经启动
    
    ; 跳转刷新流水线
    ; 刷新流水线的原因：CPU会提前取指 + 提前译码。在实模式下，CPU已经将保护模式的后续指令读到流水线，并完成了16位指令格式译码，
    ; 而进入保护模式后，指令是32位的，而流水线还是16位的，所以需要刷新流水线,刷新流水线的方法，
    ; 增加一个远跳转即可，这会触发流水线清空，然后重新取指、译码
    jmp dword SELECTOR_CODE:p_mode_start


[bits 32]
p_mode_start:
    ;将各个选择子信息放入对应的段寄存器
    mov ax, SELECTOR_DATA
    mov ds, ax                  ; 数据段选择子
    mov es, ax
    mov ss, ax                  ; 栈段选择子
    mov esp, LOADER_STACK_TOP   ; 栈指针初始化

    mov ax, SELECTOR_VIDEO
    mov gs, ax                  ; 显存段选择子

    ; ==================== 加载内核====================
    mov eax, KERNEL_START_SECTOR    ; kernel在磁盘中的起始扇区
    mov ebx, KERNEL_BIN_BASE_ADDR   ; kernel在内存中的基址
    mov ecx, 200                    ; kernel预留的大小，从硬盘中加载200个扇区到内存中
    call rd_disk_m_32


    ; ==================== 构建页目录表====================
    call setup_page             ; 构建页目录表
    sgdt [gdt_ptr]              ; 将gdtr的值暂时保存到gdt_ptr中
    ; 将段描述符的地址改为虚拟地址
    mov ebx, [gdt_ptr + 2]      ; 将GDT表的基址加载到ebx中

    ; 在0x0~0x100000地址空间中的段描述符，需要映射到内核空间，所以需要加上0xC0000000，将基址映射到内核空间
    or dword [gdt_ptr + 2], 0xC0000000      ; 修改GDT表的基址为虚拟地址
    or dword [ebx + 3*8 + 4], 0xC0000000    ; 修改显存段的基址为虚拟地址
    or esp, 0xC0000000                      ; 修改栈指针为虚拟地址

    ; ==================== 开启分页机制====================
    ;  1. 准备页目录表和页表 已完成
    ;  2. 将页目录表地址写入CR3寄存器
    mov eax, PAGE_DIR_TABLE_POS
    mov cr3, eax
    ;  3. 设置CR0的PG位
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax

    lgdt [gdt_ptr]              ; 重新加载gdt到gdtr

    ; 进入内核
    jmp SELECTOR_CODE:enter_kernel

enter_kernel:
    call kernel_init             ; 解析kernel.bin的头文件，将segment、section复制到对应的内存地址
    mov esp, 0xC009f000         ; 这里使用0x9F000作为栈底指针
    jmp KERNEL_ENTER_POINT      ; 跳转到内核进入点，开始执行内核代码



    ; 在第1行的第0列输出一个字符串"hello hsl's protected mode."
    mov ecx, 26                 ; 字符串长度
    mov eax, 160                ; 显示的位置 160/2列
    mov esi, 0

    mov bh, 0xAF                ; 闪烁黑底高亮白色字体
    call ShowString

ShowString:
    mov bl, protected_print[esi]
    mov [gs:eax], bx
    inc esi
    add eax, 2

    loop ShowString

    jmp $

    protected_print db "hello hsl's page mechanism"