
# 链接目标
ldTarget: C_with_S_S.o C_with_S_c.o
	ld -m elf_i386 C_with_S_S.o C_with_S_c.o -o mixProgram

# 编译目标
C_with_S_S.o: C_with_S_S.S
	nasm -f elf32 C_with_S_S.S -o C_with_S_S.o

C_with_S_c.o: C_with_S_c.c
	gcc -m32 -c C_with_S_c.c -o C_with_S_c.o

.PHONY: clean
clean:
	rm mixProgram C_with_S_S.o C_with_S_c.o