# Ciboleger geographic data

Downloaded 2026-10-22. MapKit projects WGS84 coordinates into local metres;
RealityKit renders the terrain and features. Apple map imagery is not used.

## Elevation

- Source: https://s3.amazonaws.com/elevation-tiles-prod/terrarium/12/3256/2123.png
- Registry: https://registry.opendata.aws/terrain-tiles/
- Attribution: Mapzen terrain tiles; SRTM/GMTED2010 data courtesy of the U.S. Geological Survey.
- Provider attribution: https://github.com/tilezen/joerd/blob/master/docs/attribution.md
- Terrarium RGB decodes to metres: R*256 + G + B/256 - 32768.
- Grid spacing at Ciboleger is approximately 38 metres. This is sample spacing,
  not a claim of vertical accuracy. Elevations are not vertically exaggerated.
- Twenty-metre contours are interpolated from the DEM triangles. Small banks,
  stairs, house platforms and recent earthworks cannot be resolved at this scale.
- Outside the bundled tile the scene uses a flat fallback; no elevation is inferred.

## Features

- No OpenStreetMap, Overpass, Google Maps, or runtime map API is used by the
  RealityKit scene.
- The three interactive landmark houses, village paths, trees, and woven accents
  are deliberately stylized Kanekes elements. They are not surveyed building
  footprints.
- Indigo land, muted blue contour/water lines and cream paths interpret the user's
  illustration; the supplied reference image is not used as geographic data.

Validation: the elevation asset is bundled locally; simulator target compiles.
