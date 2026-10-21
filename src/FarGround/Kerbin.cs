using System;
using System.Collections.Generic;
using System.Reflection;
using UnityEngine;

namespace FarGround
{
    /// <summary>
    /// Kerbin's ground as the points' shader has it (tools/shaderpack/fargroundpoints.glsl, written by
    /// research/rendering/lab/kerbinground.swift from the game's own values): its layers checked against the world's own when a
    /// flight begins there (their kinds and values; any other layer that moves its ground, a planet pack's or another mod's, and
    /// the far ground stays off, saying which), and the textures the shader reads made from the game's own data: the height
    /// map's bytes, the noises' tables (each a permutation the game shuffles at its seed with Unity's random numbers: read from
    /// the game's own noise objects, so they are the game's whatever those numbers are), and the decals' maps one above the
    /// other. With them, the textures and switches of the game's own ground material, which the rings are shaded with.
    /// </summary>
    sealed class Kerbin : IDisposable
    {
        const BindingFlags Any = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static;
        public Texture2D Map { get; private set; }
        public Texture2D Tables { get; private set; }
        public Texture2D DecalMaps { get; private set; }
        /// <summary>Which of the shader's decals the game has: its map decals (x, y, z) and its flattenings (x, y), 1 where there; and
        /// (z, w) how much longer than one each flattening's centre is as the game holds it.</summary>
        public Vector4 DecalsOn, FlatsOn;
        public double RadiusMax { get; private set; }
        /// <summary>The game's own ground material, and whether it has its own fog on (AERIAL_ON).</summary>
        public Material Ground { get; private set; }
        public bool Aerial { get; private set; }
        /// <summary>What it found, for the log.</summary>
        public string Found { get; private set; } = "";
        /// <summary>EVE's city lights on Kerbin's ground, where EVE is installed with them: its material on the game's quads.</summary>
        public Material CityLights { get; private set; }

        /// <summary>Kerbin's layers read and checked: nothing, and why, where they are not those the shader was written from.</summary>
        public static Kerbin Read(PQS pqs, out string why)
        {
            var k = new Kerbin();
            why = k.Check(pqs);
            if (why != null) { k.Dispose(); return null; }
            return k;
        }

        string Check(PQS pqs)
        {
            var mods = (PQSMod[])typeof(PQS).GetField("mods", Any).GetValue(pqs);
            int count = (int)typeof(PQS).GetField("modCount", Any).GetValue(pqs);
            MapSO heightMap = null;
            var noises = new Dictionary<int, Simplex>();
            var decalMaps = new MapSO[KerbinTables.MapDecals.Length];
            bool hm = false, rac = false, abs = false, hc2 = false, land = false;
            var laid = new List<string>();
            for (int i = 0; i < count; i++)
            {
                PQSMod m = mods[i];
                switch (m)
                {
                    case PQSMod_VertexHeightMap v:
                        if (hm || v.heightMap == null || v.heightMap.MapName != "kerbin_height_new" || v.heightMap.Width != 4096 || v.heightMap.Height != 2048 || v.heightMap.BitsPerPixel != 1
                            || v.heightMapOffset != -1500.0 || v.heightMapDeformity != 5000.0 || v.scaleDeformityByRadius) return "the height map";
                        heightMap = v.heightMap; hm = true; break;
                    case PQSMod_VertexRidgedAltitudeCurve r:
                        if (rac || r.deformity != 750f || r.ridgedAddSeed != 1384047773 || r.ridgedAddFrequency != 140f || r.ridgedAddLacunarity != 2.5f || r.ridgedAddOctaves != 3
                            || r.ridgedMinimum != -0.7f || r.ridgedMode != LibNoise.NoiseQuality.Standard || r.simplexSeed != 248775058 || r.simplexOctaves != 2.0
                            || r.simplexFrequency != 50.0 || r.simplexHeightStart != 0.0 || r.simplexHeightEnd != 6000.0 || r.simplexCurve == null || r.simplexCurve.length != 8) return "the ridged layer";
                        noises[r.simplexSeed] = (Simplex)typeof(PQSMod_VertexRidgedAltitudeCurve).GetField("simplex", Any).GetValue(r); rac = true; break;
                    case PQSMod_VertexSimplexHeightAbsolute a:
                        if (abs || a.seed != 453453435 || a.deformity != 485.0 || a.octaves != 8.0 || a.frequency != 24.0) return "the simplex layer";
                        noises[a.seed] = (Simplex)typeof(PQSMod_VertexSimplexHeightAbsolute).GetField("simplex", Any).GetValue(a); abs = true; break;
                    case PQSMod_VertexHeightNoiseVertHeightCurve2 c:
                        if (hc2 || c.deformity != 4000f || c.ridgedAddSeed != 1384047773 || c.ridgedAddFrequency != 48f || c.ridgedAddLacunarity != 4f || c.ridgedAddOctaves != 6
                            || c.ridgedSubSeed != 2113370706 || c.ridgedSubFrequency != 32f || c.ridgedSubLacunarity != 4f || c.ridgedSubOctaves != 6 || c.ridgedMode != LibNoise.NoiseQuality.Low
                            || c.simplexSeed != 248775058 || c.simplexOctaves != 4.0 || c.simplexFrequency != 32.0 || c.simplexHeightStart != 800.0 || c.simplexHeightEnd != 4600.0
                            || c.simplexCurve == null || c.simplexCurve.length != 3) return "the mountains' layer";
                        hc2 = true; break;
                    case PQSMod_MapDecalTangent t:
                        {
                            string w = MapDecal(true, t.name, t.radius, t.position, t.angle, t.heightMap, t.heightMapDeformity, t.absolute, t.absoluteOffset, t.smoothHeight,
                                                t.useAlphaHeightSmoothing, t.cullBlack, t.colorMap, decalMaps);
                            if (w != null) return w;
                            laid.Add(t.name); break;
                        }
                    case PQSMod_MapDecal d:
                        {
                            string w = MapDecal(false, d.name, d.radius, d.position, d.angle, d.heightMap, d.heightMapDeformity, d.absolute, d.absoluteOffset, d.smoothHeight,
                                                d.useAlphaHeightSmoothing, d.cullBlack, d.colorMap, decalMaps);
                            if (w != null) return w;
                            laid.Add(d.name); break;
                        }
                    case PQSMod_FlattenArea f:
                        {
                            int n = Array.FindIndex(KerbinTables.Flattenings, e => e.Name == f.name);
                            if (n < 0) return "a flattening it does not know: '" + f.name + "'";
                            KerbinTables.Flattening e2 = KerbinTables.Flattenings[n];
                            if (!Near(f.position.x, e2.X, 1.0) || !Near(f.position.y, e2.Y, 1.0) || !Near(f.position.z, e2.Z, 1.0) || f.innerRadius != e2.Inner || f.outerRadius != e2.Outer
                                || f.flattenTo != e2.To || f.smoothStart != e2.SmoothStart || f.smoothEnd != e2.SmoothEnd) return "the flattening '" + f.name + "'";
                            // (and how much longer than one its centre's direction is as the game holds it: normalised in single
                            // precision, which shifts the game's own angles from it by tens of metres; the shader does the same)
                            object held = typeof(PQSMod_FlattenArea).GetField("posNorm", Any)?.GetValue(f);
                            float stretch = held is Vector3d c ? (float)(c.magnitude - 1.0) : 0f;
                            if (n == 0) { FlatsOn.x = 1f; FlatsOn.z = stretch; }
                            else if (n == 1) { FlatsOn.y = 1f; FlatsOn.w = stretch; }
                            else return "the flattening '" + f.name + "'";
                            laid.Add(f.name); break;
                        }
                    case PQSLandControl l:
                        if (land || l.landClasses == null || l.landClasses.Length != 11 || l.useHeightMap || l.vHeightMax != 3500f) return "the land layer";
                        noises[l.altitudeSeed] = l.altitudeSimplex; noises[l.latitudeSeed] = l.latitudeSimplex; noises[l.longitudeSeed] = l.longitudeSimplex;
                        foreach (PQSLandControl.LandClass lc in l.landClasses) { noises[lc.coverageSeed] = lc.coverageSimplex; noises[lc.noiseSeed] = lc.noiseSimplex; }
                        land = true; break;
                    default:
                        // (what else stands in the list: buildings, materials, colliders, the sea's and the air's own and the like; a
                        // kind that moves points, and the far ground would not be the game's)
                        string kind = m.GetType().Name;
                        if (kind.StartsWith("PQSMod_Vertex", StringComparison.Ordinal) || kind.StartsWith("PQSMod_Flatten", StringComparison.Ordinal)
                            || kind.StartsWith("PQSMod_MapDecal", StringComparison.Ordinal) || kind == "PQSMod_VoronoiCraters") return "a layer of a kind it does not know: " + kind;
                        // (EVE's material laid over every quad of the game's ground, its city lights: Utils.MaterialPQS)
                        if (kind == "MaterialPQS" && m.GetType().GetField("material", Any)?.GetValue(m) is Material em && em.shader != null && em.shader.name == "EVE/TerrainCityLight")
                            CityLights = em;
                        break;
                }
            }
            if (!(hm && rac && abs && hc2 && land)) return "a layer missing";

            // (the height map's bytes as the game holds them: a byte a dot, rows from the south pole)
            byte[] bytes = (byte[])typeof(MapSO).GetField("_data", Any).GetValue(heightMap);
            if (bytes == null || bytes.Length != 4096 * 2048) return "the height map's dots";
            Map = new Texture2D(4096, 2048, TextureFormat.R8, false, true) { name = "Far Ground: Kerbin's heights", filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp };
            Map.LoadRawTextureData(bytes);
            Map.Apply(false, true);
            // (row 0: LibNoise's 256 directions; then each simplex's table, in the order the shader reads them)
            var vectors = (double[])typeof(LibNoise.GradientNoiseBasis).GetField("RandomVectors", Any).GetValue(null);
            int[] seeds = KerbinTables.Seeds;
            var t2 = new Color[256 * (1 + seeds.Length)];
            for (int i = 0; i < 256; i++) t2[i] = new Color((float)vectors[i * 4], (float)vectors[i * 4 + 1], (float)vectors[i * 4 + 2], 0f);
            FieldInfo permField = typeof(Simplex).GetField("perm", Any);
            for (int row = 0; row < seeds.Length; row++)
            {
                if (!noises.TryGetValue(seeds[row], out Simplex s) || s == null) return "no simplex with the seed " + seeds[row];
                int[] perm = (int[])permField.GetValue(s);
                for (int i = 0; i < 256; i++) t2[(1 + row) * 256 + i] = new Color(perm[i], 0f, 0f, 0f);
            }
            Tables = new Texture2D(256, 1 + seeds.Length, TextureFormat.RGBAFloat, false, true) { name = "Far Ground: the noises' tables", filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp };
            Tables.SetPixels(t2);
            Tables.Apply(false, true);
            // (the decals' maps, a height and an alpha a dot, one above the other where the shader reads each: absent ones left empty)
            var atlas = new byte[KerbinTables.DecalMapWidth * KerbinTables.DecalMapHeight * 2];
            for (int n = 0; n < decalMaps.Length; n++)
            {
                if (decalMaps[n] == null) continue;
                KerbinTables.MapDecal e = KerbinTables.MapDecals[n];
                byte[] dots = (byte[])typeof(MapSO).GetField("_data", Any).GetValue(decalMaps[n]);
                if (dots == null || dots.Length != e.Size * e.Size * 2) return "the decal '" + e.Name + "''s dots";
                for (int y = 0; y < e.Size; y++) Buffer.BlockCopy(dots, y * e.Size * 2, atlas, (e.Row + y) * KerbinTables.DecalMapWidth * 2, e.Size * 2);
            }
            DecalMaps = new Texture2D(KerbinTables.DecalMapWidth, KerbinTables.DecalMapHeight, TextureFormat.RG16, false, true) { name = "Far Ground: the decals' maps", filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp };
            DecalMaps.LoadRawTextureData(atlas);
            DecalMaps.Apply(false, true);
            RadiusMax = pqs.radiusMax;
            Ground = pqs.surfaceMaterial;
            Aerial = Ground != null && Ground.IsKeywordEnabled("AERIAL_ON") && Ground.HasProperty("_fogColorRamp") && Ground.GetTexture("_fogColorRamp") != null;
            Found = "4096 x 2048 heights, " + seeds.Length + " noise tables, decals: " + (laid.Count > 0 ? string.Join(", ", laid.ToArray()) : "none");
            return null;
        }

        // (a map decal: one the shader has, by kind and name, with the values it was written with; its map kept to be copied)
        string MapDecal(bool tangent, string name, double radius, Vector3 position, float angle, MapSO map, double deformity, bool absolute, double offset, float smooth,
                        bool alphaSmooth, bool cullBlack, MapSO colours, MapSO[] maps)
        {
            int n = Array.FindIndex(KerbinTables.MapDecals, e => e.Name == name && e.Tangent == tangent);
            if (n < 0 || n > 2) return "a decal it does not know: '" + name + "'";
            KerbinTables.MapDecal e2 = KerbinTables.MapDecals[n];
            if (radius != e2.Radius || !Near(position.x, e2.X, 0.5) || !Near(position.y, e2.Y, 0.5) || !Near(position.z, e2.Z, 0.5) || angle != e2.Angle || map == null || map.MapName != e2.Map
                || map.Width != e2.Size || map.Height != e2.Size || map.BitsPerPixel != 2 || deformity != e2.Deformity || absolute != e2.Absolute || offset != e2.Offset || smooth != e2.Smooth
                || alphaSmooth != e2.AlphaSmooth || cullBlack != e2.CullBlack || colours != null) return "the decal '" + name + "'";
            maps[n] = map;
            if (n == 0) DecalsOn.x = 1f; else if (n == 1) DecalsOn.y = 1f; else DecalsOn.z = 1f;
            return null;
        }

        static bool Near(double a, double b, double within) => Math.Abs(a - b) <= within;

        public void Dispose()
        {
            if (Map != null) UnityEngine.Object.Destroy(Map);
            if (Tables != null) UnityEngine.Object.Destroy(Tables);
            if (DecalMaps != null) UnityEngine.Object.Destroy(DecalMaps);
            Map = Tables = DecalMaps = null;
        }
    }
}
