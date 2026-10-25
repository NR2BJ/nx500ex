/*
 * nxgpio: 카메라 키의 GPIO 선을 레지스터로 직접 눌렀다 뗀다 (셔터 버튼 신호를 하드웨어 수준에서 흉내. 벌브 30 초 넘기기용).
 * DRIMe5 의 GPIO 블록은 8 선짜리 ARM PL061 식이다 (gpiochip 이 8 개씩, 라벨 gpio0..):
 *   DATA: base + (1 << 선) * 4 (주소 마스크 방식, 그 비트만 읽고 쓴다), DIR: base + 0x400 (1 = 출력)
 * 누름 = 그 선을 출력 0 으로 (버튼이 GND 로 당기는 것과 같음), 뗌 = 다시 입력으로 (풀업이 1 로 되돌림). 출력 1 은 절대 쓰지 않는다.
 *   nxgpio <블록 물리 주소 hex> <선 0-7> press|release|read
 * 셔터1 (반셔터) = gpio-59 = gpiochip56 (gpio7) 의 선 3, 셔터2 = gpio-27 = gpiochip24 (gpio3) 의 선 3 (2026-10-26, /sys/kernel/debug/gpio).
 */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	unsigned long base, pa;
	int line, fd;
	volatile unsigned char *m;
	volatile unsigned int *data, *dir;
	if (argc < 4) { fprintf(stderr, "nxgpio <base hex> <line 0-7> press|release|read\n"); return 1; }
	base = strtoul(argv[1], NULL, 16); line = atoi(argv[2]);
	if (line < 0 || line > 7) return 1;
	fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) { perror("/dev/mem"); return 2; }
	pa = base & ~0xfffUL;
	m = mmap(NULL, 0x1000, PROT_READ | PROT_WRITE, MAP_SHARED, fd, pa);
	if (m == MAP_FAILED) { perror("mmap"); return 2; }
	m += base - pa;
	data = (volatile unsigned int *)(m + ((1u << line) << 2));
	dir = (volatile unsigned int *)(m + 0x400);
	if (!strcmp(argv[3], "read")) {
		volatile unsigned int *all = (volatile unsigned int *)(m + 0x3fc), *afsel = (volatile unsigned int *)(m + 0x420);
		printf("dir=0x%02x data(line %d)=%u all=0x%02x afsel=0x%02x\n", *dir & 0xff, line, (*data >> line) & 1, *all & 0xff, *afsel & 0xff);
	} else if (!strcmp(argv[3], "press")) {
		*dir = (*dir | (1u << line)) & 0xff;   /* 출력으로 */
		*data = 0;                      /* 마스크된 쓰기: 이 선만 0 (방향을 먼저 바꾼 뒤 써야 반영되는 구현도 있어 이 순서) */
	} else if (!strcmp(argv[3], "release")) {
		*dir = (*dir & ~(1u << line)) & 0xff;  /* 입력으로 (풀업) */
	} else return 1;
	return 0;
}
