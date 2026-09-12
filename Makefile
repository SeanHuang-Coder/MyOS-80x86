########################启动bochs########################
bochs:
	@echo "启动bochs"
	sh StartBochs.sh


compileMBR:
	nasm -f bin mbr.S -o mbr.bin -I boot.inc
	@echo "MBR编译完成"

compileLoader:
	nasm -f bin loader.S -o loader.bin -I boot.inc
	@echo "loader编译完成"


.PHONY: clean
clean:
	@echo "清理"
	rm -f bochs.out mbr.bin loader.bin
	@echo "清理完成"