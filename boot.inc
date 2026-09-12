;==========================这是一个配置文件==========================
; loader在内存起始位置中的位置，本质是一个宏定义，与C语言中的#define宏定义功能相同
LOADER_BASE_ADDR equ 0x900
; loader在磁盘中的起始扇区
LOADER_START_SECTOR equ 2