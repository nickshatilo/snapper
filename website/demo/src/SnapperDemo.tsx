import React from "react";
import {
  AbsoluteFill,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
  Easing,
} from "remotion";

// ─── Colors matching Snapper website ────────────────────────────────
const C = {
  bg: "#0a0a12",
  surface: "#141420",
  border: "#1e1e2e",
  menuBar: "#18181f",
  titleBar: "#16161e",
  accent: "#6366f1",
  purple: "#8b5cf6",
  text: "#e4e4e7",
  dim: "#71717a",
  muted: "#3f3f46",
  white: "#ffffff",
  red: "#ff5f57",
  yellow: "#febc2e",
  green: "#28c840",
  // Syntax colors
  synPurple: "#c084fc",
  synBlue: "#60a5fa",
  synCyan: "#22d3ee",
  synGreen: "#4ade80",
  synOrange: "#fb923c",
  synPink: "#f472b6",
};

// ─── Timeline (frames @ 24fps) ──────────────────────────────────────
// 0-18     Desktop fades in
// 12-28    Shortcut hint "⌘⇧4" appears
// 26-62    Area selection draws
// 62-72    Capture flash
// 72-78    Desktop dims
// 72-108   Editor springs in
// 100-128  Arrow annotation draws
// 122-138  Text annotation appears
// 130-160  Overlay pops in
// 155-192  Hold / loop point

// ─── Sub-components ─────────────────────────────────────────────────

const TrafficLights: React.FC = () => (
  <div style={{ display: "flex", gap: 7, alignItems: "center" }}>
    <div style={{ width: 11, height: 11, borderRadius: "50%", background: C.red }} />
    <div style={{ width: 11, height: 11, borderRadius: "50%", background: C.yellow }} />
    <div style={{ width: 11, height: 11, borderRadius: "50%", background: C.green }} />
  </div>
);

const MenuBar: React.FC = () => (
  <div
    style={{
      position: "absolute",
      top: 0,
      left: 0,
      right: 0,
      height: 28,
      background: C.menuBar,
      borderBottom: `1px solid ${C.border}`,
      display: "flex",
      alignItems: "center",
      padding: "0 14px",
      justifyContent: "space-between",
      zIndex: 5,
    }}
  >
    <div style={{ display: "flex", gap: 14, alignItems: "center" }}>
      <svg width="13" height="15" viewBox="0 0 14 17" fill={C.text}>
        <path d="M10.3 0C10.3 0 11 2.3 9.1 3.8C7.3 5.2 5.6 4.4 5.6 4.4C5.6 4.4 4.8 2.2 6.7 0.7C8.1-0.4 10.3 0 10.3 0ZM7.5 5C8.3 5 9.8 3.9 11.5 3.9C14 3.9 15 5.8 15 5.8C15 5.8 12.8 7 12.8 9.7C12.8 12.9 15.6 14 15.6 14C15.6 14 13.7 18.5 11.1 18.5C9.9 18.5 9 17.7 7.8 17.7C6.6 17.7 5.4 18.5 4.5 18.5C2.2 18.5 0 14.2 0 10C0 6 2.4 4.8 4.2 4.8C5.8 5 7 6 7.5 5Z" transform="scale(0.8)" />
      </svg>
      <span style={{ fontSize: 11, fontWeight: 600, color: C.text }}>Finder</span>
      {["File", "Edit", "View", "Go"].map((t) => (
        <span key={t} style={{ fontSize: 11, color: C.dim }}>{t}</span>
      ))}
    </div>
    <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
      <span style={{ fontSize: 10.5, color: C.dim, fontVariantNumeric: "tabular-nums" }}>
        Mon 9:41 AM
      </span>
      <div
        style={{
          width: 13,
          height: 13,
          borderRadius: 3,
          background: `linear-gradient(135deg, ${C.accent}, ${C.purple})`,
        }}
      />
    </div>
  </div>
);

// Fake code lines for the editor window
const codeLinesData = [
  { indent: 0, segs: [{ c: C.synPurple, w: 48 }, { c: C.text, w: 30 }, { c: C.synGreen, w: 70 }] },
  { indent: 0, segs: [{ c: C.synPurple, w: 48 }, { c: C.text, w: 22 }, { c: C.synGreen, w: 56 }] },
  { indent: 0, segs: [] },
  { indent: 0, segs: [{ c: C.synCyan, w: 58 }, { c: C.synBlue, w: 80 }, { c: C.muted, w: 12 }] },
  { indent: 1, segs: [{ c: C.synPurple, w: 36 }, { c: C.text, w: 64 }, { c: C.synOrange, w: 40 }] },
  { indent: 1, segs: [{ c: C.synPurple, w: 36 }, { c: C.text, w: 44 }] },
  { indent: 1, segs: [] },
  { indent: 1, segs: [{ c: C.synCyan, w: 46 }, { c: C.muted, w: 12 }] },
  { indent: 2, segs: [{ c: C.synPink, w: 24 }, { c: C.synBlue, w: 90 }] },
  { indent: 3, segs: [{ c: C.text, w: 40 }, { c: C.synOrange, w: 60 }] },
  { indent: 3, segs: [{ c: C.text, w: 34 }, { c: C.synGreen, w: 70 }] },
  { indent: 3, segs: [{ c: C.text, w: 40 }, { c: C.synPurple, w: 48 }] },
  { indent: 2, segs: [{ c: C.synPink, w: 18 }] },
  { indent: 1, segs: [{ c: C.muted, w: 8 }] },
  { indent: 0, segs: [{ c: C.muted, w: 8 }] },
  { indent: 0, segs: [] },
  { indent: 0, segs: [{ c: C.synPurple, w: 48 }, { c: C.synCyan, w: 56 }, { c: C.text, w: 30 }] },
];

const CodeWindow: React.FC = () => (
  <div
    style={{
      position: "absolute",
      left: 32,
      top: 52,
      width: 470,
      height: 340,
      background: C.surface,
      borderRadius: 10,
      border: `1px solid ${C.border}`,
      overflow: "hidden",
      boxShadow: "0 20px 60px rgba(0,0,0,0.5)",
    }}
  >
    <div
      style={{
        height: 34,
        background: C.titleBar,
        borderBottom: `1px solid ${C.border}`,
        display: "flex",
        alignItems: "center",
        padding: "0 12px",
        gap: 8,
      }}
    >
      <TrafficLights />
      <div
        style={{
          display: "flex",
          gap: 1,
          marginLeft: 16,
        }}
      >
        {["App.tsx", "utils.ts"].map((tab, i) => (
          <div
            key={tab}
            style={{
              padding: "4px 14px",
              fontSize: 10.5,
              color: i === 0 ? C.text : C.muted,
              background: i === 0 ? "rgba(255,255,255,0.05)" : "transparent",
              borderRadius: 5,
            }}
          >
            {tab}
          </div>
        ))}
      </div>
    </div>
    {/* Sidebar + Code */}
    <div style={{ display: "flex", height: "calc(100% - 34px)" }}>
      {/* Mini sidebar */}
      <div
        style={{
          width: 36,
          background: "rgba(0,0,0,0.15)",
          borderRight: `1px solid ${C.border}`,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          padding: "10px 0",
          gap: 10,
        }}
      >
        {[C.dim, C.accent, C.dim, C.dim].map((c, i) => (
          <div
            key={i}
            style={{
              width: 16,
              height: 16,
              borderRadius: 3,
              border: `1.5px solid ${c}`,
              opacity: 0.5,
            }}
          />
        ))}
      </div>
      {/* Code area */}
      <div style={{ padding: "10px 14px", flex: 1 }}>
        {codeLinesData.map((line, i) => (
          <div
            key={i}
            style={{
              display: "flex",
              alignItems: "center",
              height: 16,
              gap: 8,
            }}
          >
            <span
              style={{
                fontSize: 9,
                color: C.muted,
                width: 18,
                textAlign: "right",
                flexShrink: 0,
                opacity: 0.6,
              }}
            >
              {i + 1}
            </span>
            <div
              style={{
                display: "flex",
                gap: 5,
                marginLeft: line.indent * 14,
              }}
            >
              {line.segs.map((seg, j) => (
                <div
                  key={j}
                  style={{
                    width: seg.w,
                    height: 8,
                    borderRadius: 2,
                    background: seg.c,
                    opacity: 0.55,
                  }}
                />
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  </div>
);

const BrowserWindow: React.FC = () => (
  <div
    style={{
      position: "absolute",
      right: 32,
      top: 90,
      width: 350,
      height: 300,
      background: "#1a1a26",
      borderRadius: 10,
      border: `1px solid ${C.border}`,
      overflow: "hidden",
      boxShadow: "0 16px 50px rgba(0,0,0,0.4)",
    }}
  >
    <div
      style={{
        height: 34,
        background: C.titleBar,
        borderBottom: `1px solid ${C.border}`,
        display: "flex",
        alignItems: "center",
        padding: "0 12px",
        gap: 8,
      }}
    >
      <TrafficLights />
      <div
        style={{
          marginLeft: 10,
          flex: 1,
          height: 20,
          background: "rgba(255,255,255,0.04)",
          borderRadius: 5,
          display: "flex",
          alignItems: "center",
          paddingLeft: 8,
        }}
      >
        <span style={{ fontSize: 10, color: C.muted }}>docs.snapper.tools</span>
      </div>
    </div>
    <div style={{ padding: "16px 18px" }}>
      {/* Heading */}
      <div
        style={{
          width: "75%",
          height: 13,
          background: C.text,
          opacity: 0.13,
          borderRadius: 3,
          marginBottom: 14,
        }}
      />
      {/* Text lines */}
      {[85, 60, 92, 40].map((w, i) => (
        <div
          key={i}
          style={{
            width: `${w}%`,
            height: 9,
            background: C.dim,
            opacity: 0.1,
            borderRadius: 2,
            marginBottom: 7,
          }}
        />
      ))}
      {/* Image placeholder */}
      <div
        style={{
          width: "100%",
          height: 75,
          background: `linear-gradient(135deg, rgba(99,102,241,0.12), rgba(139,92,246,0.08))`,
          borderRadius: 8,
          border: `1px solid rgba(99,102,241,0.08)`,
          marginTop: 10,
          marginBottom: 14,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <svg
          width="24"
          height="24"
          viewBox="0 0 24 24"
          fill="none"
          stroke={C.accent}
          strokeWidth="1.5"
          opacity={0.3}
        >
          <rect x="3" y="3" width="18" height="18" rx="2" />
          <circle cx="8.5" cy="8.5" r="1.5" />
          <path d="m21 15-5-5L5 21" />
        </svg>
      </div>
      {/* More text */}
      {[70, 55, 80].map((w, i) => (
        <div
          key={i}
          style={{
            width: `${w}%`,
            height: 9,
            background: C.dim,
            opacity: 0.1,
            borderRadius: 2,
            marginBottom: 7,
          }}
        />
      ))}
    </div>
  </div>
);

// ─── Editor Window ──────────────────────────────────────────────────

const editorTools = [
  // Arrow tool (selected)
  { icon: "arrow", active: true },
  // Rectangle
  { icon: "rect", active: false },
  // Text
  { icon: "text", active: false },
  // Blur
  { icon: "blur", active: false },
];

const EditorToolIcon: React.FC<{ icon: string; active: boolean }> = ({ icon, active }) => {
  const color = active ? C.white : C.dim;
  const bg = active ? C.accent : "transparent";

  return (
    <div
      style={{
        width: 30,
        height: 26,
        borderRadius: 5,
        background: bg,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      {icon === "arrow" && (
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2.5">
          <path d="M5 12h14M12 5l7 7-7 7" />
        </svg>
      )}
      {icon === "rect" && (
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2">
          <rect x="3" y="3" width="18" height="18" rx="2" />
        </svg>
      )}
      {icon === "text" && (
        <span style={{ fontSize: 13, fontWeight: 700, color }}>{`T`}</span>
      )}
      {icon === "blur" && (
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2">
          <circle cx="12" cy="12" r="9" strokeDasharray="3 3" />
        </svg>
      )}
    </div>
  );
};

const EditorWindow: React.FC<{
  scale: number;
  arrowProg: number;
  textOpacity: number;
}> = ({ scale, arrowProg, textOpacity }) => {
  const translateY = interpolate(scale, [0, 1], [40, 0]);
  const opacity = interpolate(scale, [0, 0.4], [0, 1], { extrapolateRight: "clamp" });

  // Arrow path: from (120, 180) to (320, 80) — a diagonal pointing at the "code"
  const ax1 = 340;
  const ay1 = 200;
  const ax2 = 160;
  const ay2 = 100;
  // Current endpoint based on progress
  const acx = interpolate(arrowProg, [0, 1], [ax1, ax2]);
  const acy = interpolate(arrowProg, [0, 1], [ay1, ay2]);

  // Arrowhead angle
  const angle = Math.atan2(ay2 - ay1, ax2 - ax1);
  const headLen = 10;

  return (
    <div
      style={{
        position: "absolute",
        left: 80,
        top: 30,
        width: 640,
        height: 420,
        opacity,
        transform: `translateY(${translateY}px) scale(${interpolate(scale, [0, 1], [0.95, 1])})`,
        zIndex: 20,
      }}
    >
      {/* Window */}
      <div
        style={{
          width: "100%",
          height: "100%",
          background: "#111118",
          borderRadius: 12,
          border: `1px solid ${C.border}`,
          overflow: "hidden",
          boxShadow: `0 30px 80px rgba(0,0,0,0.7), 0 0 60px rgba(99,102,241,0.08)`,
          display: "flex",
          flexDirection: "column",
        }}
      >
        {/* Title bar */}
        <div
          style={{
            height: 38,
            background: C.titleBar,
            borderBottom: `1px solid ${C.border}`,
            display: "flex",
            alignItems: "center",
            padding: "0 12px",
            justifyContent: "space-between",
            flexShrink: 0,
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <TrafficLights />
            <span style={{ fontSize: 11, color: C.dim, marginLeft: 6 }}>
              Screenshot — Snapper
            </span>
          </div>
          {/* Zoom controls */}
          <div style={{ display: "flex", gap: 4, alignItems: "center" }}>
            <span style={{ fontSize: 10, color: C.muted }}>100%</span>
          </div>
        </div>

        {/* Toolbar */}
        <div
          style={{
            height: 40,
            background: "rgba(255,255,255,0.02)",
            borderBottom: `1px solid ${C.border}`,
            display: "flex",
            alignItems: "center",
            padding: "0 10px",
            gap: 4,
            flexShrink: 0,
          }}
        >
          {/* Cursor tool */}
          <div
            style={{
              width: 30,
              height: 26,
              borderRadius: 5,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <svg width="12" height="14" viewBox="0 0 12 16" fill={C.dim}>
              <path d="M1 0L11 8H5L8 15L6 16L3 9L1 12Z" />
            </svg>
          </div>

          <div style={{ width: 1, height: 18, background: C.border, margin: "0 4px" }} />

          {editorTools.map((tool) => (
            <EditorToolIcon key={tool.icon} icon={tool.icon} active={tool.active} />
          ))}

          <div style={{ width: 1, height: 18, background: C.border, margin: "0 4px" }} />

          {/* Color swatch */}
          <div
            style={{
              width: 20,
              height: 20,
              borderRadius: 4,
              background: C.accent,
              border: "2px solid rgba(255,255,255,0.15)",
            }}
          />

          {/* Stroke width indicator */}
          <div
            style={{
              marginLeft: 4,
              display: "flex",
              gap: 3,
              alignItems: "center",
            }}
          >
            <div
              style={{
                width: 24,
                height: 3,
                borderRadius: 2,
                background: C.dim,
              }}
            />
          </div>
        </div>

        {/* Canvas area */}
        <div
          style={{
            flex: 1,
            background: "#0e0e16",
            position: "relative",
            overflow: "hidden",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          {/* Checkerboard-ish pattern behind screenshot */}
          <div
            style={{
              position: "absolute",
              inset: 0,
              opacity: 0.03,
              backgroundImage: `
                linear-gradient(45deg, #fff 25%, transparent 25%),
                linear-gradient(-45deg, #fff 25%, transparent 25%),
                linear-gradient(45deg, transparent 75%, #fff 75%),
                linear-gradient(-45deg, transparent 75%, #fff 75%)
              `,
              backgroundSize: "16px 16px",
              backgroundPosition: "0 0, 0 8px, 8px -8px, -8px 0px",
            }}
          />

          {/* The "captured screenshot" — simplified desktop content */}
          <div
            style={{
              width: 460,
              height: 290,
              borderRadius: 4,
              overflow: "hidden",
              position: "relative",
              boxShadow: "0 4px 24px rgba(0,0,0,0.3)",
            }}
          >
            {/* Mini desktop inside editor */}
            <div
              style={{
                width: "100%",
                height: "100%",
                background: C.bg,
                position: "relative",
              }}
            >
              {/* Mini code window */}
              <div
                style={{
                  position: "absolute",
                  left: 10,
                  top: 8,
                  width: 260,
                  height: 200,
                  background: C.surface,
                  borderRadius: 6,
                  border: `1px solid ${C.border}`,
                  overflow: "hidden",
                }}
              >
                <div
                  style={{
                    height: 20,
                    background: C.titleBar,
                    borderBottom: `1px solid ${C.border}`,
                    display: "flex",
                    alignItems: "center",
                    padding: "0 7px",
                    gap: 4,
                  }}
                >
                  {[C.red, C.yellow, C.green].map((c, i) => (
                    <div
                      key={i}
                      style={{ width: 7, height: 7, borderRadius: "50%", background: c }}
                    />
                  ))}
                </div>
                <div style={{ padding: "6px 10px" }}>
                  {codeLinesData.slice(0, 10).map((line, i) => (
                    <div
                      key={i}
                      style={{ display: "flex", gap: 3, height: 11, marginLeft: line.indent * 8 }}
                    >
                      {line.segs.map((seg, j) => (
                        <div
                          key={j}
                          style={{
                            width: seg.w * 0.55,
                            height: 5,
                            borderRadius: 1,
                            background: seg.c,
                            opacity: 0.5,
                          }}
                        />
                      ))}
                    </div>
                  ))}
                </div>
              </div>

              {/* Mini browser window */}
              <div
                style={{
                  position: "absolute",
                  right: 10,
                  top: 30,
                  width: 190,
                  height: 170,
                  background: "#1a1a26",
                  borderRadius: 6,
                  border: `1px solid ${C.border}`,
                  overflow: "hidden",
                }}
              >
                <div
                  style={{
                    height: 20,
                    background: C.titleBar,
                    borderBottom: `1px solid ${C.border}`,
                    display: "flex",
                    alignItems: "center",
                    padding: "0 7px",
                    gap: 4,
                  }}
                >
                  {[C.red, C.yellow, C.green].map((c, i) => (
                    <div
                      key={i}
                      style={{ width: 7, height: 7, borderRadius: "50%", background: c }}
                    />
                  ))}
                </div>
                <div style={{ padding: "8px 10px" }}>
                  {[70, 50, 85, 40, 60].map((w, i) => (
                    <div
                      key={i}
                      style={{
                        width: `${w}%`,
                        height: i === 0 ? 8 : 5,
                        background: C.dim,
                        opacity: i === 0 ? 0.12 : 0.08,
                        borderRadius: 2,
                        marginBottom: 5,
                      }}
                    />
                  ))}
                  <div
                    style={{
                      width: "100%",
                      height: 40,
                      background: `linear-gradient(135deg, rgba(99,102,241,0.1), rgba(139,92,246,0.06))`,
                      borderRadius: 4,
                      marginTop: 6,
                    }}
                  />
                </div>
              </div>
            </div>

            {/* Arrow annotation overlay */}
            {arrowProg > 0 && (
              <svg
                style={{
                  position: "absolute",
                  inset: 0,
                  width: "100%",
                  height: "100%",
                  pointerEvents: "none",
                }}
                viewBox="0 0 460 290"
              >
                {/* Arrow line */}
                <line
                  x1={ax1}
                  y1={ay1}
                  x2={acx}
                  y2={acy}
                  stroke={C.accent}
                  strokeWidth="3"
                  strokeLinecap="round"
                />
                {/* Arrowhead */}
                {arrowProg > 0.8 && (
                  <g opacity={interpolate(arrowProg, [0.8, 1], [0, 1])}>
                    <line
                      x1={ax2}
                      y1={ay2}
                      x2={ax2 - headLen * Math.cos(angle - 0.5)}
                      y2={ay2 - headLen * Math.sin(angle - 0.5)}
                      stroke={C.accent}
                      strokeWidth="3"
                      strokeLinecap="round"
                    />
                    <line
                      x1={ax2}
                      y1={ay2}
                      x2={ax2 - headLen * Math.cos(angle + 0.5)}
                      y2={ay2 - headLen * Math.sin(angle + 0.5)}
                      stroke={C.accent}
                      strokeWidth="3"
                      strokeLinecap="round"
                    />
                  </g>
                )}
              </svg>
            )}

            {/* Text annotation */}
            {textOpacity > 0 && (
              <div
                style={{
                  position: "absolute",
                  left: 320,
                  top: 206,
                  background: C.accent,
                  color: C.white,
                  padding: "4px 10px",
                  borderRadius: 4,
                  fontSize: 11,
                  fontWeight: 600,
                  opacity: textOpacity,
                  transform: `scale(${interpolate(textOpacity, [0, 1], [0.8, 1])})`,
                  whiteSpace: "nowrap",
                }}
              >
                Check this!
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

// ─── Quick Access Overlay ───────────────────────────────────────────

const QuickOverlay: React.FC<{ progress: number }> = ({ progress }) => {
  const translateY = interpolate(progress, [0, 1], [20, 0]);
  const opacity = interpolate(progress, [0, 0.5], [0, 1], { extrapolateRight: "clamp" });
  const scale = interpolate(progress, [0, 1], [0.9, 1]);

  return (
    <div
      style={{
        position: "absolute",
        right: 24,
        bottom: 24,
        opacity,
        transform: `translateY(${translateY}px) scale(${scale})`,
        zIndex: 30,
      }}
    >
      <div
        style={{
          width: 200,
          background: "rgba(22,22,30,0.95)",
          borderRadius: 12,
          border: `1px solid ${C.border}`,
          overflow: "hidden",
          boxShadow: "0 16px 48px rgba(0,0,0,0.6), 0 0 24px rgba(99,102,241,0.06)",
        }}
      >
        {/* Thumbnail */}
        <div
          style={{
            width: "100%",
            height: 110,
            background: C.bg,
            position: "relative",
            overflow: "hidden",
          }}
        >
          {/* Tiny preview of the screenshot */}
          <div
            style={{
              width: "100%",
              height: "100%",
              background: `linear-gradient(135deg, ${C.surface}, #1a1a26)`,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <div style={{ opacity: 0.5, transform: "scale(0.35)", transformOrigin: "center" }}>
              <div style={{ display: "flex", gap: 8 }}>
                <div
                  style={{
                    width: 140,
                    height: 100,
                    background: C.surface,
                    borderRadius: 4,
                    border: `1px solid ${C.border}`,
                  }}
                />
                <div
                  style={{
                    width: 100,
                    height: 80,
                    background: "#1a1a26",
                    borderRadius: 4,
                    border: `1px solid ${C.border}`,
                    marginTop: 12,
                  }}
                />
              </div>
            </div>
          </div>
        </div>

        {/* Action bar */}
        <div
          style={{
            display: "flex",
            justifyContent: "center",
            gap: 8,
            padding: "10px 12px",
            borderTop: `1px solid ${C.border}`,
          }}
        >
          {/* Copy */}
          <OverlayButton icon="copy" />
          {/* Save */}
          <OverlayButton icon="save" />
          {/* Annotate */}
          <OverlayButton icon="edit" />
          {/* Pin */}
          <OverlayButton icon="pin" />
          {/* Close */}
          <OverlayButton icon="close" />
        </div>
      </div>
    </div>
  );
};

const OverlayButton: React.FC<{ icon: string }> = ({ icon }) => (
  <div
    style={{
      width: 28,
      height: 28,
      borderRadius: 6,
      background: "rgba(255,255,255,0.05)",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
    }}
  >
    <svg
      width="13"
      height="13"
      viewBox="0 0 24 24"
      fill="none"
      stroke={icon === "close" ? C.muted : C.dim}
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      {icon === "copy" && (
        <>
          <rect x="9" y="9" width="13" height="13" rx="2" />
          <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
        </>
      )}
      {icon === "save" && (
        <>
          <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
          <polyline points="7 10 12 15 17 10" />
          <line x1="12" y1="15" x2="12" y2="3" />
        </>
      )}
      {icon === "edit" && <path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z" />}
      {icon === "pin" && (
        <>
          <line x1="12" y1="17" x2="12" y2="22" />
          <path d="M5 17h14v-1.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V6h1a2 2 0 0 0 0-4H8a2 2 0 0 0 0 4h1v4.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24Z" />
        </>
      )}
      {icon === "close" && (
        <>
          <line x1="18" y1="6" x2="6" y2="18" />
          <line x1="6" y1="6" x2="18" y2="18" />
        </>
      )}
    </svg>
  </div>
);

// ─── Main Composition ───────────────────────────────────────────────

export const SnapperDemo: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // ── Desktop ──
  const desktopOpacity = interpolate(frame, [0, 18], [0, 1], {
    extrapolateRight: "clamp",
  });

  // ── Keyboard hint ──
  const hintOpacity = interpolate(frame, [12, 20, 55, 62], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // ── Selection ──
  const selectionActive = frame >= 26 && frame < 70;
  const selectionProgress = interpolate(frame, [26, 60], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  // ── Flash ──
  const flashOpacity = interpolate(frame, [60, 63, 70], [0, 0.65, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // ── Desktop dims after capture ──
  const desktopDim = frame >= 70
    ? interpolate(frame, [70, 82], [1, 0], { extrapolateRight: "clamp" })
    : 1;

  // ── Editor ──
  const editorSpring = frame >= 72
    ? spring({
        frame: frame - 72,
        fps,
        config: { damping: 13, stiffness: 110, mass: 0.8 },
      })
    : 0;

  // ── Arrow ──
  const arrowProg = interpolate(frame, [102, 126], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.quad),
  });

  // ── Text ──
  const textOpacity = frame >= 122
    ? spring({
        frame: frame - 122,
        fps,
        config: { damping: 12, stiffness: 100 },
      })
    : 0;

  // ── Quick Overlay ──
  const overlayProg = frame >= 138
    ? spring({
        frame: frame - 138,
        fps,
        config: { damping: 11, stiffness: 80, mass: 0.9 },
      })
    : 0;

  // Selection box area
  const selX = 180;
  const selY = 75;
  const selW = 440;
  const selH = 290;
  const curW = selW * selectionProgress;
  const curH = selH * selectionProgress;

  return (
    <AbsoluteFill
      style={{
        backgroundColor: C.bg,
        fontFamily: "'Inter', -apple-system, system-ui, sans-serif",
      }}
    >
      {/* Desktop layer */}
      <div style={{ opacity: desktopOpacity * desktopDim }}>
        <MenuBar />
        <CodeWindow />
        <BrowserWindow />
      </div>

      {/* Selection overlay */}
      {selectionActive && selectionProgress > 0 && (
        <>
          {/* Selection box with massive shadow to darken outside */}
          <div
            style={{
              position: "absolute",
              left: selX,
              top: selY,
              width: curW,
              height: curH,
              boxShadow: `0 0 0 2000px rgba(0,0,0,0.4)`,
              zIndex: 10,
            }}
          />
          {/* Border */}
          <div
            style={{
              position: "absolute",
              left: selX - 1,
              top: selY - 1,
              width: curW + 2,
              height: curH + 2,
              border: `1.5px solid rgba(255,255,255,0.8)`,
              borderRadius: 1,
              zIndex: 11,
              boxShadow: "0 0 8px rgba(0,0,0,0.4)",
            }}
          />
          {/* Crosshairs */}
          <div
            style={{
              position: "absolute",
              left: selX + curW,
              top: 0,
              width: 1,
              height: 500,
              background: "rgba(255,255,255,0.15)",
              zIndex: 11,
            }}
          />
          <div
            style={{
              position: "absolute",
              top: selY + curH,
              left: 0,
              width: 800,
              height: 1,
              background: "rgba(255,255,255,0.15)",
              zIndex: 11,
            }}
          />
          {/* Dimension label */}
          {selectionProgress > 0.2 && (
            <div
              style={{
                position: "absolute",
                left: selX + curW / 2 - 38,
                top: selY + curH + 8,
                background: "rgba(0,0,0,0.75)",
                borderRadius: 5,
                padding: "3px 10px",
                fontSize: 10.5,
                fontWeight: 500,
                color: C.white,
                opacity: interpolate(selectionProgress, [0.2, 0.4], [0, 1], {
                  extrapolateRight: "clamp",
                }),
                zIndex: 12,
                fontVariantNumeric: "tabular-nums",
              }}
            >
              {Math.round(curW)} × {Math.round(curH)}
            </div>
          )}
        </>
      )}

      {/* Flash */}
      {flashOpacity > 0 && (
        <div
          style={{
            position: "absolute",
            inset: 0,
            background: C.white,
            opacity: flashOpacity,
            zIndex: 15,
          }}
        />
      )}

      {/* Editor */}
      {editorSpring > 0 && (
        <EditorWindow
          scale={editorSpring}
          arrowProg={arrowProg}
          textOpacity={textOpacity}
        />
      )}

      {/* Quick overlay */}
      {overlayProg > 0 && <QuickOverlay progress={overlayProg} />}

      {/* Keyboard shortcut hint */}
      {hintOpacity > 0 && (
        <div
          style={{
            position: "absolute",
            bottom: 32,
            left: "50%",
            transform: "translateX(-50%)",
            background: "rgba(0,0,0,0.65)",
            borderRadius: 10,
            padding: "7px 14px",
            display: "flex",
            gap: 5,
            alignItems: "center",
            opacity: hintOpacity,
            zIndex: 8,
          }}
        >
          {["⌘", "⇧", "4"].map((key) => (
            <span
              key={key}
              style={{
                background: "rgba(255,255,255,0.08)",
                borderRadius: 5,
                padding: "3px 9px",
                fontSize: 13,
                fontWeight: 600,
                color: C.text,
                border: "1px solid rgba(255,255,255,0.08)",
                lineHeight: 1.2,
              }}
            >
              {key}
            </span>
          ))}
        </div>
      )}

      {/* Subtle corner vignette */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(ellipse 80% 60% at 50% 40%, transparent 50%, rgba(0,0,0,0.3) 100%)",
          pointerEvents: "none",
          zIndex: 0,
        }}
      />

      {/* Snapper watermark */}
      <div
        style={{
          position: "absolute",
          bottom: 10,
          right: 14,
          fontSize: 9,
          color: C.muted,
          opacity: 0.4,
          letterSpacing: "0.05em",
          zIndex: 40,
        }}
      >
        snapper.tools
      </div>
    </AbsoluteFill>
  );
};
