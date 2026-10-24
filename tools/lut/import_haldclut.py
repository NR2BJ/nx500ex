#!/usr/bin/env python3
"""공개 HaldCLUT 필름 에뮬레이션 모음에서 고른 것을 메뉴 LUT 로 들여온다.

출처: github.com/NatronGitHub/clut (Pat David 의 필름 에뮬레이션, Marc Roovers 의 PictureFX, Juan Melara 의 인화 필름.
      CC BY-SA 4.0. 파일 이름의 상표는 어떤 필름을 흉내 냈는지 알리는 용도일 뿐이다)
사용: python3 import_haldclut.py <clut 저장소 폴더>
  -> sd/nx500ex/lut/<id>_a.bin, _b.bin, <id>.bin, luts.txt 에 분류와 함께 추가, 메뉴 재생성, 미리보기.
원본 PNG 는 저장소에 두지 않는다 (clone 해서 다시 돌리면 된다). 변환 결과 .bin 은 CC BY-SA 4.0 (sd/nx500ex/lut/LICENSE-haldclut.txt).
선정 기준: 각 필름의 기본판 (+, -, cold, warm 변형은 뺌), 회사별로 대표 필름.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cube2bank as C
import make_luts as M

# (id, 메뉴 이름, 분류, 폴더/파일)
PICKS = [
    # 코닥
    ("k_portra160",  "Portra 160",        "kodak", "negative_new/kodak_portra_160"),
    ("k_portra400",  "Portra 400",        "kodak", "negative_new/kodak_portra_400"),
    ("k_portra800",  "Portra 800",        "kodak", "negative_new/kodak_portra_800"),
    ("k_portra160vc","Portra 160 VC",     "kodak", "negative_color/kodak_portra_160_vc"),
    ("k_portra400uc","Portra 400 UC",     "kodak", "negative_old/kodak_portra_400_uc"),
    ("k_elite200",   "Elite Color 200",   "kodak", "negative_color/kodak_elite_color_200"),
    ("k_e100vs",     "Ektachrome 100 VS", "kodak", "colorslide/kodak_ektachrome_100_vs"),
    ("k_e100gx",     "E100 GX",           "kodak", "colorslide/kodak_e-100_gx_ektachrome_100"),
    ("k_kodachrome25","Kodachrome 25",    "kodak", "colorslide/kodak_kodachrome_25"),
    ("k_kodachrome64","Kodachrome 64",    "kodak", "colorslide/kodak_kodachrome_64"),
    ("k_kodachrome200","Kodachrome 200",  "kodak", "colorslide/kodak_kodachrome_200"),
    ("k_elitechrome200","Elite Chrome 200","kodak", "colorslide/kodak_elite_chrome_200"),
    ("k_elite100xpro","Elite 100 X-Pro",  "kodak", "negative_color/kodak_elite_100_xpro"),
    ("k_trix400",    "Tri-X 400",         "kodak", "bw/kodak_tri-x_400"),
    ("k_tmax100",    "T-Max 100",         "kodak", "bw/kodak_t-max_100"),
    ("k_tmax400",    "T-Max 400",         "kodak", "bw/kodak_t-max_400"),
    ("k_tmax3200",   "T-Max 3200",        "kodak", "bw/kodak_t-max_3200"),
    ("k_bw400cn",    "BW 400CN",          "kodak", "bw/kodak_bw_400_cn"),
    ("k_hie",        "HIE 적외선",         "kodak", "bw/kodak_hie_(hs_infra)"),
    # 후지
    ("f_160c",       "Pro 160C",          "fuji", "negative_new/fuji_160c"),
    ("f_400h",       "Pro 400H",          "fuji", "negative_new/fuji_400h"),
    ("f_800z",       "Pro 800Z",          "fuji", "negative_new/fuji_800z"),
    ("f_reala100",   "Superia Reala 100", "fuji", "negative_color/fuji_superia_reala_100"),
    ("f_superia100", "Superia 100",       "fuji", "negative_old/fuji_superia_100"),
    ("f_superia200", "Superia 200",       "fuji", "negative_color/fuji_superia_200"),
    ("f_superia400", "Superia 400",       "fuji", "negative_old/fuji_superia_400"),
    ("f_superia800", "Superia 800",       "fuji", "negative_old/fuji_superia_800"),
    ("f_xtra800",    "Superia X-TRA 800", "fuji", "negative_color/fuji_superia_x-tra_800"),
    ("f_superia1600","Superia 1600",      "fuji", "negative_old/fuji_superia_1600"),
    ("f_hg1600",     "Superia HG 1600",   "fuji", "negative_color/fuji_superia_hg_1600"),
    ("f_velvia50",   "Velvia 50",         "fuji", "colorslide/fuji_velvia_50"),
    ("f_provia100f", "Provia 100F",       "fuji", "colorslide/fuji_provia_100f"),
    ("f_provia400f", "Provia 400F",       "fuji", "colorslide/fuji_provia_400f"),
    ("f_provia400x", "Provia 400X",       "fuji", "colorslide/fuji_provia_400x"),
    ("f_astia100f",  "Astia 100F",        "fuji", "colorslide/fuji_astia_100f"),
    ("f_sensia100",  "Sensia 100",        "fuji", "colorslide/fuji_sensia_100"),
    ("f_superia200xpro","Superia 200 X-Pro","fuji", "colorslide/fuji_superia_200_xpro"),
    ("f_acros100",   "Neopan Acros 100",  "fuji", "bw/fuji_neopan_acros_100"),
    ("f_neopan1600", "Neopan 1600",       "fuji", "bw/fuji_neopan_1600"),
    ("f_fp100c",     "FP-100C 즉석",       "fuji", "instant_pro/fuji_fp-100c"),
    ("f_fp3000b",    "FP-3000B 즉석",      "fuji", "instant_pro/fuji_fp-3000b"),
    # 아그파, 일포드, 롤라이, 로모
    ("a_ultra100",   "Agfa Ultra 100",    "etc", "negative_color/agfa_ultra_color_100"),
    ("a_vista200",   "Agfa Vista 200",    "etc", "negative_color/agfa_vista_200"),
    ("a_precisa100", "Agfa Precisa 100",  "etc", "colorslide/agfa_precisa_100"),
    ("a_apx100",     "Agfa APX 100",      "etc", "bw/agfa_apx_100"),
    ("a_apx25",      "Agfa APX 25",       "etc", "bw/agfa_apx_25"),
    ("i_delta100",   "Ilford Delta 100",  "etc", "bw/ilford_delta_100"),
    ("i_delta400",   "Ilford Delta 400",  "etc", "bw/ilford_delta_400"),
    ("i_delta3200",  "Ilford Delta 3200", "etc", "bw/ilford_delta_3200"),
    ("i_fp4",        "Ilford FP4 125",    "etc", "bw/ilford_fp4_plus_125"),
    ("i_hp5",        "Ilford HP5 400",    "etc", "bw/ilford_hp5_plus_400"),
    ("i_hps800",     "Ilford HPS 800",    "etc", "bw/ilford_hps_800"),
    ("i_panf50",     "Ilford Pan F 50",   "etc", "bw/ilford_pan_f_plus_50"),
    ("i_xp2",        "Ilford XP2",        "etc", "bw/ilford_xp2"),
    ("r_ir400",      "Rollei IR 400",     "etc", "bw/rollei_ir_400"),
    ("r_ortho25",    "Rollei Ortho 25",   "etc", "bw/rollei_ortho_25"),
    ("r_retro100",   "Rollei Retro 100",  "etc", "bw/rollei_retro_100_tonal"),
    ("r_retro80s",   "Rollei Retro 80S",  "etc", "bw/rollei_retro_80s"),
    ("l_redscale",   "Lomo Redscale 100", "etc", "negative_color/lomography_redscale_100"),
    ("l_xpro200",    "Lomo X-Pro 200",    "etc", "colorslide/lomography_x-pro_slide_200"),
    # 폴라로이드
    ("p_px70",       "PX-70",             "polaroid", "instant_consumer/polaroid_px-70"),
    ("p_px680",      "PX-680",            "polaroid", "instant_consumer/polaroid_px-680"),
    ("p_px100warm",  "PX-100UV+ 따뜻",     "polaroid", "instant_consumer/polaroid_px-100uv+_warm"),
    ("p_px100cold",  "PX-100UV+ 차가움",   "polaroid", "instant_consumer/polaroid_px-100uv+_cold"),
    ("p_timezero",   "Time Zero 만료",     "polaroid", "instant_consumer/polaroid_time_zero_(expired)"),
    ("p_665",        "Polaroid 665",      "polaroid", "instant_pro/polaroid_665"),
    ("p_669",        "Polaroid 669",      "polaroid", "instant_pro/polaroid_669"),
    ("p_690",        "Polaroid 690",      "polaroid", "instant_pro/polaroid_690"),
    ("p_664",        "Polaroid 664 흑백",  "polaroid", "bw/polaroid_664"),
    ("p_667",        "Polaroid 667 흑백",  "polaroid", "bw/polaroid_667"),
    ("p_672",        "Polaroid 672 흑백",  "polaroid", "bw/polaroid_672"),
    ("p_polachrome", "Polachrome",        "polaroid", "colorslide/polaroid_polachrome"),
    # 스타일 (various, PictureFX)
    ("s_bleach",     "블리치 바이패스",     "style", "various/bleach_bypass"),
    ("s_60s",        "60년대",             "style", "various/60's"),
    ("s_60sfaded",   "60년대 바램",         "style", "various/60's_faded"),
    ("s_faded",      "바램",               "style", "various/faded"),
    ("s_expired",    "만료 필름 바램",      "style", "various/expired_fade"),
    ("s_golden",     "골든",               "style", "various/golden"),
    ("s_hongkong",   "홍콩",               "style", "various/hong_kong"),
    ("s_lomo",       "로모",               "style", "various/lomo"),
    ("s_nostalgic",  "노스탤직",            "style", "various/nostalgic"),
    ("s_retro",      "레트로",              "style", "various/retro"),
    ("s_vintage",    "빈티지",              "style", "various/vintage"),
    ("s_sutro",      "수트로",              "style", "various/sutro_fx"),
    ("s_solarized",  "솔라리제이션",        "style", "various/solarized_color"),
    ("s_fauxir",     "가짜 적외선",         "style", "various/faux_infrared"),
    ("s_warm",       "따뜻함",              "style", "various/warm"),
    ("s_sunny",      "맑음",               "style", "various/sunny"),
    ("s_summer",     "여름",               "style", "various/summer"),
    ("s_muteshift",  "뮤트 시프트",         "style", "various/mute_shift"),
    ("s_anno1870",   "AnalogFX 1870",     "style", "picturefx/analogfx_anno_1870_color"),
    ("s_sepiafx",    "AnalogFX 세피아",    "style", "picturefx/analogfx_sepia_color"),
    ("s_zilverbw",   "ZilverFX 빈티지 흑백","style", "picturefx/zilverfx_vintage_b_w"),
    ("s_zilverir",   "ZilverFX 적외선",    "style", "picturefx/zilverfx_infrared"),
    ("s_goldfx",     "GoldFX 여름",        "style", "picturefx/goldfx_bright_summer_heat"),
    # 영화 인화 필름 (Juan Melara) - 스타일 화면에
    ("pr_k2383",     "인화 Kodak 2383",   "style", "print/kodak2383_cuspclip"),
    ("pr_k2393",     "인화 Kodak 2393",   "style", "print/kodak2393_cuspclip"),
    ("pr_f3510",     "인화 Fuji 3510",    "style", "print/fuji3510_cuspclip"),
    ("pr_f3513",     "인화 Fuji 3513",    "style", "print/fuji3513_cuspclip"),
]

def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    src = sys.argv[1]
    os.makedirs(M.PREVIEW, exist_ok=True)
    dump = open(M.DUMP, "rb").read()
    img = M.test_image()
    lst = os.path.join(M.LUTDIR, "luts.txt")
    rows = M.read_list(lst) if os.path.exists(lst) else []
    ids = {p[0] for p in PICKS}
    rows = [r for r in rows if r[0] not in ids]
    for rid, name, cat, rel in PICKS:
        path = os.path.join(src, rel + ".png")
        if not os.path.exists(path):
            print(f"없음: {rel}"); continue
        fn = C.hald_func(path)
        M.write_look(rid, fn, dump, True, img)
        rows.append((rid, name, rel + " (CC BY-SA 4.0)", cat))
        print(f"{rid:16s} {name}")
    M.write_list(rows)
    M.gen_menu()
    print(f"{len(PICKS)} 개 들여옴")

if __name__ == "__main__":
    main()
