/*
 * nxkey: 카메라 키 장치 (/dev/input/event0 GPIO, event1 ADC) 에 진짜 키 이벤트를 써 넣는다 (evdev write = 커널 입력 코어로 주입).
 * st key 와 달리 물리 키와 같은 경로 (커널 -> X -> 카메라 앱) 로 들어가므로, st key 로 안 끝나던 BULB 의 셔터 떼기 등에 쓴다.
 *   nxkey <코드|이름> <1=누름|0=뗌>        한 이벤트 (두 장치 모두에 씀. 그 키를 모르는 장치는 커널이 버린다)
 *   nxkey tap <코드|이름> [누른 ms (기본 80)]
 *   nxkey hold <코드|이름> <ms>             누르고 ms 뒤 뗌 (벌브: hold s2 40000)
 * 이름: s1 s2 ok menu ev fn del up down left right pb ael mobile (nxkeys.c 의 코드와 같음)
 */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <linux/input.h>

static int code_of(const char *s)
{
	static const struct { const char *n; int c; } t[] = {
		{"ev", 173}, {"ok", 96}, {"pb", 183}, {"fn", 172}, {"del", 83}, {"up", 72}, {"down", 80}, {"left", 75}, {"right", 77},
		{"ael", 156}, {"mobile", 215}, {"wifi", 215}, {"s1", 125}, {"s2", 126}, {NULL, 0} };
	int i;
	for (i = 0; t[i].n; i++) if (!strcmp(t[i].n, s)) return t[i].c;
	return atoi(s);
}

static int fds[2];

static void emit(int type, int code, int value)
{
	struct input_event ev;
	int i;
	memset(&ev, 0, sizeof ev);
	ev.type = type; ev.code = code; ev.value = value;
	for (i = 0; i < 2; i++) if (fds[i] >= 0 && write(fds[i], &ev, sizeof ev) != (ssize_t)sizeof ev && getenv("NXKEY_DEBUG")) perror(i ? "event1 write" : "event0 write");
}

static void key(int code, int value) { emit(EV_KEY, code, value); emit(EV_SYN, SYN_REPORT, 0); }

int main(int argc, char **argv)
{
	int code, ms;
	if (argc < 3) { fprintf(stderr, "nxkey <code|name> <1|0> | tap <code|name> [ms] | hold <code|name> <ms>\n"); return 1; }
	fds[0] = open("/dev/input/event0", O_WRONLY);
	fds[1] = open("/dev/input/event1", O_WRONLY);
	if (fds[0] < 0 && fds[1] < 0) { perror("event0/1"); return 2; }
	if (!strcmp(argv[1], "tap")) {
		code = code_of(argv[2]); ms = argc > 3 ? atoi(argv[3]) : 80;
		key(code, 1); usleep(ms * 1000); key(code, 0);
	} else if (!strcmp(argv[1], "hold")) {
		if (argc < 4) return 1;
		code = code_of(argv[2]); ms = atoi(argv[3]);
		key(code, 1); usleep((useconds_t)ms * 1000); key(code, 0);
	} else {
		code = code_of(argv[1]);
		key(code, atoi(argv[2]));
	}
	return 0;
}
