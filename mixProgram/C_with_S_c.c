extern void asm_print(char* str, int len);
void c_print(char* str)
{
    int len = 0;
    while (str[len] != '\0')
    {
        len++;
    }
    asm_print(str, len);
}