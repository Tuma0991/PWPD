// ============================================================
// GuardianNako WATCH Enclosure (wrist-worn variant)
// Houses: ESP32-S3 SuperMini, MPU6050, GT-U8 GPS, TP4056,
//         mini boost converter, 1000mAh LiPo 803040 (40x30x8mm)
// Two-part shell: BASE (deep, holds stack) + LID (front, button)
//
// DESIGN NOTES vs. the pendant version
// -------------------------------------
// - Fall detection is less reliable on the wrist (arm swing causes
//   false positives/negatives) and the SOS button is necessarily
//   smaller than the pendant's — both are inherent trade-offs of a
//   wrist form factor, called out in the hardware doc.
// - The GPS thin-window sits on the FRONT (outward) face here, not
//   the wrist-facing back — the wrist itself blocks GPS signal far
//   more than plastic does, so a thinned back wall wouldn't help.
// - Lugs use a standard spring-bar hole (not a fixed loop), so any
//   off-the-shelf quick-release watch band works with this case.
//
// ACTUAL SIZES USED IN THIS DESIGN
// ---------------------------------
// Case body (excl. lugs):   48 x 38 x 20 mm   (L x W x H)
// Lug-to-lug length:        48 + 2x7mm lugs = ~62 mm
// Base shell height:        18 mm | Lid plate: 2 mm
// Wall thickness:           2 mm | Floor: 2 mm | Lid plate: 2 mm
// Outer top/bottom edge fillet radius: 1.2 mm
// Corner rounding (vertical corners): 5 mm radius
// SOS button clearance hole: 10 mm diameter (smaller than the
//   pendant's 12mm — the wrist face has less room)
// Screw bosses: 4x M2 self-tapping, 4.5mm OD post / 1.6mm pilot hole,
//   6mm from the edge
// GPS window (front face, rectangular): 24 x 14mm footprint,
//   1.1mm residual wall — sized for the GT-U8's onboard rectangular
//   ceramic patch antenna (commonly ~25 x 20mm; measure your exact
//   module and adjust gps_window_l/gps_window_w if it differs —
//   note this footprint is tighter than the pendant's since it has
//   to share the front face with the button)
// USB-C charging slot: 9.5 x 3.6mm, centered on the -X side wall
// Watch lugs: 20mm band width (standard), two 4mm-thick arms per
//   end, 2mm spring-bar hole — fits any standard quick-release band
// ============================================================

$fn = 64;

// ---------- Outer dimensions (case body, excluding lugs) ----------
case_L   = 48;    // length (X)
case_W   = 38;    // width  (Y)
case_H   = 20;    // total height (Z) when assembled
corner_r = 5;      // corner rounding radius (inner corner = 3mm)

wall     = 2;      // outer wall thickness
floor_t  = 2;      // base floor thickness
lid_t    = 2;      // lid (front) thickness

base_H   = 18;     // base shell height (holds the stack) -> 16mm interior cavity
lid_H    = case_H - base_H; // lid shell height (2mm)

lip_h    = 1.2;    // friction-fit lip height
lip_gap  = 0.2;    // clearance so the lid slides on

edge_fillet = 1.2;   // radius of the true rounded curve on the outer
                      // top/bottom edges

// Screw bosses (M2 self-tapping) at 4 corners. inset 6 keeps the 4.5mm
// post clear of the 3mm inner corner radius and the outer wall.
boss_od    = 4.5;
boss_id    = 1.6;   // pilot hole for M2 self-tap
boss_inset = 6;     // distance of boss center from each edge

// SOS button (front face, on the LID)
button_d   = 10;    // SOS button clearance hole (smaller face than the pendant)
button_pos = [0, -8];       // offset from case center (X,Y) — lower half,
                             // leaves room for the GPS window above it

// GPS window (front face, on the LID — see design note above)
gps_window_wall = 1.1;
gps_window_l    = 24;
gps_window_w    = 14;
gps_window_r    = 2;
gps_window_pos  = [0, 7];    // offset from case center — upper half

// USB-C charging cutout (centered on the -X side wall of the base)
usb_w = 9.5;
usb_h = 3.6;

// Watch lugs — standard spring-bar style, 20mm band width
lug_band_w  = 20;   // gap between the two arms == band width
lug_arm_w   = 4;    // each arm's thickness along X
lug_dep     = 7;    // how far the arms protrude beyond the case body
lug_h       = 6;    // arm height (Z)
lug_hole_d  = 2;     // spring-bar hole diameter (fits standard ~1.5-1.8mm bars)
lug_z       = base_H / 2 + 1;  // vertical placement of the spring-bar axis

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
// Watch lugs — two arms per end (+Y and -Y), spring-bar hole
// running along X through both arms of the same end
// ============================================================
module lug_arms(y_sign) {
    for (x_arm = [-(lug_band_w/2 + lug_arm_w/2), (lug_band_w/2 + lug_arm_w/2)])
        translate([x_arm, y_sign * (case_W/2 - 1), lug_z])
            hull() {
                cube([lug_arm_w, 2, lug_h], center = true);
                translate([0, y_sign * (lug_dep - 1), 0])
                    cube([lug_arm_w, 2, lug_h], center = true);
            }
}

module lug_hole(y_sign) {
    translate([0, y_sign * (case_W/2 - 1 + lug_dep - 2.5), lug_z])
        rotate([0, 90, 0])
            cylinder(h = lug_band_w + 2*lug_arm_w + 4, d = lug_hole_d, center = true);
}

// ============================================================
// BASE SHELL — deep part that holds the electronics stack
// ============================================================
module base_shell() {
    difference() {
        union() {
            shell(case_L, case_W, base_H, wall, floor_t, corner_r, edge_fillet);

            // friction-fit lip around the inner top edge, sized to
            // receive the lid
            translate([0, 0, base_H - lip_h])
                difference() {
                    rounded_rect(case_L - 2*wall, case_W - 2*wall,
                                 max(corner_r - wall, 0.5), lip_h);
                    translate([0, 0, -0.1])
                        rounded_rect(case_L - 2*wall - 2*lip_gap - 2,
                                     case_W - 2*wall - 2*lip_gap - 2,
                                     max(corner_r - wall - 2, 0.5), lip_h + 0.2);
                }

            // screw bosses (solid posts with pilot hole, drilled below)
            for (x = [-(case_L/2 - boss_inset), (case_L/2 - boss_inset)])
                for (y = [-(case_W/2 - boss_inset), (case_W/2 - boss_inset)])
                    translate([x, y, floor_t])
                        cylinder(h = base_H - floor_t - 1, d = boss_od);

            // watch lugs, both ends
            lug_arms(1);
            lug_arms(-1);
        }

        // drill boss pilot holes
        for (x = [-(case_L/2 - boss_inset), (case_L/2 - boss_inset)])
            for (y = [-(case_W/2 - boss_inset), (case_W/2 - boss_inset)])
                translate([x, y, floor_t - 0.1])
                    cylinder(h = base_H, d = boss_id);

        // USB-C charging cutout, centered on the -X side wall
        // (cylinders oriented along X so the hull actually spans
        // through the wall thickness, from outside to inside)
        translate([-(case_L/2) - 1, 0, base_H/2])
            hull() {
                translate([0, -(usb_w/2 - usb_h/2), 0])
                    rotate([0, 90, 0]) cylinder(h = wall + 3, d = usb_h);
                translate([0,  (usb_w/2 - usb_h/2), 0])
                    rotate([0, 90, 0]) cylinder(h = wall + 3, d = usb_h);
            }

        // spring-bar holes through the lugs, both ends
        lug_hole(1);
        lug_hole(-1);
    }

    // internal battery/PCB standoff ridge (simple ledge to rest the
    // ~6mm-thick LiPo pouch + PCB stack on, keeps components off the floor)
    translate([0, 0, floor_t])
        rounded_rect(case_L - 2*wall - 4, case_W - 2*wall - 4, 1, 1.5);
}

// ============================================================
// LID — front cover with SOS button hole and the GPS window
// ============================================================
module lid_shell() {
    difference() {
        union() {
            // front plate with a true rounded curve on the outward-facing
            // edge (the edge people actually see and touch)
            filleted_top(case_L, case_W, corner_r, lid_t, min(edge_fillet, lid_t/2 - 0.2));

            // downward skirt that plugs into the base's lip
            translate([0, 0, -lip_h + 0.01])
                rounded_rect(case_L - 2*wall - 2*lip_gap,
                             case_W - 2*wall - 2*lip_gap,
                             max(corner_r - wall - lip_gap, 0.5),
                             lip_h);
        }

        // SOS button hole
        translate([button_pos[0], button_pos[1], -1])
            cylinder(h = lid_t + lip_h + 2, d = button_d);

        // soft countersink at the button hole's outer rim
        translate([button_pos[0], button_pos[1], lid_t - 0.6])
            cylinder(h = 0.7, d1 = button_d, d2 = button_d + 1.6);

        // GPS thin-window: mill a rectangular pocket that cuts all the
        // way through the skirt AND into the front plate, so it truly
        // opens onto the interior cavity (where the GPS module sits)
        // and leaves only gps_window_wall of plastic on the outside.
        // (A shallow pocket alone would dead-end against the solid
        // skirt plug below it — this reaches past that.)
        translate([gps_window_pos[0], gps_window_pos[1], -lip_h - 0.1])
            rounded_rect(gps_window_l, gps_window_w, gps_window_r,
                         lip_h + lid_t - gps_window_wall + 0.1);

        // screw clearance holes (through-holes, aligned to base bosses)
        for (x = [-(case_L/2 - boss_inset), (case_L/2 - boss_inset)])
            for (y = [-(case_W/2 - boss_inset), (case_W/2 - boss_inset)])
                translate([x, y, -lip_h - 1])
                    cylinder(h = lid_t + lip_h + 2, d = boss_id + 0.6);
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
