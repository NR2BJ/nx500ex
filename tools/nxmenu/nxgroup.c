/*
 * nxgroup: 사진 여러 장을 재생 화면에서 순정 연사처럼 한 묶음으로 보이게 한다.
 *
 * 순정 펌웨어 분석 (fw 1.12):
 *   - 연사 사진은 메이커노트(Samsung Type2) 태그 0x000a 에 LONG 2개 (연사 상태, 묶음 키) 가 있다.
 *     libsif ExifDecoder::parseMakerNote 가 읽고, 없으면 상태 = -1, 키 = 0 이다.
 *   - 재생 화면(di-camera-app UI_Folderview_Check_Folder)은 JPG, RAW+JPG, SRW 중 상태가 0~2 이고
 *     앞이나 뒤 파일과 키가 같으면 묶음으로 본다. 첫 장은 상태 1 (libmm-photo 가 이때 새 키를 만든다).
 *
 * 파일 크기를 바꾸지 않고 제자리에서 고친다:
 *   - 메이커노트의 값 위치는 메이커노트 시작 기준이라 IFD 안에서 항목 순서를 바꿔도 값은 그대로다.
 *   - 방법 1 (SRW): 값이 없는 항목(개수 0) 두 개를 빼고 0x000a 를 번호 순서 자리에 넣는다. 항목 수가 하나 줄어
 *     IFD 끝에 남는 12바이트에 다음 IFD 위치(0)와 0x000a 의 값 8바이트를 쓴다. IFD 전체 크기는 그대로다.
 *   - 방법 2 (개수 0 항목이 없을 때, JPEG): 얼굴 관련 항목(0x00e0~0x0102) 중 값이 모두 0 이고 8바이트 이상인 항목 하나를
 *     0x000a 로 바꾸고 그 값 자리를 쓴다.
 *   - 이미 0x000a 가 있으면 값만 바꾼다. 조건이 맞지 않는 파일은 건드리지 않는다.
 *
 * 사용법:
 *   nxgroup 파일...      한 묶음으로 만든다 (새 키). 첫 파일과 이름(확장자 앞)이 같은 파일이 첫 장(상태 1), 나머지는 상태 2
 *   nxgroup -l 파일...   0x000a 값을 보여준다
 *   nxgroup -d 파일...   메이커노트 항목 목록 (구조 확인용)
 *   nxgroup -k 키 파일...  키를 정해서 묶는다 (16진수)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>

#define HEAD_MAX (64 * 1024)   /* 메이커노트 IFD 가 이 안에 있어야 한다 */
#define TAG_CONTI 0x000a

static unsigned char buf[HEAD_MAX];
static long len, base;   /* base = 파일 안 TIFF 머리 위치 */
static int be;           /* 1 = MM (big endian) */

static unsigned u16(long o) { return be ? (buf[o] << 8 | buf[o + 1]) : (buf[o] | buf[o + 1] << 8); }
static unsigned u32(long o)
{
	return be ? ((unsigned)buf[o] << 24 | buf[o + 1] << 16 | buf[o + 2] << 8 | buf[o + 3])
	          : (buf[o] | buf[o + 1] << 8 | buf[o + 2] << 16 | (unsigned)buf[o + 3] << 24);
}
static void p16(unsigned char *p, unsigned v) { if (be) { p[0] = v >> 8; p[1] = v; } else { p[0] = v; p[1] = v >> 8; } }
static void p32(unsigned char *p, unsigned v)
{
	if (be) { p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v; }
	else { p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24; }
}
static int in(long o, long n) { return o >= 0 && n >= 0 && o + n <= len; }
/* 항목(파일 기준 위치)의 값 바이트 수 */
static unsigned dsize(long en)
{
	static const unsigned char ts[13] = { 0, 1, 1, 2, 4, 8, 1, 1, 2, 4, 8, 4, 8 };
	unsigned t = u16(en + 2);
	return t < 13 ? ts[t] * u32(en + 4) : 0;
}

/* IFD (TIFF 기준 off) 에서 태그를 찾아 항목 위치(파일 기준)를 돌려준다 */
static long find_tag(unsigned off, unsigned tag)
{
	long p = base + off;
	unsigned n, i;
	if (!in(p, 2)) return -1;
	n = u16(p);
	if (n == 0 || n > 500 || !in(p + 2, 12L * n)) return -1;
	for (i = 0; i < n; i++)
		if (u16(p + 2 + 12 * i) == tag) return p + 2 + 12 * i;
	return -1;
}

/* 메이커노트 IFD 위치(파일 기준)를 찾는다. 실패하면 -1 */
static long makernote(int fd)
{
	long e;
	len = pread(fd, buf, HEAD_MAX, 0);
	if (len < 16) return -1;
	base = 0;
	if (buf[0] == 0xff && buf[1] == 0xd8) {   /* JPEG: APP1 Exif 를 찾는다 */
		long p = 2;
		base = -1;
		while (in(p, 10) && buf[p] == 0xff) {
			unsigned m = buf[p + 1], l = buf[p + 2] << 8 | buf[p + 3];
			if (m == 0xe1 && memcmp(buf + p + 4, "Exif\0\0", 6) == 0) { base = p + 10; break; }
			if (m == 0xda || m == 0xd9) break;
			p += 2 + l;
		}
		if (base < 0) return -1;
	}
	if (!in(base, 8)) return -1;
	if (buf[base] == 'M' && buf[base + 1] == 'M') be = 1;
	else if (buf[base] == 'I' && buf[base + 1] == 'I') be = 0;
	else return -1;
	if (u16(base + 2) != 42) return -1;
	e = find_tag(u32(base + 4), 0x8769);          /* Exif IFD */
	if (e < 0) return -1;
	e = find_tag(u32(e + 8), 0x927c);             /* MakerNote */
	if (e < 0) return -1;
	e = base + u32(e + 8);
	/* Samsung Type2: 헤더 없이 IFD 로 시작하고 첫 항목이 0x0001 "0100" */
	if (!in(e, 14) || u16(e + 2) != 0x0001 || memcmp(buf + e + 10, "0100", 4) != 0) return -1;
	return e;
}

static int list(const char *path)
{
	int fd = open(path, O_RDONLY);
	long mn, e;
	if (fd < 0) { perror(path); return 1; }
	mn = makernote(fd);
	close(fd);
	if (mn < 0) { printf("%s: no samsung makernote\n", path); return 1; }
	e = find_tag(mn - base, TAG_CONTI);
	if (e < 0) { printf("%s: none\n", path); return 0; }
	if (u16(e + 2) != 4 || u32(e + 4) != 2 || !in(mn + u32(e + 8), 8)) { printf("%s: 0x000a unexpected\n", path); return 1; }
	printf("%s: mode %d key %08x\n", path, (int)u32(mn + u32(e + 8)), u32(mn + u32(e + 8) + 4));
	return 0;
}

static int set(const char *path, unsigned mode, unsigned key)
{
	int fd = open(path, O_RDWR);
	long mn, e;
	unsigned n, i, j, d1, d2, pos, cnt, data;
	unsigned char blk[2 + 12 * 500], ins[12], val[8];
	if (fd < 0) { perror(path); return 1; }
	mn = makernote(fd);
	if (mn < 0) { fprintf(stderr, "%s: no samsung makernote\n", path); close(fd); return 1; }

	e = find_tag(mn - base, TAG_CONTI);
	if (e >= 0) {   /* 이미 있으면 값만 바꾼다 */
		if (u16(e + 2) != 4 || u32(e + 4) != 2 || !in(mn + u32(e + 8), 8)) {
			fprintf(stderr, "%s: 0x000a unexpected\n", path); close(fd); return 1;
		}
		p32(val, mode);
		p32(val + 4, key);
		if (pwrite(fd, val, 8, mn + u32(e + 8)) != 8) { perror(path); close(fd); return 1; }
		fsync(fd); close(fd);
		return 0;
	}

	/* 방법 1 (실기 SRW): 값 개수가 0 인 항목 두 개를 빼고 항목 수를 하나 줄여, IFD 끝에 남는 12바이트에 다음 IFD 위치(0)와 값을 쓴다.
	 * 방법 2 (실기 JPEG, 개수 0 항목 없음): 얼굴 관련 항목(0x00e0~0x0102) 중 값이 IFD 밖에 8바이트 이상 있고 모두 0 인 항목 하나를
	 * 0x000a 로 바꾸고 그 값 자리를 쓴다. 두 방법 모두 IFD 크기와 파일 크기는 그대로다. */
	n = u16(mn);
	d1 = d2 = n;
	for (i = 0; i < n; i++)
		if (u32(mn + 2 + 12 * i + 4) == 0) {
			if (d1 == n) d1 = i;
			else { d2 = i; break; }
		}
	if (d2 < n) {
		cnt = n - 1;
		data = 2 + 12 * (n - 1) + 4;
	} else {
		d1 = d2 = n;
		for (i = 0; i < n && d1 == n; i++) {
			long en = mn + 2 + 12 * i;
			unsigned t = u16(en), sz = dsize(en), k;
			if (t < 0x00e0 || t > 0x0102 || sz < 8 || !in(mn + u32(en + 8), sz)) continue;
			for (k = 0; k < sz && !buf[mn + u32(en + 8) + k]; k++) ;
			if (k == sz) d1 = i;
		}
		if (d1 == n) { fprintf(stderr, "%s: no room for 0x000a\n", path); close(fd); return 1; }
		cnt = n;
		data = u32(mn + 2 + 12 * d1 + 8);
	}

	/* 새 IFD: 뺀 항목 자리 없이 0x000a 를 번호 순서 자리에 넣는다 */
	p16(ins, TAG_CONTI);
	p16(ins + 2, 4);
	p32(ins + 4, 2);
	p32(ins + 8, data);   /* 메이커노트 시작 기준 */
	memcpy(blk, buf + mn, 2 + 12L * n);
	p16(blk, cnt);
	pos = 0;
	for (i = 0, j = 0; i < n; i++) {
		if (i == d1 || i == d2) continue;
		if (!pos && u16(mn + 2 + 12 * i) > TAG_CONTI) { memcpy(blk + 2 + 12 * j++, ins, 12); pos = 1; }
		memcpy(blk + 2 + 12 * j++, buf + mn + 2 + 12 * i, 12);
	}
	if (!pos) memcpy(blk + 2 + 12 * j++, ins, 12);
	if (j != cnt) { fprintf(stderr, "%s: internal\n", path); close(fd); return 1; }
	p32(val, mode);
	p32(val + 4, key);
	if (cnt < n) {   /* 방법 1: IFD 끝 12바이트 = 다음 IFD 0 + 값 */
		p32(blk + 2 + 12 * j, 0);
		memcpy(blk + 2 + 12 * j + 4, val, 8);
	} else if (pwrite(fd, val, 8, mn + data) != 8) {   /* 방법 2: 값을 먼저 쓴다 (0 이던 자리라 무해) */
		perror(path); close(fd); return 1;
	}

	if (pwrite(fd, blk, 2 + 12L * n, mn) != (long)(2 + 12 * n)) { perror(path); close(fd); return 1; }
	fsync(fd);
	close(fd);
	return 0;
}

/* 메이커노트 항목을 보여준다 (구조 확인용) */
static int dump(const char *path)
{
	int fd = open(path, O_RDONLY);
	long mn;
	unsigned n, i;
	if (fd < 0) { perror(path); return 1; }
	mn = makernote(fd);
	close(fd);
	if (mn < 0) { printf("%s: no samsung makernote\n", path); return 1; }
	n = u16(mn);
	printf("%s: %s makernote at %ld, %u entries\n", path, be ? "MM" : "II", mn, n);
	for (i = 0; i < n; i++) {
		long en = mn + 2 + 12 * i;
		unsigned sz = dsize(en), z = 0, k;
		if (sz > 4 && in(mn + u32(en + 8), sz)) {
			for (k = 0; k < sz && !buf[mn + u32(en + 8) + k]; k++) ;
			z = k == sz;
		}
		printf("%04x t%u n%u %s %u%s\n", u16(en), u16(en + 2), u32(en + 4), sz > 4 ? "off" : "val",
		       u32(en + 8), sz > 4 ? (z ? " zero" : "") : "");
	}
	return 0;
}

/* 확장자 앞 이름 (경로 포함) 길이 */
static size_t stem(const char *p)
{
	const char *d = strrchr(p, '.'), *s = strrchr(p, '/');
	return (d && (!s || d > s)) ? (size_t)(d - p) : strlen(p);
}

int main(int argc, char **argv)
{
	int i, a = 1, err = 0;
	unsigned key = 0;
	if (argc < 2) {
		fprintf(stderr, "usage: %s [-k key] file... | -l file... | -d file...\n", argv[0]);
		return 2;
	}
	if (strcmp(argv[1], "-d") == 0) {
		for (i = 2; i < argc; i++) err |= dump(argv[i]);
		return err;
	}
	if (strcmp(argv[1], "-l") == 0) {
		for (i = 2; i < argc; i++) err |= list(argv[i]);
		return err;
	}
	if (strcmp(argv[1], "-k") == 0 && argc > 3) { key = strtoul(argv[2], NULL, 16); a = 3; }
	if (!key) {
		key = (unsigned)time(NULL) * 2654435761u ^ (unsigned)getpid() << 16;
		if (!key) key = 1;
	}
	for (i = a; i < argc; i++) {
		int first = stem(argv[i]) == stem(argv[a]) && strncmp(argv[i], argv[a], stem(argv[a])) == 0;
		if (set(argv[i], first ? 1 : 2, key)) err = 1;
		else printf("%s: mode %d key %08x\n", argv[i], first ? 1 : 2, key);
	}
	return err;
}
