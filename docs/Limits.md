# Limits

* **Kerbin only**, for now. Every world's ground is made from its own layers, and each world's have to be written for the
  graphics card as Kerbin's were (the Mun and Minmus next).
* **Up to 120 km.** From high up the game hands its ground over to the far planet: the whole of Kerbin drawn as one ball, from
  a map a few kilometres a pixel, its coasts bands as wide. The game begins that at 20 km and ends it at 120 km, the far planet
  showing through its ground more and more. While the far ground is drawn the hand-over begins at 100 km instead: both grounds
  solid and sharp till then, then fading into the far planet together. Above 120 km the far planet alone, as the game draws
  it. (A planet pack whose hand-over is not as Kerbin's: up to 30 km, as before.)
* **Stock Kerbin only.** A planet pack, or a mod that changes Kerbin's ground (its layers or its decals), and it stays off and
  says why.
* **The seam** where the game's own ground ends: on the plains under a pixel; in the mountains the two can differ by a few
  pixels along it (the game's quads are straight between points 131 m apart; the far ground follows the ground between them).
  Not seen in the tests so far.
* **Things on the ground far off** that the game draws only near the craft (its scatter of rocks and trees) are not there; the
  buildings it places (the space centre, the airfields) are the game's own and drawn as it draws them.
* **EVE's city lights:** laid on the far ground where EVE's map of them is the cube's six faces (the usual EVE configs); EVE's
  other kind (two halves) is not, and then the far ground has none. Far off, where the true ground's relief is seen at a grazing
  angle, the lights' street pattern breaks up into specks where the game's flat far quads show it as a grid.
* **The camera held low and far from the craft** (a test's, not a flight's): the ground just under it, within 400 m, is drawn
  by neither (the game's is round the craft, the far camera's begins at 400 m).
* **Windows:** its shaders are made from the same ones for Direct3D 11; not run there yet. **Linux:** never run.
