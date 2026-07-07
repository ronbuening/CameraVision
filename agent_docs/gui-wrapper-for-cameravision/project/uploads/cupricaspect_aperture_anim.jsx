import { useState, useEffect, useRef } from "react";

// ─── APERTURE GEOMETRY ────────────────────────────────────────────────────────
const CX = 80, CY = 80;
const OUT_R  = 72;          // outer blade radius (fixed)
const INN_MAX = 46;         // inner vertex radius when fully open
const INN_MIN = 2.5;        // inner vertex radius when fully closed
const N = 8;
const SPACING    = 360 / N;  // 45°  — blade angular spacing
const OUTER_HALF = 180 / N;  // 22.5° — half outer arc (gapless)
const INNER_LEAD = SPACING - 3; // 42° — inner leading offset

function pt(r, deg) {
  const rad = deg * (Math.PI / 180);
  return [CX + r * Math.cos(rad), CY + r * Math.sin(rad)];
}
const f = (n) => +n.toFixed(2);

// Compute one blade's SVG path for a given inner radius
function bladePath(theta, innerR) {
  const [ax, ay] = pt(OUT_R, theta - OUTER_HALF);
  const [bx, by] = pt(OUT_R, theta + OUTER_HALF);
  const [cx, cy] = pt(innerR, theta + INNER_LEAD);
  const [dx, dy] = pt(innerR, theta - 3);
  return `M${f(ax)} ${f(ay)} A${OUT_R} ${OUT_R} 0 0 1 ${f(bx)} ${f(by)} ` +
         `L${f(cx)} ${f(cy)} L${f(dx)} ${f(dy)}Z`;
}

// Inner polygon point string for the cutting-edge highlight
function innerPolyPts(innerR) {
  return Array.from({ length: N }, (_, i) => {
    const [x, y] = pt(innerR, i * SPACING + INNER_LEAD);
    return `${f(x)},${f(y)}`;
  }).join(" ");
}

// ─── ANIMATION TIMING ─────────────────────────────────────────────────────────
// Total cycle 3800 ms:
//   0 % – 26 %  →  hold open      (988 ms)
//  26 % – 66 %  →  close          (1520 ms, ease-in  — slow start like an iris ring)
//  66 % – 79 %  →  hold closed    (494 ms)
//  79 % – 100%  →  snap open      (798 ms, ease-out  — characteristic quick pop)
const CYCLE = 3800;

const easeIn  = (t) => t * t * t;
const easeOut = (t) => 1 - Math.pow(1 - t, 3);

function closeFactor(phase) {
  if (phase < 0.26) return 0;
  if (phase < 0.66) return easeIn((phase  - 0.26) / 0.40);
  if (phase < 0.79) return 1;
  return 1 - easeOut((phase - 0.79) / 0.21);
}

// ─── BLADE COLOURS ────────────────────────────────────────────────────────────
// Per-blade [outerBright, innerDark].  θ = 0°, 45°, …, 315°.
// Luminosity stepped to simulate upper-left (225°) light source.
const COLORS = [
  ["#F0AA40", "#9C5018"],  // 0°   right          medium-bright
  ["#B87A26", "#4E3220"],  // 45°  lower-right     dark
  ["#A86C1E", "#42281A"],  // 90°  bottom          darkest
  ["#BA7620", "#503018"],  // 135° lower-left      dark
  ["#D08830", "#743610"],  // 180° left            medium-dark
  ["#FFD060", "#B05E20"],  // 225° upper-left  ←   brightest (lit)
  ["#F8BC50", "#A85820"],  // 270° top             bright
  ["#ECA034", "#8A4414"],  // 315° upper-right     medium-bright
];

const THETAS = Array.from({ length: N }, (_, i) => i * SPACING);

// ─── COMPONENT ────────────────────────────────────────────────────────────────
export default function ApertureAnimation() {
  const [cf, setCf] = useState(0);   // close factor: 0 = open, 1 = closed
  const rafRef = useRef(null);
  const t0Ref  = useRef(null);
  const [paused, setPaused] = useState(false);
  const pausedRef = useRef(false);
  const pauseOffsetRef = useRef(0);
  const pauseStartRef  = useRef(null);

  useEffect(() => {
    pausedRef.current = paused;
  }, [paused]);

  useEffect(() => {
    function tick(ts) {
      if (t0Ref.current === null) t0Ref.current = ts;

      if (!pausedRef.current) {
        if (pauseStartRef.current !== null) {
          pauseOffsetRef.current += ts - pauseStartRef.current;
          pauseStartRef.current = null;
        }
        const elapsed = ts - t0Ref.current - pauseOffsetRef.current;
        const phase   = (elapsed % CYCLE) / CYCLE;
        setCf(closeFactor(phase));
      } else {
        if (pauseStartRef.current === null) pauseStartRef.current = ts;
      }

      rafRef.current = requestAnimationFrame(tick);
    }
    rafRef.current = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(rafRef.current);
  }, []);

  const innerR = INN_MAX + (INN_MIN - INN_MAX) * cf;
  // Clockwise twist mirrors real iris-ring rotation as aperture closes
  const twist  = f(24 * cf);

  return (
    <div
      onClick={() => setPaused(p => !p)}
      style={{
        background: "#000",
        minHeight: "100vh",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: "24px",
        cursor: "pointer",
        userSelect: "none",
      }}
    >
      <svg
        viewBox="0 0 160 160"
        style={{ width: "min(72vw, 72vh)", height: "min(72vw, 72vh)" }}
      >
        <defs>
          {/* ── disc clip ── */}
          <clipPath id="disc">
            <circle cx="80" cy="80" r="74"/>
          </clipPath>

          {/* ── background ── */}
          <radialGradient id="bg" cx="50%" cy="50%" r="50%">
            <stop offset="0%"   stopColor="#2A1408"/>
            <stop offset="100%" stopColor="#0A0500"/>
          </radialGradient>

          {/* ── metal grain ── */}
          <filter id="wear" x="-3%" y="-3%" width="106%" height="106%"
                  colorInterpolationFilters="sRGB">
            <feTurbulence type="fractalNoise" baseFrequency="0.55 0.80"
                          numOctaves="4" seed="9" result="n"/>
            <feComponentTransfer in="n" result="wg">
              <feFuncR type="linear" slope="0.18" intercept="0.41"/>
              <feFuncG type="linear" slope="0.14" intercept="0.41"/>
              <feFuncB type="linear" slope="0.10" intercept="0.38"/>
            </feComponentTransfer>
            <feBlend in="SourceGraphic" in2="wg" mode="overlay" result="g"/>
            <feComposite in="g" in2="SourceGraphic" operator="in"/>
          </filter>

          {/* ── iris fibre distortion ── */}
          <filter id="irisOrg" x="-12%" y="-12%" width="124%" height="124%">
            <feTurbulence type="fractalNoise" baseFrequency="0.08 0.05"
                          numOctaves="3" seed="14" result="w"/>
            <feDisplacementMap in="SourceGraphic" in2="w" scale="3.5"
                               xChannelSelector="R" yChannelSelector="G"/>
          </filter>

          {/* ── iris ── */}
          <radialGradient id="iris" cx="42%" cy="37%" r="64%" fx="42%" fy="37%">
            <stop offset="0%"   stopColor="#C8F0A0"/>
            <stop offset="14%"  stopColor="#68CE64"/>
            <stop offset="32%"  stopColor="#389050"/>
            <stop offset="56%"  stopColor="#256040"/>
            <stop offset="77%"  stopColor="#184A2C"/>
            <stop offset="90%"  stopColor="#2E3C1C"/>
            <stop offset="100%" stopColor="#060A04"/>
          </radialGradient>

          {/* ── limbal ring ── */}
          <radialGradient id="limbus" cx="50%" cy="50%" r="50%">
            <stop offset="68%"  stopColor="#000" stopOpacity="0"/>
            <stop offset="100%" stopColor="#000" stopOpacity="0.94"/>
          </radialGradient>

          {/* ── pupil ── */}
          <radialGradient id="pup" cx="33%" cy="29%" r="72%">
            <stop offset="0%"   stopColor="#1A1A1A"/>
            <stop offset="100%" stopColor="#010101"/>
          </radialGradient>

          {/* ── per-blade gradients (fixed coords; rotate naturally with blade group) ── */}
          {COLORS.map(([outer, inner], i) => {
            const [sx, sy] = pt(OUT_R, THETAS[i]);
            const [ex, ey] = pt(46,    THETAS[i]);
            return (
              <linearGradient key={i} id={`g${i}`}
                gradientUnits="userSpaceOnUse"
                x1={f(sx)} y1={f(sy)} x2={f(ex)} y2={f(ey)}>
                <stop offset="0%"   stopColor={outer}/>
                <stop offset="100%" stopColor={inner}/>
              </linearGradient>
            );
          })}

          {/* ── patina ── */}
          <radialGradient id="patina" gradientUnits="userSpaceOnUse"
                          cx="48" cy="128" r="80">
            <stop offset="0%"   stopColor="#3E7C60" stopOpacity="0.22"/>
            <stop offset="35%"  stopColor="#306050" stopOpacity="0.09"/>
            <stop offset="100%" stopColor="#306050" stopOpacity="0"/>
          </radialGradient>

          {/* ── iris clip ── */}
          <clipPath id="ic">
            <ellipse cx="80" cy="80" rx="43" ry="34"/>
          </clipPath>
        </defs>

        <g clipPath="url(#disc)">

          {/* Background */}
          <circle cx="80" cy="80" r="74" fill="url(#bg)"/>
          <circle cx="80" cy="80" r="73.5" fill="none"
                  stroke="#1E0C04" strokeWidth="1.5" strokeOpacity="0.85"/>

          {/* ── EYE — behind blades ── */}
          <ellipse cx="80" cy="80" rx="43" ry="34" fill="url(#iris)"/>
          <g clipPath="url(#ic)" filter="url(#irisOrg)"
             stroke="#082010" strokeOpacity="0.22" strokeWidth="0.8">
            {Array.from({ length: 18 }, (_, i) => {
              const [x, y] = pt(45, i * 20);
              return <line key={i} x1={80} y1={80} x2={f(x)} y2={f(y)}/>;
            })}
          </g>
          <ellipse cx="80" cy="80" rx="43" ry="34" fill="url(#limbus)"/>
          <ellipse cx="80" cy="80" rx="43" ry="34" fill="none"
                   stroke="#3AB048" strokeWidth="0.5" strokeOpacity="0.20"/>

          {/* Pupil */}
          <circle cx="80" cy="80" r="16" fill="url(#pup)"/>
          {/* CCD dot grid */}
          <g fill="white" fillOpacity="0.12">
            {[-8,-4,0,4,8].flatMap(dy =>
              [-8,-4,0,4,8].map(dx =>
                <circle key={`${dx},${dy}`}
                        cx={80 + dx} cy={80 + dy} r="0.8"/>
              )
            )}
          </g>
          {/* Catchlights */}
          <ellipse cx="73.5" cy="73.5" rx="5.5" ry="3.8"
                   transform="rotate(-40 73.5 73.5)"
                   fill="white" fillOpacity="0.88"/>
          <circle cx="86.5" cy="86.5" r="1.8" fill="white" fillOpacity="0.22"/>

          {/* ── APERTURE BLADES ── animated via innerR + twist ── */}
          {/*
            Per-blade gradients share the blade group's rotated coordinate
            system, so lighting correctly tracks each blade as it rotates.
            filter="url(#wear)" applies the grain texture to the whole
            assembled mechanism in one pass.
          */}
          <g transform={`rotate(${twist}, ${CX}, ${CY})`}
             filter="url(#wear)">
            {THETAS.map((th, i) => (
              <path key={i}
                    d={bladePath(th, innerR)}
                    fill={`url(#g${i})`}
                    stroke="#1A0A04"
                    strokeWidth="0.7"
                    strokeLinejoin="round"/>
            ))}
          </g>

          {/* Inner cutting-edge highlight — rotates with blades */}
          <g transform={`rotate(${twist}, ${CX}, ${CY})`}>
            <polygon
              points={innerPolyPts(innerR)}
              fill="none"
              stroke="#D89030"
              strokeWidth="0.8"
              strokeOpacity="0.35"
              strokeLinejoin="round"/>
          </g>

          {/* Patina overlay — fixed; weathering doesn't rotate */}
          <circle cx="80" cy="80" r="73" fill="url(#patina)"/>

        </g>
      </svg>

      {/* Pause hint */}
      <p style={{
        color: "#4A2808",
        fontFamily: "monospace",
        fontSize: "11px",
        letterSpacing: "0.18em",
        margin: 0,
      }}>
        {paused ? "PAUSED — click to resume" : "click to pause"}
      </p>
    </div>
  );
}
