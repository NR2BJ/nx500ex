/*
 * nxweb: nx500ex 웹 원격 (브라우저에서 라이브 뷰, 키 조작, 상태, 사진 보기). 포트 80.
 *   nxweb [-p 포트] [-r 웹 루트] [-s scripts 폴더] [-d]
 *
 * 정적 파일: <웹 루트>/ (index.html, app.js ...). 경로에 .. 은 거부.
 * API (모두 GET, 응답에 Access-Control-Allow-Origin: *):
 *   /lv            라이브 뷰 한 장, NV12 원본 720x480 (518400 바이트). /lv?low=1 은 Y 를 가로세로 반으로 줄인 259200 바이트
 *                  (Y 360x240 + 원래 UV 360x240). 헤더 X-Width, X-Height. 라이브 뷰가 없으면 204.
 *   /osd           카메라 화면 (X 루트 창, xwd) 의 UI 겹침. 투명 픽셀을 건너뛰는 RLE: [u32 건너뛸 픽셀 수][u32 픽셀 수][BGRA...] 반복.
 *                  헤더 X-Width, X-Height. 카메라 UI 는 투명 바탕 위에 그려져 있어 (실기: 345600 중 불투명 5천~2만) 수십 KB 로 줄어든다.
 *   /fb            /dev/fb0 원본 (64x64 라 OSD 아님, 시험용). 헤더 X-Width, X-Height, X-Bpp, X-Stride
 *   /key?k=이름[&a=click|push|release]   카메라 키 (st key <a> <이름>). 기본 click
 *   /run?s=이름    <scripts>/<이름>.sh 를 뒤에서 실행 (메뉴 동작과 같음)
 *   /status        JSON: 다이얼, 드라이브, 배터리, 동영상, IP, 가동 시간, 부하
 *   /actions       <scripts>/actions.list 그대로 (웹 화면의 동작 버튼 목록)
 *   /dcim          JSON: /mnt/mmc/DCIM 의 최근 파일 (최대 200), 새 것부터
 *   /dcim/<폴더>/<파일>          그 파일 (JPG, SRW, MP4). ?thumb=1 이면 JPG 안의 EXIF 미리보기 (작고 빠름)
 *
 * 라이브 뷰 원리 (상류 nx-remote-controller-mod 의 liveview.c 와 같음): 카메라 앱이 표시용 NV12 프레임을 고정된 물리 주소 네 곳에
 * 번갈아 쓴다. /dev/mem 으로 네 곳을 매핑해 두고, 요청 때마다 첫 두 줄의 합이 바뀐 버퍼 (방금 쓰인 것) 를 고른다.
 * 한 번에 한 요청씩 처리한다 (단일 코어, 카메라 앱이 CPU 를 많이 쓰므로 스레드를 늘려도 빨라지지 않는다).
 */
#include <arpa/inet.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define FRAME_W 720
#define FRAME_H 480
#define FRAME_SIZE (FRAME_W * FRAME_H * 3 / 2)
#define MAP_LEN (FRAME_SIZE + 4096)
#define DCIM "/mnt/mmc/DCIM"

static const off_t LV_ADDR[] = { 0xbbaea500, 0xbbb68e00, 0xbbbe7700, 0xbba6bc00 };
#define NLV ((int)(sizeof LV_ADDR / sizeof LV_ADDR[0]))

static int debug;
static const char *webroot = "/mnt/mmc/nx500ex/www";
static const char *scripts = "/mnt/mmc/nx500ex/scripts";
static unsigned char *lv_map[NLV];
static unsigned lv_hash[NLV];
static int lv_cur = -1;

static void logf_(const char *fmt, ...)
{
	va_list ap;
	if (!debug) return;
	va_start(ap, fmt); vfprintf(stderr, fmt, ap); va_end(ap);
	fputc('\n', stderr);
}

/* ---------- 소켓 출력 ---------- */
static int send_all(int fd, const void *buf, size_t len)
{
	const char *p = buf;
	while (len > 0) {
		ssize_t n = write(fd, p, len);
		if (n < 0) { if (errno == EINTR) continue; return -1; }
		p += n; len -= n;
	}
	return 0;
}

static int send_head(int fd, int code, const char *ctype, long clen, const char *extra)
{
	char h[1024];
	const char *msg = code == 200 ? "OK" : code == 204 ? "No Content" : code == 404 ? "Not Found" : code == 400 ? "Bad Request" : "Error";
	int n = snprintf(h, sizeof h, "HTTP/1.1 %d %s\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: no-store\r\n%s%s%s",
		code, msg, ctype ? "Content-Type: " : "", ctype ? ctype : "", ctype ? "\r\n" : "");
	if (clen >= 0) n += snprintf(h + n, sizeof h - n, "Content-Length: %ld\r\n", clen);
	if (extra) n += snprintf(h + n, sizeof h - n, "%s", extra);
	n += snprintf(h + n, sizeof h - n, "\r\n");
	return send_all(fd, h, n);
}

static void send_text(int fd, int code, const char *ctype, const char *body)
{
	send_head(fd, code, ctype, (long)strlen(body), NULL);
	send_all(fd, body, strlen(body));
}

/* ---------- 라이브 뷰 ---------- */
static void lv_init(void)
{
	int fd = open("/dev/mem", O_RDWR | O_SYNC), i;
	if (fd < 0) { perror("/dev/mem"); return; }
	for (i = 0; i < NLV; i++) {
		off_t pa = LV_ADDR[i] & ~(off_t)4095;
		void *p = mmap(NULL, MAP_LEN, PROT_READ, MAP_SHARED, fd, pa);
		if (p == MAP_FAILED) { perror("mmap"); lv_map[i] = NULL; continue; }
		lv_map[i] = (unsigned char *)p + (LV_ADDR[i] - pa);
	}
	close(fd);
}

/* 방금 바뀐 버퍼를 고른다. 없으면 이전 것. 첫 요청은 두 번 훑어 (40 ms 간격) 바뀐 것을 찾고, 그래도 없으면 첫 버퍼 */
static void lv_scan(void)
{
	int i, j;
	for (i = 0; i < NLV; i++) {
		unsigned h = 0;
		if (!lv_map[i]) continue;
		for (j = 0; j < FRAME_W * 2; j++) h += lv_map[i][j];
		if (lv_hash[i] != 0 && h != lv_hash[i]) lv_cur = i;
		lv_hash[i] = h;
	}
}

static unsigned char *lv_pick(void)
{
	lv_scan();
	if (lv_cur < 0) { usleep(40000); lv_scan(); }
	if (lv_cur < 0 && lv_map[0]) lv_cur = 0;
	return lv_cur >= 0 ? lv_map[lv_cur] : NULL;
}

static void handle_lv(int fd, int low)
{
	unsigned char *p = lv_pick();
	char extra[128];
	if (!p) { send_head(fd, 204, NULL, 0, NULL); return; }
	snprintf(extra, sizeof extra, "X-Width: %d\r\nX-Height: %d\r\nX-Low: %d\r\n", FRAME_W, FRAME_H, low);
	if (low) {
		static unsigned char ys[FRAME_W * FRAME_H / 4];
		int x, y, i = 0;
		for (y = 0; y < FRAME_H; y += 2)
			for (x = 0; x < FRAME_W; x += 2) ys[i++] = p[y * FRAME_W + x];
		send_head(fd, 200, "application/octet-stream", FRAME_W * FRAME_H / 4 * 3, extra);
		send_all(fd, ys, sizeof ys);
		send_all(fd, p + FRAME_W * FRAME_H, FRAME_W * FRAME_H / 2);
	} else {
		send_head(fd, 200, "application/octet-stream", FRAME_SIZE, extra);
		send_all(fd, p, FRAME_SIZE);
	}
}

/* ---------- 프레임 버퍼 ---------- */
static int read_file(const char *path, char *buf, size_t size)
{
	int fd = open(path, O_RDONLY), n;
	if (fd < 0) return -1;
	n = read(fd, buf, size - 1);
	close(fd);
	if (n < 0) return -1;
	buf[n] = 0;
	while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == ' ')) buf[--n] = 0;
	return n;
}

static void handle_fb(int fd)
{
	char vs[64] = "", bpp[16] = "", st[16] = "", extra[256];
	int w = 0, h = 0, fb, b = 0, stride = 0;
	static unsigned char buf[65536];
	long total = 0;
	read_file("/sys/class/graphics/fb0/virtual_size", vs, sizeof vs);
	read_file("/sys/class/graphics/fb0/bits_per_pixel", bpp, sizeof bpp);
	read_file("/sys/class/graphics/fb0/stride", st, sizeof st);
	sscanf(vs, "%d,%d", &w, &h); b = atoi(bpp); stride = atoi(st);
	if (!stride) stride = w * b / 8;
	fb = open("/dev/fb0", O_RDONLY);
	if (fb < 0 || w <= 0 || h <= 0) { if (fb >= 0) close(fb); send_text(fd, 404, "text/plain", "no fb0"); return; }
	total = (long)stride * h;
	snprintf(extra, sizeof extra, "X-Width: %d\r\nX-Height: %d\r\nX-Bpp: %d\r\nX-Stride: %d\r\n", w, h, b, stride);
	send_head(fd, 200, "application/octet-stream", total, extra);
	while (total > 0) {
		int n = read(fb, buf, total < (long)sizeof buf ? (size_t)total : sizeof buf);
		if (n <= 0) break;
		if (send_all(fd, buf, n) < 0) break;
		total -= n;
	}
	close(fb);
}

/* ---------- OSD (X 화면) ---------- */
#define XWD_MAX (4 * 1024 * 1024)
static unsigned char xwd_buf[XWD_MAX];
static unsigned char osd_buf[XWD_MAX];

static unsigned be32(const unsigned char *p) { return ((unsigned)p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]; }

static void handle_osd(int fd)
{
	FILE *f = popen("xwd -root -display :0 -silent 2>/dev/null", "r");
	size_t n = 0, out = 0;
	unsigned hs, ncol, w, h, bpl, bpp, off, x, y, skip = 0;
	char extra[64];
	if (!f) { send_text(fd, 500, "text/plain", "xwd failed"); return; }
	while (n < XWD_MAX) {
		size_t r = fread(xwd_buf + n, 1, XWD_MAX - n, f);
		if (r == 0) break;
		n += r;
	}
	pclose(f);
	if (n < 100) { send_head(fd, 204, NULL, 0, NULL); return; }
	hs = be32(xwd_buf); w = be32(xwd_buf + 16); h = be32(xwd_buf + 20); bpp = be32(xwd_buf + 44); bpl = be32(xwd_buf + 48); ncol = be32(xwd_buf + 76);
	off = hs + ncol * 12;
	if (bpp != 32 || w > 2000 || h > 2000 || off + (size_t)bpl * h > n) { send_text(fd, 500, "text/plain", "xwd format"); return; }
	/* RLE: 알파 0 인 픽셀은 건너뛴 수로 세고, 불투명 픽셀은 행 안에서 이어지는 만큼 묶어 [skip][run][BGRA*run] */
	for (y = 0; y < h; y++) {
		const unsigned char *row = xwd_buf + off + (size_t)y * bpl;
		x = 0;
		while (x < w) {
			unsigned run;
			if (row[x * 4 + 3] == 0) { skip++; x++; continue; }
			run = 0;
			while (x + run < w && row[(x + run) * 4 + 3] != 0) run++;
			if (out + 8 + run * 4 > XWD_MAX) break;
			memcpy(osd_buf + out, &skip, 4); memcpy(osd_buf + out + 4, &run, 4); out += 8;
			memcpy(osd_buf + out, row + x * 4, run * 4); out += run * 4;
			skip = 0; x += run;
		}
	}
	snprintf(extra, sizeof extra, "X-Width: %u\r\nX-Height: %u\r\n", w, h);
	send_head(fd, 200, "application/octet-stream", (long)out, extra);
	send_all(fd, osd_buf, out);
}

/* ---------- 명령 실행 ---------- */
static int safe_name(const char *s)
{
	if (!*s) return 0;
	for (; *s; s++) if (!((*s >= 'a' && *s <= 'z') || (*s >= 'A' && *s <= 'Z') || (*s >= '0' && *s <= '9') || *s == '_' || *s == '-')) return 0;
	return 1;
}

static void run_bg(char *const argv[])
{
	pid_t pid = fork();
	if (pid == 0) {
		int nul = open("/dev/null", O_RDWR);
		if (nul >= 0) { dup2(nul, 0); dup2(nul, 1); dup2(nul, 2); }
		setsid();
		execvp(argv[0], argv);
		_exit(127);
	}
}

static void handle_key(int fd, const char *k, const char *a)
{
	char *argv[5];
	if (!safe_name(k) || !safe_name(a)) { send_text(fd, 400, "text/plain", "bad key"); return; }
	argv[0] = "st"; argv[1] = "key"; argv[2] = (char *)a; argv[3] = (char *)k; argv[4] = NULL;
	run_bg(argv);
	send_text(fd, 200, "text/plain", "ok");
}

static void handle_run(int fd, const char *s)
{
	char path[512];
	char *argv[3];
	if (!safe_name(s)) { send_text(fd, 400, "text/plain", "bad name"); return; }
	snprintf(path, sizeof path, "%s/%s.sh", scripts, s);
	if (access(path, R_OK) != 0) { send_text(fd, 404, "text/plain", "no script"); return; }
	argv[0] = "sh"; argv[1] = path; argv[2] = NULL;
	run_bg(argv);
	send_text(fd, 200, "text/plain", "ok");
}

/* ---------- 상태 ---------- */
static void json_str(char *out, size_t size, const char *path, const char *key, int *first)
{
	char v[128];
	if (read_file(path, v, sizeof v) < 0) strcpy(v, "");
	snprintf(out + strlen(out), size - strlen(out), "%s\"%s\":\"%s\"", *first ? "" : ",", key, v);
	*first = 0;
}

static const char *mode_name(int m)
{
	static const char *names[] = { "Scene", "Auto", "P", "A", "S", "M", "C1", "C2", "SAS" };
	return (m >= 0 && m < 9) ? names[m] : "?";
}

static const char *drive_name(int d)
{
	static const char *names[] = { "1장", "연속", "고속 연속", "타이머", "브라케팅" };
	return (d >= 0 && d < 5) ? names[d] : "?";
}

static void handle_status(int fd)
{
	static char body[2048];
	char v[256], ip[64] = "";
	int mode = -1, drive = -1, level = -1, charging = 0;
	FILE *f;
	unsigned char b[32];
	int bf;
	/* NX500: 다이얼은 d5-keys, 배터리 단계는 sysman 의 공유 메모리 파일 (상류 status.c), 충전은 power_supply */
	if (read_file("/sys/devices/platform/d5-keys/dial_mode", v, sizeof v) > 0) mode = atoi(v);
	if (read_file("/sys/devices/platform/d5-keys/dial_drive", v, sizeof v) > 0) drive = atoi(v);
	bf = open("/var/run/memory/sysman/battery_status_low", O_RDONLY);
	if (bf >= 0) { if (read(bf, b, sizeof b) >= 5) level = b[4]; close(bf); }
	if (read_file("/sys/devices/platform/d5-adc-battery/power_supply/battery/charge_now", v, sizeof v) > 0) charging = atoi(v) == 1;
	f = popen("ip addr ls mlan0 2>/dev/null | sed -n 's/.*inet \\([0-9.]*\\).*/\\1/p'", "r");
	if (f) { if (!fgets(ip, sizeof ip, f)) ip[0] = 0; pclose(f); }
	ip[strcspn(ip, "\n")] = 0;
	body[0] = 0;
	snprintf(body, sizeof body, "{\"mode\":\"%s\",\"mode_n\":%d,\"drive\":\"%s\",\"drive_n\":%d,\"bat\":\"%d단계\",\"bat_level\":%d,\"charging\":\"%d\"",
		mode_name(mode), mode, drive_name(drive), drive, level, level, charging);
	{
		int first = 0;
		json_str(body, sizeof body, "/sys/kernel/debug/pmu/hevc/state", "hevc", &first);
		json_str(body, sizeof body, "/proc/uptime", "uptime", &first);
		json_str(body, sizeof body, "/proc/loadavg", "load", &first);
	}
	snprintf(body + strlen(body), sizeof body - strlen(body), ",\"ip\":\"%s\",\"lv\":%d}", ip, lv_cur >= 0);
	send_text(fd, 200, "application/json", body);
}

/* ---------- 사진 ---------- */
struct ent { char name[64]; long size; long mtime; };

static int ent_cmp(const void *a, const void *b)
{
	const struct ent *x = a, *y = b;
	if (x->mtime != y->mtime) return x->mtime < y->mtime ? 1 : -1;
	return strcmp(y->name, x->name);
}

static void handle_dcim(int fd)
{
	static struct ent ents[2000];
	static char body[200 * 128 + 64];
	int n = 0, i, first = 1;
	DIR *d = opendir(DCIM);
	struct dirent *de;
	if (!d) { send_text(fd, 404, "application/json", "[]"); return; }
	while ((de = readdir(d)) != NULL && n < 2000) {
		char sub[512];
		DIR *d2;
		struct dirent *de2;
		if (de->d_name[0] == '.') continue;
		snprintf(sub, sizeof sub, "%s/%s", DCIM, de->d_name);
		d2 = opendir(sub);
		if (!d2) continue;
		while ((de2 = readdir(d2)) != NULL && n < 2000) {
			char path[1024];
			struct stat st;
			const char *ext = strrchr(de2->d_name, '.');
			if (de2->d_name[0] == '.' || !ext) continue;
			if (strcasecmp(ext, ".jpg") && strcasecmp(ext, ".srw") && strcasecmp(ext, ".mp4")) continue;
			snprintf(path, sizeof path, "%s/%s", sub, de2->d_name);
			if (stat(path, &st) != 0) continue;
			snprintf(ents[n].name, sizeof ents[n].name, "%s/%s", de->d_name, de2->d_name);
			ents[n].size = (long)st.st_size; ents[n].mtime = (long)st.st_mtime;
			n++;
		}
		closedir(d2);
	}
	closedir(d);
	qsort(ents, n, sizeof ents[0], ent_cmp);
	body[0] = 0; strcat(body, "[");
	for (i = 0; i < n && i < 200; i++) {
		snprintf(body + strlen(body), sizeof body - strlen(body), "%s{\"n\":\"%s\",\"s\":%ld,\"t\":%ld}", first ? "" : ",", ents[i].name, ents[i].size, ents[i].mtime);
		first = 0;
	}
	strcat(body, "]");
	send_text(fd, 200, "application/json", body);
}

/* JPEG 안의 EXIF 미리보기 (IFD1 의 JPEGInterchangeFormat) 를 찾는다. 성공하면 오프셋과 길이 */
static int exif_thumb(int fd, long *off, long *len)
{
	unsigned char b[65536 + 4];
	int n = pread(fd, b, sizeof b, 0), p = 2, le, i;
	long tiff, ifd0, nent, ifd1;
	if (n < 4 || b[0] != 0xFF || b[1] != 0xD8) return -1;
	while (p + 4 < n) {
		int marker = b[p + 1], seglen = (b[p + 2] << 8) | b[p + 3];
		if (b[p] != 0xFF) return -1;
		if (marker == 0xE1 && p + 10 < n && memcmp(b + p + 4, "Exif\0\0", 6) == 0) {
			tiff = p + 10;
			if (tiff + 8 > n) return -1;
			le = b[tiff] == 'I';
#define U16(o) ((long)(le ? (b[(o)] | (b[(o) + 1] << 8)) : ((b[(o)] << 8) | b[(o) + 1])))
#define U32(o) ((long)(le ? (b[(o)] | (b[(o) + 1] << 8) | (b[(o) + 2] << 16) | ((unsigned)b[(o) + 3] << 24)) : (((unsigned)b[(o)] << 24) | (b[(o) + 1] << 16) | (b[(o) + 2] << 8) | b[(o) + 3])))
			ifd0 = tiff + U32(tiff + 4);
			if (ifd0 + 2 > n) return -1;
			nent = U16(ifd0);
			if (ifd0 + 2 + nent * 12 + 4 > n) return -1;
			ifd1 = tiff + U32(ifd0 + 2 + nent * 12);
			if (ifd1 <= tiff || ifd1 + 2 > n) return -1;
			nent = U16(ifd1);
			*off = *len = 0;
			for (i = 0; i < nent && ifd1 + 2 + i * 12 + 12 <= n; i++) {
				long e = ifd1 + 2 + i * 12, tag = U16(e), val = U32(e + 8);
				if (tag == 0x0201) *off = tiff + val;
				if (tag == 0x0202) *len = val;
			}
			return (*off > 0 && *len > 0) ? 0 : -1;
		}
		if (marker == 0xDA) return -1;
		p += 2 + seglen;
	}
	return -1;
}

static void handle_file(int fd, const char *rel, int thumb)
{
	char path[1024];
	const char *ext = strrchr(rel, '.');
	const char *ctype = "application/octet-stream";
	int f;
	struct stat st;
	long off = 0, len;
	static unsigned char buf[65536];
	if (strstr(rel, "..") || rel[0] == '/' || !ext) { send_text(fd, 400, "text/plain", "bad path"); return; }
	snprintf(path, sizeof path, "%s/%s", DCIM, rel);
	f = open(path, O_RDONLY);
	if (f < 0 || fstat(f, &st) != 0) { if (f >= 0) close(f); send_text(fd, 404, "text/plain", "no file"); return; }
	if (!strcasecmp(ext, ".jpg")) ctype = "image/jpeg";
	else if (!strcasecmp(ext, ".mp4")) ctype = "video/mp4";
	len = (long)st.st_size;
	if (thumb) {
		if (!strcasecmp(ext, ".jpg") && exif_thumb(f, &off, &len) == 0) ctype = "image/jpeg";
		else { close(f); send_head(fd, 204, NULL, 0, NULL); return; }
	}
	send_head(fd, 200, ctype, len, NULL);
	while (len > 0) {
		int n = pread(f, buf, len < (long)sizeof buf ? (size_t)len : sizeof buf, off);
		if (n <= 0) break;
		if (send_all(fd, buf, n) < 0) break;
		off += n; len -= n;
	}
	close(f);
}

static void handle_static_path(int fd, const char *path, const char *ctype)
{
	int f;
	struct stat st;
	long len;
	static unsigned char buf[65536];
	f = open(path, O_RDONLY);
	if (f < 0 || fstat(f, &st) != 0 || !S_ISREG(st.st_mode)) { if (f >= 0) close(f); send_text(fd, 404, "text/plain", "not found"); return; }
	len = (long)st.st_size;
	send_head(fd, 200, ctype, len, NULL);
	while (len > 0) {
		int n = read(f, buf, len < (long)sizeof buf ? (size_t)len : sizeof buf);
		if (n <= 0) break;
		if (send_all(fd, buf, n) < 0) break;
		len -= n;
	}
	close(f);
}

static void handle_static(int fd, const char *rel)
{
	char path[1024];
	const char *ext;
	const char *ctype = "application/octet-stream";
	if (!*rel) rel = "index.html";
	if (strstr(rel, "..")) { send_text(fd, 400, "text/plain", "bad path"); return; }
	snprintf(path, sizeof path, "%s/%s", webroot, rel);
	ext = strrchr(rel, '.');
	if (ext) {
		if (!strcmp(ext, ".html")) ctype = "text/html; charset=utf-8";
		else if (!strcmp(ext, ".js")) ctype = "application/javascript; charset=utf-8";
		else if (!strcmp(ext, ".css")) ctype = "text/css; charset=utf-8";
		else if (!strcmp(ext, ".png")) ctype = "image/png";
		else if (!strcmp(ext, ".svg")) ctype = "image/svg+xml";
		else if (!strcmp(ext, ".json")) ctype = "application/json";
		else if (!strcmp(ext, ".txt")) ctype = "text/plain; charset=utf-8";
	}
	handle_static_path(fd, path, ctype);
}

/* ---------- 요청 ---------- */
static const char *query_get(const char *q, const char *key, char *out, size_t size)
{
	size_t kl = strlen(key);
	const char *p = q;
	out[0] = 0;
	while (p && *p) {
		if (!strncmp(p, key, kl) && p[kl] == '=') {
			const char *e = strchr(p + kl + 1, '&');
			size_t l = e ? (size_t)(e - p - kl - 1) : strlen(p + kl + 1);
			if (l >= size) l = size - 1;
			memcpy(out, p + kl + 1, l); out[l] = 0;
			return out;
		}
		p = strchr(p, '&');
		if (p) p++;
	}
	return out;
}

static void handle(int fd)
{
	char req[2048], path[1024], v1[128], v2[64];
	char *q, *sp;
	int n = 0;
	struct timeval tv = { 3, 0 };
	setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
	tv.tv_sec = 15;
	setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
	/* 요청 줄과 헤더를 빈 줄까지 읽는다 */
	while (n < (int)sizeof req - 1) {
		int r = read(fd, req + n, sizeof req - 1 - n);
		if (r <= 0) break;
		n += r; req[n] = 0;
		if (strstr(req, "\r\n\r\n") || strstr(req, "\n\n")) break;
	}
	req[n] = 0;
	if (strncmp(req, "GET ", 4) != 0) { send_text(fd, 400, "text/plain", "GET only"); return; }
	sp = strchr(req + 4, ' ');
	if (!sp) { send_text(fd, 400, "text/plain", "bad request"); return; }
	*sp = 0;
	snprintf(path, sizeof path, "%s", req + 4);
	q = strchr(path, '?');
	if (q) *q++ = 0; else q = path + strlen(path);
	logf_("%s ? %s", path, q);

	if (!strcmp(path, "/lv")) handle_lv(fd, query_get(q, "low", v1, sizeof v1)[0] == '1');
	else if (!strcmp(path, "/fb")) handle_fb(fd);
	else if (!strcmp(path, "/osd")) handle_osd(fd);
	else if (!strcmp(path, "/key")) { query_get(q, "k", v1, sizeof v1); query_get(q, "a", v2, sizeof v2); handle_key(fd, v1, v2[0] ? v2 : "click"); }
	else if (!strcmp(path, "/run")) handle_run(fd, query_get(q, "s", v1, sizeof v1));
	else if (!strcmp(path, "/status")) handle_status(fd);
	else if (!strcmp(path, "/actions")) { char p2[1024]; snprintf(p2, sizeof p2, "%s/actions.list", scripts); handle_static_path(fd, p2, "text/plain; charset=utf-8"); }
	else if (!strcmp(path, "/dcim")) handle_dcim(fd);
	else if (!strncmp(path, "/dcim/", 6)) handle_file(fd, path + 6, query_get(q, "thumb", v1, sizeof v1)[0] == '1');
	else handle_static(fd, path + 1);
}

int main(int argc, char **argv)
{
	int port = 80, opt, ls, one = 1;
	struct sockaddr_in sa;
	while ((opt = getopt(argc, argv, "p:r:s:d")) != -1) {
		if (opt == 'p') port = atoi(optarg);
		else if (opt == 'r') webroot = optarg;
		else if (opt == 's') scripts = optarg;
		else if (opt == 'd') debug = 1;
		else { fprintf(stderr, "nxweb [-p port] [-r webroot] [-s scripts] [-d]\n"); return 1; }
	}
	signal(SIGPIPE, SIG_IGN);
	signal(SIGCHLD, SIG_IGN);
	lv_init();
	ls = socket(AF_INET, SOCK_STREAM, 0);
	setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
	memset(&sa, 0, sizeof sa);
	sa.sin_family = AF_INET; sa.sin_port = htons(port); sa.sin_addr.s_addr = htonl(INADDR_ANY);
	if (bind(ls, (struct sockaddr *)&sa, sizeof sa) < 0) { perror("bind"); return 1; }
	if (listen(ls, 8) < 0) { perror("listen"); return 1; }
	logf_("nxweb listening on %d, root %s", port, webroot);
	for (;;) {
		int fd = accept(ls, NULL, NULL);
		if (fd < 0) { if (errno == EINTR) continue; perror("accept"); break; }
		setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
		handle(fd);
		close(fd);
	}
	return 0;
}
