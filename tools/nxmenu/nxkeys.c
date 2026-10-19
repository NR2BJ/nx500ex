/*
 * nxkeys: nx500ex 키 감지 (keyscan 대체)
 *
 * ottokiksmaler/nx500_nx1_modding 의 keyscan.c (AGPL-3.0) 를 바탕으로 새로 작성했다.
 * 사용법: nxkeys <입력 장치0> <입력 장치1> <scripts 폴더> [debug]
 *
 * 키 이벤트마다 <scripts>/<이름>.sh 가 있으면 sh 로 실행한다 (기다리지 않음, 백그라운드).
 *   EV_<키>.sh       EV 를 누른 채 그 키를 누름. EV 를 계속 누르고 있으면 반복해서 쓸 수 있다 (NX-KS keyscan 빌드와 같음)
 *   <키>_<키>.sh     같은 키를 1초 안에 두 번 누름
 *   <키>_PRESS.sh    누르는 순간
 *   <키>_RELEASE.sh  떼는 순간
 *   <키>_LONG.sh     0.8초 이상 누르고 있음 (누르고 있는 동안 한 번)
 *   MODE_SAS.sh      모드 다이얼이 SAS 를 벗어남 (상류와 같음)
 * 키 이름: EV OK PB FN DEL UP DOWN LEFT RIGHT AEL MOBILE S1 S2 MODE_SAS MODE_SCENE MODE_AUTO MODE_P MODE_A MODE_S MODE_M MODE_C
 *
 * 시작할 때 <scripts>/auto 의 .sh 를 이름 순서로 차례대로 실행한다 (끝날 때까지 기다림).
 * 상류 keyscan 과 달리 스크립트를 기다리지 않아, 스크립트가 도는 동안에도 키를 놓치지 않는다.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <glob.h>
#include <sys/time.h>
#include <sys/select.h>
#include <linux/input.h>

#define LONG_MS 800
#define DOUBLE_MS 1000
#define KEY_EV 173
#define KEY_SAS 59

static const char *keyname[256];
static char scripts[512];
static int debug;

static long ms_of(const struct timeval *t) { return t->tv_sec * 1000L + t->tv_usec / 1000; }
static long now_ms(void)
{
	struct timeval t;
	gettimeofday(&t, NULL);
	return ms_of(&t);
}

/* <scripts>/<name>.sh 가 있으면 백그라운드로 실행 */
static void fire(const char *name)
{
	char path[640];
	pid_t pid;
	snprintf(path, sizeof path, "%s/%s.sh", scripts, name);
	if (access(path, R_OK) != 0) {
		if (debug) printf("no %s\n", path);
		return;
	}
	if (debug) printf("run %s\n", path);
	fflush(stdout);
	pid = fork();
	if (pid == 0) {
		setsid();
		execl("/bin/sh", "sh", path, (char *)NULL);
		_exit(127);
	}
}

static void run_auto(void)
{
	char pattern[640];
	glob_t g;
	size_t i;
	snprintf(pattern, sizeof pattern, "%s/auto/*.sh", scripts);
	if (glob(pattern, 0, NULL, &g) != 0) return;
	for (i = 0; i < g.gl_pathc; i++) {
		char cmd[800];
		if (debug) printf("auto %s\n", g.gl_pathv[i]);
		fflush(stdout);
		snprintf(cmd, sizeof cmd, "sh %s", g.gl_pathv[i]);
		if (system(cmd) == -1) perror("system");
	}
	globfree(&g);
}

static void init_names(void)
{
	int i;
	for (i = 0; i < 256; i++) keyname[i] = NULL;
	keyname[173] = "EV"; keyname[96] = "OK"; keyname[183] = "PB"; keyname[172] = "FN"; keyname[83] = "DEL";
	keyname[72] = "UP"; keyname[80] = "DOWN"; keyname[75] = "LEFT"; keyname[77] = "RIGHT";
	keyname[156] = "AEL"; keyname[215] = "MOBILE"; keyname[125] = "S1"; keyname[126] = "S2";
	keyname[59] = "MODE_SAS"; keyname[62] = "MODE_SCENE"; keyname[64] = "MODE_AUTO"; keyname[65] = "MODE_P";
	keyname[66] = "MODE_A"; keyname[67] = "MODE_S"; keyname[68] = "MODE_M"; keyname[71] = "MODE_C";
}

int main(int argc, char **argv)
{
	int fd[2], i, maxfd;
	long down_at[256];      /* 누른 시각 (0 = 안 눌림) */
	int long_done[256];     /* 이번 누름에서 LONG 을 이미 실행했는지 */
	int last_key = -1;      /* 두 번 누름 판정: 바로 앞에 누른 키와 시각 (상류와 같음) */
	long last_t = 0;
	int ev_held = 0;
	char name[128];

	if (argc < 4) {
		fprintf(stderr, "usage: %s <dev0> <dev1> <scripts dir> [debug]\n", argv[0]);
		return 1;
	}
	for (i = 4; i < argc; i++)
		if (strcmp(argv[i], "debug") == 0) debug = 1;
	snprintf(scripts, sizeof scripts, "%s", argv[3]);
	if (scripts[0] && scripts[strlen(scripts) - 1] == '/') scripts[strlen(scripts) - 1] = 0;
	init_names();
	memset(down_at, 0, sizeof down_at);
	memset(long_done, 0, sizeof long_done);

	fd[0] = open(argv[1], O_RDONLY);
	fd[1] = open(argv[2], O_RDONLY);
	if (fd[0] < 0 || fd[1] < 0) {
		fprintf(stderr, "cannot open input: %s\n", strerror(errno));
		return 1;
	}
	maxfd = fd[0] > fd[1] ? fd[0] : fd[1];
	if (debug) printf("nxkeys start %s\n", scripts);
	run_auto();
	signal(SIGCHLD, SIG_IGN);  /* 이후 키 스크립트는 종료를 기다리지 않음, 좀비 방지 (auto 는 위에서 차례로 기다림) */

	for (;;) {
		fd_set set;
		struct timeval tv, *tvp = NULL;
		long now = now_ms(), next = -1;
		struct input_event ev;
		int k, r;

		/* 길게 누르기 시각이 가장 가까운 키까지 기다린다 */
		for (k = 0; k < 256; k++)
			if (down_at[k] && !long_done[k] && keyname[k]) {
				long due = down_at[k] + LONG_MS;
				if (next < 0 || due < next) next = due;
			}
		if (next >= 0) {
			long wait = next - now;
			if (wait < 0) wait = 0;
			tv.tv_sec = wait / 1000;
			tv.tv_usec = (wait % 1000) * 1000;
			tvp = &tv;
		}
		FD_ZERO(&set);
		FD_SET(fd[0], &set);
		FD_SET(fd[1], &set);
		r = select(maxfd + 1, &set, NULL, NULL, tvp);
		if (r < 0) {
			if (errno == EINTR) continue;
			break;
		}

		/* 길게 누르기 */
		now = now_ms();
		for (k = 0; k < 256; k++)
			if (down_at[k] && !long_done[k] && keyname[k] && now - down_at[k] >= LONG_MS) {
				long_done[k] = 1;
				snprintf(name, sizeof name, "%s_LONG", keyname[k]);
				fire(name);
			}
		if (r == 0) continue;

		for (i = 0; i < 2; i++) {
			if (!FD_ISSET(fd[i], &set)) continue;
			if (read(fd[i], &ev, sizeof ev) != sizeof ev) continue;
			if (ev.type != EV_KEY || ev.code >= 256) continue;
			k = ev.code;
			if (debug) printf("key %d %s %d\n", k, keyname[k] ? keyname[k] : "?", ev.value);
			if (!keyname[k] || ev.value == 2) continue;   /* 모르는 키, 자동 반복 */
			if (ev.value == 1) {
				long t = now_ms();
				down_at[k] = t;
				long_done[k] = 0;
				snprintf(name, sizeof name, "%s_PRESS", keyname[k]);
				fire(name);
				if (k == KEY_EV) ev_held = 1;
				else if (ev_held) {
					snprintf(name, sizeof name, "EV_%s", keyname[k]);
					fire(name);
				}
				if (k == last_key && t - last_t < DOUBLE_MS) {
					snprintf(name, sizeof name, "%s_%s", keyname[k], keyname[k]);
					fire(name);
					last_key = -1;   /* 세 번째 누름이 다시 두 번으로 잡히지 않게 */
				} else {
					last_key = k;
					last_t = t;
				}
			} else if (ev.value == 0) {
				down_at[k] = 0;
				snprintf(name, sizeof name, "%s_RELEASE", keyname[k]);
				fire(name);
				if (k == KEY_EV) ev_held = 0;
				if (k == KEY_SAS) fire("MODE_SAS");
			}
			fflush(stdout);
		}
	}
	fprintf(stderr, "nxkeys: %s\n", strerror(errno));
	return 1;
}
