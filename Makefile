BIN_DIR = binDir
KERNEL_DIR = kernel
LIB_DIR = lib
LIB_KERNEL_DIR = lib/kernel



KERNEL_TARGET = ${KERNEL_DIR}/*.o ${LIB_KERNEL_DIR}/*.o
#导出所有的目录
export BIN_DIR KERNEL_DIR LIB_DIR LIB_KERNEL_DIR

########################启动bochs########################
bochs: compileMBR compileLoader compileKernel
	@echo "启动bochs"
	sh myShell/StartBochs.sh

# 编译并写入MBR到硬盘
compileMBR:
	nasm -f bin mbr.S -o ${BIN_DIR}/mbr.bin -I boot.inc
	dd if=${BIN_DIR}/mbr.bin of=Myhd60M.img bs=512 count=1 conv=notrunc
	@echo "MBR编译并写入硬盘完成"

# 编译并写入loader到硬盘
compileLoader:
	nasm -f bin loader.S -o ${BIN_DIR}/loader.bin -I boot.inc
	dd if=${BIN_DIR}/loader.bin of=Myhd60M.img bs=512 count=4 seek=2 conv=notrunc
	@echo "loader编译并写入硬盘完成"

# 编译并写入kernel到硬盘
compileKernel:
	make -f kernel.mk
	dd if=${BIN_DIR}/kernel.bin of=Myhd60M.img bs=512 count=200 seek=9 conv=notrunc
	@echo "kernel编译并写入硬盘完成"


.PHONY: clean
clean:
	@echo "清理"

	rm -f bochs.out \
		${BIN_DIR}/mbr.bin ${BIN_DIR}/loader.bin ${BIN_DIR}/kernel.bin \
		${KERNEL_TARGET}

	@echo "清理完成"