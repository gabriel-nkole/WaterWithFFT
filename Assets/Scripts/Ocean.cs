using UnityEngine;
using Unity.Jobs;
using Unity.Collections;
using Unity.Burst;

using Random = Unity.Mathematics.Random;


public class Ocean : MonoBehaviour {
    // General Parameters
    [SerializeField, Range(1, 10)]
    public int SimulationSpeed = 8;

    [SerializeField, Range(1, 10)]
    public int Resolution = 8;

    private int M;


    // Wind Parameters
    [SerializeField, Range(1, 20)]
    public float Gravity = 9.80665f;

    [SerializeField, Range(0, 1000)]
    public float WindSpeed = 40f;

    private float L_;

    [SerializeField]
    public Vector2 WindDirection = new Vector2(1, 1);

    [SerializeField, Range(1, 4)]
    public int DirectionExpOver2 = 2;   //exponent for suppressing waves perpendicular to wind [1 -> 2, 2 -> 4, 3 -> 6, 4 -> 8, ...] 

    [SerializeField, Range(1, 100)]
    public float Amplitude = 4.0f;

    [SerializeField, Range(0, 1)]         
    public float smallL = 0.5f;   //small wave suppression coefficient


    // Displacement Parameters
    [SerializeField, Range(0, 1f)]
    public float lambda = 1f;   //lateral displacement strength


    // Foam
    [SerializeField, Range(-2, 1)]
    public float FoamBias = 0.68f;

    [SerializeField, Range(0, 1)]
    public float decayFactor = 0.4f;

    [SerializeField]
    public Color FoamColor = Color.gray;


    // Thread Info
    private const int LOCAL_WORK_GROUPS_X = 8;
    private const int LOCAL_WORK_GROUPS_Y = 8;

    private int threadGroupsX;
    private int threadGroupsY;


    // Ocean Material
    [SerializeField]
    public Material OceanMaterial;
    

    // Pre-computed Textures (Noise, Butterfly)
    private NativeArray<Color> noiseArr;
    private Texture2D noise;
    private Random rand;

    private ComputeShader ButterflyTexture_CS;
    private RenderTexture butterfly;


    // Cascades
    private CascadeParams cascParams;
    private Cascade Cascade0;
    private Cascade Cascade1;
    private Cascade Cascade2;


    // Extras
    private float elapsedTime = 0f;



    void Awake() {
        ButterflyTexture_CS = Resources.Load<ComputeShader>("ButterflyTexture");
    }
    
    void OnEnable() {
        // Initialisation
        M = (int) Mathf.Pow(2f, Resolution);
        threadGroupsX = Mathf.CeilToInt(M/(float)LOCAL_WORK_GROUPS_X);
        threadGroupsY = Mathf.CeilToInt(M/(float)LOCAL_WORK_GROUPS_Y);

        L_ = WindSpeed*WindSpeed/Gravity;


        // Setting parameters to be sent to cascades
        cascParams.Resolution = Resolution;
        cascParams.M = M;

        cascParams.Gravity = Gravity;
        cascParams.WindSpeed = WindSpeed;
        cascParams.L_ = L_;
        cascParams.WindDirection = WindDirection.normalized;
        cascParams.DirectionExpOver2 = DirectionExpOver2;
        cascParams.Amplitude = Amplitude;
        cascParams.smallL = smallL;

        cascParams.lambda = lambda;

        cascParams.FoamBias = FoamBias;
        cascParams.decayFactor = decayFactor;
        cascParams.FoamColor = FoamColor;

        cascParams.LOCAL_WORK_GROUPS_X = LOCAL_WORK_GROUPS_X;
        cascParams.threadGroupsX = threadGroupsX;
        cascParams.threadGroupsY = threadGroupsY;

        cascParams.OceanMaterial = OceanMaterial;


        // Noise Texture Computation (CPU)
        noise = new Texture2D(M, M, TextureFormat.RGBAFloat, false);
        noise.filterMode = FilterMode.Point;
        noise.wrapMode = TextureWrapMode.Clamp;

        noiseArr = new NativeArray<Color>(M * M, Allocator.Persistent);
        rand = new Random(1);
        JobHandle jobHandle = new NoiseJob { M = M, noiseArr = noiseArr, rand = rand }.Schedule(cascParams.M * cascParams.M, 1);
        jobHandle.Complete();
        noise.SetPixelData(noiseArr, 0);
        noise.Apply();


        // Butterfly Texture Computation (GPU)
        butterfly = CreateButterflyRenderTexture(cascParams.Resolution, cascParams.M, FilterMode.Point, TextureWrapMode.Clamp);
        ButterflyTexture_CS.SetFloat("M", cascParams.M);
        ButterflyTexture_CS.SetInt("numBits", cascParams.Resolution);
        ButterflyTexture_CS.SetTexture(0, "butterfly", butterfly);
        
        ButterflyTexture_CS.Dispatch(0, Mathf.CeilToInt(cascParams.Resolution / (float)cascParams.LOCAL_WORK_GROUPS_X), cascParams.threadGroupsY, 1);


        // Initialise cascades at different length scales (1000m, 250m, 50m)
        Cascade0 = CreateCascade(0, 1000, 1000);
        Cascade0.OnEnable();
        Cascade1 = CreateCascade(1, 250, 1000);
        Cascade1.OnEnable();
        Cascade2 = CreateCascade(2, 50, 1000);
        Cascade2.OnEnable();
    }

    void OnDisable() {
        // Free cascades
        Cascade0.OnDisable();
        Cascade0 = null;
        Cascade1.OnDisable();
        Cascade1 = null;
        Cascade2.OnDisable();
        Cascade2 = null;


        // Free noise data
        noiseArr.Dispose();
        Destroy(noise);

        // Free butterfly texture
        butterfly.Release();
        butterfly = null;
    }

    void OnValidate() {
        // Refresh whenever parameters are updated
        if (Cascade0 != null && enabled) {
            OnDisable();
            OnEnable();
        }
    }


    void Update() {
        float deltaT = Time.unscaledDeltaTime * SimulationSpeed;
        elapsedTime += deltaT;

        // Update cascades
        Cascade0.Update(elapsedTime, deltaT);
        Cascade1.Update(elapsedTime, deltaT);
        Cascade2.Update(elapsedTime, deltaT);
    }



    [BurstCompile(FloatPrecision.Standard, FloatMode.Fast, CompileSynchronously = true)]
    struct NoiseJob : IJobParallelFor {
        public int M;
        public Random rand;

        [WriteOnly]
        public NativeArray<Color> noiseArr;
        
        public void Execute(int i) {
            float xRandom = rand.NextFloat(-1f, 1f);
            float yRandom = rand.NextFloat(-1f, 1f);
            float zRandom = rand.NextFloat(-1f, 1f);
            float wRandom = rand.NextFloat(-1f, 1f);
            
            int y = i / M;
            int x = i % M;
            noiseArr[y*M + x] = new Color(xRandom, yRandom, zRandom, wRandom);
        }
    }

    public static RenderTexture CreateButterflyRenderTexture(int width, int height, FilterMode fM, TextureWrapMode wM) {
        RenderTexture rt = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
        rt.enableRandomWrite = true;
        rt.filterMode = fM;
        rt.wrapMode = wM;
        rt.Create();
        return rt;
    }

    public Cascade CreateCascade(int ID, int inL, int inL0) {
        return new Cascade(ID, inL, inL0, cascParams, noise, butterfly);
    }
}