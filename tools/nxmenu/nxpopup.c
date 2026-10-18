/*
 * nxpopup: nx500ex 알림 창. 사용법: nxpopup "글" [초]
 *
 * NX-KS popup_timeout 대신 쓴다. popup_timeout 은 반투명 배경이 첫 줄 높이만큼만 그려지고(<br> 두 줄이면 아랫줄은 배경 없음),
 * 반투명 합성 때문에 카메라 화면의 AF 박스와 아이콘이 겹쳐 보였다 (2026-10-19 실기).
 * nxpopup 은 불투명 바탕에 줄 수(<br> 개수)만큼 높이를 잡는다. 한 줄은 한글 20자 안팎. 아무 키나 누르면 닫힌다.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "efl_min.h"

#define POPUP_W 640
#define LINE_H 48
#define PAD 24

static Eina_Bool on_timeout(void *data)
{
	(void)data;
	elm_exit();
	exit(0);
	return EINA_FALSE;
}

static Eina_Bool on_key(void *data, int type, void *event)
{
	(void)data; (void)type; (void)event;
	elm_exit();
	exit(0);
	return ECORE_CALLBACK_PASS_ON;
}

int main(int argc, char **argv)
{
	Evas_Object *win, *bg, *edge, *lab;
	char text[1024];
	const char *msg = argc > 1 ? argv[1] : "";
	double secs = argc > 2 ? atof(argv[2]) : 2.0;
	const char *p;
	int lines = 1, h;

	for (p = msg; (p = strstr(p, "<br>")); p += 4) lines++;
	h = lines * LINE_H + PAD;
	snprintf(text, sizeof text, "<align=center>%s</align>", msg);

	elm_init(argc, argv);
	ecore_event_handler_add(ECORE_EVENT_KEY_DOWN, on_key, NULL);
	win = elm_win_add(NULL, "nxpopup", ELM_WIN_DIALOG_BASIC);
	/* 테두리 + 불투명 바탕 */
	edge = evas_object_rectangle_add(evas_object_evas_get(win));
	evas_object_color_set(edge, 80, 100, 120, 255);
	elm_win_resize_object_add(win, edge);
	evas_object_show(edge);
	bg = evas_object_rectangle_add(evas_object_evas_get(win));
	evas_object_color_set(bg, 20, 30, 40, 255);
	evas_object_size_hint_min_set(bg, POPUP_W - 4, h - 4);
	elm_win_resize_object_add(win, bg);
	evas_object_show(bg);
	lab = elm_label_add(win);
	elm_object_part_text_set(lab, NULL, text);
	evas_object_size_hint_min_set(lab, POPUP_W - 2 * PAD, h - PAD);
	elm_win_resize_object_add(win, lab);
	evas_object_show(lab);
	evas_object_resize(win, POPUP_W, h);
	evas_object_show(win);
	ecore_timer_add(secs > 0 ? secs : 2.0, on_timeout, NULL);
	elm_run();
	elm_shutdown();
	return 0;
}
