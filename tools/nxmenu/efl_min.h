/* nxmenu 가 쓰는 EFL 1.7 함수 선언 (NX500 펌웨어의 라이브러리와 링크한다. EFL 헤더 없이 빌드하기 위한 최소 선언) */
#ifndef EFL_MIN_H
#define EFL_MIN_H

typedef struct _Evas_Object Evas_Object;
typedef struct _Evas Evas;
typedef unsigned char Eina_Bool;
typedef int Evas_Coord;
typedef void (*Evas_Smart_Cb)(void *data, Evas_Object *obj, void *event_info);
typedef Eina_Bool (*Ecore_Event_Handler_Cb)(void *data, int type, void *event);

/* Ecore_Event_Key 의 앞부분 (EFL 1.7). key 는 두 번째 필드 */
typedef struct {
	const char *keyname;
	const char *key;
	const char *string;
	const char *compose;
} Ecore_Event_Key_Head;

#define EINA_TRUE ((Eina_Bool)1)
#define EINA_FALSE ((Eina_Bool)0)
#define ECORE_CALLBACK_PASS_ON EINA_TRUE
#define ELM_WIN_DIALOG_BASIC 1

extern int ECORE_EVENT_KEY_DOWN;

int elm_init(int argc, char **argv);
int elm_shutdown(void);
void elm_run(void);
void elm_exit(void);

Evas_Object *elm_win_add(Evas_Object *parent, const char *name, int type);
void elm_win_resize_object_add(Evas_Object *win, Evas_Object *subobj);
Evas_Object *elm_table_add(Evas_Object *parent);
void elm_table_clear(Evas_Object *obj, Eina_Bool clear);
void elm_table_pack(Evas_Object *obj, Evas_Object *subobj, int x, int y, int w, int h);
Evas_Object *elm_button_add(Evas_Object *parent);
Evas_Object *elm_check_add(Evas_Object *parent);
void elm_check_state_set(Evas_Object *obj, Eina_Bool state);
Eina_Bool elm_check_state_get(const Evas_Object *obj);
void elm_object_part_text_set(Evas_Object *obj, const char *part, const char *label);
Eina_Bool elm_object_style_set(Evas_Object *obj, const char *style);

Evas *evas_object_evas_get(const Evas_Object *obj);
Evas_Object *evas_object_rectangle_add(Evas *e);
void evas_object_show(Evas_Object *obj);
void evas_object_hide(Evas_Object *obj);
void evas_object_del(Evas_Object *obj);
void evas_object_resize(Evas_Object *obj, Evas_Coord w, Evas_Coord h);
void evas_object_move(Evas_Object *obj, Evas_Coord x, Evas_Coord y);
void evas_object_size_hint_min_set(Evas_Object *obj, Evas_Coord w, Evas_Coord h);
void evas_object_color_set(Evas_Object *obj, int r, int g, int b, int a);
void evas_object_smart_callback_add(Evas_Object *obj, const char *event, Evas_Smart_Cb func, const void *data);

void *ecore_event_handler_add(int type, Ecore_Event_Handler_Cb func, const void *data);
void ecore_main_loop_iterate(void);
void *ecore_job_add(void (*func)(void *data), const void *data);
void *ecore_timer_add(double in, Eina_Bool (*func)(void *data), const void *data);
Evas_Object *elm_label_add(Evas_Object *parent);
void evas_smart_objects_calculate(Evas *e);
void evas_object_size_hint_min_get(const Evas_Object *obj, Evas_Coord *w, Evas_Coord *h);

#endif
