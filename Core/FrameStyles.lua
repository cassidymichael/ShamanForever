-- Frame styles: data only. Client art by file ID or atlas, ours by path in Art\Frames\.
-- Sizes and holes are in texels of the piece as drawn (after coords); shown: the art's opaque part.

local _, ns = ...

local FR = ns.Frames

-- Round one icon
FR.addStyle("stormwings", { name = "Storm-grey wings", group = "blizzard", weight = "wispy", tint = true,
	art = { file = 629199, size = { 256, 128 } }, hole = { 106, 43, 44, 44 }, shown = { 8, 17, 245, 107 } })
FR.addStyle("gale", { name = "Gale", group = "blizzard", weight = "wispy",
	art = { file = 4880072, size = { 256, 128 } }, hole = { 110, 45, 41, 41 }, shown = { 53, 12, 205, 114 } })
FR.addStyle("flamewings", { name = "Flame wings", group = "blizzard", weight = "wispy",
	art = { file = 4880073, size = { 256, 128 } }, hole = { 110, 45, 41, 41 }, shown = { 34, 15, 227, 110 } })
FR.addStyle("tide", { name = "Tide", group = "blizzard", weight = "solid",
	art = { file = 4880074, size = { 256, 128 } }, hole = { 110, 45, 41, 41 }, shown = { 70, 16, 194, 104 } })
FR.addStyle("marblegold", { name = "Marble and gold", group = "blizzard", weight = "solid",
	art = { file = 3853104, size = { 256, 128 } }, hole = { 106, 41, 43, 43 }, shown = { 87, 19, 167, 106 } })
FR.addStyle("achgold", { name = "Achievement gold", group = "blizzard", weight = "solid", tint = true,
	art = { file = 130656, coords = { 0, 0.5625, 0, 0.5625 }, size = { 72, 72 } }, hole = { 16, 16, 40, 40 },
	shown = { 1, 1, 71, 71 } })
FR.addStyle("brackets", { name = "Corner brackets", group = "blizzard", weight = "wispy", tint = true,
	art = { atlas = "ConduitIconFrame-Corners", size = { 64, 64 } }, hole = { 7, 7, 50, 50 }, shown = { 1, 1, 63, 63 } })
FR.addStyle("runewood", { name = "Runed wood", group = "painted", weight = "solid", credit = "ai",
	art = { path = "Runewood", size = { 256, 256 } }, hole = { 64, 64, 128, 128 } })
FR.addStyle("storm", { name = "Storm", group = "blizzard", weight = "wispy",
	art = { file = 4861473, size = { 256, 128 } }, hole = { 108, 44, 41, 42 }, shown = { 38, 11, 224, 119 } })
FR.addStyle("palestorm", { name = "Pale storm", group = "blizzard", weight = "wispy", tint = true,
	art = { file = 6017378, size = { 256, 128 } }, hole = { 108, 44, 41, 42 }, shown = { 38, 11, 225, 119 } })
FR.addStyle("bronzewood", { name = "Bronze and wood", group = "blizzard", weight = "solid",
	art = { file = 1016657, size = { 256, 128 } }, hole = { 109, 43, 43, 44 }, shown = { 53, 23, 207, 108 } })
FR.addStyle("slate", { name = "Slate", group = "blizzard", weight = "solid", tint = true,
	art = { file = 4820990, size = { 256, 128 } }, hole = { 105, 42, 46, 45 }, shown = { 64, 24, 191, 103 } })
FR.addStyle("roughstone", { name = "Rough stone", group = "blizzard", weight = "solid", tint = true,
	art = { atlas = "ZoneAbility-Generic-IconBorder", size = { 63, 65 } }, hole = { 13, 15, 37, 35 },
	shown = { 1, 2, 62, 63 } })
FR.addStyle("gildedleaf", { name = "Gilded leaf", group = "blizzard", weight = "solid",
	art = { atlas = "spellbook-item-iconframe", size = { 138, 131 } }, hole = { 39, 16, 84, 84 },
	shown = { 4, 3, 136, 128 } })

-- Round a group
FR.addGroupStyle("midnight", { name = "Midnight", group = "blizzard", weight = "solid", tint = true,
	pieces = FR.cut({ atlas = "ui-frame-midnight-border", size = { 588, 588 } }, 110), edges = "stretch",
	rim = 30, scale = 0.30, gap = 4 })
FR.addGroupStyle("dragonstone", { name = "Dragon stone", group = "blizzard", weight = "solid", tint = true,
	pieces = {
		tl = { atlas = "Dragonflight-NineSlice-CornerTopLeft", size = { 166, 166 } },
		tr = { atlas = "Dragonflight-NineSlice-CornerTopRight", size = { 166, 166 } },
		bl = { atlas = "Dragonflight-NineSlice-CornerBottomLeft", size = { 166, 166 } },
		br = { atlas = "Dragonflight-NineSlice-CornerBottomRight", size = { 166, 166 } },
		t = { atlas = "_Dragonflight-Nineslice-EdgeTop", size = { 256, 30 } },
		b = { atlas = "_Dragonflight-Nineslice-EdgeBottom", size = { 256, 30 } },
		l = { atlas = "!Dragonflight-NineSlice-EdgeLeft", size = { 30, 256 } },
		r = { atlas = "!Dragonflight-NineSlice-EdgeRight", size = { 30, 256 } },
	}, edges = "tile", rim = 24, scale = 0.32, gap = 7 })

local RAIL_H = { file = 130659, coords = { 0, 454 / 512, 0, 10 / 16 }, size = { 454, 10 } }
local RAIL_V = { file = 130658, coords = { 0, 10 / 16, 0, 454 / 512 }, size = { 10, 454 } }
local JOINT = { file = 130657, coords = { 0, 26 / 32, 0, 26 / 32 }, size = { 26, 26 } }   -- the bottom-right bend
FR.addGroupStyle("lattice", { name = "Steel lattice", group = "blizzard", weight = "solid", tint = true,
	pieces = { t = RAIL_H, b = RAIL_H, l = RAIL_V, r = RAIL_V, br = JOINT,
		tl = { file = JOINT.file, coords = JOINT.coords, size = JOINT.size, rotate = 180 },
		tr = { file = JOINT.file, coords = JOINT.coords, size = JOINT.size, flipY = true },
		bl = { file = JOINT.file, coords = JOINT.coords, size = JOINT.size, flipX = true } },
	edges = "stretch", rim = 10, scale = 0.4, gap = -1, between = { art = RAIL_V, along = "gap" } })

local LINKS = "StoneLinks"
FR.addGroupStyle("stonelinks", { name = "Stone link band", group = "painted", weight = "solid", credit = "ai",
	cells = {
		first = { path = LINKS, coords = { 0, 163 / 512, 0, 168 / 256 }, size = { 163, 168 } },
		unit = { path = LINKS, coords = { 163 / 512, 325 / 512, 0, 168 / 256 }, size = { 162, 168 } },
		last = { path = LINKS, coords = { 325 / 512, 509 / 512, 0, 168 / 256 }, size = { 184, 168 } },
		hole = { 38, 40, 88, 88 },
	} })

FR.addGroupStyle("diamondsteel", { name = "Diamond steel", group = "blizzard", weight = "solid", tint = true,
	pieces = {
		tl = { atlas = "UI-Frame-DiamondMetal-CornerTopLeft", size = { 128, 128 } },
		tr = { atlas = "UI-Frame-DiamondMetal-CornerTopRight", size = { 128, 128 } },
		bl = { atlas = "UI-Frame-DiamondMetal-CornerBottomLeft", size = { 128, 128 } },
		br = { atlas = "UI-Frame-DiamondMetal-CornerBottomRight", size = { 128, 128 } },
		t = { atlas = "_UI-Frame-DiamondMetal-EdgeTop", size = { 128, 128 } },
		b = { atlas = "_UI-Frame-DiamondMetal-EdgeBottom", size = { 128, 128 } },
		l = { atlas = "!UI-Frame-DiamondMetal-EdgeLeft", size = { 128, 128 } },
		r = { atlas = "!UI-Frame-DiamondMetal-EdgeRight", size = { 128, 128 } },
	}, edges = "tile", rim = 24, scale = 0.32, gap = 4 })
FR.addGroupStyle("gilded", { name = "Gilded", group = "blizzard", weight = "solid",
	pieces = {
		tl = { atlas = "plunderstorm-nineslice-cornertopleft", size = { 166, 166 } },
		tr = { atlas = "plunderstorm-nineslice-cornertopright", size = { 166, 166 } },
		bl = { atlas = "plunderstorm-nineslice-cornerbottomleft", size = { 166, 166 } },
		br = { atlas = "plunderstorm-nineslice-cornerbottomright", size = { 166, 166 } },
		t = { atlas = "_plunderstorm-nineslice-edgetop", size = { 256, 30 } },
		b = { atlas = "_plunderstorm-nineslice-edgebottom", size = { 256, 30 } },
		l = { atlas = "!plunderstorm-nineslice-edgeleft", size = { 30, 256 } },
		r = { atlas = "!plunderstorm-nineslice-edgeright", size = { 30, 256 } },
	}, edges = "tile", rim = 24, scale = 0.32, gap = 7 })
