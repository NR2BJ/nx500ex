/*
 * nxpopup: nx500ex 알림 창. 사용법: nxpopup "글" [초]
 *
 * NX-KS popup_timeout 대신 쓴다. popup_timeout 은 반투명 배경이 첫 줄 높이만큼만 그려지고(<br> 두 줄이면 아랫줄은 배경 없음),
 * 반투명 합성 때문에 카메라 화면의 AF 박스와 아이콘이 겹쳐 보였다 (2026-10-19 실기).
 * nxpopup 은 불투명 바탕이고, 창 크기를 글의 실제 크기(라벨 최소 크기)에 맞춘다 (좌우 아이콘을 가리지 않게).
 * 한 줄은 한글 20자 안팎, 더 필요하면 <br>. 아무 키나 누르면 닫힌다.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "efl_min.h"

#define MAX_W 700
#define PAD_X 3
/* 라벨 테마가 글 위에 약 11, 아래에 약 28 픽셀을 더 잡는다 (PC 에서 카메라 라이브러리로 측정). 그만큼 잘라 낸다 */
#define TRIM_TOP 8
#define TRIM_BOTTOM 20

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
	Evas_Object *win, *bg, *lab;
	char text[1024];
	const char *msg = argc > 1 ? argv[1] : "";
	double secs = argc > 2 ? atof(argv[2]) : 2.0;
	Evas_Coord w = 0, h = 0;

	snprintf(text, sizeof text, "<align=center>%s</align>", msg);

	elm_init(argc, argv);
	ecore_event_handler_add(ECORE_EVENT_KEY_DOWN, on_key, NULL);
	win = elm_win_add(NULL, "nxpopup", ELM_WIN_DIALOG_BASIC);
	bg = evas_object_rectangle_add(evas_object_evas_get(win));
	evas_object_color_set(bg, 20, 30, 40, 255);
	elm_win_resize_object_add(win, bg);
	evas_object_show(bg);
	lab = elm_label_add(win);
	elm_object_part_text_set(lab, NULL, text);
	evas_object_show(lab);
	/* 글의 실제 크기를 계산해 창 크기를 정한다 */
	evas_smart_objects_calculate(evas_object_evas_get(win));
	evas_object_size_hint_min_get(lab, &w, &h);
	if (w <= 0 || h <= 0) { w = 600; h = 60; }
	w += 2 * PAD_X;
	if (w > MAX_W) w = MAX_W;
	/* 라벨은 창 크기에 묶지 않고 직접 놓아 위아래 빈 공간을 창 밖으로 뺀다 */
	evas_object_move(lab, 0, -TRIM_TOP);
	evas_object_resize(lab, w, h);
	evas_object_resize(win, w, h - TRIM_TOP - TRIM_BOTTOM);
	evas_object_show(win);
	ecore_timer_add(secs > 0 ? secs : 2.0, on_timeout, NULL);
	elm_run();
	elm_shutdown();
	return 0;
}
