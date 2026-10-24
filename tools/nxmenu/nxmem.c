/*
 * nxmem: 물리 메모리(/dev/mem)를 읽고 쓴다. 이미지 처리 펌웨어(RTOS) 메모리의 3D LUT 를 조사하기 위한 도구.
 *
 * 순정 펌웨어 분석 (fw 1.12, docs/research/2026-10-23-lut-firmware-analysis.md):
 *   - 이미지 처리 RTOS 는 가상 주소 = 물리 주소로 0x80000000 부터 있고, 리눅스 커널은 0x86000000 이후라 겹치지 않는다.
 *   - 3D LUT 뱅크로 보이는 영역이 0x810c3500 ~ 0x8118db00 (간격 0x4d00).
 *
 * 4바이트 단위로만 접근한다 (장치 메모리일 수 있어 바이트 접근, 정렬 안 된 접근을 피함).
 *
 * 사용법:
 *   nxmem x 주소 [개수]        4바이트 값을 16진수로 보여준다 (기본 16개)
 *   nxmem r 주소 길이 파일     주소부터 길이 바이트를 파일로 덤프한다
 *   nxmem w 주소 파일          파일 내용을 주소에 쓴다 (되돌릴 덤프를 먼저 떠 둘 것)
 * 주소, 길이는 16진수(0x...) 또는 10진수. 주소와 길이는 4의 배수.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

static volatile unsigned int *map(unsigned long addr, unsigned long len, int wr, void **base, unsigned long *mlen)
{
	long pg = sysconf(_SC_PAGESIZE);
	unsigned long a0 = addr & ~(pg - 1);
	int fd = open("/dev/mem", (wr ? O_RDWR : O_RDONLY) | O_SYNC);
	if (fd < 0) { perror("/dev/mem"); exit(1); }
	*mlen = (addr - a0 + len + pg - 1) & ~(pg - 1);
	*base = mmap(0, *mlen, wr ? PROT_READ | PROT_WRITE : PROT_READ, MAP_SHARED, fd, a0);
	close(fd);
	if (*base == MAP_FAILED) { perror("mmap"); exit(1); }
	return (volatile unsigned int *)((char *)*base + (addr - a0));
}

static unsigned long num(const char *s)
{
	char *e;
	unsigned long v = strtoul(s, &e, 0);
	if (*e) { fprintf(stderr, "bad number: %s\n", s); exit(2); }
	return v;
}

int main(int argc, char **argv)
{
	void *base;
	unsigned long mlen, addr, len, i;
	volatile unsigned int *p;

	if (argc < 3) {
		fprintf(stderr, "usage: nxmem x addr [count] | r addr len file | w addr file\n");
		return 2;
	}
	addr = num(argv[2]);
	if (addr & 3) { fprintf(stderr, "address must be a multiple of 4\n"); return 2; }

	if (!strcmp(argv[1], "x")) {
		unsigned long n = argc > 3 ? num(argv[3]) : 16;
		p = map(addr, n * 4, 0, &base, &mlen);
		for (i = 0; i < n; i++)
			printf("%s%08x%s", i % 8 ? "" : (printf("%08lx:", addr + i * 4), " "), p[i], i % 8 == 7 || i == n - 1 ? "\n" : " ");
	} else if (!strcmp(argv[1], "r") && argc == 5) {
		FILE *f;
		len = num(argv[3]);
		if (len & 3) { fprintf(stderr, "length must be a multiple of 4\n"); return 2; }
		p = map(addr, len, 0, &base, &mlen);
		f = fopen(argv[4], "wb");
		if (!f) { perror(argv[4]); return 1; }
		for (i = 0; i < len / 4; i++) {
			unsigned int v = p[i];
			fwrite(&v, 4, 1, f);
		}
		fclose(f);
		printf("read %lu bytes at %08lx -> %s\n", len, addr, argv[4]);
	} else if (!strcmp(argv[1], "w") && argc == 4) {
		FILE *f = fopen(argv[3], "rb");
		unsigned int v;
		if (!f) { perror(argv[3]); return 1; }
		fseek(f, 0, SEEK_END);
		len = ftell(f);
		rewind(f);
		if (len & 3) { fprintf(stderr, "file size must be a multiple of 4\n"); return 2; }
		p = map(addr, len, 1, &base, &mlen);
		for (i = 0; i < len / 4 && fread(&v, 4, 1, f) == 1; i++)
			p[i] = v;
		fclose(f);
		printf("wrote %lu bytes at %08lx\n", i * 4, addr);
	} else {
		fprintf(stderr, "usage: nxmem x addr [count] | r addr len file | w addr file\n");
		return 2;
	}
	munmap(base, mlen);
	return 0;
}
