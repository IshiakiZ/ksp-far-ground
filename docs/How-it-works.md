# How it works

Asked for (2026-10-18): "Can we make it so that you can render the whole world from your view? If you're at cloud height, you
can see until the world's edge or a hill or something. Maybe we could use LOD like Minecraft does with distant horizons and
Voxy and all that."

## What the game draws far off

The game builds its ground on the processor, as a tree of square pieces ("quads") over a cube blown up into a sphere: fine near
a point of its own (by the craft), coarser further off. Each quad is one draw, its points 15 to a side. Near the craft its points
are 131 m apart; 6 km off still that; 12 km off 263 m; and far off a few big quads stand for whole ranges, their points
kilometres apart. The game does draw its ground to the horizon (to about 590 km from cloud height): what is missing far off is
not the reach but the detail. From 2 km up the range 40-70 km west of the space centre is a row of smooth humps, a few big
flat facets with straight edges; the real ground there, as the game's own layers make it, is spires, ridges and creased slopes.

## Kerbin's ground, worked out on the graphics card

The game makes each point of its ground from layers, one after another: a height map (4096 x 2048), three layers of noise
(ridged and simplex noise: the hills, the mountains), the decals that flatten the space centre and the airfields, and a land
layer that picks the land's colour from eleven kinds (beach, grass, mountain, snow, desert...) by height, latitude and noise.
Far Ground has the same layers written for the graphics card, from the game's own values and data:

* the height map is the game's own, read out of the game as it runs;
* the noises' tables (the shuffled numbers each noise is made from) are read from the game's own noise objects, so they are the
  game's whatever its random numbers are;
* the decals are the game's own five on Kerbin (the space centre's 15 km of flat ground, the island's airfield, the old space
  centre, the pyramids, the desert's airfield), with their maps read out of the game, down to a quirk of the game's (it keeps a
  flattening's centre in single precision, which moves its edge by up to 30 m: Far Ground does the same);
* the land layer's eleven kinds with their colours and noises.

Checked against the game: its own points, layer by layer, and its own drawn ground round the space centre, 73,000 points of it
(10 cm apart on average; 11 cm over the 868 within the space centre's decal, which lifts the ground there from 450 m under the
sea to 65 m); and the graphics card's copy against the processor's (4-23 cm apart at worst, the colours to a thousandth). When a flight begins on Kerbin, Far
Ground checks that Kerbin's layers are those it was written from, every kind and value; any other layer that moves the ground
(a planet pack's, another mod's) and it stays off, saying why.

## Rings round the camera, a point every few pixels

Each frame, before the far camera draws, Far Ground lays rings round the point under the camera, out to the horizon: points
round each ring as far apart as 3 pixels of the screen, as wide as the view and a little more; each ring further out than the
last by as much as the ground seen at a slant needs. A pass on the graphics card works out every point's height, land colour
and how high it looks (for the ground's textures), one pixel a point; the rings are then drawn from those points as the game
draws its ground (its material's textures, laid three ways over the world, by height bands and by slope; its own fog; the sun
on each face and the sky's light), and again into the camera's depth picture, which Scatterer lays its air by: the far ground
is hazed as the game's own is. Where EVE draws its city lights on the game's ground, Far Ground lays them on the far ground the
same way: EVE's own program, read out of its shader bundle and written again for the far ground, with EVE's own map of the
lights (the cube's six faces, taken where EVE takes them: its config and the game's database) and detail textures. At night the
towns' lights go on to the horizon instead of ending where the game's quads end.

Nothing is kept from frame to frame and nothing is invented: about 270,000 points a frame, worked out afresh: about a
millisecond of a Mac's graphics card in the lab, and in the game within the frame rate's own noise (the far quads it saves the
game pay for it). The game's own quads are drawn only near the craft (its visible radius cut
back to 6 km, and put back when Far Ground is off or the flight ends), where they stand in front: there, and only there, the far
ground is drawn a little further than it is (by 0.3 % of how far off, 25 m at most). Elsewhere it is drawn where it is: pushed
back everywhere, as it first was, low land seen from high up at a slant fell behind the sea's surface, drawn after it, and the
coasts' low ground showed as patches of sea. The game builds its ground round a point by the craft, not the camera: zoomed far out, or with the
camera elsewhere, its fine ground stays round the craft. So Far Ground walks the game's tree of quads each frame from the point
under the camera and begins its rings inside the nearest quad the game has not drawn, wherever that is, under the camera if need
be: there is never a gap between the two, and round a camera far from the craft the far ground is finer than the game's own
coarse quads there would be.

## From high up

The game hands its ground over to the far planet as the camera climbs (the scaled-space Kerbin: one ball drawn before the
ground, from a map a few kilometres a pixel). Its ground's shader lets what was drawn behind it show through by a value the game
raises with height, from nought at 20 km to one at 120 km; the far planet's coarse coasts, brightened by Scatterer, then show as
cream bands along every shore. Far Ground fades by the same value, blended the same way, so that the two grounds go together;
and while it is drawn the hand-over begins at 100 km instead (put back when it is off): up to there both are solid and sharp,
through the height of a low orbit.

## The craft's ground

The game builds a quad, and gives the finest their colliders, only once it is drawn. So the game's own ground is always kept
3 km beyond every craft that is loaded, and drawn round them as the game draws it.
