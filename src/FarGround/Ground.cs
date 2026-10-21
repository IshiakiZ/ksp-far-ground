using System;
using System.IO;
using Keystone;
using UnityEngine;
using UnityEngine.Rendering;

#if !DEV
[assembly: KSPAssembly("FarGround", 0, 1)]
[assembly: KSPAssemblyDependency("Keystone", 0, 8)]
#endif

namespace FarGround
{
    /// <summary>
    /// Kerbin's ground drawn to the horizon (the owner, 2026-10-18: "can we make it so that you can render the whole world from
    /// your view? If you're at cloud height, you can see until the world's edge or a hill or something. Maybe we could use LOD
    /// like Minecraft does with distant horizons and Voxy and all that").
    ///
    /// The game builds its ground on the processor as a tree of quads round a point of its own (by the craft, in the game: not the
    /// camera, when the camera is held away from it), fine near it and coarser further off: far off a few big quads stand for
    /// whole ranges, their points kilometres apart, and from the clouds' height the mountains are smooth humps. Here, beyond the game's own ground near the camera, Kerbin's ground is drawn again on the
    /// graphics card at a point every few pixels: rings round the point under the camera, each point's height and land colour
    /// worked out where it stands from the game's own layers (its height map, its noises with the game's own tables, its decals
    /// round the space centre and the airfields, its land classes: Kerbin.cs, tools/shaderpack/fargroundpoints.glsl), shaded as
    /// the game shades its ground (fargrounddraw.glsl), and put into the camera's depth picture so that the air is laid over it as
    /// over the game's (fargrounddepth.glsl). Nothing is made up and nothing is kept: the points are worked out afresh each frame
    /// for that view, about a millisecond of a Mac's graphics card at a point every 3 pixels. The game's own quads are drawn only
    /// near the camera (its visible radius cut back, and put back when this is off or the flight ends), and stand in front where
    /// both are; the rings begin inside the nearest quad the game leaves undrawn, so there is never a gap between the two.
    ///
    /// From high up the game hands its ground over to the far planet (the scaled-space Kerbin: one ball drawn before the ground, from
    /// a map a few kilometres a pixel, its coasts bands as wide): its ground's shader lets what is behind it show by the material's
    /// _PlanetOpacity, which the game raises from nought at 20 km to one at 120 km. The far ground fades by the same value, the
    /// same way; and while it is drawn that hand-over begins only 20 km below its end, so that up to 100 km both grounds are solid
    /// and sharp (the owner, 2026-10-20: "glitchy ... land and atmosphere from far away"; research/rendering/experiments/
    /// far-away-glitches.md).
    ///
    /// Kerbin only, up to where the game's own ground has gone into the far planet, and only while Kerbin's layers are those the
    /// shaders were written from (checked when a flight begins there: any other layer that moves the ground, a planet pack's or
    /// another mod's, and it stays off and says why on its page).
    /// </summary>
    [KSPAddon(KSPAddon.Startup.Instantly, true)]
    public sealed class GroundAtStart : MonoBehaviour
    {
        void Awake() { Ground.Setup(); Destroy(gameObject); }
    }

    [KSPAddon(KSPAddon.Startup.Flight, false)]
    public sealed class Ground : MonoBehaviour
    {
        public const string Version = "0.1.0";
        // (where the game hands its ground over to the far planet otherwise than Kerbin's does (a planet pack's): off above 30 km of
        // the camera, the game's own ground as it is up there; on again below 29, so as not to flicker between)
        const double Highest = 30000.0, Again = 29000.0;
        // (while the far ground is drawn, the game's hand-over to the far planet begins this far below its end)
        const float FadeOver = 20000f;
        // (the far ground drawn a little farther than it is where the game's own quads may be drawn too, so that they stand in front
        // there: by 0.3 % of how far off it is, and by no more than this many metres)
        const float PushMost = 25f;
        // (the rings never begin nearer than this; and the game's own ground kept beyond every craft that is loaded by this much)
        const double Nearest = 300.0, BeyondCraft = 3000.0;

        static Mod mod;
        static Toggle on;
        static Slider apart, own;
        static string said = "not in flight", detail = "";

        static Shader pointsShader, drawShader, depthShader, lightsShader;
        static bool shadersTried;
        static string shadersWhy = "";

        Material pointsMat, drawMat, depthMat, lightsMat;
        Material eveLights;                         // (EVE's city lights on the game's quads, whose look the far ground's take, where drawn)
        bool lightsSix;                             // (their map the cube's six faces as six pictures, not one cube)
        Mesh sheet, rings;
        int meshAround, meshRings, meshDrawn;
        RenderTexture points;
        CommandBuffer pointsCmd, drawCmd, depthCmd;
        Camera far;
        CelestialBody world;
        PQS pqs;
        Kerbin kerbin;
        string why = "";
        bool cutting, above;
        double keptSea, keptAlt, cutM, reach = double.MaxValue, best, away;
        Vector3d under;
        int drawnAround, drawnRings;
        double drawnNear;
        float seenThrough;                          // (how far the far planet shows through the ground: the game's _PlanetOpacity)
        PQSMod_CelestialBodyTransform.AltitudeFade fade;    // (Kerbin's hand-over of its ground to the far planet, where it is as Kerbin's)
        float keptFadeStart, keptFadeStartHigh;
        bool fadeHeld;
        float sayAt;

        static readonly int idUp = Shader.PropertyToID("_FGUp"), idNorth = Shader.PropertyToID("_FGNorth"), idEast = Shader.PropertyToID("_FGEast"),
            idRound = Shader.PropertyToID("_FGRound"), idSheet = Shader.PropertyToID("_FGSheet"), idMap = Shader.PropertyToID("_KMap"),
            idTables = Shader.PropertyToID("_KTables"), idDecalMaps = Shader.PropertyToID("_KDecalMaps"), idDecals = Shader.PropertyToID("_KDecals"),
            idFlats = Shader.PropertyToID("_KFlats"), idRow0 = Shader.PropertyToID("_FGRow0"), idRow1 = Shader.PropertyToID("_FGRow1"),
            idRow2 = Shader.PropertyToID("_FGRow2"), idRow3 = Shader.PropertyToID("_FGRow3"), idCam = Shader.PropertyToID("_FGCam"),
            idPush = Shader.PropertyToID("_FGPush"), idPoints = Shader.PropertyToID("_FGPoints"), idSun = Shader.PropertyToID("_FGSun"),
            idSunLight = Shader.PropertyToID("_FGSunLight"), idAhead = Shader.PropertyToID("_FGAhead"), idWorldX = Shader.PropertyToID("_FGWorldX"),
            idWorldY = Shader.PropertyToID("_FGWorldY"), idWorldZ = Shader.PropertyToID("_FGWorldZ"), idTexAt = Shader.PropertyToID("_FGTexAt"),
            idOrigin = Shader.PropertyToID("_floatingOriginOffset"), idFog = Shader.PropertyToID("_FGFog"), idFogSun = Shader.PropertyToID("_FGFogSun"),
            idGlobalDensity = Shader.PropertyToID("_globalDensity"), idHeightDensity = Shader.PropertyToID("_heightDensityAtViewer"),
            idSunLightDirection = Shader.PropertyToID("_sunLightDirection"), idCity = Shader.PropertyToID("_FGCity"),
            idCut = Shader.PropertyToID("_FGCut"), idPlanetOpacity = Shader.PropertyToID("_PlanetOpacity");
        static readonly int[] idSh = { Shader.PropertyToID("_FGShA"), Shader.PropertyToID("_FGShB"), Shader.PropertyToID("_FGShC"), Shader.PropertyToID("_FGShD"),
            Shader.PropertyToID("_FGShE"), Shader.PropertyToID("_FGShF"), Shader.PropertyToID("_FGShG") };
#if DEV
        // (development build: its switches for tests, through Try; none of them is a setting)
        static bool devOff, tint, devNoCraft, devSolid;
        static float devApart, devOwn;
        static double devHighest;
        static Ground live;
#endif

        /// <summary>The mod's page in Keystone's window: once, when the game starts.</summary>
        public static void Setup()
        {
            if (mod != null && Kit.Find("Far Ground") == mod) return;
            mod = Kit.Register("Far Ground", Version, "Kerbin's ground drawn to the horizon at a point every few pixels, from the game's own heights, decals and land, where the game draws a few coarse quads far off: from the clouds' height the ranges, ridges and valleys far away as they are.");
            on = mod.Toggle("on", "Far ground", true, "Off: the game's own ground to the horizon, as the game draws it.");
            apart = mod.Slider("apart", "Points apart", 3f, 2f, 6f, " px", 0, "How far apart its points are on the screen: 2 the finest, which costs about twice as much as 3; 6 the coarsest and the cheapest.");
            own = mod.Slider("own", "The game's own ground within", 6f, 4f, 20f, " km", 0, "Within this distance of the camera the game's own ground is drawn, as the game draws it; beyond it, the far ground. Further: more of the game's own quads drawn, which costs the processor more.");
            mod.Panel = () => { GUILayout.Label(said); if (detail.Length > 0) GUILayout.Label(detail); };
            mod.Status = () => said;
        }

        void Start()
        {
            if (!shadersTried) LoadShaders();
            if (pointsShader == null || drawShader == null) { Say("not drawn: " + shadersWhy); enabled = false; return; }
            pointsMat = new Material(pointsShader) { name = "Far Ground: points" };
            drawMat = new Material(drawShader) { name = "Far Ground: rings" };
            if (depthShader != null) depthMat = new Material(depthShader) { name = "Far Ground: rings, how far off" };
            if (lightsShader != null) lightsMat = new Material(lightsShader) { name = "Far Ground: EVE's city lights" };
            sheet = new Mesh { name = "Far Ground: the sheet" };
            sheet.vertices = new[] { new Vector3(-1f, -1f, 0f), new Vector3(3f, -1f, 0f), new Vector3(-1f, 3f, 0f) };
            sheet.triangles = new[] { 0, 1, 2 };
            sheet.bounds = new Bounds(Vector3.zero, Vector3.one * 1e6f);
            pointsCmd = new CommandBuffer { name = "Far Ground: points" };
            drawCmd = new CommandBuffer { name = "Far Ground: rings" };
            depthCmd = new CommandBuffer { name = "Far Ground: rings, how far off" };
            Camera.onPreCull += PreCull;
#if DEV
            live = this;
#endif
        }

        // (OpenGL, the Mac's and Linux's: the three hand-packed shaders; Direct3D, Windows: the three built from tools/unityshaders in
        // one bundle beside them, where the release has it)
        static void LoadShaders()
        {
            shadersTried = true;
            string folder = KSPUtil.ApplicationRootPath + "GameData/FarGround/PluginData/";
            bool gl = SystemInfo.graphicsDeviceType == GraphicsDeviceType.OpenGLCore;
            string[] files = gl ? new[] { "fargroundpoints.bundle", "fargrounddraw.bundle", "fargrounddepth.bundle", "fargroundlights.bundle" } : new[] { "farground-windows.bundle" };
            try
            {
                foreach (string file in files)
                {
                    if (!File.Exists(folder + file)) { shadersWhy = gl ? "its shaders' files are not there" : "no shaders for " + SystemInfo.graphicsDeviceType + " in this build yet"; continue; }
                    AssetBundle bundle = AssetBundle.LoadFromFile(folder + file);
                    if (bundle == null) { shadersWhy = "its shaders did not load"; continue; }
                    foreach (Shader s in bundle.LoadAllAssets<Shader>())
                    {
                        if (s == null || !s.isSupported) continue;
                        if (s.name == "FarGround/Points") pointsShader = s;
                        else if (s.name == "FarGround/Draw") drawShader = s;
                        else if (s.name == "FarGround/Depth") depthShader = s;
                        else if (s.name == "FarGround/Lights") lightsShader = s;
                    }
                    bundle.Unload(false);
                }
                if ((pointsShader == null || drawShader == null) && shadersWhy.Length == 0) shadersWhy = "its shaders did not load";
            }
            catch (Exception ex) { pointsShader = drawShader = depthShader = null; shadersWhy = "its shaders did not load (" + ex.Message + ")"; }
            Kit.Log("Far Ground", pointsShader != null && drawShader != null ? "shaders loaded" + (depthShader == null ? " (not the depth's: the air will not lie over the far ground)" : "") : "not drawn: " + shadersWhy);
        }

        void OnDestroy()
        {
            Camera.onPreCull -= PreCull;
            Uncut();
            Detach();
            pointsCmd?.Release(); drawCmd?.Release(); depthCmd?.Release();
            Forget();
            if (pointsMat != null) Destroy(pointsMat);
            if (drawMat != null) Destroy(drawMat);
            if (depthMat != null) Destroy(depthMat);
            if (lightsMat != null) Destroy(lightsMat);
            if (sheet != null) Destroy(sheet);
            said = "not in flight"; detail = "";
#if DEV
            if (live == this) live = null;
#endif
        }

        void Forget()
        {
            Uncut();
            LetFade();
            fade = null;
            kerbin?.Dispose();
            kerbin = null;
            eveLights = null;
#if DEV
            if (devSolid) Solid(false);     // (the game's ground outlives the flight: its fade not left held for the next scene)
#endif
            pqs = null;
            if (points != null) { points.Release(); Destroy(points); points = null; }
            if (rings != null) { Destroy(rings); rings = null; }
            meshAround = meshRings = 0;
        }

        void Update()
        {
            CelestialBody now = FlightGlobals.currentMainBody;
            if (now != world) { Forget(); world = now; Begin(); }
            FindCamera();
            double height = far != null && world != null ? world.GetAltitude(far.transform.position) : double.MaxValue;
            // (up to where the game's own ground has gone into the far planet, by the height its fade goes by: the higher of the
            // craft's and the camera's)
            double highest = Highest, again = Again;
            if (fade != null) { highest = FadeEnd() - 500.0; again = highest - 1000.0; height = Math.Max(height, pqs.visibleAltitude); }
#if DEV
            if (devHighest > 0.0) { highest = devHighest; again = devHighest - 1000.0; }
            if (devSolid) Solid(true);
#endif
            if (above ? height < again : height > highest) above = !above;
            bool wanted = on.Value && kerbin != null && far != null && !above && pqs.isActive;
#if DEV
            if (devOff) wanted = false;
#endif
            if (wanted) { Cut(); HoldFade(); reach = Reach(); } else { Uncut(); LetFade(); away = 0; }
            // (what it is doing, for its page and its line in the list: twice a second, the words being made anew each time)
            if (Time.unscaledTime < sayAt) return;
            sayAt = Time.unscaledTime + 0.5f;
            if (!on.Value) Say("off: the game's own ground");
            else if (kerbin == null) Say(why);
            else if (above) Say("above " + (highest / 1000.0).ToString("F0") + " km: the game's own ground" + (fade != null ? ", gone into the far planet" : ""));
            else if (!pqs.isActive) Say("not drawn: the game's own ground is put away");
            else if (far == null) Say("waiting for the flight camera");
#if DEV
            else if (devOff) Say("held off (development build)");
#endif
            else Say("drawing to the horizon", "a point every " + Apart().ToString("F0") + " px: " + drawnAround + " round x " + drawnRings + " rings from " + (drawnNear / 1000.0).ToString("F1")
                     + " km; the game's own ground within " + (cutM / 1000.0).ToString("F1") + " km" + (away > 100.0 ? " of a point " + (away / 1000.0).ToString("F1") + " km from the camera" : "")
                     + (reach < double.MaxValue ? ", drawn without a gap to " + (reach / 1000.0).ToString("F1") + " km from under the camera" : "")
                     + (seenThrough > 0.005f ? "; the far planet through it by " + (seenThrough * 100f).ToString("F0") + " %" : ""));
        }

        static void Say(string what, string more = "") { said = what; detail = more; }

        float Apart()
        {
#if DEV
            if (devApart > 0f) return devApart;
#endif
            return Mathf.Clamp(Mathf.Round(apart.Value), 2f, 6f);
        }

        // ---- Kerbin's layers, as the shaders were written from them
        void Begin()
        {
            why = "not on Kerbin: only Kerbin's ground, as yet";
            if (world == null || world.bodyName != "Kerbin" || world.pqsController == null) return;
            Kerbin k = Kerbin.Read(world.pqsController, out string not);
            if (k == null) { why = "off: Kerbin's ground is not as its shader has it (" + not + ")"; Kit.Log("Far Ground", why); return; }
            kerbin = k;
            pqs = world.pqsController;
            fade = KerbinFade(pqs);
            Look(k.Ground);
            Kit.Log("Far Ground", "Kerbin's layers found as the shader has them: " + k.Found + (fade != null ? "; its ground goes into the far planet from "
                    + (fade.fadeStart / 1000f).ToString("F0") + " to " + (fade.fadeEnd / 1000f).ToString("F0") + " km" : "; its hand-over to the far planet not as Kerbin's: drawn up to 30 km"));
            Lights(k.CityLights);
        }

        // (the game's own ground material's textures, values and switches, for shading the far ground as it shades the near: the draw
        // shader is written from "Terrain/PQS/PQS Main Shader" and "- Optimised", read out of the game's data)
        void Look(Material ground)
        {
            if (ground == null) { Kit.Log("Far Ground", "no ground material: the far ground is lit plainly"); return; }
            Kit.Log("Far Ground", "the ground's material: '" + ground.name + "', shader '" + ground.shader.name + "', keywords " + string.Join(" ", ground.shaderKeywords)
                + (ground.shader.name == "Terrain/PQS/PQS Main Shader" || ground.shader.name == "Terrain/PQS/PQS Main - Optimised" ? "" : " (not a shader the far ground was written from: its look may differ)"));
            float F(string n, float d) => ground.HasProperty(n) ? ground.GetFloat(n) : d;
            Color tintC = ground.HasProperty("_tintColor") ? ground.GetColor("_tintColor") : new Color(0f, 0f, 0f, 0f);
            int flags = (ground.IsKeywordEnabled("LOW_TEXTURING_ON") ? 1 : 0) + (ground.IsKeywordEnabled("HIGH_TEXTURING_ON") ? 2 : 0) + (ground.IsKeywordEnabled("STEEP_TEXTURING_ON") ? 4 : 0);
            drawMat.SetVector("_FGLook", new Vector4(F("_saturation", 1f), F("_contrast", 1f), F("_groundTexStart", 0f), F("_groundTexEnd", 1f)));
            drawMat.SetVector("_FGTint", tintC);
            drawMat.SetVector("_FGPower", new Vector4(F("_powerNear", 0f), F("_powerFar", 0f), F("_steepPower", 1f), flags));
            drawMat.SetVector("_FGSteep", new Vector4(F("_steepNearTiling", 1f), F("_steepTiling", 1f), F("_steepTexStart", 0f), F("_steepTexEnd", 1f)));
            drawMat.SetVector("_FGTile", new Vector4(F("_lowNearTiling", 1f), F("_lowMultiFactor", 1f), F("_midNearTiling", 1f), F("_midMultiFactor", 1f)));
            drawMat.SetVector("_FGTile2", new Vector4(F("_highNearTiling", 1f), F("_highMultiFactor", 1f), 0f, 0f));
            drawMat.SetVector("_FGBands", new Vector4(F("_lowStart", 0f), F("_lowEnd", 1f), F("_highStart", 0f), F("_highEnd", 1f)));
            foreach (string t in new[] { "_lowTex", "_midTex", "_highTex", "_steepTex" })
                drawMat.SetTexture(t, ground.HasProperty(t) && ground.GetTexture(t) != null ? ground.GetTexture(t) : Texture2D.whiteTexture);
            // (its own fog, where it has it on: the ramp of colours by the sun's height; how thick, the game hands every shader as it goes)
            drawMat.SetTexture("_fogColorRamp", kerbin.Aerial ? ground.GetTexture("_fogColorRamp") : Texture2D.whiteTexture);
        }

        // (EVE's city lights, where it lays them on the game's ground: the far ground lays them on its own as EVE does, from EVE's own
        // textures and values. Its lights shader is EVE's programs for a map of the lights in a cube or in the cube's six faces, one
        // of its channels chosen by a mask (EVE's keywords ALPHAMAP_1 and MAP_TYPE_CUBE_1 or MAP_TYPE_CUBE6_1; the owner's EVE has the
        // six faces); any other kind of EVE's maps, and the far ground goes without)
        static readonly string[] faces = { "xn", "xp", "yn", "yp", "zn", "zp" };
        static Cubemap noCube;
        static bool Declared(Material m, string name) => m.shader != null && m.shader.FindPropertyIndex(name) >= 0;
        void Lights(Material eve)
        {
            if (eve == null || lightsMat == null) return;
            bool cube = eve.IsKeywordEnabled("MAP_TYPE_CUBE_1") && Declared(eve, "cube_CityOverlayTex") && eve.GetTexture("cube_CityOverlayTex") != null;
            bool six = eve.IsKeywordEnabled("MAP_TYPE_CUBE6_1");
            // (EVE sets the six faces, and the mask, on its material by names its shader does not declare: the shader is given them,
            // but Unity hands them back to no one, GetTexture giving nothing for them. So the faces are taken where EVE took them,
            // CityFaces, and the mask from EVE's keyword for it, Mask. A name the shader does not declare is not asked for: GetTexture
            // logs an error for each, six at every start with the owner's EVE, seen on the Windows PC 2026-10-20; HasProperty does
            // not tell, as it counts the names set on the material too: the shader's own list does)
            var sixFaces = new Texture[faces.Length];
            string why = "";
            if (six)
            {
                for (int i = 0; i < faces.Length; i++) { string n = "cube_CityOverlayTex" + faces[i]; sixFaces[i] = Declared(eve, n) ? eve.GetTexture(n) : null; }
                if (Array.Exists(sixFaces, t => t == null))
                {
                    Texture2D[] found = CityFaces(out why);
                    if (found != null) sixFaces = found; else six = false;
                }
            }
            if (!eve.IsKeywordEnabled("ALPHAMAP_1") || !(cube || six))
            {
                Kit.Log("Far Ground", "EVE's city lights are of a kind the far ground does not lay (keywords " + string.Join(" ", eve.shaderKeywords) + (why.Length > 0 ? "; " + why : "") + "): none on it");
                return;
            }
            if (noCube == null) { noCube = new Cubemap(1, TextureFormat.RGBA32, false) { name = "Far Ground: no cube" }; foreach (CubemapFace f in Enum.GetValues(typeof(CubemapFace))) if (f != CubemapFace.Unknown) noCube.SetPixel(f, 0, 0, Color.clear); noCube.Apply(); }
            lightsMat.SetTexture("_FGCityMap", cube ? eve.GetTexture("cube_CityOverlayTex") : noCube);
            for (int i = 0; i < faces.Length; i++)
                lightsMat.SetTexture("_FGCity" + faces[i].ToUpperInvariant(), six ? sixFaces[i] : Texture2D.blackTexture);
            lightsSix = six && !cube;
            lightsMat.SetTexture("_FGCityDark", eve.GetTexture("_CityDarkOverlayDetailTex") ?? Texture2D.blackTexture);
            lightsMat.SetTexture("_FGCityLight", eve.GetTexture("_CityLightOverlayDetailTex") ?? Texture2D.blackTexture);
            lightsMat.SetVector("_FGCityMask", Mask(eve));
            eveLights = eve;
            Kit.Log("Far Ground", "EVE's city lights laid on the far ground too (keywords " + string.Join(" ", eve.shaderKeywords) + (six ? "; its six faces " + sixFaces[0].name + " ..." : "") + ")");
        }

        // (the six faces of EVE's map of Kerbin's city lights, as EVE takes them (its TextureConfigObject.Apply): its EVE_CITY_LIGHTS
        // object for Kerbin names the map, its EVE_TEXTURE_CONFIG object of that name, of the kind TEX_CUBE_6, names the six faces,
        // and the game's database holds them. In the order of the faces above; nothing, and why, where any is missing)
        static Texture2D[] CityFaces(out string why)
        {
            string map = null;
            foreach (ConfigNode lights in GameDatabase.Instance.GetConfigNodes("EVE_CITY_LIGHTS"))
                foreach (ConfigNode o in lights.GetNodes("OBJECT"))
                {
                    if (o.GetValue("body") != "Kerbin") continue;
                    ConfigNode mat = o.GetNode("cityLightsMaterial");
                    ConfigNode tex = mat?.GetNode("_CityOverlayTex");
                    map = tex != null ? tex.GetValue("value") : mat?.GetValue("_CityOverlayTex");
                }
            why = "";
            if (string.IsNullOrEmpty(map)) { why = "no map named for Kerbin in EVE_CITY_LIGHTS"; return null; }
            foreach (ConfigNode config in GameDatabase.Instance.GetConfigNodes("EVE_TEXTURE_CONFIG"))
                foreach (ConfigNode o in config.GetNodes("OBJECT"))
                {
                    if (o.GetValue("name") != map) continue;
                    if (o.GetValue("type") != "TEX_CUBE_6") { why = map + " is not of six faces"; return null; }
                    bool.TryParse(o.GetValue("isNormalMap"), out bool normal);
                    var found = new Texture2D[faces.Length];
                    for (int i = 0; i < faces.Length; i++)
                    {
                        string path = o.GetValue("tex" + char.ToUpperInvariant(faces[i][0]) + faces[i].Substring(1));
                        found[i] = string.IsNullOrEmpty(path) ? null : GameDatabase.Instance.GetTexture(path, normal);
                        if (found[i] == null) { why = map + "'s face " + faces[i] + " (" + path + ") not in the game's database"; return null; }
                    }
                    return found;
                }
            why = "no EVE_TEXTURE_CONFIG of " + map;
            return null;
        }

        // (the channel of EVE's map its lights are in, from its keyword for it, as EVE makes alphaMask1: ALPHAMAP_A where none is said)
        static Vector4 Mask(Material eve) =>
            eve.IsKeywordEnabled("ALPHAMAP_R_1") ? new Vector4(1f, 0f, 0f, 0f) : eve.IsKeywordEnabled("ALPHAMAP_G_1") ? new Vector4(0f, 1f, 0f, 0f)
            : eve.IsKeywordEnabled("ALPHAMAP_B_1") ? new Vector4(0f, 0f, 1f, 0f) : new Vector4(0f, 0f, 0f, 1f);

        // (the light probe's harmonics as Unity hands them to a shader, unity_SHAr ... unity_SHC)
        static void Harmonics(Material m)
        {
            SphericalHarmonicsL2 sh = RenderSettings.ambientProbe;
            for (int c = 0; c < 3; c++)
            {
                m.SetVector(idSh[c], new Vector4(sh[c, 3], sh[c, 1], sh[c, 2], sh[c, 0] - sh[c, 6]));
                m.SetVector(idSh[3 + c], new Vector4(sh[c, 4], sh[c, 5], sh[c, 6] * 3f, sh[c, 7]));
            }
            m.SetVector(idSh[6], new Vector4(sh[0, 8], sh[1, 8], sh[2, 8], 1f));
        }

        // ---- the camera that draws the far ground: the far flight camera on OpenGL ("Camera 01", from 400 m on), the one flight
        // camera on Direct3D 11 ("Camera 00", which draws near and far there)
        void FindCamera()
        {
            // (asked every frame: the far camera whenever it is on, so that the rings go back to it after anything that switched it
            // off for a while; neither on, as in the map's view, and they stay where they are)
            Camera c = Names.CameraNamed("Camera 01") ?? Names.CameraNamed("Camera 00");
            if (c == null || c == far) return;
            Detach();
            far = c;
            far.AddCommandBuffer(CameraEvent.BeforeForwardOpaque, drawCmd);
            if (depthMat != null) far.AddCommandBuffer(CameraEvent.AfterDepthTexture, depthCmd);
            Kit.Log("Far Ground", "on " + Names.Of(far) + " (" + far.nearClipPlane + " to " + far.farClipPlane + " m)");
        }

        void Detach()
        {
            if (far != null)
            {
                if (drawCmd != null) far.RemoveCommandBuffer(CameraEvent.BeforeForwardOpaque, drawCmd);
                if (depthCmd != null) far.RemoveCommandBuffer(CameraEvent.AfterDepthTexture, depthCmd);
            }
            far = null;
        }

        // ---- the game's quads cut back to the near ground: its visible radius is horizonDistance x sin(horizonAngle) x visRad,
        // visRad going from visRadSeaLevelValue to visRadAltitudeValue with height and held between them; both set to the one value
        // that gives the radius wanted (a quad is drawn while its middle is within it, the distance along the ground times 1.3)
        void Cut()
        {
            float ownKm = own.Value;
#if DEV
            if (devOwn > 0f) ownKm = devOwn;
#endif
            // (and beyond every craft that is loaded, from the point the game builds its ground round: it builds a quad, and gives
            // the finest their colliders, only once it is drawn, and a craft on the ground needs its ground built)
            double craft = Craft() + BeyondCraft;
#if DEV
            if (devNoCraft) craft = 0;
#endif
            double want = Math.Max(ownKm * 1000.0, craft);
            if (!cutting) { keptSea = pqs.visRadSeaLevelValue; keptAlt = pqs.visRadAltitudeValue; cutting = true; }
            double horizon = pqs.horizonDistance * Math.Sin(pqs.horizonAngle);
            if (horizon <= 0) return;
            double v = Math.Min(1.3 * want / horizon, keptSea);
            pqs.visRadSeaLevelValue = v; pqs.visRadAltitudeValue = v;
            cutM = want;
        }

        void Uncut()
        {
            if (!cutting) return;
            if (pqs != null) { pqs.visRadSeaLevelValue = keptSea; pqs.visRadAltitudeValue = keptAlt; }
            cutting = false;
        }

        // ---- the game's hand-over of its ground to the far planet with height: PQSMod_CelestialBodyTransform's planetFade, the
        // material's _PlanetOpacity from nought at fadeStart to one at fadeEnd, the alpha the ground's shader blends with
        // (OneMinusSrcAlpha, SrcAlpha) over the far planet drawn before it. While the far ground is drawn, begun only FadeOver below
        // its end; put back as it was after (the game's ground outlives the flight)
        static PQSMod_CelestialBodyTransform.AltitudeFade KerbinFade(PQS sphere)
        {
            foreach (PQSMod_CelestialBodyTransform t in sphere.GetComponentsInChildren<PQSMod_CelestialBodyTransform>(true))
            {
                PQSMod_CelestialBodyTransform.AltitudeFade f = t.planetFade;
                if (f != null && f.fadeFloatName == "_PlanetOpacity" && f.valueStart == 0f && f.valueEnd == 1f && f.fadeEnd > f.fadeStart) return f;
            }
            return null;
        }

        // (its end: the high-quality shaders' where those are in use and it has one)
        double FadeEnd() => GameSettings.TERRAIN_SHADER_QUALITY >= 2 && fade.highQualityShaderFadeEnd > 0f ? fade.highQualityShaderFadeEnd : fade.fadeEnd;

        void HoldFade()
        {
            if (fade == null || fadeHeld) return;
            keptFadeStart = fade.fadeStart; keptFadeStartHigh = fade.highQualityShaderFadeStart;
            fade.fadeStart = Mathf.Max(fade.fadeStart, fade.fadeEnd - FadeOver);
            if (fade.highQualityShaderFadeStart > 0f && fade.highQualityShaderFadeEnd > 0f)
                fade.highQualityShaderFadeStart = Mathf.Max(fade.highQualityShaderFadeStart, fade.highQualityShaderFadeEnd - FadeOver);
            fadeHeld = true;
        }

        void LetFade()
        {
            if (fade == null || !fadeHeld) return;
            fade.fadeStart = keptFadeStart; fade.highQualityShaderFadeStart = keptFadeStartHigh;
            fadeHeld = false;
        }

        // (how far along the ground from the point the game builds its ground round the farthest loaded craft on this world stands, m)
        double Craft()
        {
            double most = 0;
            Vector3d at = pqs.relativeTargetPositionNormalized;
            Transform frame = pqs.transform;
            foreach (Vessel v in FlightGlobals.VesselsLoaded)
            {
                if (v == null || v.mainBody != world) continue;
                Vector3d d = ((Vector3d)frame.InverseTransformPoint(v.CoMD)).normalized;
                double a = Math.Acos(Math.Max(-1.0, Math.Min(1.0, Vector3d.Dot(d, at)))) * pqs.radius;
                if (a > most) most = a;
            }
            return most;
        }

        // ---- how far from the point under the camera the game's own ground is drawn without a gap: as near as the nearest corner
        // of the nearest quad it leaves undrawn may lie. The game draws a quad only while its middle is within its visible radius of
        // the point it builds its ground round, and that point is not always under the camera: with the camera held kilometres from
        // the craft (the mod's first look in the game, 2026-10-20 14:30), the game's ground stayed round the craft and none was drawn
        // round the camera, a pale plane and the sea's own surface there. Measured from the point under the camera, where the rings
        // are laid, the rings begin within the game's ground wherever that is, under the camera if need be. The tree is walked from
        // its six faces, leaving out whatever cannot hold a quad nearer than the nearest known.
        double Reach()
        {
            under = ((Vector3d)pqs.transform.InverseTransformPoint(far.transform.position)).normalized;
            away = Math.Acos(Math.Max(-1.0, Math.Min(1.0, Vector3d.Dot(under, pqs.relativeTargetPositionNormalized)))) * pqs.radius;
            best = cutM;
            PQ[] faces = pqs.quads;
            if (faces != null) for (int i = 0; i < faces.Length; i++) Walk(faces[i]);
            return best;
        }

        void Walk(PQ q)
        {
            if (q == null) return;
            double middle = Math.Acos(Math.Max(-1.0, Math.Min(1.0, Vector3d.Dot(q.positionPlanetRelative, under)))) * pqs.radius;
            // (half its diagonal at most: its size on the cube's face, which is never less than the angle it spans)
            double nearest = middle - 1.42 * q.scalePlaneRelative * pqs.radius;
            if (nearest >= best) return;
            if (q.isSubdivided && q.subNodes != null) { for (int i = 0; i < q.subNodes.Length; i++) Walk(q.subNodes[i]); return; }
            if (q.isVisible && q.meshRenderer != null && q.meshRenderer.enabled) return;
            best = Math.Max(0.0, nearest);
        }

        // ---- each frame, before the far camera draws: the rings for this view, their points worked out, the draws set
        void PreCull(Camera cam)
        {
            if (cam != far || drawCmd == null) return;
            drawCmd.Clear();
            depthCmd?.Clear();
            if (!cutting || kerbin == null) return;
            Transform frame = pqs.transform;
            double R = pqs.radius;
            Vector3 camAt = frame.InverseTransformPoint(cam.transform.position);
            Vector3 up = camAt.normalized;
            Vector3 north = Vector3.up - up * Vector3.Dot(up, Vector3.up);
            north = north.sqrMagnitude > 1e-6f ? north.normalized : Vector3.Cross(up, Vector3.right).normalized;
            Vector3 east = Vector3.Cross(up, north);
            Vector3 ahead = frame.InverseTransformDirection(cam.transform.forward);
            float heading = Mathf.Atan2(Vector3.Dot(ahead, east), Vector3.Dot(ahead, north));
            // (a point every so many pixels seen square-on, round each ring as wide as the view and a little more; the rings three times
            // as far apart outward, the ground being seen at a slant)
            float tanY = Mathf.Tan(cam.fieldOfView * 0.5f * Mathf.Deg2Rad), tanX = tanY * cam.aspect;
            double pxPerRad = cam.pixelWidth / (2.0 * Math.Atan(tanX));
            double step = Apart() / pxPerRad;
            // (the bearings the view's corners reach on the ground: as wide as the view looking level, wider looking down, and all
            // round once the view comes down to the point under the camera. Worked out for a level look alone, as it first was, a
            // view straight down from 100 km left a wedge of the ground beside that point undrawn, its edge a straight line from it)
            double corner = Math.Atan(Math.Sqrt(tanX * tanX + tanY * tanY));
            double down = Math.Asin(Mathf.Clamp(-Vector3.Dot(ahead, up), -1f, 1f));
            double spread = down + corner >= 0.5 * Math.PI - 0.1 ? Math.PI : Math.Asin(Math.Min(1.0, Math.Sin(corner) / Math.Cos(down)));
            double halfWedge = Math.Min(Math.PI, spread * 1.5 + 10.0 * Math.PI / 180.0);
            int around = (int)Math.Ceiling(2.0 * halfWedge / step) + 1;
            double camAlt = camAt.magnitude - R;
            double ground = pqs.GetSurfaceHeight(up) - R;
            // (the first ring inside the game's own ground, a little within the nearest place it leaves undrawn)
            double near = Math.Max(Nearest, Math.Min(0.7 * cutM, reach * 0.95 - 50.0));
            // (the camera below the sea's level, under the water, sees the land's horizon as from the sea's level: below it the root
            // here was of less than nought, the rings' count not a number, and the rings' mesh, put away before a new one could not
            // be made, missing from every frame after: an exception a frame; the PC's sea looks at the reef, 2026-10-20)
            double eye = Math.Max(0.0, Math.Max(camAlt, ground));
            double ringFar = Math.Sqrt(Math.Pow(R + eye, 2) - R * R) + Math.Sqrt(kerbin.RadiusMax * kerbin.RadiusMax - R * R);
            double q = 1.0 + 3.0 * step;
            double count = Math.Ceiling(Math.Log(ringFar / near) / Math.Log(q)) + 1;
            if (!(count >= 2.0 && count < 100000.0)) return;
            int needRings = (int)count;
            // (the mesh and the points' picture made with room to spare, round and out, and made again only when the view needs more
            // or much less: the points round a ring now change as the camera tips; those beyond what is drawn are left out)
            if (around > meshAround || around < meshAround * 0.7 || needRings > meshRings || needRings < meshRings * 0.7)
                Make((int)(around * 1.15) + 2, (int)(needRings * 1.15) + 2);
            // (only the rings drawn this frame are drawn: the mesh's spare rings beyond them are left out of its triangles. The
            // shaders put a spare ring's points outside the view (z 2, w 1), which on OpenGL is beyond the far end; with Direct3D's
            // depth the other way round it is nearer than the near end, and each triangle from the last ring drawn to a spare one
            // was cut only at the near end: a dark band from the farthest rings halfway to the middle of the screen, nearer than
            // anything, over the craft and the pad (the PC, 2026-10-20). A row of the mesh's triangles is all of its points round,
            // spare ones too (meshAround), so the rows kept are counted in those)
            if (needRings != meshDrawn)
            {
                rings.SetSubMesh(0, new SubMeshDescriptor(0, (meshAround - 1) * (needRings - 1) * 6, MeshTopology.Triangles),
                                 MeshUpdateFlags.DontRecalculateBounds | MeshUpdateFlags.DontValidateIndices);
                meshDrawn = needRings;
            }
            drawnAround = around; drawnRings = needRings; drawnNear = near;

            Vector4 upV = up, northV = north, eastV = east;
            northV.w = (float)(near / R); eastV.w = (float)Math.Log(q);
            var round = new Vector4((float)(heading - halfWedge), (float)(2.0 * halfWedge / (around - 1)), (float)(ringFar / R), needRings);
            Rings(pointsMat, upV, northV, eastV, round); Rings(drawMat, upV, northV, eastV, round);
            pointsMat.SetVector(idSheet, new Vector4(1f, 1f, 0.5f, 1f));
            pointsMat.SetVector(idPush, new Vector4(1.003f, around, PushMost, 0f));
            pointsMat.SetTexture(idMap, kerbin.Map); pointsMat.SetTexture(idTables, kerbin.Tables); pointsMat.SetTexture(idDecalMaps, kerbin.DecalMaps);
            pointsMat.SetVector(idDecals, kerbin.DecalsOn); pointsMat.SetVector(idFlats, kerbin.FlatsOn);
            pointsCmd.Clear();
            pointsCmd.SetRenderTarget(points);
            pointsCmd.DrawMesh(sheet, Matrix4x4.identity, pointsMat, 0, 0);
            Graphics.ExecuteCommandBuffer(pointsCmd);

            // (from the PQS's frame, the camera at its origin, to the screen: the projection as it stands (turned over in the shaders
            // where the camera draws upside down, by _ProjectionParams, as Unity's own matrices are), the camera's turn, the world's)
            Matrix4x4 view = cam.worldToCameraMatrix;
            view.m03 = 0f; view.m13 = 0f; view.m23 = 0f;
            Matrix4x4 toScreen = GL.GetGPUProjectionMatrix(cam.projectionMatrix, false) * view * Matrix4x4.Rotate(frame.rotation);
            // (where the game's own quads may be drawn too: round the point it builds its ground round, out to its visible radius and
            // half the largest quad it draws there; the rings are drawn a little farther than they are only there)
            Vector3 cutAt = (Vector3)pqs.relativeTargetPositionNormalized;
            var cut = new Vector4(cutAt.x, cutAt.y, cutAt.z, (float)((1.3 * cutM + 3000.0) / R));
            // (w: where the shaders put the mesh's spare points, beyond the far end of the depth: z 2 on OpenGL, z -1 where the depth
            // runs the other way round (Direct3D); nearer than the near end, triangles to them were drawn across the screen)
            var push = new Vector4(1.003f, around, PushMost, SystemInfo.usesReversedZBuffer ? -1f : 2f);
            drawMat.SetVector(idRow0, toScreen.GetRow(0)); drawMat.SetVector(idRow1, toScreen.GetRow(1));
            drawMat.SetVector(idRow2, toScreen.GetRow(2)); drawMat.SetVector(idRow3, toScreen.GetRow(3));
            drawMat.SetVector(idCam, new Vector4(camAt.x, camAt.y, camAt.z, (float)R));
            drawMat.SetVector(idPush, push); drawMat.SetVector(idCut, cut);
            drawMat.SetTexture(idPoints, points);
            Vector3d toSun = Planetarium.fetch.Sun.position - world.position;
            Vector3 sun = frame.InverseTransformDirection((Vector3)toSun.normalized);
            bool red = false;
#if DEV
            red = tint;
#endif
            drawMat.SetVector(idSun, new Vector4(sun.x, sun.y, sun.z, red ? 1f : 0f));
            Light light = Sun.Instance != null ? Sun.Instance.sunLight : null;
            drawMat.SetVector(idSunLight, light != null ? light.color * light.intensity : Color.white);
            Harmonics(drawMat);
            // (the frame the game lays its ground's textures in: the scene's, plus the floating origin's offset, in 100 km)
            drawMat.SetVector(idAhead, ahead);
            Matrix4x4 turn = Matrix4x4.Rotate(frame.rotation);
            drawMat.SetVector(idWorldX, turn.GetRow(0)); drawMat.SetVector(idWorldY, turn.GetRow(1)); drawMat.SetVector(idWorldZ, turn.GetRow(2));
            Vector3 offset = Shader.GetGlobalVector(idOrigin);      // (FloatingOrigin sets it for every shader)
            drawMat.SetVector(idTexAt, (frame.position + offset) * 1e-5f);
            // (the ground's own fog: how thick, as the game has handed it to every shader this frame, and the sun's direction its ramp is read by)
            // (and how far the far planet shows through the ground, as the game has set it on its ground's material this frame; with the
            // camera under the sea the game's shader takes another alpha, and the far ground is drawn solid)
            Material own = pqs.surfaceMaterial;
            seenThrough = camAlt > 0.0 && own != null && own.HasProperty(idPlanetOpacity) ? Mathf.Clamp01(own.GetFloat(idPlanetOpacity)) : 0f;
            drawMat.SetVector(idFog, new Vector4(Shader.GetGlobalFloat(idGlobalDensity), Shader.GetGlobalFloat(idHeightDensity), kerbin.Aerial ? 1f : 0f, seenThrough));
            drawMat.SetVector(idFogSun, Shader.GetGlobalVector(idSunLightDirection));
            drawCmd.DrawMesh(rings, Matrix4x4.identity, drawMat, 0, 0);
            // (and into the depth picture, placed the same)
            if (depthMat != null)
            {
                Rings(depthMat, upV, northV, eastV, round);
                depthMat.SetVector(idRow0, toScreen.GetRow(0)); depthMat.SetVector(idRow1, toScreen.GetRow(1));
                depthMat.SetVector(idRow2, toScreen.GetRow(2)); depthMat.SetVector(idRow3, toScreen.GetRow(3));
                depthMat.SetVector(idCam, new Vector4(camAt.x, camAt.y, camAt.z, (float)R));
                depthMat.SetVector(idPush, push); depthMat.SetVector(idCut, cut);
                depthMat.SetTexture(idPoints, points);
                depthCmd.SetRenderTarget(BuiltinRenderTextureType.Depth);
                depthCmd.DrawMesh(rings, Matrix4x4.identity, depthMat, 0, 0);
            }
            // (EVE's city lights over the rings, as EVE lays them over the game's ground: just after them, at their very places)
            if (eveLights != null)
            {
                Rings(lightsMat, upV, northV, eastV, round);
                lightsMat.SetVector(idRow0, toScreen.GetRow(0)); lightsMat.SetVector(idRow1, toScreen.GetRow(1));
                lightsMat.SetVector(idRow2, toScreen.GetRow(2)); lightsMat.SetVector(idRow3, toScreen.GetRow(3));
                lightsMat.SetVector(idCam, new Vector4(camAt.x, camAt.y, camAt.z, (float)R));
                lightsMat.SetVector(idPush, push); lightsMat.SetVector(idCut, cut);
                lightsMat.SetTexture(idPoints, points);
                lightsMat.SetVector(idSun, new Vector4(sun.x, sun.y, sun.z, 0f));
                lightsMat.SetVector(idCity, new Vector4(eveLights.HasProperty("_CityOverlayDetailScale") ? eveLights.GetFloat("_CityOverlayDetailScale") : 1f,
                                                        eveLights.HasProperty("_PlanetOpacity") ? eveLights.GetFloat("_PlanetOpacity") : 1f, lightsSix ? 1f : 0f, 0f));
                drawCmd.DrawMesh(rings, Matrix4x4.identity, lightsMat, 0, 0);
            }
        }

        static void Rings(Material m, Vector4 up, Vector4 north, Vector4 east, Vector4 round)
        {
            m.SetVector(idUp, up); m.SetVector(idNorth, north); m.SetVector(idEast, east); m.SetVector(idRound, round);
        }

        // (the rings' mesh: a point (its place round, its ring) for each, two triangles to each cell; and their points' picture)
        void Make(int around, int ringCount)
        {
            if (rings != null) Destroy(rings);
            if (points != null) { points.Release(); Destroy(points); }
            var at = new Vector3[around * ringCount];
            for (int r = 0; r < ringCount; r++) for (int k = 0; k < around; k++) at[r * around + k] = new Vector3(k, r, 0f);
            var idx = new int[(around - 1) * (ringCount - 1) * 6];
            int n = 0;
            for (int r = 1; r < ringCount; r++)
                for (int k = 1; k < around; k++)
                {
                    int a0 = (r - 1) * around + k - 1, b0 = r * around + k - 1;
                    idx[n++] = a0; idx[n++] = b0; idx[n++] = a0 + 1; idx[n++] = a0 + 1; idx[n++] = b0; idx[n++] = b0 + 1;
                }
            rings = new Mesh { name = "Far Ground: rings", indexFormat = IndexFormat.UInt32 };
            rings.vertices = at;
            rings.SetIndices(idx, MeshTopology.Triangles, 0);
            rings.bounds = new Bounds(Vector3.zero, Vector3.one * 1e7f);
            points = new RenderTexture(around, ringCount, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear)
            { name = "Far Ground: points", filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp, useMipMap = false };
            points.Create();
            meshAround = around; meshRings = ringCount; meshDrawn = ringCount;
            Kit.Log("Far Ground", "rings made: " + around + " round x " + ringCount + " out (" + (around * ringCount) + " points)");
        }

#if DEV
        /// <summary>
        /// (Development build: "off" and "on" (the far ground held off for a test, or let be: the setting is left as it is), "tint"
        /// and "untint" (the far ground tinted red, to see where it is), "own N" (the game's own ground within N km; 0: the
        /// setting's), "px N" (points apart; 0: the setting's), "craft off" and "craft on" (the game's own ground kept beyond the
        /// loaded craft or not: off for a test that holds the camera far from a craft standing on the pad, whose own collider holds
        /// it), "high N" (drawn up to N m instead of where the game's own ground has gone into the far planet; 0: as it is), "solid on" and "solid off" (the game's own
        /// ground held solid, the far planet not seen through it), "stats" (what it draws), "eve" (EVE's city lights as found on the
        /// game's ground, and what is taken instead), "fades" (how the game hands its ground over to the far planet with height).)
        /// </summary>
        public static string Try(string arg)
        {
            string[] w = (arg ?? "").Trim().Split(' ');
            switch (w[0])
            {
                case "off": devOff = true; break;
                case "on": devOff = false; break;
                case "tint": tint = true; break;
                case "untint": tint = false; break;
                case "own": if (w.Length > 1 && float.TryParse(w[1], out float o) && o >= 0f) devOwn = o; break;
                case "px": if (w.Length > 1 && float.TryParse(w[1], out float p) && p >= 0f) devApart = p; break;
                case "craft": devNoCraft = w.Length > 1 && w[1] == "off"; break;
                case "high": if (w.Length > 1 && double.TryParse(w[1], out double h) && h >= 0.0) devHighest = h; break;
                case "solid": devSolid = w.Length > 1 && w[1] == "on"; live?.Solid(devSolid); break;
                case "fades": return Fades(live);
                case "stats": break;
                case "eve": return Eve(live?.kerbin?.CityLights);
                default: return "off | on | tint | untint | own N | px N | craft off | craft on | high N | solid on | solid off | stats | eve | fades";
            }
            Ground g = live;
            return said + (detail.Length > 0 ? "; " + detail : "") + (g != null && g.pqs != null ? "; the game's visible radius " + (g.pqs.visibleRadius / 1000.0).ToString("F1") + " km" : "")
                + (g != null && g.far != null ? "; on " + Names.Of(g.far) : "") + (tint ? "; tinted" : "") + (devNoCraft ? "; the craft left out of the cut" : "")
                + (devHighest > 0.0 ? "; drawn up to " + (devHighest / 1000.0).ToString("F0") + " km" : "")
                + (g != null && g.pqs != null && g.pqs.surfaceMaterial != null ? "; the game's ground seen through by " + g.pqs.surfaceMaterial.GetFloat("_PlanetOpacity").ToString("F2") + (devSolid ? " (held solid)" : "") : "");
        }

        // ("eve": EVE's city lights' material as the far ground found it on Kerbin's quads: its shader and keywords, which of the
        // names it reads hand back a texture (EVE sets the faces by names its shader does not declare, which hand back nothing),
        // and the faces and mask the far ground takes instead)
        static string Eve(Material m)
        {
            if (m == null) return "no EVE city lights found on Kerbin's ground";
            var s = new System.Text.StringBuilder(m.shader.name + "; keywords " + string.Join(" ", m.shaderKeywords) + ";");
            var names = new System.Collections.Generic.List<string> { "_CityOverlayTex", "_CityDarkOverlayDetailTex", "_CityLightOverlayDetailTex", "cube_CityOverlayTex" };
            foreach (string f in faces) names.Add("cube_CityOverlayTex" + f);
            foreach (string n in names)
            {
                Texture t = Declared(m, n) ? m.GetTexture(n) : null;
                s.Append(" " + n + " = " + (t != null ? t.name + " " + t.width + "x" + t.height : Declared(m, n) ? "nothing" : "not in its shader") + ";");
            }
            Texture2D[] found = CityFaces(out string why);
            s.Append(" taken instead: " + (found != null ? string.Join(", ", Array.ConvertAll(found, t => t.name)) : why) + "; the mask " + Mask(m));
            return s.ToString();
        }

        // ("solid on": the game's own ground held as solid as below the height its fade begins at. Its shader blends
        // OneMinusSrcAlpha, SrcAlpha with the PQS material's _PlanetOpacity as its alpha, which Kerbin's
        // PQSMod_CelestialBodyTransform raises with the higher of the craft's and the camera's height, so the far planet (the
        // scaled-space Kerbin, drawn before) shows through it; the game's own overrideFade holds the fade at its value at sea level)
        void Solid(bool held)
        {
            if (pqs == null) return;
            foreach (PQSMod_CelestialBodyTransform t in pqs.GetComponentsInChildren<PQSMod_CelestialBodyTransform>(true)) t.overrideFade = held;
        }

        // ("fades": how the game hands Kerbin's ground over to the far planet with height: its fades, the heights it puts the
        // ground away at, the far planet's own fader, and their values now)
        static string Fades(Ground g)
        {
            if (g == null || g.pqs == null || g.world == null) return "not on Kerbin's ground";
            var s = new System.Text.StringBuilder("seen from " + (g.pqs.visibleAltitude / 1000.0).ToString("F1") + " km (the game's terrain shader quality " + GameSettings.TERRAIN_SHADER_QUALITY + ");");
            foreach (PQSMod_CelestialBodyTransform t in g.pqs.GetComponentsInChildren<PQSMod_CelestialBodyTransform>(true))
            {
                s.Append(" put away above " + t.deactivateAltitude + " m (" + t.highQualityShaderDeactivateAltitude + " at high quality);");
                Fade(s, "the ground", t.planetFade);
                foreach (PQSMod_CelestialBodyTransform.AltitudeFade f in t.secondaryFades) Fade(s, "another", f);
            }
            foreach (PQSMod_MaterialFadeAltitude m in g.pqs.GetComponentsInChildren<PQSMod_MaterialFadeAltitude>(true))
                s.Append(" " + m.floatName + " " + m.fadeStart + "-" + m.fadeEnd + " m: " + m.valueStart + "-" + m.valueEnd + ";");
            if (g.pqs.surfaceMaterial != null) s.Append(" the ground's _PlanetOpacity now " + g.pqs.surfaceMaterial.GetFloat("_PlanetOpacity").ToString("F3") + ";");
            ScaledSpaceFader sf = g.world.scaledBody != null ? g.world.scaledBody.GetComponent<ScaledSpaceFader>() : null;
            if (sf == null) return s.Append(" no fader on the far planet").ToString();
            Renderer r = sf.GetComponent<Renderer>();
            return s.Append(" the far planet: " + sf.floatName + " " + sf.fadeStart + "-" + sf.fadeEnd + " m (" + sf.highQualityShaderFadeStart + "-" + sf.highQualityShaderFadeEnd
                + " at high quality), " + (r != null && r.enabled ? "drawn at " + r.sharedMaterial.GetFloat(sf.floatName).ToString("F3") : "not drawn")).ToString();
        }

        static void Fade(System.Text.StringBuilder s, string what, PQSMod_CelestialBodyTransform.AltitudeFade f)
        {
            if (f == null) return;
            s.Append(" " + what + ": " + f.fadeFloatName + " " + f.fadeStart + "-" + f.fadeEnd + " m (" + f.highQualityShaderFadeStart + "-" + f.highQualityShaderFadeEnd
                     + " at high quality), " + f.valueStart + " to " + f.valueEnd + ";");
        }
#endif
    }
}
