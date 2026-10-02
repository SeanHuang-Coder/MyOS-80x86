;==========================这是一个配置文件==========================

;------------------------loader配置信息------------------------
; loader在内存起始位置中的位置，本质是一个宏定义，与C语言中的#define宏定义功能相同
LOADER_BASE_ADDR equ 0x900
; loader在磁盘中的起始扇区
LOADER_START_SECTOR equ 2


;------------------------gdt配置信息------------------------
DESC_G_4K  equ      1_00000000000000000000000b    ; 4K字节粒度
DESC_D_32  equ      1_0000000000000000000000b     ; 代码段(数据段)用D来表示，有效地址与操作数均32位，指令有效地址用EIP寄存器
                                                  ; 栈段用B来表示，有效地址与操作数均32位，指令有效地址用ESP寄存器
DESC_L     equ      0_000000000000000000000b      ; 设置是否是64位代码段
DESC_AVL   equ      0_00000000000000000000b       ; available，目前无专门用途


DESC_LIMIT_CODE2    equ      1111_0000000000000000b  ; 代码段
DESC_LIMIT_DATA2    equ      DESC_LIMIT_CODE2        ; 数据段
DESC_LIMIT_VIDEO2   equ      0000_0000000000000000b  ; 视频段


DESC_P     equ         1_000000000000000b         ; present，段是否存在于内存中
DESC_DPL_0 equ          00_0000000000000b         ; 特权级0
DESC_DPL_1 equ          01_0000000000000b         ; 特权级1
DESC_DPL_2 equ          10_0000000000000b         ; 特权级2
DESC_DPL_3 equ          11_0000000000000b         ; 特权级3

; 指示段描述符的类型，系统段 or 数据段(包含代码段 与 数据段)
;---数据段部分
DESC_S_CODE equ           1_000000000000b         ; 代码段
DESC_S_DATA equ           DESC_S_CODE             ; 数据段

;---系统段部分
DESC_S_SYS equ            0_000000000000b         ; 系统段


DESC_TYPE_DATA equ          0010_00000000b         ; 数据段
; X E W A，分别代表可执行 段生长方向 可写 已访问(访问后CPU置位)
DESC_TYPE_CODE equ          1000_00000000b         ; 代码段
; X C R A，分别代表可执行 一致性 可读 已访问(访问后CPU置位)


; 代码段的高4B的段描述符的具体内容
DESC_CODE_HIGH4 equ (0x00 << 24) + DESC_G_4K + DESC_D_32 + DESC_L + DESC_AVL + \
                                        DESC_LIMIT_CODE2 + DESC_P + DESC_DPL_0 + \
                                            DESC_S_CODE + DESC_TYPE_CODE +0x00

; 数据段的高4B的段描述符的具体内容
DESC_DATA_HIGH4 equ (0x00 << 24) + DESC_G_4K + DESC_D_32 + DESC_L + DESC_AVL + \
                                        DESC_LIMIT_DATA2 + DESC_P + DESC_DPL_0 + \
                                            DESC_S_DATA + DESC_TYPE_DATA +0x00

; 显存段的高4B的段描述符的具体内容
DESC_VIDEO_HIGH4 equ (0x00 << 24) + DESC_G_4K + DESC_D_32 + DESC_L + DESC_AVL + \
                                        DESC_LIMIT_VIDEO2 + DESC_P + DESC_DPL_0 + \
                                            DESC_S_DATA + DESC_TYPE_DATA +0x0B

;---------------------------选择子属性---------------------------
RPL0 equ          0
RPL1 equ          1
RPL2 equ          2
RPL3 equ          3

TI_GDT equ        000b
TI_LDT equ        100b

