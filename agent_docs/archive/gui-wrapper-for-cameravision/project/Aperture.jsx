// CupricAspect aperture — animated "working" indicator.
// Adapted from the uploaded cupricaspect_aperture_anim.jsx into a sized,
// prop-driven component. React is provided globally by the DC runtime.
const { useState, useEffect, useRef } = React;

const CX = 80, CY = 80;
const OUT_R = 72;
const INN_MAX = 46;
const INN_MIN = 2.5;
const N = 8;
const SPACING = 360 / N;
const OUTER_HALF = 180 / N;
const INNER_LEAD = SPACING - 3;

function pt(r, deg) {
  const rad = deg * (Math.PI / 180);
  return [CX + r * Math.cos(rad), CY + r * Math.sin(rad)];
}
const f = (n) => +n.toFixed(2);

function bladePath(theta, innerR) {
  const [ax, ay] = pt(OUT_R, theta - OUTER_HALF);
  const [bx, by] = pt(OUT_R, theta + OUTER_HALF);
  const [cx, cy] = pt(innerR, theta + INNER_LEAD);
  const [dx, dy] = pt(innerR, theta - 3);
  return `M${f(ax)} ${f(ay)} A${OUT_R} ${OUT_R} 0 0 1 ${f(bx)} ${f(by)} ` +
    `L${f(cx)} ${f(cy)} L${f(dx)} ${f(dy)}Z`;
}
function innerPolyPts(innerR) {
  return Array.from({ length: N }, (_, i) => {
    const [x, y] = pt(innerR, i * SPACING + INNER_LEAD);
    return `${f(x)},${f(y)}`;
  }).join(" ");
}

const CYCLE = 3800;
const easeIn = (t) => t * t * t;
const easeOut = (t) => 1 - Math.pow(1 - t, 3);
function closeFactor(phase) {
  if (phase < 0.26) return 0;
  if (phase < 0.66) return easeIn((phase - 0.26) / 0.40);
  if (phase < 0.79) return 1;
  return 1 - easeOut((phase - 0.79) / 0.21);
}

const COLORS = [
  ["#F0AA40", "#9C5018"],
  ["#B87A26", "#4E3220"],
  ["#A86C1E", "#42281A"],
  ["#BA7620", "#503018"],
  ["#D08830", "#743610"],
  ["#FFD060", "#B05E20"],
  ["#F8BC50", "#A85820"],
  ["#ECA034", "#8A4414"],
];
const THETAS = Array.from({ length: N }, (_, i) => i * SPACING);

// idle: gently held near-open. running: full breathing close/open cycle.
function Aperture({ size = 72, running = false, spin = false, uid }) {
  const [cf, setCf] = useState(0);
  const [rot, setRot] = useState(0);
  const rafRef = useRef(null);
  const t0Ref = useRef(null);
  const id = uid || "ap";

  useEffect(() => {
    function tick(ts) {
      if (t0Ref.current === null) t0Ref.current = ts;
      const elapsed = ts - t0Ref.current;
      if (running) {
        const phase = (elapsed % CYCLE) / CYCLE;
        setCf(closeFactor(phase));
        if (spin) setRot((elapsed / 1000) * 26);
      } else {
        setCf(0);
        if (spin) setRot(0);
      }
      rafRef.current = requestAnimationFrame(tick);
    }
    rafRef.current = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(rafRef.current);
  }, [running, spin]);

  const innerR = INN_MAX + (INN_MIN - INN_MAX) * cf;
  const twist = f(24 * cf + rot);

  return React.createElement(
    "svg",
    { viewBox: "0 0 160 160", width: size, height: size, style: { display: "block" } },
    React.createElement(
      "defs",
      null,
      React.createElement(
        "clipPath",
        { id: `disc-${id}` },
        React.createElement("circle", { cx: 80, cy: 80, r: 74 })
      ),
      React.createElement(
        "radialGradient",
        { id: `bg-${id}`, cx: "50%", cy: "50%", r: "50%" },
        React.createElement("stop", { offset: "0%", stopColor: "#2A1408" }),
        React.createElement("stop", { offset: "100%", stopColor: "#0A0500" })
      ),
      React.createElement(
        "radialGradient",
        { id: `iris-${id}`, cx: "42%", cy: "37%", r: "64%", fx: "42%", fy: "37%" },
        React.createElement("stop", { offset: "0%", stopColor: "#C8F0A0" }),
        React.createElement("stop", { offset: "14%", stopColor: "#68CE64" }),
        React.createElement("stop", { offset: "32%", stopColor: "#389050" }),
        React.createElement("stop", { offset: "56%", stopColor: "#256040" }),
        React.createElement("stop", { offset: "77%", stopColor: "#184A2C" }),
        React.createElement("stop", { offset: "90%", stopColor: "#2E3C1C" }),
        React.createElement("stop", { offset: "100%", stopColor: "#060A04" })
      ),
      React.createElement(
        "radialGradient",
        { id: `limbus-${id}`, cx: "50%", cy: "50%", r: "50%" },
        React.createElement("stop", { offset: "68%", stopColor: "#000", stopOpacity: "0" }),
        React.createElement("stop", { offset: "100%", stopColor: "#000", stopOpacity: "0.94" })
      ),
      React.createElement(
        "radialGradient",
        { id: `pup-${id}`, cx: "33%", cy: "29%", r: "72%" },
        React.createElement("stop", { offset: "0%", stopColor: "#1A1A1A" }),
        React.createElement("stop", { offset: "100%", stopColor: "#010101" })
      ),
      COLORS.map(([outer, inner], i) => {
        const [sx, sy] = pt(OUT_R, THETAS[i]);
        const [ex, ey] = pt(46, THETAS[i]);
        return React.createElement(
          "linearGradient",
          {
            key: i, id: `g${i}-${id}`, gradientUnits: "userSpaceOnUse",
            x1: f(sx), y1: f(sy), x2: f(ex), y2: f(ey),
          },
          React.createElement("stop", { offset: "0%", stopColor: outer }),
          React.createElement("stop", { offset: "100%", stopColor: inner })
        );
      })
    ),
    React.createElement(
      "g",
      { clipPath: `url(#disc-${id})` },
      React.createElement("circle", { cx: 80, cy: 80, r: 74, fill: `url(#bg-${id})` }),
      React.createElement("circle", { cx: 80, cy: 80, r: 73.5, fill: "none", stroke: "#1E0C04", strokeWidth: 1.5, strokeOpacity: 0.85 }),
      React.createElement("ellipse", { cx: 80, cy: 80, rx: 43, ry: 34, fill: `url(#iris-${id})` }),
      React.createElement("ellipse", { cx: 80, cy: 80, rx: 43, ry: 34, fill: `url(#limbus-${id})` }),
      React.createElement("ellipse", { cx: 80, cy: 80, rx: 43, ry: 34, fill: "none", stroke: "#3AB048", strokeWidth: 0.5, strokeOpacity: 0.20 }),
      React.createElement("circle", { cx: 80, cy: 80, r: 16, fill: `url(#pup-${id})` }),
      React.createElement("ellipse", { cx: 73.5, cy: 73.5, rx: 5.5, ry: 3.8, transform: "rotate(-40 73.5 73.5)", fill: "white", fillOpacity: 0.88 }),
      React.createElement(
        "g",
        { transform: `rotate(${twist}, ${CX}, ${CY})` },
        THETAS.map((th, i) =>
          React.createElement("path", {
            key: i, d: bladePath(th, innerR), fill: `url(#g${i}-${id})`,
            stroke: "#1A0A04", strokeWidth: 0.7, strokeLinejoin: "round",
          })
        ),
        React.createElement("polygon", {
          points: innerPolyPts(innerR), fill: "none", stroke: "#D89030",
          strokeWidth: 0.8, strokeOpacity: 0.35, strokeLinejoin: "round",
        })
      )
    )
  );
}

window.Aperture = Aperture;
