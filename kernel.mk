# 存放所有的目标文件，  需要注意目标文件放置顺序是调用在前，被调用在后
target=${KERNEL_DIR}/main.o ${LIB_KERNEL_DIR}/print.o
# 存放所有的头文件
INCLUDE_FLAGS = -I ${KERNEL_DIR} -I ${LIB_KERNEL_DIR} -I ${LIB_DIR}


compileKernel: ${target}
	ld -m elf_i386  ${target} -e main -Ttext 0xC0001500 -o ${BIN_DIR}/kernel.bin

${KERNEL_DIR}/%.o: ${KERNEL_DIR}/%.c
	gcc -m32 -c $< ${INCLUDE_FLAGS} -o $@

${LIB_KERNEL_DIR}/%.o: ${LIB_KERNEL_DIR}/%.S
	nasm -f elf32 $< -o $@

${LIB_KERNEL_DIR}/%.o: ${LIB_KERNEL_DIR}/%.c
	gcc -m32 -c $< ${INCLUDE_FLAGS} -o $@
