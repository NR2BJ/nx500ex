/*
 * nxwake: 카메라 키가 눌릴 때까지 기다린다 (화면 끄기용). 사용: nxwake [무시할 처음 ms (기본 500)] [최대 대기 초 (0 = 무한)]
 * /dev/input/event0, event1 (nxkeys 가 읽는 같은 장치) 에서 EV_KEY 누름 (value 1) 이 오면 0 으로 끝난다. 시간이 다 되면 1.
 * 처음 얼마 동안은 무시한다 (이 프로그램을 띄운 키의 떼기 이벤트에 바로 깨지 않게).
 */
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>
#include <unistd.h>
#include <linux/input.h>

static long now_ms(void) { struct timeval tv; gettimeofday(&tv, NULL); return tv.tv_sec * 1000L + tv.tv_usec / 1000; }

int main(int argc, char **argv)
{
	long grace = argc > 1 ? atol(argv[1]) : 500, limit = argc > 2 ? atol(argv[2]) * 1000L : 0, t0 = now_ms();
	struct pollfd p[2];
	int i;
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
					if (argc > 3) printf("key %d\n", ev.code);
					return 0;
				}
			}
		}
	}
}
