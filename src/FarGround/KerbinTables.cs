// Written by research/rendering/lab/kerbinground.swift (fargroundglsl) with tools/shaderpack/fargroundpoints.glsl: not to be
// edited by hand.
// The seeds of the simplex noises whose tables fill _KTables' rows 1 on, in the order that shader reads them.
namespace FarGround
{
    static class KerbinTables
    {
        public static readonly int[] Seeds = { 121214, 14554, 454545, 1247389, 121221, 44473, 4563456, 453737, 44445, 1, 973572, 8687, 6858, 17857, 435345, 248775058, 453453435, 212121, 47373, 768453 };
        // The decals the shader holds (its _KDecals.xyz and _KFlats.xy, in that order), with the values it was written with: each
        // is laid only where the game has one of that kind and name with those values. Map decals: tangent or not, the radius,
        // the position, the angle, the map's name and size and its first row in _KDecalMaps, the deformity, absolute or not,
        // the offset, the smoothing, the alpha's smoothing, black left out. Flattenings: the position, the inner and outer
        // radii, the height, the smoothing's two tangents.
        public struct MapDecal { public bool Tangent; public string Name; public double Radius; public float X, Y, Z, Angle; public string Map; public int Size, Row; public double Deformity; public bool Absolute; public double Offset; public float Smooth; public bool AlphaSmooth, CullBlack; }
        public struct Flattening { public string Name; public float X, Y, Z; public double Inner, Outer, To, SmoothStart, SmoothEnd; }
        public const int DecalMapWidth = 1024, DecalMapHeight = 2304;
        public static readonly MapDecal[] MapDecals = {
            new MapDecal { Tangent = true, Name = "IslandAirfield", Radius = 1200.0, X = 186100.0f, Y = -15810.0f, Z = -570000.0f, Angle = 110.0f, Map = "island_runway_decal", Size = 256, Row = 2048, Deformity = 200.0, Absolute = true, Offset = -85.0, Smooth = 0.2f, AlphaSmooth = true, CullBlack = true },
            new MapDecal { Tangent = false, Name = "KSC2", Radius = 2000.0, X = -468960.0f, Y = 211164.7f, Z = -310261.0f, Angle = 220.0f, Map = "decal_spaceport_0_height", Size = 1024, Row = 1024, Deformity = 100.0, Absolute = true, Offset = 400.0, Smooth = 0.1f, AlphaSmooth = true, CullBlack = false },
            new MapDecal { Tangent = true, Name = "KSC", Radius = 7500.0, X = 157000.0f, Y = -3000.0f, Z = -570000.0f, Angle = 220.0f, Map = "ksc_decal_heightMap", Size = 1024, Row = 0, Deformity = 70.0, Absolute = true, Offset = 0.0, Smooth = 0.0f, AlphaSmooth = true, CullBlack = false },
        };
        public static readonly Flattening[] Flattenings = {
            new Flattening { Name = "Pyramids", X = -468635.1f, Y = -68111.1f, Z = -370297.1f, Inner = 400.0, Outer = 1000.0, To = 1300.0, SmoothStart = 0.0, SmoothEnd = 0.0 },
            new Flattening { Name = "Desert_Airfield", X = -483136.0f, Y = -68639.9f, Z = -350503.8f, Inner = 2000.0, Outer = 4500.0, To = 820.0, SmoothStart = 0.0, SmoothEnd = 0.0 },
        };
    }
}
