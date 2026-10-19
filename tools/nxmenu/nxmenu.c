/*
 * nxmenu: nx500ex 메뉴 (NX500, 720x480 터치 화면)
 *
 * NX-KS 의 mod_gui (ottokiksmaler/nx500_nx1_modding, AGPL-3.0) 의 화면 구성과 키 처리를 바탕으로 새로 작성했다.
 * mod_gui 와 다른 점:
 *   - 칸 크기가 모든 화면에서 같다 (2열 x 5행). 마지막 행은 왼쪽 뒤로, 오른쪽 닫기로 고정.
 *     화면을 바꿔도 이전 화면 조각이 남지 않는다 (mod_gui 는 화면마다 칸 높이를 바꿔 이전 화면이 비치고 눌리는 위치가 어긋났다)
 *   - 창은 하나만 만들고 내용만 바꾼다 (화면 버퍼를 늘리지 않게). 동시에 하나만 실행
 *   - 체크박스, 화면 이동, 숫자 설정은 눌러도 메뉴가 닫히지 않는다
 *   - 숫자 설정 화면이 메뉴 안에 있다 (popup_entry 의 키패드는 처음 뜨는 데 오래 걸리고 터치음이 났다)
 *   - 라벨의 < > & 를 그대로 표시한다 (EFL 마크업으로 해석되지 않게 바꿔 넣는다)
 *
 * 사용법: nxmenu <scripts 폴더> [화면 이름]     화면 파일은 <scripts>/<화면 이름>.NX500, 숫자 설정은 <scripts>/../conf/<이름>
 *
 * 화면 파일 형식 (한 줄에 하나, 빈 줄과 # 줄은 무시. 항목은 최대 8개, 왼쪽부터 두 개씩 한 행)
 *   button|라벨|스크립트     스크립트를 실행하고 메뉴를 닫는다 (촬영, 정보 팝업 등)
 *   keep|라벨|스크립트       메뉴를 숨기고 스크립트가 끝날 때까지 기다린 뒤 메뉴를 다시 보인다
 *   checkbox|라벨|스크립트   켜면 스크립트를 scripts/auto 에 복사하고 실행, 끄면 지우고 off_스크립트 실행
 *   page|라벨|화면 이름      하위 화면으로 이동
 *   num|라벨|이름|최소|최대|기본|단위|단계|특수값
 *                            "라벨: 값단위" 로 보이고, 누르면 숫자 설정 화면.
 *                            단계는 쉼표로 최대 3개 (예: 1,5,10 -> -1 +1 / -5 +5 / -10 +10). 없으면 1,10
 *                            특수값은 "값:라벨" (예: 0:계속) -> 값 옆에 그 값으로 바로 바꾸는 버튼
 *   ip|라벨                  라벨 뒤에 지금 WiFi IP 를 붙여 표시 (누르면 다시 읽음)
 *   key|라벨|이벤트          키 할당. "라벨: 동작" 으로 보이고, 누르면 동작 고르기 화면 (scripts/actions.list 의 동작들).
 *                            고른 결과는 <scripts>/../conf/keymap 에 "이벤트=동작" 으로 저장 (nxkeys 가 읽는다)
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
#include <sys/stat.h>
#include "efl_min.h"

#define SCREEN_W 720
/* 창이 화면(480)을 다 덮으면 창 관리자가 카메라 앱을 "완전히 가려짐" 으로 보고 일시정지시킨다.
 * 그때 카메라 앱이 자기 화면을 캡처하다 Xorg 가 죽었다 (2026-10-19 실기, dlog: fully_obscured -> PAUSE -> Xorg SIGSEGV).
 * 그래서 높이를 420 으로 한다. 창 관리자가 대화상자 창을 가운데로 옮겨 위아래 30 픽셀씩 카메라 정보가 보인다
 * (위쪽 고정을 요청해도 받아들이지 않았고, 이 배치가 좋다는 사용자 판단으로 그대로 둔다. 2026-10-19). */
#define MENU_H 420
#define COLS 2
#define ROWS 5
#define CELL_W (SCREEN_W / COLS)
#define CELL_H (MENU_H / ROWS)
#define MAX_ITEMS ((ROWS - 1) * COLS)
#define PIDFILE "/tmp/nx500ex-menu.pid"
#define LASTFILE "/tmp/nx500ex-menu.last"

enum { T_BUTTON, T_KEEP, T_CHECK, T_PAGE, T_NUM, T_IP, T_BLANK, T_BACK, T_CLOSE, T_TEXT, T_STEP, T_OK, T_SPECIAL,
       T_KEY, T_CHOICE, T_MORE };

typedef struct {
	int type;
	char label[128];
	char arg[256];
	int min, max, def, step;
	char unit[32];
	int steps[3], n_steps;
	int special;
	char special_label[32];
	Evas_Object *obj;
} Item;

static char scripts[512];
static char page[256];
static char back_page[256];
static Item items[MAX_ITEMS + 2];
static int n_items;
static Evas_Object *win, *table;

/* 숫자 설정 화면 상태 */
static Item num_item;
static int num_value;

static void close_menu(void);
static void show_chooser(void);
static void show_page(const char *name);
static void show_number(void);

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

static void set_text(Evas_Object *obj, const char *text)
{
	char esc[512];
	escape_label(text, esc, sizeof esc);
	elm_object_part_text_set(obj, NULL, esc);
}

static void run_cmd(const char *script, int background)
{
	char cmd[1024];
	snprintf(cmd, sizeof cmd, "sh %s%s%s < /dev/null > /dev/null 2>&1%s",
		 script[0] == '/' ? "" : scripts, script[0] == '/' ? "" : "/", script, background ? " &" : "");
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

/* 숫자 설정 값: <scripts>/../conf/<이름> */
static void conf_path(const char *name, char *out, size_t size)
{
	snprintf(out, size, "%s/../conf/%s", scripts, name);
}

static int conf_read(Item *it)
{
	char path[640];
	FILE *f;
	int v = it->def;
	conf_path(it->arg, path, sizeof path);
	f = fopen(path, "r");
	if (f) {
		if (fscanf(f, "%d", &v) != 1) v = it->def;
		fclose(f);
	}
	if (v < it->min || v > it->max) v = it->def;
	return v;
}

static void conf_write(Item *it, int v)
{
	char path[640];
	FILE *f;
	snprintf(path, sizeof path, "%s/../conf", scripts);
	mkdir(path, 0755);
	conf_path(it->arg, path, sizeof path);
	f = fopen(path, "w");
	if (f) { fprintf(f, "%d\n", v); fclose(f); }
	sync();
}

/* ---- 키 할당: <scripts>/actions.list (동작|라벨), <scripts>/../conf/keymap (이벤트=동작) ---- */
#define MAX_ACTIONS 40
static char act_id[MAX_ACTIONS][64], act_label[MAX_ACTIONS][128];
static int n_actions = -1;

static void load_actions(void)
{
	char path[640], line[256];
	FILE *f;
	if (n_actions >= 0) return;
	n_actions = 0;
	snprintf(path, sizeof path, "%s/actions.list", scripts);
	f = fopen(path, "r");
	if (!f) return;
	while (n_actions < MAX_ACTIONS && fgets(line, sizeof line, f)) {
		char *bar;
		line[strcspn(line, "\r\n")] = 0;
		if (!line[0] || line[0] == '#' || !(bar = strchr(line, '|'))) continue;
		*bar = 0;
		snprintf(act_id[n_actions], sizeof act_id[0], "%s", line);
		snprintf(act_label[n_actions], sizeof act_label[0], "%s", bar + 1);
		n_actions++;
	}
	fclose(f);
}

static const char *action_label(const char *id)
{
	int i;
	load_actions();
	for (i = 0; i < n_actions; i++)
		if (strcmp(act_id[i], id) == 0) return act_label[i];
	return id;
}

/* 이벤트에 할당된 동작 id. 없으면 "" */
static void keymap_get(const char *event, char *out, size_t size)
{
	char path[640], line[256];
	size_t n = strlen(event);
	FILE *f;
	out[0] = 0;
	snprintf(path, sizeof path, "%s/../conf/keymap", scripts);
	f = fopen(path, "r");
	if (!f) return;
	while (fgets(line, sizeof line, f)) {
		line[strcspn(line, "\r\n")] = 0;
		if (strncmp(line, event, n) == 0 && line[n] == '=') { snprintf(out, size, "%s", line + n + 1); break; }
	}
	fclose(f);
}

/* 이벤트의 동작을 바꾼다 (id 가 "none" 이면 지운다) */
static void keymap_set(const char *event, const char *id)
{
	char path[640], tmp[660], line[256];
	size_t n = strlen(event);
	FILE *in, *out;
	snprintf(path, sizeof path, "%s/../conf", scripts);
	mkdir(path, 0755);
	snprintf(path, sizeof path, "%s/../conf/keymap", scripts);
	snprintf(tmp, sizeof tmp, "%s.new", path);
	out = fopen(tmp, "w");
	if (!out) return;
	in = fopen(path, "r");
	if (in) {
		while (fgets(line, sizeof line, in)) {
			if (strncmp(line, event, n) == 0 && line[n] == '=') continue;
			fputs(line, out);
		}
		fclose(in);
	}
	if (strcmp(id, "none") != 0) fprintf(out, "%s=%s\n", event, id);
	fclose(out);
	rename(tmp, path);
	sync();
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
		char *field[10];
		int nf = 0;
		char *p = line;
		line[strcspn(line, "\r\n")] = 0;
		if (!line[0] || line[0] == '#') continue;
		while (nf < 10) {
			field[nf++] = p;
			p = strchr(p, '|');
			if (!p) break;
			*p++ = 0;
		}
		if (strcmp(field[0], "back") == 0) {
			if (nf > 1) snprintf(back_page, sizeof back_page, "%s", field[1]);
			continue;
		}
		if (n_items >= MAX_ITEMS) continue;
		Item *it = &items[n_items];
		memset(it, 0, sizeof *it);
		if (strcmp(field[0], "button") == 0) it->type = T_BUTTON;
		else if (strcmp(field[0], "keep") == 0) it->type = T_KEEP;
		else if (strcmp(field[0], "checkbox") == 0) it->type = T_CHECK;
		else if (strcmp(field[0], "page") == 0) it->type = T_PAGE;
		else if (strcmp(field[0], "num") == 0) it->type = T_NUM;
		else if (strcmp(field[0], "ip") == 0) it->type = T_IP;
		else if (strcmp(field[0], "key") == 0) it->type = T_KEY;
		else if (strcmp(field[0], "blank") == 0) it->type = T_BLANK;
		else continue;
		snprintf(it->label, sizeof it->label, "%s", nf > 1 ? field[1] : "");
		snprintf(it->arg, sizeof it->arg, "%s", nf > 2 ? field[2] : "");
		if (it->type == T_NUM) {
			it->min = nf > 3 ? atoi(field[3]) : 0;
			it->max = nf > 4 ? atoi(field[4]) : 100;
			it->def = nf > 5 ? atoi(field[5]) : it->min;
			snprintf(it->unit, sizeof it->unit, "%s", nf > 6 ? field[6] : "");
			it->n_steps = 0;
			if (nf > 7 && field[7][0]) {
				char *q = field[7];
				while (it->n_steps < 3 && q && *q) {
					it->steps[it->n_steps++] = atoi(q);
					q = strchr(q, ',');
					if (q) q++;
				}
			}
			if (it->n_steps == 0) { it->steps[0] = 1; it->steps[1] = 10; it->n_steps = 2; }
			it->special = -1;
			if (nf > 8 && strchr(field[8], ':')) {
				it->special = atoi(field[8]);
				snprintf(it->special_label, sizeof it->special_label, "%s", strchr(field[8], ':') + 1);
			}
		}
		n_items++;
	}
	fclose(f);
	return 0;
}

/* 화면 전환은 버튼 콜백이 끝난 뒤에 한다 (콜백 안에서 그 버튼을 지우지 않도록) */
static char pending[256];
static int pending_number;
/* 키 할당 고르기 화면 상태 */
static Item key_item;
static int chooser_start;

static void switch_job(void *data)
{
	(void)data;
	if (pending_number == 2) show_chooser();
	else if (pending_number) show_number();
	else show_page(pending);
}
static void switch_later(const char *name)
{
	snprintf(pending, sizeof pending, "%s", name);
	pending_number = 0;
	ecore_job_add(switch_job, NULL);
}

/* "라벨: 값단위". 특수값이면 "라벨: 특수값 라벨" */
static void value_text(Item *it, int v, char *out, size_t size)
{
	if (it->special >= 0 && v == it->special)
		snprintf(out, size, "%s: %s", it->label, it->special_label);
	else
		snprintf(out, size, "%s: %d%s", it->label, v, it->unit);
}

static void on_click(void *data, Evas_Object *obj, void *ev)
{
	Item *it = data;
	(void)obj; (void)ev;
	switch (it->type) {
	case T_BUTTON:
		evas_object_hide(win);
		ecore_main_loop_iterate();
		run_cmd(it->arg, 1);
		close_menu();
		break;
	case T_KEEP:
		/* 스크립트가 띄우는 창이 메뉴에 가리지 않게 메뉴를 숨기고, 끝나면 다시 보인다 */
		evas_object_hide(win);
		ecore_main_loop_iterate();
		run_cmd(it->arg, 0);
		evas_object_show(win);
		break;
	case T_PAGE:
		switch_later(it->arg);
		break;
	case T_NUM:
		num_item = *it;
		num_value = conf_read(it);
		pending_number = 1;
		ecore_job_add(switch_job, NULL);
		break;
	/* 값 글자를 바꾸면 영문이 섞인 라벨이 ... 으로 잘리므로(EFL) 숫자 화면을 새로 그린다 */
	case T_SPECIAL:
		num_value = num_item.special;
		pending_number = 1;
		ecore_job_add(switch_job, NULL);
		break;
	case T_STEP:
		num_value += it->step;
		if (num_value < num_item.min) num_value = num_item.min;
		if (num_value > num_item.max) num_value = num_item.max;
		pending_number = 1;
		ecore_job_add(switch_job, NULL);
		break;
	case T_OK:
		conf_write(&num_item, num_value);
		switch_later(page);
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
	case T_KEY:
		key_item = *it;
		chooser_start = 0;
		pending_number = 2;
		ecore_job_add(switch_job, NULL);
		break;
	case T_MORE:
		chooser_start = it->step;
		pending_number = 2;
		ecore_job_add(switch_job, NULL);
		break;
	case T_CHOICE:
		keymap_set(key_item.arg, it->arg);
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
		run_cmd(src, 1);
	} else {
		if (unlink(dst) != 0) { elm_check_state_set(obj, EINA_TRUE); return; }
		sync();
		if (access(off, R_OK) == 0) run_cmd(off, 1);
	}
}

/* 칸 하나: 테두리 사각형 + 바탕 사각형 + 투명 버튼 (+ 체크). mod_gui 와 같은 모양. span 은 차지하는 열 수 */
static Evas_Object *add_cell(Item *it, int col, int row, int span)
{
	Evas *e = evas_object_evas_get(table);
	Evas_Object *edge = evas_object_rectangle_add(e), *bg = evas_object_rectangle_add(e), *btn;
	char text[256];
	int w = CELL_W * span;

	evas_object_size_hint_min_set(edge, w, CELL_H);
	evas_object_color_set(edge, 20, 30, 40, 255);
	evas_object_show(edge);
	elm_table_pack(table, edge, col, row, span, 1);
	evas_object_size_hint_min_set(bg, w - 2, CELL_H - 2);
	if (it->type == T_BLANK || it->type == T_TEXT) evas_object_color_set(bg, 20, 30, 40, 255);
	else evas_object_color_set(bg, 40, 60, 80, 255);
	evas_object_show(bg);
	elm_table_pack(table, bg, col, row, span, 1);
	if (it->type == T_BLANK) return NULL;

	btn = elm_button_add(table);
	elm_object_style_set(btn, "transparent");
	if (it->type == T_IP) {
		char ip[64];
		get_ip(ip, sizeof ip);
		snprintf(text, sizeof text, "%s %s", it->label, ip);
	} else if (it->type == T_NUM)
		value_text(it, conf_read(it), text, sizeof text);
	else if (it->type == T_KEY) {
		/* 키 이름과 동작을 두 줄로 (한 줄이면 "오른쪽 두 번: ..." 처럼 길어 잘린다) */
		char id[64], e1[256], e2[256];
		keymap_get(it->arg, id, sizeof id);
		escape_label(it->label, e1, sizeof e1);
		escape_label(id[0] ? action_label(id) : "-", e2, sizeof e2);
		snprintf(text, sizeof text, "%s<br>%s", e1, e2);
	}
	else
		snprintf(text, sizeof text, "%s", it->label);
	if (it->type == T_KEY) elm_object_part_text_set(btn, NULL, text);   /* 이미 바꿔 넣은 글 (<br> 유지) */
	else set_text(btn, text);
	evas_object_show(btn);
	evas_object_size_hint_min_set(btn, w, CELL_H);
	elm_table_pack(table, btn, col, row, span, 1);
	it->obj = btn;

	if (it->type == T_CHECK) {
		char autop[640];
		Evas_Object *chk = elm_check_add(table);
		elm_object_style_set(chk, "transparent");
		evas_object_size_hint_min_set(chk, w, CELL_H);
		snprintf(autop, sizeof autop, "%s/auto/%s", scripts, it->arg);
		elm_check_state_set(chk, access(autop, F_OK) == 0 ? EINA_TRUE : EINA_FALSE);
		evas_object_show(chk);
		elm_table_pack(table, chk, col, row, span, 1);
		evas_object_smart_callback_add(chk, "changed", on_check, it);
		it->obj = chk;
	} else if (it->type != T_TEXT)
		evas_object_smart_callback_add(btn, "clicked", on_click, it);
	return btn;
}

/* 창은 처음 한 번만 만든다 */
static void ensure_window(void)
{
	Evas_Object *bg;
	if (win) {
		elm_table_clear(table, EINA_TRUE);
		return;
	}
	win = elm_win_add(NULL, "nxmenu", ELM_WIN_DIALOG_BASIC);
	evas_object_smart_callback_add(win, "delete,request", (Evas_Smart_Cb)close_menu, NULL);
	bg = evas_object_rectangle_add(evas_object_evas_get(win));
	evas_object_color_set(bg, 0, 0, 0, 255);
	elm_win_resize_object_add(win, bg);
	evas_object_show(bg);
	table = elm_table_add(win);
	elm_win_resize_object_add(win, table);
	evas_object_move(win, 0, 0);
	evas_object_resize(win, SCREEN_W, MENU_H);
}

static void add_nav_row(int with_back)
{
	items[MAX_ITEMS].type = with_back ? T_BACK : T_BLANK;
	snprintf(items[MAX_ITEMS].label, sizeof items[MAX_ITEMS].label, "< 뒤로");
	add_cell(&items[MAX_ITEMS], 0, ROWS - 1, 1);
	items[MAX_ITEMS + 1].type = T_CLOSE;
	snprintf(items[MAX_ITEMS + 1].label, sizeof items[MAX_ITEMS + 1].label, "닫기");
	add_cell(&items[MAX_ITEMS + 1], 1, ROWS - 1, 1);
}

static void show_window(void)
{
	evas_object_show(table);
	evas_object_show(win);
}

static void show_page(const char *name)
{
	static char cur[256];
	static Item blank = { T_BLANK };
	int i;
	FILE *f;

	snprintf(cur, sizeof cur, "%s", name);
	if (load_page(cur) != 0) return;
	snprintf(page, sizeof page, "%s", cur);
	f = fopen(LASTFILE, "w");
	if (f) { fprintf(f, "%s\n", page); fclose(f); }

	ensure_window();
	for (i = 0; i < MAX_ITEMS; i++)
		add_cell(i < n_items ? &items[i] : &blank, i % COLS, i / COLS, 1);
	add_nav_row(back_page[0] != 0);
	show_window();
}

/* 숫자 설정 화면: 값 (+ 특수값 버튼) / 단계마다 -n +n 한 행 / 취소 확인 */
static void show_number(void)
{
	static Item text, steps[6], ok, cancel, special, blank = { T_BLANK };
	int i;

	ensure_window();
	/* 값 칸은 한 열만 쓴다 (두 열 칸에서는 글자를 바꾸면 ... 으로 잘렸다) */
	memset(&text, 0, sizeof text);
	text.type = T_TEXT;
	value_text(&num_item, num_value, text.label, sizeof text.label);
	add_cell(&text, 0, 0, 1);
	if (num_item.special >= 0) {
		memset(&special, 0, sizeof special);
		special.type = T_SPECIAL;
		snprintf(special.label, sizeof special.label, "%s", num_item.special_label);
		add_cell(&special, 1, 0, 1);
	} else
		add_cell(&blank, 1, 0, 1);
	for (i = 0; i < 3; i++) {
		int r = 1 + i;
		if (i >= num_item.n_steps) {
			add_cell(&blank, 0, r, 1);
			add_cell(&blank, 1, r, 1);
			continue;
		}
		memset(&steps[2 * i], 0, sizeof steps[0]);
		memset(&steps[2 * i + 1], 0, sizeof steps[0]);
		steps[2 * i].type = steps[2 * i + 1].type = T_STEP;
		steps[2 * i].step = -num_item.steps[i];
		steps[2 * i + 1].step = num_item.steps[i];
		snprintf(steps[2 * i].label, sizeof steps[0].label, "-%d", num_item.steps[i]);
		snprintf(steps[2 * i + 1].label, sizeof steps[0].label, "+%d", num_item.steps[i]);
		add_cell(&steps[2 * i], 0, r, 1);
		add_cell(&steps[2 * i + 1], 1, r, 1);
	}
	memset(&cancel, 0, sizeof cancel);
	cancel.type = T_PAGE;
	snprintf(cancel.label, sizeof cancel.label, "취소");
	snprintf(cancel.arg, sizeof cancel.arg, "%s", page);
	add_cell(&cancel, 0, ROWS - 1, 1);
	memset(&ok, 0, sizeof ok);
	ok.type = T_OK;
	snprintf(ok.label, sizeof ok.label, "확인");
	add_cell(&ok, 1, ROWS - 1, 1);
	show_window();
}

/* 동작 고르기 화면: 첫 칸 = 어느 키인지, 나머지 칸 = 동작들. 칸이 모자라면 마지막 칸이 "다음 >" (처음으로 돌아감) */
static void show_chooser(void)
{
	static Item title, choices[MAX_ITEMS], more, cancel, blank = { T_BLANK };
	int slots = MAX_ITEMS - 1, i, n, has_more;

	load_actions();
	ensure_window();
	memset(&title, 0, sizeof title);
	title.type = T_TEXT;
	snprintf(title.label, sizeof title.label, "%s:", key_item.label);
	add_cell(&title, 0, 0, 1);
	if (chooser_start >= n_actions) chooser_start = 0;
	has_more = n_actions - chooser_start > slots;
	n = has_more ? slots - 1 : n_actions - chooser_start;
	for (i = 0; i < slots; i++) {
		int slot = i + 1;
		if (i < n) {
			memset(&choices[i], 0, sizeof choices[i]);
			choices[i].type = T_CHOICE;
			snprintf(choices[i].arg, sizeof choices[i].arg, "%s", act_id[chooser_start + i]);
			snprintf(choices[i].label, sizeof choices[i].label, "%s", act_label[chooser_start + i]);
			add_cell(&choices[i], slot % COLS, slot / COLS, 1);
		} else if (i == n && has_more) {
			memset(&more, 0, sizeof more);
			more.type = T_MORE;
			more.step = chooser_start + n;
			snprintf(more.label, sizeof more.label, "다음 >");
			add_cell(&more, slot % COLS, slot / COLS, 1);
		} else
			add_cell(&blank, slot % COLS, slot / COLS, 1);
	}
	memset(&cancel, 0, sizeof cancel);
	cancel.type = T_PAGE;
	snprintf(cancel.label, sizeof cancel.label, "취소");
	snprintf(cancel.arg, sizeof cancel.arg, "%s", page);
	add_cell(&cancel, 0, ROWS - 1, 1);
	items[MAX_ITEMS + 1].type = T_CLOSE;
	snprintf(items[MAX_ITEMS + 1].label, sizeof items[MAX_ITEMS + 1].label, "닫기");
	add_cell(&items[MAX_ITEMS + 1], 1, ROWS - 1, 1);
	show_window();
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
