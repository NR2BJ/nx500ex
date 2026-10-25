/*
 * nxwake: 카메라 키가 눌릴 때까지 기다린다 (화면 끄기, 벌브 중단용). 사용: nxwake [무시할 처음 ms (기본 500)] [최대 대기 초 (0 = 무한)] [v]
 * /dev/input/event0, event1 (nxkeys 가 읽는 같은 장치) 에서 EV_KEY 누름 (value 1) 이 오면 0 으로 끝난다. 시간이 다 되면 1.
 * 처음 얼마 동안은 무시한다 (이 프로그램을 띄운 키의 떼기 이벤트에 바로 깨지 않게).
 * 환경 NXWAKE_IGNORE="125,126" 처럼 주면 그 키 코드의 누름은 무시한다 (벌브가 GPIO 로 누르는 반셔터 125, 셔터 126).
 * 주의: 노출 중에 이 프로그램을 새로 띄우면 안 된다. 입력 장치를 여는 순간 키 드라이버가 GPIO 를 다시 입력으로 잡아 우리가 누른 셔터가
 *   떼진 것으로 보여 벌브가 1초 만에 끝났다 (2026-10-26 추정, 다음 실기에서 DIR 레지스터로 확인 예정). 누르기 전에 먼저 띄워 둔다.
 */
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>
#include <linux/input.h>

static long now_ms(void) { struct timeval tv; gettimeofday(&tv, NULL); return tv.tv_sec * 1000L + tv.tv_usec / 1000; }

int main(int argc, char **argv)
{
	long grace = argc > 1 ? atol(argv[1]) : 500, limit = argc > 2 ? atol(argv[2]) * 1000L : 0, t0 = now_ms();
	struct pollfd p[2];
	int i, ignore[16], nign = 0;
	const char *ig = getenv("NXWAKE_IGNORE");
	while (ig && *ig && nign < 16) { ignore[nign++] = atoi(ig); ig = strchr(ig, ','); if (ig) ig++; }
	p[0].fd = open("/dev/input/event0", O_RDONLY | O_NONBLOCK);
	p[1].fd = open("/dev/input/event1", O_RDONLY | O_NONBLOCK);
	if (p[0].fd < 0 && p[1].fd < 0) { perror("event0/1"); return 2; }
	p[0].events = p[1].events = POLLIN;
	for (;;) {
		int timeout = limit ? (int)(limit - (now_ms() - t0)) : -1;
		if (limit && timeout <= 0) return 1;
		if (poll(p, 2, timeout) <= 0) continue;
		for (i = 0; i < 2; i++) {
			struct input_event ev;
			if (p[i].fd < 0 || !(p[i].revents & POLLIN)) continue;
			while (read(p[i].fd, &ev, sizeof ev) == (ssize_t)sizeof ev) {
				if (ev.type == EV_KEY && ev.value == 1 && now_ms() - t0 >= grace) {
					int k, skip = 0;
					for (k = 0; k < nign; k++) if (ignore[k] == ev.code) skip = 1;
					if (skip) continue;
					if (argc > 3) printf("key %d\n", ev.code);
					return 0;
				}
			}
		}
	}
}
