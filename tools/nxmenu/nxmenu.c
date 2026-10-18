/*
 * nxmenu: nx500ex 메뉴 (NX500, 720x480 터치 화면)
 *
 * NX-KS 의 mod_gui (ottokiksmaler/nx500_nx1_modding, AGPL-3.0) 의 화면 구성과 키 처리를 바탕으로 새로 작성했다.
 * mod_gui 와 다른 점:
 *   - 하위 화면으로 갈 때 창을 새로 만든다 (mod_gui 는 같은 창의 표를 지우고 다시 그려 이전 화면이 비치고 눌리는 위치가 어긋났다)
 *   - 체크박스와 keep 항목은 눌러도 메뉴가 닫히지 않는다
 *   - 칸 크기가 모든 화면에서 같다 (2열 x 5행). 마지막 행은 왼쪽 뒤로, 오른쪽 닫기로 고정
 *   - 라벨의 < > & 를 그대로 표시한다 (EFL 마크업으로 해석되지 않게 바꿔 넣는다)
 *
 * 사용법: nxmenu <scripts 폴더> [화면 이름]     화면 파일은 <scripts>/<화면 이름>.NX500
 *
 * 화면 파일 형식 (한 줄에 하나, 빈 줄과 # 줄은 무시. 항목은 최대 8개, 왼쪽부터 두 개씩 한 행)
 *   button|라벨|스크립트     스크립트를 실행하고 메뉴를 닫는다 (촬영, 정보 팝업 등)
 *   keep|라벨|스크립트       메뉴를 숨기고 스크립트가 끝날 때까지 기다린 뒤 메뉴를 다시 보인다 (입력 창 등)
 *   checkbox|라벨|스크립트   켜면 스크립트를 scripts/auto 에 복사하고 실행, 끄면 지우고 off_스크립트 실행. 메뉴는 그대로
 *   page|라벨|화면 이름      하위 화면으로 이동
 *   ip|라벨                  라벨 뒤에 지금 WiFi IP 를 붙여 표시 (누르면 다시 읽음)
 *   blank                    빈 칸
 *   back|화면 이름           (항목 아님) 마지막 행 왼쪽 "뒤로" 가 갈 화면. 없으면 빈 칸
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include "efl_min.h"

#define SCREEN_W 720
#define SCREEN_H 480
#define COLS 2
#define ROWS 5
#define CELL_W (SCREEN_W / COLS)
#define CELL_H (SCREEN_H / ROWS)
#define MAX_ITEMS ((ROWS - 1) * COLS)
#define PIDFILE "/tmp/nx500ex-menu.pid"
#define LASTFILE "/tmp/nx500ex-menu.last"

enum { T_BUTTON, T_KEEP, T_CHECK, T_PAGE, T_IP, T_BLANK, T_BACK, T_CLOSE };

typedef struct {
	int type;
	char label[128];
	char arg[256];
	Evas_Object *obj; /* 체크박스 또는 버튼 */
} Item;

static char scripts[512];
static char page[256];
static char back_page[256];
static Item items[MAX_ITEMS + 2];
static int n_items;
static Evas_Object *win;

static void close_menu(void);

/* EFL 마크업으로 해석되지 않게 < > & 를 바꾼다 */
static void escape_label(const char *in, char *out, size_t size)
{
	size_t o = 0;
	for (; *in && o + 6 < size; in++) {
		const char *rep = NULL;
		if (*in == '<') rep = "&lt;";
		else if (*in == '>') rep = "&gt;";
		else if (*in == '&') rep = "&amp;";
		if (rep) { strcpy(out + o, rep); o += strlen(rep); }
		else out[o++] = *in;
	}
	out[o] = 0;
}

static void run_bg(const char *script)
{
	char cmd[1024];
	if (script[0] == '/') snprintf(cmd, sizeof cmd, "sh %s < /dev/null > /dev/null 2>&1 &", script);
	else snprintf(cmd, sizeof cmd, "sh %s/%s < /dev/null > /dev/null 2>&1 &", scripts, script);
	if (system(cmd) == -1) perror("system");
}

static void run_fg(const char *script)
{
	char cmd[1024];
	if (script[0] == '/') snprintf(cmd, sizeof cmd, "sh %s < /dev/null > /dev/null 2>&1", script);
	else snprintf(cmd, sizeof cmd, "sh %s/%s < /dev/null > /dev/null 2>&1", scripts, script);
	if (system(cmd) == -1) perror("system");
}

static int file_copy(const char *from, const char *to)
{
	char buf[4096];
	int in = open(from, O_RDONLY), out, n, ok = 1;
	if (in < 0) return -1;
	out = open(to, O_WRONLY | O_CREAT | O_TRUNC, 0755);
	if (out < 0) { close(in); return -1; }
	while ((n = read(in, buf, sizeof buf)) > 0)
		if (write(out, buf, n) != n) { ok = 0; break; }
	close(in);
	close(out);
	return ok ? 0 : -1;
}

static void get_ip(char *out, size_t size)
{
	struct ifaddrs *ifa, *p;
	snprintf(out, size, "WiFi 미연결");
	if (getifaddrs(&ifa) != 0) return;
	for (p = ifa; p; p = p->ifa_next) {
		if (!p->ifa_addr || p->ifa_addr->sa_family != AF_INET) continue;
		/* WiFi 만 (mlan0 등). USB 등 다른 연결은 표시하지 않는다 */
		if (strncmp(p->ifa_name, "mlan", 4) != 0 && strncmp(p->ifa_name, "wlan", 4) != 0) continue;
		snprintf(out, size, "%s", inet_ntoa(((struct sockaddr_in *)p->ifa_addr)->sin_addr));
		break;
	}
	freeifaddrs(ifa);
}

static void set_text(Evas_Object *obj, const char *text)
{
	char esc[512];
	escape_label(text, esc, sizeof esc);
	elm_object_part_text_set(obj, NULL, esc);
}


static int load_page(const char *name)
{
	char path[640], line[512];
	FILE *f;
	snprintf(path, sizeof path, "%s/%s.NX500", scripts, name);
	f = fopen(path, "r");
	if (!f) {
		snprintf(path, sizeof path, "%s/%s", scripts, name);
		f = fopen(path, "r");
	}
	if (!f) { fprintf(stderr, "nxmenu: no page %s\n", name); return -1; }
	n_items = 0;
	back_page[0] = 0;
	while (fgets(line, sizeof line, f)) {
		char *type, *label, *arg;
		line[strcspn(line, "\r\n")] = 0;
		if (!line[0] || line[0] == '#') continue;
		type = strtok(line, "|");
		label = strtok(NULL, "|");
		arg = strtok(NULL, "|");
		if (!type) continue;
		if (strcmp(type, "back") == 0) {
			if (label) snprintf(back_page, sizeof back_page, "%s", label);
			continue;
		}
		if (n_items >= MAX_ITEMS) continue;
		Item *it = &items[n_items];
		memset(it, 0, sizeof *it);
		if (strcmp(type, "button") == 0) it->type = T_BUTTON;
		else if (strcmp(type, "keep") == 0) it->type = T_KEEP;
		else if (strcmp(type, "checkbox") == 0) it->type = T_CHECK;
		else if (strcmp(type, "page") == 0) it->type = T_PAGE;
		else if (strcmp(type, "ip") == 0) it->type = T_IP;
		else if (strcmp(type, "blank") == 0) it->type = T_BLANK;
		else continue;
		snprintf(it->label, sizeof it->label, "%s", label ? label : "");
		snprintf(it->arg, sizeof it->arg, "%s", arg ? arg : "");
		n_items++;
	}
	fclose(f);
	return 0;
}

static void show_page(const char *name);

/* 화면 전환은 버튼 콜백이 끝난 뒤에 한다 (콜백 안에서 그 버튼이 속한 창을 지우지 않도록) */
static char pending[256];
static void switch_job(void *data)
{
	(void)data;
	show_page(pending);
}
static void switch_later(const char *name)
{
	snprintf(pending, sizeof pending, "%s", name);
	ecore_job_add(switch_job, NULL);
}

static void on_click(void *data, Evas_Object *obj, void *ev)
{
	Item *it = data;
	(void)obj; (void)ev;
	switch (it->type) {
	case T_BUTTON:
		evas_object_hide(win);
		ecore_main_loop_iterate();
		run_bg(it->arg);
		close_menu();
		break;
	case T_KEEP:
		/* 입력 창 등이 메뉴에 가리지 않게 메뉴를 숨기고, 스크립트가 끝나면 다시 보인다 */
		evas_object_hide(win);
		ecore_main_loop_iterate();
		run_fg(it->arg);
		evas_object_show(win);
		break;
	case T_PAGE:
		switch_later(it->arg);
		break;
	case T_BACK:
		switch_later(back_page);
		break;
	case T_CLOSE:
		close_menu();
		break;
	case T_IP:
		/* 라벨을 그린 뒤 글자를 바꾸면 폭 계산이 틀어져 ... 으로 잘리므로 화면을 다시 그린다 */
		switch_later(page);
		break;
	}
}

static void on_check(void *data, Evas_Object *obj, void *ev)
{
	Item *it = data;
	char src[640], dst[640], off[640];
	(void)ev;
	snprintf(src, sizeof src, "%s/%s", scripts, it->arg);
	snprintf(dst, sizeof dst, "%s/auto/%s", scripts, it->arg);
	snprintf(off, sizeof off, "%s/off_%s", scripts, it->arg);
	if (elm_check_state_get(obj)) {
		if (file_copy(src, dst) != 0) { elm_check_state_set(obj, EINA_FALSE); return; }
		sync();
		run_bg(src);
	} else {
		if (unlink(dst) != 0) { elm_check_state_set(obj, EINA_TRUE); return; }
		sync();
		if (access(off, R_OK) == 0) run_bg(off);
	}
}

/* 칸 하나: 테두리 사각형 + 바탕 사각형 + 투명 버튼 (+ 체크) . mod_gui 와 같은 모양 */
static void add_cell(Evas_Object *table, Item *it, int col, int row)
{
	Evas *e = evas_object_evas_get(table);
	Evas_Object *edge = evas_object_rectangle_add(e), *bg = evas_object_rectangle_add(e), *btn;
	evas_object_size_hint_min_set(edge, CELL_W, CELL_H);
	evas_object_color_set(edge, 20, 30, 40, 255);
	evas_object_show(edge);
	elm_table_pack(table, edge, col, row, 1, 1);
	evas_object_size_hint_min_set(bg, CELL_W - 2, CELL_H - 2);
	if (it->type == T_BLANK) evas_object_color_set(bg, 20, 30, 40, 255);
	else evas_object_color_set(bg, 40, 60, 80, 255);
	evas_object_show(bg);
	elm_table_pack(table, bg, col, row, 1, 1);
	if (it->type == T_BLANK) return;

	btn = elm_button_add(table);
	elm_object_style_set(btn, "transparent");
	if (it->type == T_IP) {
		char ip[64], text[256];
		get_ip(ip, sizeof ip);
		snprintf(text, sizeof text, "%s %s", it->label, ip);
		set_text(btn, text);
	} else
		set_text(btn, it->label);
	evas_object_show(btn);
	evas_object_size_hint_min_set(btn, CELL_W, CELL_H);
	elm_table_pack(table, btn, col, row, 1, 1);
	it->obj = btn;

	if (it->type == T_CHECK) {
		char autop[640];
		Evas_Object *chk = elm_check_add(table);
		elm_object_style_set(chk, "transparent");
		evas_object_size_hint_min_set(chk, CELL_W, CELL_H);
		snprintf(autop, sizeof autop, "%s/auto/%s", scripts, it->arg);
		elm_check_state_set(chk, access(autop, F_OK) == 0 ? EINA_TRUE : EINA_FALSE);
		evas_object_show(chk);
		elm_table_pack(table, chk, col, row, 1, 1);
		evas_object_smart_callback_add(chk, "changed", on_check, it);
		it->obj = chk;
	} else {
		evas_object_smart_callback_add(btn, "clicked", on_click, it);
	}
}

static void show_page(const char *name)
{
	Evas_Object *old = win, *bg, *table;
	static char cur[256];
	int i;
	FILE *f;

	snprintf(cur, sizeof cur, "%s", name);
	if (load_page(cur) != 0) return;
	snprintf(page, sizeof page, "%s", cur);
	f = fopen(LASTFILE, "w");
	if (f) { fprintf(f, "%s\n", page); fclose(f); }

	win = elm_win_add(NULL, "nxmenu", ELM_WIN_DIALOG_BASIC);
	evas_object_smart_callback_add(win, "delete,request", (Evas_Smart_Cb)close_menu, NULL);
	bg = evas_object_rectangle_add(evas_object_evas_get(win));
	evas_object_color_set(bg, 0, 0, 0, 255);
	elm_win_resize_object_add(win, bg);
	evas_object_show(bg);
	table = elm_table_add(win);
	elm_win_resize_object_add(win, table);

	for (i = 0; i < MAX_ITEMS; i++) {
		static Item blank = { T_BLANK };
		add_cell(table, i < n_items ? &items[i] : &blank, i % COLS, i / COLS);
	}
	/* 마지막 행: 왼쪽 뒤로, 오른쪽 닫기 */
	items[MAX_ITEMS].type = back_page[0] ? T_BACK : T_BLANK;
	snprintf(items[MAX_ITEMS].label, sizeof items[MAX_ITEMS].label, "< 뒤로");
	add_cell(table, &items[MAX_ITEMS], 0, ROWS - 1);
	items[MAX_ITEMS + 1].type = T_CLOSE;
	snprintf(items[MAX_ITEMS + 1].label, sizeof items[MAX_ITEMS + 1].label, "닫기");
	add_cell(table, &items[MAX_ITEMS + 1], 1, ROWS - 1);

	evas_object_show(table);
	evas_object_move(win, 0, 0);
	evas_object_resize(win, SCREEN_W, SCREEN_H);
	evas_object_show(win);
	if (old) evas_object_del(old);
}

static void close_menu(void)
{
	if (win) evas_object_hide(win);
	ecore_main_loop_iterate();
	unlink(PIDFILE);
	elm_exit();
	exit(0);
}

/* 하드웨어 키: mod_gui 와 같게 모드 다이얼, 드라이브 키는 카메라에 넘기고, 그 밖의 키는 메뉴를 닫는다 */
static Eina_Bool on_key(void *data, int type, void *event)
{
	const char *key = ((Ecore_Event_Key_Head *)event)->key;
	static const char *modes[][2] = {
		{"F6", "smart"}, {"F7", "p"}, {"F8", "a"}, {"F9", "s"}, {"F10", "m"},
		{"KP_Home", "custom1"}, {"Scroll_Lock", "custom2"}, {NULL, NULL}};
	static const char *drives[][2] = {
		{"Hiragana", "conti_n"}, {"Muhenkan", "conti_h"}, {"Control_R", "timer"},
		{"Alt_R", "bracket"}, {"Katakana", "single"}, {NULL, NULL}};
	char cmd[128];
	int i;
	(void)data; (void)type;
	if (!key) return ECORE_CALLBACK_PASS_ON;
	if (strcmp(key, "XF86Reload") == 0 || strcmp(key, "XF86WWW") == 0 || strcmp(key, "KP_Enter") == 0)
		return ECORE_CALLBACK_PASS_ON;
	evas_object_hide(win);
	ecore_main_loop_iterate();
	if (strcmp(key, "XF86PowerOff") == 0 && system("st key click pwoff") == -1) perror("system");
	for (i = 0; modes[i][0]; i++)
		if (strcmp(key, modes[i][0]) == 0) {
			snprintf(cmd, sizeof cmd, "/usr/bin/st key mode %s", modes[i][1]);
			if (system(cmd) == -1) perror("system");
		}
	for (i = 0; drives[i][0]; i++)
		if (strcmp(key, drives[i][0]) == 0) {
			snprintf(cmd, sizeof cmd, "/usr/bin/st key drive %s", drives[i][1]);
			if (system(cmd) == -1) perror("system");
		}
	close_menu();
	return ECORE_CALLBACK_PASS_ON;
}

/* 이미 떠 있는 nxmenu 는 닫는다 (한 번에 하나만) */
static void single_instance(void)
{
	FILE *f = fopen(PIDFILE, "r");
	int pid = 0;
	if (f) {
		if (fscanf(f, "%d", &pid) != 1) pid = 0;
		fclose(f);
	}
	if (pid > 0 && pid != getpid()) {
		char comm[64] = "", path[64];
		snprintf(path, sizeof path, "/proc/%d/comm", pid);
		f = fopen(path, "r");
		if (f) {
			if (!fgets(comm, sizeof comm, f)) comm[0] = 0;
			fclose(f);
		}
		if (strncmp(comm, "nxmenu", 6) == 0) kill(pid, SIGTERM);
	}
	f = fopen(PIDFILE, "w");
	if (f) { fprintf(f, "%d\n", getpid()); fclose(f); }
}

int main(int argc, char **argv)
{
	if (argc < 2) {
		fprintf(stderr, "usage: %s <scripts dir> [page]\n", argv[0]);
		return 1;
	}
	snprintf(scripts, sizeof scripts, "%s", argv[1]);
	if (scripts[strlen(scripts) - 1] == '/') scripts[strlen(scripts) - 1] = 0;
	/* 메뉴에서 실행되는 스크립트용 표시 */
	setenv("NX500EX_MENU", "1", 1);
	unsetenv("NX500EX_PAGE");
	single_instance();
	elm_init(argc, argv);
	ecore_event_handler_add(ECORE_EVENT_KEY_DOWN, on_key, NULL);
	show_page(argc > 2 ? argv[2] : "gui_ini");
	if (!win) { unlink(PIDFILE); return 1; }
	elm_run();
	elm_shutdown();
	unlink(PIDFILE);
	return 0;
}
