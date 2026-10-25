#!/usr/bin/env python3
"""타사 .cube 를 메뉴 LUT 로 더한다.

사용: python3 add_cube.py <id> "<메뉴 이름>" file.cube|.3dl|.vlt|.csp|.png(HaldCLUT) ["설명" [분류]] [--space=vlog] [--ev=0.5]
  분류: basic(기본) kodak fuji etc polaroid style print (make_luts.CATS). 없으면 basic
  -> sd/nx500ex/lut/<id>_a.bin, <id>_b.bin, <id>.bin, luts.txt 한 줄 추가, 메뉴 화면 재생성, dumps/lut/preview/<id>.png
id 는 영문 소문자, 숫자, 밑줄. 메뉴 이름은 한글 12자 안팎 (메뉴 한 칸).
.cube 는 표준 RGB 3D LUT (DOMAIN 0..1 기본, 아무 크기). 카메라가 JPEG 로 만드는 sRGB 영상에 적용되는 것으로 보고
BT.601 전범위 YCbCr 격자로 다시 샘플링하며, 표마다 카메라 원래 표를 먼저 거친다.
"""
import os, sys, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cube2bank as C
import make_luts as M

def main():
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    opts = {a.split("=", 1)[0]: a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--") and "=" in a}
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    rid, name, path = args[0], args[1], args[2]
    desc = args[3] if len(args) > 3 else os.path.basename(path)
    cat = args[4] if len(args) > 4 else "basic"
    space = opts.get("--space") or C.inspace.guess_space(path, open(path, encoding="utf-8", errors="replace").read(4000) if path.lower().endswith(".cube") else None)
    ev = float(opts.get("--ev", "0"))
    if cat not in [c[0] for c in M.CATS]:
        raise SystemExit("분류는 " + " ".join(c[0] for c in M.CATS))
    if not re.fullmatch(r"[a-z0-9_]+", rid) or rid.startswith("cal_"):
        raise SystemExit("id 는 영문 소문자, 숫자, 밑줄만 (cal_ 로 시작 불가)")
    os.makedirs(M.PREVIEW, exist_ok=True)
    dump = open(M.DUMP, "rb").read()
    fn = C.look_func(path, space, ev)
    if space != "srgb":
        print(f"입력 공간: {C.inspace.SPACES[space][0]}, 노출 {ev:+.2f} 스톱")
    M.write_look(rid, fn, dump, True, M.test_image())
    lst = os.path.join(M.LUTDIR, "luts.txt")
    rows = [r for r in M.read_list(lst) if r[0] != rid] + [(rid, name, desc, cat)]
    M.write_list(rows)
    M.gen_menu()
    print(f"{rid} ({name}) 추가. SD 의 nx500ex/lut/ 와 scripts/gui_lut*.NX500 을 복사하면 메뉴에 보인다. 미리보기 dumps/lut/preview/{rid}.png")

if __name__ == "__main__":
    main()
