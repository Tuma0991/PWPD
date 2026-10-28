// ============================================================
// GuardianNako SPRING-CLAMP Enclosure (pager-style belt clip)
// Houses: ESP32-S3 SuperMini, MPU6050, GT-U8 GPS, TP4056,
//         mini boost converter, 1000mAh LiPo 803040 (40x30x8mm)
// Two-part shell: BASE (deep, holds stack + spring clamp) + LID (front, button)
//
// Same case body as the watch/clip variants, but the mount is a
// FLEXING CANTILEVER ARM with a deep hook that actively CLAMPS the
// belt/strap instead of just sliding on. This is the "quick clip that
// also stays on" option — unlike the rigid slide-on clip, the hook here
// wraps around the belt's lower edge and the arm's spring force holds it.
//
// HOW IT WORKS
// ------------
// - The arm is a thin cantilever rooted at the TOP (+Y) of the back face,
//   angled slightly inward so at rest its hook tip sits ~0.8mm from the
//   case. A belt (3-5mm thick) cannot pass that gap without bending the arm.
// - To put it on: pull the hook end outward (away from the body), slide the
//   belt up into the channel, release. The arm springs back and the hook
//   curls around the belt's lower edge, clamping it.
// - To take it off: pull the hook end outward and slide the device up.
//
// ORIENTATION WHEN WORN (same as the clip variant)
// ------------------------------------------------
// - Belt/strap runs along X (the long, 42mm axis).
// - +Y is UP (GPS window), -Y is DOWN (SOS button). Arm roots at +Y, hook at -Y.
//
// TUNING — READ BEFORE PRINTING
// -----------------------------
// - sc_arm_t (arm thickness) is THE knob. Thinner = easier to flex + gentler
//   clamp, but weaker and more likely to snap at the root. Thicker = stiffer
//   + stronger, but hard to put on. Start at 1.4mm and iterate.
// - MATERIAL: PLA works for a demo but creeps/fatigues under repeated bending
//   and may snap. PETG is strongly recommended; a PETG/TPU blend is ideal.
// - If it snaps at the root, add a fillet where the arm meets the root wall,
//   or taper sc_arm_t thinner near the root to spread the bend.
// - sc_tip_gap (hook tip clearance) sets how hard the belt is to get past:
//   0.8mm is a firm clamp; raise to ~1.5mm for an easier clip, lower to 0.4mm
//   for a tighter hold.
//
// PRINTING NOTE
// --------------
// For the strongest flex, print so the arm's LENGTH runs along the print
// layers (arm lying flat) — a vertically-printed arm bends across layer lines
// and can delaminate at the root. If that's awkward with the case, print the
// base back-face-up and accept a slightly weaker arm for early prototypes.
//
// ACTUAL SIZES USED IN THIS DESIGN (same as the watch variant)
// ------------------------------------------------------------
// Case body (excl. clamp): 46 x 36 x 18 mm   (L x W x H)
// Base shell height: 16 mm | Lid plate: 2 mm
// Wall thickness: 2 mm | Floor: 2 mm | Lid plate: 2 mm
// SOS button clearance hole: 10 mm diameter
// Snap-fit lid: 4 snap tabs (3mm bump / 3.4mm hole), no screws
// GPS window (front face): 24 x 14mm, 1.1mm residual wall
// USB-C charging slot: 9.5 x 3.6mm, centered on the -X side wall
// Spring clamp: 26mm wide arm (X), 28mm long (Y), ~5mm channel, deep hook
// ============================================================

$fn = 64;

// ---------- Outer dimensions (case body, excluding clamp) ----------
case_L   = 46;    // length (X) — belt runs along this axis
case_W   = 36;    // width  (Y) — vertical (up/down) when worn
case_H   = 18;    // total height (Z) when assembled
corner_r = 4;      // corner rounding radius (inner corner = 2mm)

wall     = 2;      // outer wall thickness
floor_t  = 2;      // base floor thickness
lid_t    = 2;      // lid (front) thickness

base_H   = 16;     // base shell height (holds the stack) -> 14mm interior cavity
lid_H    = case_H - base_H; // lid shell height (2mm)

lip_h    = 4.0;    // lid skirt height (snap engagement depth)
lip_gap  = 0.2;    // clearance so the lid slides on

edge_fillet = 1.2;   // radius of the true rounded curve on the outer
                      // top/bottom edges

// Snap-fit (no screws) — bumps on the lid skirt snap into holes in the
// base wall at the four side midpoints. snap_h is the retention knob.
snap_d      = 3.0;   // snap bump diameter
snap_h      = 0.7;   // bump protrusion beyond the skirt face (retention)
snap_hole_d = 3.4;   // receiving hole diameter through the base wall

// SOS button (front face, on the LID)
button_d   = 10;    // SOS button clearance hole
button_pos = [0, -8];       // offset from case center (X,Y) — lower half,
                             // leaves room for the GPS window above it

// GPS window (front face, on the LID)
gps_window_wall = 1.1;
gps_window_l    = 24;
gps_window_w    = 14;
gps_window_r    = 2;
gps_window_pos  = [0, 7];    // offset from case center — upper half

// USB-C charging cutout (centered on the -X side wall of the base)
usb_w = 9.5;
usb_h = 3.6;

// ---------- Spring clamp (on the BACK face, i.e. the base floor side) ----------
sc_w       = 26;    // arm width along X (the belt direction)
sc_arm_t   = 1.4;   // arm thickness (Z) — THE flex tuning knob
sc_len     = 28;    // arm length along Y (root at +Y to hook at -Y)
sc_root_y  = 14;    // Y position of the arm root (top)
sc_stand   = 5.0;   // channel gap at the root (Z)
sc_gap     = 2.0;   // channel gap at the free end (Z) — rest position
sc_wall_t  = 2.5;   // root wall thickness (Y)
sc_lip_r   = 2.5;   // hook curl radius
sc_lip_up  = 4.0;   // hook return finger height (+Y)
sc_lip_t   = 2.0;   // hook return finger thickness (Z)
sc_tip_gap = 0.8;   // rest gap between hook tip and the back face

// ============================================================
// Helper: rounded-rectangle prism, centered at origin in X/Y
// ============================================================
module rounded_rect(l, w, r, h) {
    hull() {
        for (x = [-(l/2 - r), (l/2 - r)])
            for (y = [-(w/2 - r), (w/2 - r)])
                translate([x, y, 0])
                    cylinder(h = h, r = r);
    }
}

// True rounded fillet on the BOTTOM edge only (top stays sharp/flat
// for the lip seam) — real curve via minkowski, not a flat chamfer
module filleted_bottom(l, w, r, h, f) {
    intersection() {
        translate([0, 0, f])
            minkowski() {
                rounded_rect(l - 2*f, w - 2*f, max(r - f, 0.1), h);
                sphere(r = f, $fn = 24);
            }
        translate([-l, -w, 0])
            cube([2*l, 2*w, h]);
    }
}

// Same fillet, mirrored to round the TOP edge instead
module filleted_top(l, w, r, h, f) {
    translate([0, 0, h])
        mirror([0, 0, 1])
            filleted_bottom(l, w, r, h, f);
}

// Shell = soft-edged outer body minus a plain inner cavity, open top
module shell(l, w, h, wall_t, floor_th, r, fillet) {
    difference() {
        filleted_bottom(l, w, r, h, fillet);
        translate([0, 0, floor_th])
            rounded_rect(l - 2*wall_t, w - 2*wall_t, max(r - wall_t, 0.5), h);
    }
}

// ============================================================
// Spring clamp — flexing cantilever arm + deep hook.
// The arm leans inward (root stands sc_stand out, free end sc_gap out)
// so it is pre-loaded against the belt. The hook wraps the belt's
// lower edge. Pulling the hook end outward opens it for attach/detach.
// ============================================================
module spring_clamp() {
    free_y = sc_root_y - sc_len;

    // flexing arm (tapered beam: root further out, free end closer in)
    hull() {
        translate([0, sc_root_y, -(sc_stand + sc_arm_t/2)])
            cube([sc_w, 0.01, sc_arm_t], center = true);
        translate([0, free_y, -(sc_gap + sc_arm_t/2)])
            cube([sc_w, 0.01, sc_arm_t], center = true);
    }

    // root wall joining the arm top to the back face
    translate([0, sc_root_y - sc_wall_t/2, -(sc_stand + sc_arm_t)/2])
        cube([sc_w, sc_wall_t, sc_stand + sc_arm_t], center = true);

    // hook curl at the free end (cylinder along X), tip sc_tip_gap from back face
    translate([0, free_y, -sc_tip_gap - sc_lip_r])
        rotate([0, 90, 0])
            cylinder(h = sc_w, r = sc_lip_r, center = true);

    // hook return finger: rises +Y behind the belt's lower edge
    translate([0, free_y + sc_lip_up/2, -sc_tip_gap - sc_lip_t/2])
        cube([sc_w, sc_lip_up, sc_lip_t], center = true);
}

// ============================================================
// Snap-fit — bumps on the lid skirt + holes in the base wall.
// Four points at the side-wall midpoints (no screws).
// ============================================================
module snap_bumps() {
    sx = case_L/2 - wall - lip_gap;   // skirt half-extent along X
    sy = case_W/2 - wall - lip_gap;   // skirt half-extent along Y
    bz = -lip_h/2;                    // skirt mid-height (lid-local Z)
    for (s = [-1, 1])
        translate([s*(sx + snap_h/2), 0, bz])
            rotate([0, 90, 0]) cylinder(h = snap_h, d = snap_d, center = true);
    for (s = [-1, 1])
        translate([0, s*(sy + snap_h/2), bz])
            rotate([90, 0, 0]) cylinder(h = snap_h, d = snap_d, center = true);
}

module snap_holes() {
    hz = base_H - lip_h/2;            // same height, in base coordinates
    for (s = [-1, 1])
        translate([s*case_L/2, 0, hz])
            rotate([0, 90, 0]) cylinder(h = wall + 2, d = snap_hole_d, center = true);
    for (s = [-1, 1])
        translate([0, s*case_W/2, hz])
            rotate([90, 0, 0]) cylinder(h = wall + 2, d = snap_hole_d, center = true);
}

// ============================================================
// BASE SHELL — deep part that holds the electronics stack + clamp
// ============================================================
module base_shell() {
    difference() {
        union() {
            shell(case_L, case_W, base_H, wall, floor_t, corner_r, edge_fillet);

            // spring clamp on the back face
            spring_clamp();
        }

        // snap-fit holes through the base wall (four side midpoints)
        snap_holes();

        // USB-C charging cutout, centered on the -X side wall
        translate([-(case_L/2) - 1, 0, base_H/2])
            hull() {
                translate([0, -(usb_w/2 - usb_h/2), 0])
                    rotate([0, 90, 0]) cylinder(h = wall + 3, d = usb_h);
                translate([0,  (usb_w/2 - usb_h/2), 0])
                    rotate([0, 90, 0]) cylinder(h = wall + 3, d = usb_h);
            }
    }

    // internal battery/PCB standoff ledge (rests the 40x30x8 LiPo + PCB
    // stack on, keeps components off the floor)
    translate([0, 0, floor_t])
        rounded_rect(case_L - 2*wall - 2, case_W - 2*wall - 2, 1, 1.5);
}

// ============================================================
// LID — front cover with SOS button hole and the GPS window
// (identical to the watch/clip variants)
// ============================================================
module lid_shell() {
    difference() {
        union() {
            // front plate with a true rounded curve on the outward-facing edge
            filleted_top(case_L, case_W, corner_r, lid_t, min(edge_fillet, lid_t/2 - 0.2));

            // downward skirt that slides into the base cavity
            translate([0, 0, -lip_h + 0.01])
                rounded_rect(case_L - 2*wall - 2*lip_gap,
                             case_W - 2*wall - 2*lip_gap,
                             max(corner_r - wall - lip_gap, 0.5),
                             lip_h);

            // snap bumps on the skirt outer faces
            snap_bumps();
        }

        // SOS button hole
        translate([button_pos[0], button_pos[1], -1])
            cylinder(h = lid_t + lip_h + 2, d = button_d);

        // soft countersink at the button hole's outer rim
        translate([button_pos[0], button_pos[1], lid_t - 0.6])
            cylinder(h = 0.7, d1 = button_d, d2 = button_d + 1.6);

        // GPS thin-window: mill a rectangular pocket that cuts all the
        // way through the skirt AND into the front plate, leaving only
        // gps_window_wall of plastic on the outside.
        translate([gps_window_pos[0], gps_window_pos[1], -lip_h - 0.1])
            rounded_rect(gps_window_l, gps_window_w, gps_window_r,
                         lip_h + lid_t - gps_window_wall + 0.1);

    }
}

// ============================================================
// Render selection
// part = "base" | "lid" | "preview" (both, assembled, for viewing only)
// ============================================================
part = "preview";

if (part == "base") {
    base_shell();
} else if (part == "lid") {
    lid_shell();
} else {
    base_shell();
    translate([0, 0, base_H])
        lid_shell();
}
