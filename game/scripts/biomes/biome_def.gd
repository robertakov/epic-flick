class_name BiomeDef
extends RefCounted
## One biome = one complete set of environmental rules for a whole level (never mixed inside a run).
## Pure data; behaviour lives in the systems that read it (TerrainBuilder, Background, BiomeHazards,
## SpringContactController via BiomeRuntime, BiomeIntro, BiomeChallenges). Definitions: BiomeCatalog.
##
## Adding a biome: add one entry in BiomeCatalog.DEFS (palette, sky style, physics, features, title style),
## optionally a sky painter in BiomePainter and props in BiomeProps, and a rule set in BiomeChallenges.

var id := "green_hills"
var display_name := "ЗЕЛЁНЫЕ ХОЛМЫ"
var special := false
## ---- physics (scoped modifiers; 1.0 = Green Hills baseline) ----
var gravity_scale := 1.0
## Multiplier of the normal release speed of VALID feet landings (spring rebound). 1.0 = unchanged.
var feet_rebound := 1.0
## Release-normal-speed ceiling multiplier for valid feet landings on this biome's surface.
var rebound_cap := 1.0
## Terrain physics material bounce for body / head contacts (Green Hills: 0.0).
var body_bounce := 0.0
## ---- terrain features ----
var chasms := false
var ceiling := false
var chocolate := false        # chocolate patches on the surface (sticky, dirties the robot)
var jelly := false            # whole surface is jelly (feet_rebound applies everywhere)
var portals := false
var anomalies := false
## ---- visuals ----
var palette: Dictionary = {}  # empty = Green Hills template palettes
var sky := "green"            # painter style id (BiomePainter)
var props := ""               # surface prop set (BiomeProps)
var ambient := Color.WHITE    # world modulate (kept bright: readability first)
## ---- presentation ----
var title_style := "green"
## Show the intro title every time a level of this biome starts (Green Hills: only before campaign r1).
var intro_always := true


static func from_dict(d: Dictionary) -> BiomeDef:
	var b := BiomeDef.new()
	for k in d:
		b.set(k, d[k])
	return b
