# Ngahuma generated textures

Created with the built-in image_gen tool, 2026-10-28. No Blender or external asset download is required. The six final PNGs live in `Baduy/NgahumaTextures/` and are bundled by Xcode's synchronized project group.

These are generated color images, not photographs of a documented Baduy location or measured PBR scans. Soil/ash use high-roughness physically based materials. Vegetation uses three intersecting alpha-cutout cards per clump. The panorama is a distant spherical backdrop, so it does not supply nearby geometry/parallax. No generated normal or roughness maps are claimed.

## Final prompts

### ngahuma-soil.png
Use case: photorealistic-natural. Asset type: seamless tileable albedo texture for a realistic tropical upland farming ground in a RealityKit iPhone 360 environment. Generate one square texture, straight down orthographic view, fills entire image edge to edge. Dry earthy brown soil, small irregular clods, fine roots, sparse weathered straw and tiny dried leaves, subtle natural variation. Physically plausible muted brown palette, diffuse evenly overcast lighting, no cast shadows or directional highlights, no perspective, no horizon, no text, no border. Photographic scanned material appearance, never cartoon or illustration. Designed to repeat seamlessly on all edges. Save the generated image as a local project asset and return its path.

### ngahuma-grass.png
Use case: photorealistic-natural. Asset type: transparent vegetation cutout texture for crossed mesh cards in a realistic 3D tropical upland field. One isolated naturally irregular clump of dry tawny grasses with some muted olive green slender leaves, thin stems and delicate seed heads. Entire plant visible with roots at bottom center, upright front view, approximately square composition with generous transparent margin around every tip, no cropped leaves. Real photographic botanical detail, soft neutral diffuse light, no stylization, no cartoon, no pot, no ground, no drop shadow, no text. Actual transparent alpha background, including gaps between blades.

### ngahuma-panorama.png
Use case: photorealistic-natural. Asset type: 2:1 equirectangular full 360 by 180 degree environment panorama texture for the INSIDE of a sphere in a realistic tropical rural field experience. A quiet dry upland clearing in West Java-like tropical countryside, dense natural mixed broadleaf forest and bamboo along the distant perimeter, distant softly hazy rolling green hills, softly cloudy pale blue sky. Eye level 1.5 meters in the center of an open earthy clearing. Horizon at exact vertical midpoint, full sky in upper hemisphere, earthy ground in lower hemisphere converging naturally at nadir. Exact equirectangular projection with continuous seamless left/right boundary, not a fisheye or little planet. Natural photographic detail, muted greens, warm brown earth, diffuse afternoon sunlight. No people, no buildings, no text, no cartoon, no painted appearance. Wide 2:1 composition.

### ngahuma-ash.png
Use case: photorealistic-natural. Asset type: seamlessly tileable square albedo texture for burned soil in a real-time 3D farming environment. Straight down orthographic photographic scan of dark charred earth with fine gray wood ash, small black charcoal fragments and thin burned stalk remnants, subtle underlying brown earth. Natural uneven detail at small scale, evenly diffuse neutral illumination, no glowing fire, no smoke, no shadows, no horizon, no border, no text. Full image edge to edge seamless repeatable surface. Real photographic material, not painted or cartoon.

### ngahuma-seedling.png
Use case: photorealistic-natural. Asset type: transparent alpha plant cutout for a 3D farming game, crossed mesh cards. One small clump of young upland rice seedlings with several slender gracefully arching natural green leaves, tender fine stems meeting at bottom center. Entire plant visible, front elevation, isolated, square frame, generous transparent margins, no pot, no soil block, no shadow, no text. Photographic botanical realism, muted natural green, diffuse daylight, no illustration, actual transparent background including gaps between leaves.

### ngahuma-flame.png
Use case: photorealistic-natural. Asset type: single fire particle sprite on genuine transparent alpha background for a real-time 3D grass fire effect. One small upright irregular tongue of flame with curling wispy edges, warm orange body, pale yellow center, delicate translucent reddish tips. Square canvas, full flame visible, fades to transparent on every side including base, centered with generous empty margins, no logs, no ground, no smoke, no sparks, no black or colored background, no text. Photographic real flame detail, not cartoon, not icon, not illustration.

## Validation

- Simulator build passed and all six PNGs were found in the built app bundle.
- Generated source images were inspected. Final in-engine appearance/performance still requires device validation; Simulator UI was unavailable through the computer-use tool in this session.
- On device: open Ngahuma, turn 360 degrees, inspect the panorama seam and foliage cutouts, clear all nine patches, start/finish burning, plant nine patches, reset, mute, and exit during playback.

## Panorama replacement

Replaced `ngahuma-panorama.png` using built-in image_gen at the user's request. Final prompt:

Use case: photorealistic-natural. Asset type: high resolution 2:1 equirectangular 360 degree environment background texture for the inner surface of a sphere in an immersive iPhone farming scene. Create a realistic photographic tropical upland field in rural western Java, seen from standing height in the CENTER of a broad gently level dry earth clearing. Surround the clearing on ALL sides with a continuous irregular edge of mixed broadleaf trees, bamboo, modest banana plants and scrub 25 to 40 metres away. Very subtle low hills behind trees, NO expansive mountain vista, NO dramatic valley, NO cliff. The foreground is muted dry brown earth with sparse straw matching a dry farming field. Soft overcast humid morning daylight, pale gray-blue sky with thin clouds, subdued olive green vegetation, natural photographic detail and believable scale, no oversaturation, no cinematic orange sunset. Projection: true full-sphere equirectangular longitude-latitude panorama, 360 horizontal and 180 vertical degrees, 2:1 ratio, horizon precisely at middle height, seamless matching left and right boundaries, upper half sky to zenith and lower half clearing to nadir. Request 3840x1920 output if supported. No people, no text, no buildings, no graphic borders, no watermark, no cartoon or painted forms. Keep tree heights moderate so the user feels inside a field rather than looking at a landscape postcard.

Returned resolution is 1774 × 887; this is not a 4K asset. In-engine seam and lighting matching still require device inspection.
