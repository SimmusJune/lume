const fs = require("fs");
const path = require("path");

const root = process.cwd();
const iconPath = path.join(root, "Lume/Assets.xcassets/AppIcon.appiconset/lume.jpg");
const outputDir = path.join(root, "appstore-assets");
const screenshotsDir = path.join(outputDir, "screenshots-6.7");
const previewDir = path.join(outputDir, "preview");

fs.mkdirSync(screenshotsDir, { recursive: true });
fs.mkdirSync(previewDir, { recursive: true });

const iconBase64 = fs.readFileSync(iconPath).toString("base64");
const iconHref = `data:image/jpeg;base64,${iconBase64}`;

const portrait = { width: 1290, height: 2796 };
const landscape = { width: 1920, height: 1080 };

function writeFile(filePath, content) {
  fs.writeFileSync(filePath, content, "utf8");
}

function escapeXml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function wrapLines(text, maxChars) {
  const words = text.split(/\s+/);
  const lines = [];
  let current = "";
  for (const word of words) {
    const next = current ? `${current} ${word}` : word;
    if (next.length > maxChars && current) {
      lines.push(current);
      current = word;
    } else {
      current = next;
    }
  }
  if (current) lines.push(current);
  return lines;
}

function textBlock(lines, x, y, size, lineHeight, fill, weight = 700, opacity = 1) {
  return lines
    .map((line, index) => {
      const dy = index * lineHeight;
      return `<text x="${x}" y="${y + dy}" font-size="${size}" font-weight="${weight}" fill="${fill}" fill-opacity="${opacity}" font-family="SF Pro Display, Inter, Arial, sans-serif">${escapeXml(line)}</text>`;
    })
    .join("\n");
}

function card({ x, y, width, height, radius = 34, fill = "rgba(255,255,255,0.13)", stroke = "rgba(255,255,255,0.20)" }) {
  return `<rect x="${x}" y="${y}" width="${width}" height="${height}" rx="${radius}" fill="${fill}" stroke="${stroke}" stroke-width="2"/>`;
}

function mediaRow({ x, y, title, subtitle, accent }) {
  return `
    <g transform="translate(${x}, ${y})">
      <rect width="640" height="150" rx="28" fill="rgba(8,11,20,0.86)" stroke="rgba(255,255,255,0.08)" stroke-width="2"/>
      <rect x="22" y="20" width="110" height="110" rx="26" fill="url(#warmGlow)"/>
      <image href="${iconHref}" x="34" y="32" width="86" height="86" preserveAspectRatio="xMidYMid meet" clip-path="url(#thumbClip)"/>
      <text x="160" y="64" font-size="38" font-weight="700" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">${escapeXml(title)}</text>
      <text x="160" y="108" font-size="26" font-weight="500" fill="rgba(255,255,255,0.62)" font-family="SF Pro Text, Inter, Arial, sans-serif">${escapeXml(subtitle)}</text>
      <rect x="510" y="46" width="96" height="58" rx="29" fill="${accent}"/>
      <polygon points="548,60 548,90 578,75" fill="#0d1118"/>
    </g>
  `;
}

function favoritePill({ x, y, label, color }) {
  const width = Math.max(170, label.length * 19);
  return `
    <g transform="translate(${x}, ${y})">
      <rect width="${width}" height="74" rx="37" fill="${color}" fill-opacity="0.18" stroke="${color}" stroke-opacity="0.42" stroke-width="2"/>
      <text x="28" y="47" font-size="28" font-weight="700" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">${escapeXml(label)}</text>
    </g>
  `;
}

function statColumn({ x, y, label, value, height, color }) {
  return `
    <g transform="translate(${x}, ${y})">
      <rect x="0" y="${150 - height}" width="52" height="${height}" rx="18" fill="${color}"/>
      <text x="26" y="182" text-anchor="middle" font-size="22" font-weight="700" fill="rgba(255,255,255,0.7)" font-family="SF Pro Text, Inter, Arial, sans-serif">${escapeXml(label)}</text>
      <text x="26" y="${150 - height - 14}" text-anchor="middle" font-size="18" font-weight="700" fill="#ffffff" font-family="SF Pro Text, Inter, Arial, sans-serif">${escapeXml(value)}</text>
    </g>
  `;
}

function phoneShell(innerContent) {
  return `
    <g transform="translate(155, 740)">
      <rect x="0" y="0" width="980" height="1760" rx="120" fill="#091019"/>
      <rect x="24" y="24" width="932" height="1712" rx="100" fill="url(#screenBg)"/>
      <rect x="350" y="54" width="280" height="48" rx="24" fill="#090c11"/>
      ${innerContent}
    </g>
  `;
}

function screenshotSvg({ eyebrow, title, body, screenContent, palette }) {
  const titleLines = wrapLines(title, 16);
  const bodyLines = wrapLines(body, 30);
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${portrait.width}" height="${portrait.height}" viewBox="0 0 ${portrait.width} ${portrait.height}">
  <defs>
    <linearGradient id="bgGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="${palette[0]}"/>
      <stop offset="48%" stop-color="${palette[1]}"/>
      <stop offset="100%" stop-color="${palette[2]}"/>
    </linearGradient>
    <linearGradient id="screenBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#090c10"/>
      <stop offset="58%" stop-color="#10151d"/>
      <stop offset="100%" stop-color="#0c1016"/>
    </linearGradient>
    <linearGradient id="warmGlow" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#ffb100"/>
      <stop offset="52%" stop-color="#ff27d3"/>
      <stop offset="100%" stop-color="#1ac7ff"/>
    </linearGradient>
    <clipPath id="thumbClip">
      <rect x="34" y="32" width="86" height="86" rx="24"/>
    </clipPath>
    <filter id="blurA">
      <feGaussianBlur stdDeviation="80"/>
    </filter>
  </defs>
  <rect width="100%" height="100%" fill="url(#bgGrad)"/>
  <circle cx="1100" cy="200" r="260" fill="rgba(255,255,255,0.18)" filter="url(#blurA)"/>
  <circle cx="240" cy="2440" r="340" fill="rgba(255,255,255,0.10)" filter="url(#blurA)"/>
  <circle cx="920" cy="1840" r="420" fill="rgba(255,255,255,0.08)" filter="url(#blurA)"/>

  <g transform="translate(96, 112)">
    <rect x="0" y="0" width="170" height="54" rx="27" fill="rgba(255,255,255,0.18)" stroke="rgba(255,255,255,0.22)" stroke-width="2"/>
    <text x="28" y="36" font-size="25" font-weight="700" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">${escapeXml(eyebrow)}</text>
  </g>

  ${textBlock(titleLines, 96, 274, 104, 116, "#ffffff", 800)}
  ${textBlock(bodyLines, 96, 570, 40, 58, "#ffffff", 500, 0.82)}

  <g transform="translate(950, 160)">
    <rect x="0" y="0" width="200" height="200" rx="54" fill="rgba(255,255,255,0.14)"/>
    <image href="${iconHref}" x="16" y="16" width="168" height="168" preserveAspectRatio="xMidYMid meet"/>
  </g>

  ${phoneShell(screenContent)}

  <text x="645" y="2690" text-anchor="middle" font-size="30" font-weight="700" fill="rgba(255,255,255,0.88)" font-family="SF Pro Display, Inter, Arial, sans-serif">Lume</text>
</svg>`;
}

function previewSvg() {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${landscape.width}" height="${landscape.height}" viewBox="0 0 ${landscape.width} ${landscape.height}">
  <defs>
    <linearGradient id="previewBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#ffae00"/>
      <stop offset="42%" stop-color="#ff28d4"/>
      <stop offset="100%" stop-color="#16bbff"/>
    </linearGradient>
    <filter id="previewBlur">
      <feGaussianBlur stdDeviation="90"/>
    </filter>
  </defs>
  <rect width="100%" height="100%" fill="#091018"/>
  <circle cx="210" cy="150" r="290" fill="#ffb100" fill-opacity="0.55" filter="url(#previewBlur)"/>
  <circle cx="1720" cy="180" r="260" fill="#ff20d1" fill-opacity="0.42" filter="url(#previewBlur)"/>
  <circle cx="1550" cy="940" r="320" fill="#14beff" fill-opacity="0.36" filter="url(#previewBlur)"/>

  <rect x="58" y="58" width="1804" height="964" rx="44" fill="rgba(255,255,255,0.06)" stroke="rgba(255,255,255,0.12)" stroke-width="2"/>

  <g transform="translate(140, 190)">
    <rect x="0" y="0" width="360" height="360" rx="94" fill="rgba(255,255,255,0.10)"/>
    <image href="${iconHref}" x="28" y="28" width="304" height="304" preserveAspectRatio="xMidYMid meet"/>
  </g>

  <text x="560" y="312" font-size="116" font-weight="800" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">Lume</text>
  <text x="560" y="430" font-size="56" font-weight="600" fill="rgba(255,255,255,0.84)" font-family="SF Pro Display, Inter, Arial, sans-serif">Play Your Media Universe</text>
  <text x="560" y="544" font-size="34" font-weight="500" fill="rgba(255,255,255,0.74)" font-family="SF Pro Text, Inter, Arial, sans-serif">Import your library, organize favorites, and keep playback flowing.</text>

  <g transform="translate(560, 644)">
    <rect x="0" y="0" width="170" height="170" rx="44" fill="url(#previewBg)"/>
    <polygon points="66,48 66,122 128,85" fill="#0a1016"/>
    <text x="214" y="72" font-size="44" font-weight="700" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">Background Playback</text>
    <text x="214" y="138" font-size="44" font-weight="700" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">Favorites & Tags</text>
    <text x="214" y="204" font-size="44" font-weight="700" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">Listening Stats</text>
  </g>
  <text x="960" y="950" text-anchor="middle" font-size="30" font-weight="700" fill="rgba(255,255,255,0.70)" font-family="SF Pro Text, Inter, Arial, sans-serif">App Preview Cover</text>
</svg>`;
}

const screen1 = `
  <g transform="translate(60, 140)">
    <text x="0" y="0" font-size="68" font-weight="800" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">Explore</text>
    <text x="0" y="56" font-size="28" font-weight="600" fill="rgba(255,255,255,0.58)" font-family="SF Pro Text, Inter, Arial, sans-serif">Local Library</text>
    <rect x="688" y="-18" width="124" height="124" rx="42" fill="rgba(255,255,255,0.08)"/>
    <image href="${iconHref}" x="706" y="0" width="88" height="88" preserveAspectRatio="xMidYMid meet"/>
  </g>
  <g transform="translate(60, 316)">
    <rect x="0" y="0" width="812" height="108" rx="34" fill="rgba(255,255,255,0.08)" stroke="rgba(255,255,255,0.10)" stroke-width="2"/>
    <circle cx="54" cy="54" r="14" fill="rgba(255,255,255,0.66)"/>
    <rect x="90" y="39" width="286" height="30" rx="15" fill="rgba(255,255,255,0.22)"/>
  </g>
  ${mediaRow({ x: 60, y: 486, title: "10 Apples On My Head", subtitle: "SSS · Audio", accent: "#9dff85" })}
  ${mediaRow({ x: 60, y: 668, title: "8 Little Planets", subtitle: "SSS · Audio", accent: "#ffd166" })}
  ${mediaRow({ x: 60, y: 850, title: "Adding Up To 10", subtitle: "SSS · Audio", accent: "#78ddff" })}
  <g transform="translate(60, 1076)">
    <rect x="0" y="0" width="812" height="466" rx="46" fill="rgba(255,255,255,0.06)" stroke="rgba(255,255,255,0.10)" stroke-width="2"/>
    <text x="36" y="64" font-size="38" font-weight="700" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">Mini Player</text>
    <rect x="34" y="104" width="130" height="130" rx="34" fill="url(#warmGlow)"/>
    <image href="${iconHref}" x="50" y="120" width="98" height="98" preserveAspectRatio="xMidYMid meet"/>
    <text x="196" y="162" font-size="40" font-weight="700" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">Play your library instantly</text>
    <text x="196" y="210" font-size="28" font-weight="500" fill="rgba(255,255,255,0.64)" font-family="SF Pro Text, Inter, Arial, sans-serif">Tap any item and resume your queue</text>
    <rect x="40" y="296" width="730" height="10" rx="5" fill="rgba(255,255,255,0.12)"/>
    <rect x="40" y="296" width="416" height="10" rx="5" fill="#9dff85"/>
    <circle cx="396" cy="300" r="22" fill="#ffffff"/>
    <circle cx="406" cy="300" r="14" fill="#0b1117"/>
    <circle cx="264" cy="380" r="44" fill="rgba(255,255,255,0.14)"/>
    <polygon points="250,380 250,360 280,380 250,400" fill="#ffffff"/>
    <circle cx="406" cy="380" r="58" fill="#ffffff"/>
    <rect x="392" y="358" width="12" height="44" rx="6" fill="#0b1117"/>
    <rect x="414" y="358" width="12" height="44" rx="6" fill="#0b1117"/>
    <circle cx="548" cy="380" r="44" fill="rgba(255,255,255,0.14)"/>
    <polygon points="536,360 536,400 566,380" fill="#ffffff"/>
  </g>
`;

const screen2 = `
  <g transform="translate(60, 140)">
    <text x="0" y="0" font-size="68" font-weight="800" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">Favorites</text>
    <text x="0" y="56" font-size="28" font-weight="600" fill="rgba(255,255,255,0.58)" font-family="SF Pro Text, Inter, Arial, sans-serif">Groups that fit the way you listen</text>
  </g>
  <g transform="translate(60, 280)">
    <rect x="0" y="0" width="812" height="286" rx="42" fill="rgba(255,255,255,0.07)" stroke="rgba(255,255,255,0.12)" stroke-width="2"/>
    <text x="34" y="56" font-size="34" font-weight="700" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">Favorite Groups</text>
    <rect x="34" y="92" width="350" height="150" rx="34" fill="rgba(157,255,133,0.20)" stroke="rgba(157,255,133,0.60)" stroke-width="2"/>
    <text x="62" y="156" font-size="40" font-weight="700" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">My Audios</text>
    <text x="62" y="206" font-size="26" font-weight="600" fill="rgba(255,255,255,0.64)" font-family="SF Pro Text, Inter, Arial, sans-serif">Quick access to saved tracks</text>
    <rect x="426" y="92" width="350" height="150" rx="34" fill="rgba(120,221,255,0.18)" stroke="rgba(120,221,255,0.54)" stroke-width="2"/>
    <text x="454" y="156" font-size="40" font-weight="700" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">Unfavorited</text>
    <text x="454" y="206" font-size="26" font-weight="600" fill="rgba(255,255,255,0.64)" font-family="SF Pro Text, Inter, Arial, sans-serif">Catch what you still need to sort</text>
  </g>
  <g transform="translate(60, 636)">
    <rect x="0" y="0" width="812" height="260" rx="42" fill="rgba(255,255,255,0.07)" stroke="rgba(255,255,255,0.12)" stroke-width="2"/>
    <text x="34" y="56" font-size="34" font-weight="700" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">Tag Playlists</text>
    ${favoritePill({ x: 34, y: 98, label: "SSS", color: "#ffb100" })}
    ${favoritePill({ x: 242, y: 98, label: "Study", color: "#ff2fd1" })}
    ${favoritePill({ x: 478, y: 98, label: "Focus", color: "#19c5ff" })}
    ${favoritePill({ x: 34, y: 188, label: "English", color: "#9dff85" })}
    ${favoritePill({ x: 290, y: 188, label: "Kids", color: "#ffd166" })}
  </g>
  ${mediaRow({ x: 60, y: 966, title: "Can You Make A Happy Face?", subtitle: "Saved to My Audios", accent: "#ffb100" })}
  ${mediaRow({ x: 60, y: 1148, title: "And The Green Grass Grew", subtitle: "Tagged with SSS", accent: "#19c5ff" })}
  <g transform="translate(60, 1340)">
    <rect x="0" y="0" width="812" height="202" rx="42" fill="rgba(255,255,255,0.07)" stroke="rgba(255,255,255,0.12)" stroke-width="2"/>
    <text x="34" y="64" font-size="34" font-weight="700" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">Build a library that feels personal</text>
    <text x="34" y="116" font-size="28" font-weight="500" fill="rgba(255,255,255,0.64)" font-family="SF Pro Text, Inter, Arial, sans-serif">Create groups, remove clutter, and jump into the right playlist faster.</text>
  </g>
`;

const screen3 = `
  <g transform="translate(60, 140)">
    <text x="0" y="0" font-size="68" font-weight="800" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">Profile</text>
    <text x="0" y="56" font-size="28" font-weight="600" fill="rgba(255,255,255,0.58)" font-family="SF Pro Text, Inter, Arial, sans-serif">See how your listening adds up</text>
  </g>
  <g transform="translate(60, 286)">
    <rect x="0" y="0" width="812" height="220" rx="42" fill="rgba(255,255,255,0.08)" stroke="rgba(255,255,255,0.12)" stroke-width="2"/>
    <text x="36" y="64" font-size="30" font-weight="700" fill="rgba(255,255,255,0.70)" font-family="SF Pro Text, Inter, Arial, sans-serif">Total Play Time</text>
    <text x="36" y="154" font-size="92" font-weight="800" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">128h</text>
    <text x="358" y="154" font-size="48" font-weight="700" fill="rgba(255,255,255,0.70)" font-family="SF Pro Display, Inter, Arial, sans-serif">42m</text>
  </g>
  <g transform="translate(60, 556)">
    <rect x="0" y="0" width="812" height="486" rx="42" fill="rgba(255,255,255,0.08)" stroke="rgba(255,255,255,0.12)" stroke-width="2"/>
    <text x="36" y="64" font-size="34" font-weight="700" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">Playback Stats</text>
    ${statColumn({ x: 58, y: 240, label: "Mon", value: "1.2h", height: 80, color: "#ffb100" })}
    ${statColumn({ x: 148, y: 240, label: "Tue", value: "2.4h", height: 132, color: "#ff56c7" })}
    ${statColumn({ x: 238, y: 240, label: "Wed", value: "3.1h", height: 170, color: "#6f6dff" })}
    ${statColumn({ x: 328, y: 240, label: "Thu", value: "1.8h", height: 108, color: "#2f9bff" })}
    ${statColumn({ x: 418, y: 240, label: "Fri", value: "4.3h", height: 210, color: "#19c5ff" })}
    ${statColumn({ x: 508, y: 240, label: "Sat", value: "2.0h", height: 124, color: "#3ce5b3" })}
    ${statColumn({ x: 598, y: 240, label: "Sun", value: "3.6h", height: 188, color: "#9dff85" })}
    <g transform="translate(40, 96)">
      <rect x="0" y="0" width="160" height="52" rx="26" fill="rgba(255,255,255,0.10)"/>
      <text x="44" y="35" font-size="22" font-weight="700" fill="#ffffff" font-family="SF Pro Text, Inter, Arial, sans-serif">Day</text>
      <rect x="178" y="0" width="160" height="52" rx="26" fill="rgba(255,255,255,0.05)"/>
      <text x="214" y="35" font-size="22" font-weight="700" fill="rgba(255,255,255,0.54)" font-family="SF Pro Text, Inter, Arial, sans-serif">Month</text>
      <rect x="356" y="0" width="160" height="52" rx="26" fill="rgba(255,255,255,0.05)"/>
      <text x="410" y="35" font-size="22" font-weight="700" fill="rgba(255,255,255,0.54)" font-family="SF Pro Text, Inter, Arial, sans-serif">Year</text>
    </g>
  </g>
  <g transform="translate(60, 1090)">
    <rect x="0" y="0" width="812" height="452" rx="42" fill="rgba(255,255,255,0.08)" stroke="rgba(255,255,255,0.12)" stroke-width="2"/>
    <text x="36" y="64" font-size="34" font-weight="700" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">Monthly Heatmap</text>
    ${Array.from({ length: 5 })
      .map((_, row) =>
        Array.from({ length: 7 })
          .map((__, col) => {
            const tones = ["rgba(255,255,255,0.06)", "rgba(255,177,0,0.28)", "rgba(255,46,205,0.32)", "rgba(25,197,255,0.30)", "rgba(157,255,133,0.30)"];
            const tone = tones[(row * 7 + col) % tones.length];
            return `<rect x="${36 + col * 106}" y="${104 + row * 62}" width="74" height="42" rx="16" fill="${tone}"/>`;
          })
          .join("")
      )
      .join("")}
  </g>
`;

const screen4 = `
  <g transform="translate(60, 130)">
    <text x="0" y="0" font-size="68" font-weight="800" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">Now Playing</text>
    <text x="0" y="56" font-size="28" font-weight="600" fill="rgba(255,255,255,0.58)" font-family="SF Pro Text, Inter, Arial, sans-serif">Queue, shuffle, and background audio</text>
  </g>
  <g transform="translate(120, 300)">
    <rect x="0" y="0" width="692" height="692" rx="70" fill="rgba(255,255,255,0.07)" stroke="rgba(255,255,255,0.14)" stroke-width="2"/>
    <circle cx="346" cy="346" r="250" fill="url(#warmGlow)"/>
    <circle cx="346" cy="346" r="124" fill="rgba(255,255,255,0.88)"/>
    <image href="${iconHref}" x="258" y="258" width="176" height="176" preserveAspectRatio="xMidYMid meet"/>
  </g>
  <g transform="translate(60, 1060)">
    <text x="0" y="0" font-size="52" font-weight="800" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">10 Apples On My Head</text>
    <text x="0" y="60" font-size="30" font-weight="600" fill="rgba(255,255,255,0.62)" font-family="SF Pro Text, Inter, Arial, sans-serif">From Playlist · SSS</text>
    <rect x="0" y="126" width="812" height="12" rx="6" fill="rgba(255,255,255,0.12)"/>
    <rect x="0" y="126" width="492" height="12" rx="6" fill="#9dff85"/>
    <circle cx="492" cy="132" r="22" fill="#ffffff"/>
    <text x="0" y="188" font-size="24" font-weight="700" fill="rgba(255,255,255,0.62)" font-family="SF Pro Text, Inter, Arial, sans-serif">1:34</text>
    <text x="740" y="188" font-size="24" font-weight="700" fill="rgba(255,255,255,0.62)" font-family="SF Pro Text, Inter, Arial, sans-serif">5:26</text>
  </g>
  <g transform="translate(86, 1280)">
    <circle cx="110" cy="110" r="58" fill="rgba(255,255,255,0.16)"/>
    <text x="90" y="124" font-size="48" font-weight="700" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">↺</text>
    <circle cx="306" cy="110" r="58" fill="rgba(255,255,255,0.16)"/>
    <text x="286" y="124" font-size="48" font-weight="700" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">⏮</text>
    <circle cx="502" cy="110" r="82" fill="#ffffff"/>
    <text x="472" y="128" font-size="64" font-weight="800" fill="#0b1117" font-family="SF Pro Display, Inter, Arial, sans-serif">❚❚</text>
    <circle cx="698" cy="110" r="58" fill="rgba(255,255,255,0.16)"/>
    <text x="678" y="124" font-size="48" font-weight="700" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">⏭</text>
  </g>
  <g transform="translate(60, 1524)">
    <rect x="0" y="0" width="812" height="324" rx="42" fill="rgba(255,255,255,0.08)" stroke="rgba(255,255,255,0.12)" stroke-width="2"/>
    <text x="34" y="64" font-size="34" font-weight="700" fill="#ffffff" font-family="SF Pro Display, Inter, Arial, sans-serif">Queue</text>
    ${mediaRow({ x: 18, y: 88, title: "8 Little Planets", subtitle: "Up next", accent: "#ffd166" })}
  </g>
`;

const assets = [
  {
    file: path.join(screenshotsDir, "01-play-your-media-universe.svg"),
    content: screenshotSvg({
      eyebrow: "Library",
      title: "Play your media universe",
      body: "Import your own collection and jump straight into a polished local library built for audio playback.",
      screenContent: screen1,
      palette: ["#ffb100", "#ff2fd1", "#1ac5ff"],
    }),
  },
  {
    file: path.join(screenshotsDir, "02-organize-favorites-and-tags.svg"),
    content: screenshotSvg({
      eyebrow: "Organize",
      title: "Sort favorites and tags your way",
      body: "Group what matters, surface unfavorited tracks, and turn tags into playlists that stay ready to play.",
      screenContent: screen2,
      palette: ["#0f1420", "#1d2a44", "#ff2fd1"],
    }),
  },
  {
    file: path.join(screenshotsDir, "03-track-your-listening.svg"),
    content: screenshotSvg({
      eyebrow: "Stats",
      title: "Track every listening session",
      body: "Watch your total play time grow with daily, monthly, and yearly views designed for quick check-ins.",
      screenContent: screen3,
      palette: ["#091018", "#0e355d", "#17c3ff"],
    }),
  },
  {
    file: path.join(screenshotsDir, "04-control-the-queue.svg"),
    content: screenshotSvg({
      eyebrow: "Playback",
      title: "Control the queue without breaking focus",
      body: "Keep music moving with shuffle, repeat, queue switching, and background playback support.",
      screenContent: screen4,
      palette: ["#130d1e", "#44239a", "#ff2fd1"],
    }),
  },
  {
    file: path.join(previewDir, "preview-cover.svg"),
    content: previewSvg(),
  },
];

for (const asset of assets) {
  writeFile(asset.file, asset.content);
}

writeFile(
  path.join(previewDir, "preview-script.md"),
  `# Lume App Preview Script

## Duration
15-20 seconds

## Scene 1
Text: Play your media universe
Visual: Open Explore, reveal imported library, tap a track to start playback.

## Scene 2
Text: Organize with favorites and tags
Visual: Add a track to Favorites, show grouped collections and tag playlists.

## Scene 3
Text: Stay in control
Visual: Open Now Playing, switch queue items, toggle shuffle/repeat.

## Scene 4
Text: See your listening take shape
Visual: Open Profile and highlight total play time plus stats views.
`
);

console.log(`Generated SVG assets in ${outputDir}`);
