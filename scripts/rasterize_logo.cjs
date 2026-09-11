#!/usr/bin/env node
/**
 * Rasterizes assets/icons/streamit_logo.svg → PNGs for flutter_native_splash & store art.
 * Requires: npm install (in this folder).
 *
 *   node scripts/rasterize_logo.cjs
 */
const path = require("path");
const sharp = require("sharp");

const root = path.join(__dirname, "..");
const svgPath = path.join(root, "assets/icons/streamit_logo.svg");
const pngSplashPath = path.join(root, "assets/icons/streamit_logo.png");
const png512Path = path.join(root, "assets/icons/streamit_logo_512.png");

const brandBg = { r: 11, g: 18, b: 32, alpha: 1 }; // #0B1220

async function main() {
  await sharp(svgPath)
    .resize(1152, 1152, {
      fit: "contain",
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    })
    .png()
    .toFile(pngSplashPath);

  console.log("Wrote", pngSplashPath);

  await sharp(svgPath)
    .resize(512, 512, {
      fit: "contain",
      background: brandBg,
    })
    .png()
    .toFile(png512Path);

  console.log("Wrote", png512Path);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
